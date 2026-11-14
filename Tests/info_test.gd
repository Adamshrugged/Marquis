extends SceneTree

## Information queries on Sample Valley: tax and growth projections (the tax
## preview) and the history samples (graphs). Prints PASS/FAIL per check.
## godot --headless --path . --script res://Tests/info_test.gd

var _fails := 0
var sim: Simulation


func _init() -> void:
	# Projections (the tax preview) match what one collection cycle does [E]: villages
	# grow by territory + 1 every Rules.CELL_DAYS days, tax is taken from their population
	_fresh()
	var me := sim.country(0)
	_standby(0)
	sim.set_tax(0, 20)
	var castle := sim.world.idx(sim.world.castle_center(0))
	while (castle + sim.day + 1) % Rules.CELL_DAYS != 0:   # the next step collects tax
		sim.step()
	var income := sim.tax_income(0, me.tax) * Rules.CELL_DAYS
	var funds := me.funds
	sim.step()
	check(income > 0 and absf((me.funds - funds) - income) < 0.001,
		"income projection %.1f = funds gained %.1f" % [income, me.funds - funds])
	var before := _total(0)
	var projected := sim.growth_per_day(0, me.tax) * Rules.CELL_DAYS
	run(Rules.CELL_DAYS)
	check(absf(_total(0) - before - projected) <= 2.0,
		"growth projection %.1f = actual %.1f over a cycle" % [projected, _total(0) - before])
	check(sim.growth_per_day(0, 0) > sim.growth_per_day(0, 30), "the tax is taken from village population")
	check(sim.tax_income(0, 30) > sim.tax_income(0, 10), "more tax, more funds")
	check(sim.tax_income(0, 0) == 0.0, "no income at 0")
	sim.set_tax(0, 0)
	run(Rules.CELL_DAYS)
	check(me.connected.is_empty() and sim.tax_income(0, 30) > 0, "at 0 the projection still finds the routes")
	var away := sim.world.castle_entrance(0)
	sim._move(me.leader, away)
	check(sim.tax_income(0, 30) == 0.0, "no income projected while the leader is away")

	# Tax routes: a village walled in by mountains is cut off
	_fresh()
	var reach := sim.tax_reach(0)
	var own := sim.world.villages_of(0)
	check(own.all(func(p): return reach.villages.has(sim.world.idx(p))), "all %d starting villages reachable" % own.size())
	var cut := own[0]
	for d in World.N4:
		if sim.world.in_bounds(cut + d) and sim.world.castle_owner[sim.world.idx(cut + d)] < 0:
			sim.world.set_terrain(cut + d, "^")
	reach = sim.tax_reach(0)
	check(not reach.villages.has(sim.world.idx(cut)), "walled-in village is cut off")
	check(reach.cells.has(sim.world.idx(sim.world.castle_entrance(0))), "reach starts at the gate")

	# History: day 0, then every 10 days, matching the day's numbers
	_fresh()
	check(sim.history.size() == 1 and sim.history[0].day == 0, "history starts on day 0")
	run(20)
	check(sim.history.map(func(h): return h.day) == [0, 10, 20], "a sample every 10 days")
	var h: Dictionary = sim.history.back()
	for c in sim.countries.size():
		var k := sim.countries[c]
		var s := sim.stats(k.id)
		check(h.land[c] == s.territory and is_equal_approx(h.strength[c], s.leader + s.unit_strength)
			and absf(h.population[c] - _pops(k.id).values().reduce(func(a, b): return a + b, 0.0)) < 0.01,
			"%s day 20: land %d, strength %d, population %d" % [k.color, h.land[c], h.strength[c], h.population[c]])
	run(3)
	sim._kill(sim.country(1).leader)
	sim.step()
	check(sim.state == "won" and sim.history.back().day == sim.day, "the last day is recorded when the game ends (day %d)" % sim.day)

	# Bounded: past HISTORY_MAX samples, every other one is dropped and the interval doubles
	_fresh()
	for i in range(1, Simulation.HISTORY_MAX + 1):
		sim.day = i * Simulation.HISTORY_DAYS
		sim._record_history()
	check(sim.history.size() <= Simulation.HISTORY_MAX and sim.history_every == Simulation.HISTORY_DAYS * 2,
		"history thinned to %d samples, every %d days" % [sim.history.size(), sim.history_every])
	check(sim.history[0].day == 0 and sim.history.back().day == Simulation.HISTORY_MAX * Simulation.HISTORY_DAYS,
		"thinning keeps the first and latest samples")

	print("FAILED: %d" % _fails if _fails else "ALL PASSED")
	quit(1 if _fails else 0)


func _fresh() -> void:
	sim = Simulation.new(Level.load_file("res://Levels/sample_valley.json"), 1)


## Village idx -> population for an owner.
func _pops(owner: int) -> Dictionary:
	var out := {}
	for i in sim.world.villages:
		if sim.world.village_owner[i] == owner:
			out[i] = sim.world.village_pop[i]
	return out


## Keep an owner's units still, so they don't build or attack during a check.
func _standby(owner: int) -> void:
	for u in sim.units:
		if u.owner == owner and not u.is_leader:
			u.order = "standby"
	sim.country(owner).default_order = "standby"


func run(days: int) -> void:
	for i in days:
		sim.step()


func check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		_fails += 1


func _total(owner: int) -> float:
	return _pops(owner).values().reduce(func(a, b): return a + b, 0.0)
