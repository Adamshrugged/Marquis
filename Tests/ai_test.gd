extends SceneTree

## AI behaviour on Sample Valley (Green = player, Red = AI).
## godot --headless --path . --script res://Tests/ai_test.gd

var _fails := 0
var sim: Simulation


func _init() -> void:
	# Personalities: player stays balanced, AI gets one of the styles, levels can choose
	_fresh()
	check(sim.country(0).style == "balanced", "player is balanced")
	check(sim.country(1).style in Rules.AI_STYLES, "AI got a style (%s)" % sim.country(1).style)
	var lvl := Level.load_file("res://Levels/sample_valley.json")
	lvl.countries[1].style = "turtle"
	check(Simulation.new(lvl, 1).country(1).style == "turtle", "level can set a style")
	var seen := {}
	for seed in range(1, 30):
		seen[Simulation.new(Level.load_file("res://Levels/sample_valley.json"), seed).country(1).style] = true
	check(seen.size() >= 3, "seeds give different styles (%s)" % ", ".join(seen.keys()))

	# Defence: an enemy near Red's castle pulls Red's units back to the gate
	_fresh()
	var red := sim.country(1)
	var gate := sim.world.castle_entrance(1)
	var defender := sim._spawn(1, gate + Vector2i(-4, 1), 200)
	sim._spawn(0, sim.world.castle_center(1) + Vector2i(-3, -2), 30)
	run(1)
	check(red.threat, "Red sees the threat")
	run(12)
	check(defender.dead or defender.pos == gate or defender.job == "guard" or defender.job == "attack",
		"defender came back to guard (job %s at %s)" % [defender.job, defender.pos])

	# Raid: an army too weak for the castle but costly to keep goes after villages
	_fresh()
	red = sim.country(1)
	sim.country(0).leader.strength = 100000   # castle far too strong to attack
	run(11)   # fields built, rally chosen
	check(red.rally.x >= 0, "Red has a rally point")
	var army := sim._spawn(1, red.rally, Rules.RAID_STRENGTH + 500)
	army.idle = 0
	run(1)
	check(army.job == "attack", "big waiting army raids (job '%s')" % army.job)

	# Target needs a bridge: Red saves funds for it
	_fresh()
	red = sim.country(1)
	for x in [20, 21]:
		sim.world.set_terrain(Vector2i(x, 6), "~")
	sim._build_fields()
	check(red.target == 0 and red.reserve > 0, "Red saves %d funds for a bridge" % red.reserve)
	check(sim._breach_field.has(1), "Red plans a way across the water")

	# No work nearby: a weak unit doesn't march across the map to attack
	_fresh()
	sim.country(0).funds = 0
	for i in sim.world.tcode.size():
		if sim.world.tcode[i] == World.C_WOODS:
			sim.world.set_terrain(sim.world.pos(i), ".")
	var far_village := Vector2i(-1, -1)
	for i in sim.world.tcode.size():
		var p := sim.world.pos(i)
		var gap := p - sim.world.castle_entrance(0)
		if absi(gap.x) + absi(gap.y) > Rules.SEARCH_RADIUS + 4 and sim.world.can_build_village(p, 1):
			far_village = p
			break
	sim.world.place_village(far_village, 1, 5)
	var weak := sim._spawn(0, sim.world.castle_entrance(0), 40)
	sim._choose_job(weak)
	check(weak.job != "attack", "weak unit stays out of far fights (job '%s')" % weak.job)
	var strong := sim._spawn(0, sim.world.castle_entrance(0) + Vector2i(0, 1), 3000)
	sim.country(0).rally = Vector2i(-1, -1)
	sim._choose_job(strong)
	check(strong.job in ["attack", "march", "rally"], "strong unit still goes to fight (job '%s')" % strong.job)

	# AI auto tax [E]: 28 when broke, 0 from 1792 funds
	_fresh()
	red = sim.country(1)
	red.funds = 100
	run(Rules.CELL_DAYS)
	check(red.tax == 28, "broke AI taxes at 28 (%d)" % red.tax)
	red.funds = 3000
	run(Rules.CELL_DAYS)
	check(red.tax == 0, "rich AI taxes at 0 (%d)" % red.tax)

	# Every country starts with a unit just outside its castle; levels can add more
	_fresh()
	for k in sim.countries:
		var starters := sim.units.filter(func(o): return o.owner == k.id and not o.is_leader)
		var outside: bool = not starters.is_empty() and sim.world.castle_owner[sim.world.idx(starters[0].pos)] < 0
		check(starters.size() == 1 and outside and starters[0].strength == Rules.START_UNIT, "%s starts with a unit outside the castle" % k.color)
	var lvl2 := Level.load_file("res://Levels/sample_valley.json")
	lvl2.units.append({"owner": 1, "pos": Vector2i(16, 10), "strength": 250.0})
	var extra := Simulation.new(lvl2, 1).units.filter(func(o): return o.pos == Vector2i(16, 10))
	check(extra.size() == 1 and extra[0].owner == 1 and extra[0].strength == 250, "level 'units' adds starting units")

	print("FAILED: %d" % _fails if _fails else "ALL PASSED")
	quit(1 if _fails else 0)


func _fresh() -> void:
	sim = Simulation.new(Level.load_file("res://Levels/sample_valley.json"), 1)


func run(days: int) -> void:
	for i in days:
		sim.step()


func check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		_fails += 1
