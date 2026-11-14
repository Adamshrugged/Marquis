extends SceneTree

## Playbooks on Sample Valley: unit lines (size, distance, order, on/off, go home,
## guard) and the tax playbook. Prints PASS/FAIL per check.
## godot --headless --path . --script res://Tests/playbook_test.gd

var _fails := 0
var sim: Simulation


func _init() -> void:
	# Defaults: the player's starts with the job board, AI ones guard the castle
	_fresh()
	var me := sim.country(0)
	var red := sim.country(1)
	check(me.playbook[0].action == "plans" and not me.playbook.any(func(l): return l.action == "guard"),
		"player playbook starts with the job board, no guarding")
	check(me.playbook.any(func(l): return l.action == "army" and l.min == Rules.STYLES.balanced.march + 1),
		"player joins the army above the balanced march size")
	check(red.playbook[0].action == "guard" and red.playbook[0].dist == Rules.STYLES[red.style].defend,
		"AI guards its castle from its style's range")
	check(me.playbook.size() <= Playbook.MAX_LINES and red.playbook.size() <= Playbook.MAX_LINES, "defaults fit the line limit")
	check(me.tax_book.lines[0].tax == Rules.STYLES.balanced.tax_high and me.tax_book.otherwise == Rules.STYLES.balanced.tax_low,
		"default tax playbook is the old auto tax")

	# First line that applies and finds work wins
	_fresh()
	me = sim.country(0)
	var spot := _by_woods()
	sim.set_playbook(0, [Playbook.line("clear", 4, 0, 50), Playbook.line("home")])
	var small := sim._spawn(0, spot, 40)
	sim._choose_job(small)
	check(small.job == "clear" and small.line == 0, "small unit clears woods on line 1 (job '%s')" % small.job)
	check(small.line_text == "Line 1: Size up to 50: Clear woods within 4", "line described (%s)" % small.line_text)
	var big := sim._spawn(0, spot + Vector2i(0, 0), 80)
	sim._drop_job(small)
	sim._choose_job(big)
	check(big.job != "clear" and big.line != 0, "size range skips a bigger unit (job '%s', line %d)" % [big.job, big.line])

	# Distance limits and the on/off switch
	_fresh()
	spot = _by_woods()
	var u := sim._spawn(0, spot, 40)
	sim.set_playbook(0, [Playbook.line("clear", 0)])
	sim._choose_job(u)
	check(u.job != "clear" and u.line == -1, "woods out of range: otherwise (job '%s')" % u.job)
	var off := Playbook.line("clear", 4)
	off.on = false
	sim.set_playbook(0, [off])
	sim._choose_job(u)
	check(u.job != "clear", "a switched-off line does nothing")

	# Go home: on an own village it waits there
	_fresh()
	var village: Vector2i = sim.world.villages_of(0)[0]
	u = sim._spawn(0, village, 30)
	sim.set_playbook(0, [Playbook.line("home")])
	sim._choose_job(u)
	check(u.line == 0 and u.job == "" and u.idle > 0, "go home line: already home, waits")

	# Guard: a player line works too
	_fresh()
	var gate := sim.world.castle_entrance(0)
	var guard := sim._spawn(0, gate + Vector2i(2, 2), 200)
	sim.set_playbook(0, [Playbook.line("guard", 10)])
	sim._spawn(1, sim.world.castle_center(0) + Vector2i(3, 2), 30)
	sim.step()
	check(sim.country(0).threat, "player castle sees the threat")
	check(guard.job == "guard" or guard.pos == gate, "player unit comes back to guard (job '%s')" % guard.job)

	# Presets
	_fresh()
	sim.reset_playbooks(0, "turtle")
	check(sim.country(0).playbook[0].action == "guard" and sim.country(0).playbook[0].dist == Rules.STYLES.turtle.defend,
		"turtle preset guards from 20")
	sim.reset_playbooks(0)
	check(sim.country(0).playbook[0].action == "plans", "reset gives the player's own default back")

	# Cleaning edited lines
	var messy := [{"action": "dance"}, {"action": "clear", "min": 50, "max": 10, "dist": -7}]
	for i in 30:
		messy.append(Playbook.line("build", 4))
	var clean := Playbook.sanitize(messy)
	check(clean.size() == Playbook.MAX_LINES, "unknown actions dropped, list capped (%d)" % clean.size())
	check(clean[0].action == "clear" and clean[0].max == 50 and clean[0].dist == -1, "size range and distance fixed")

	# Tax playbook
	_fresh()
	me = sim.country(0)
	sim.set_tax_book(0, {"lines": [{"below": 1000, "tax": 60}, {"below": 10000, "tax": -1}], "otherwise": 5})
	check(me.auto_tax, "setting a tax playbook turns automatic tax on")
	me.funds = 500
	sim.step()
	check(me.tax == 60, "below 1000: 60%% (%d)" % me.tax)
	me.funds = 5000
	sim.step()
	check(me.tax == 60, "below 10000: keeps the rate (%d)" % me.tax)
	me.funds = 50000
	sim.step()
	check(me.tax == 5, "otherwise: 5%% (%d)" % me.tax)
	sim.set_tax(0, 40)
	me.funds = 500
	sim.step()
	check(me.tax == 40 and not me.auto_tax, "moving the tax bar turns the tax playbook off")

	print("FAILED: %d" % _fails if _fails else "ALL PASSED")
	quit(1 if _fails else 0)


## Plants woods touching Green's land and returns a free clear cell next to them.
func _by_woods() -> Vector2i:
	var w := sim.world
	for i in w.tcode.size():
		var p := w.pos(i)
		if not _free(p) or not sim._next_to_own_land(p, 0):
			continue
		for d in World.N4:
			if _free(p + d):
				w.set_terrain(p, "T")
				return p + d
	return Vector2i(-1, -1)


func _free(p: Vector2i) -> bool:
	var w := sim.world
	return w.in_bounds(p) and w.terrain_at(p) == "." and w.village_at(p) < 0 and w.castle_owner[w.idx(p)] < 0 \
		and sim._units_at(p).is_empty()


func _fresh() -> void:
	sim = Simulation.new(Level.load_file("res://Levels/sample_valley.json"), 1)


func check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		_fails += 1
