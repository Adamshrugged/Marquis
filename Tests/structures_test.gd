extends SceneTree

## Barricades, bridges, Clear Path, Dismantle, Seal Cave and monsters on Sample Valley.
## godot --headless --path . --script res://Tests/structures_test.gd
##
## Sample Valley: barricade at (14,10), cave at (10,12), the river (x 20-21) is
## crossed only by the bridge at (20,6)-(21,6).

var _fails := 0
var sim: Simulation


func _init() -> void:
	_fresh()
	var me := sim.country(0)
	var w := sim.world

	# Clear Path: the barricade is worked from the next cell and becomes clear land
	var u := sim._spawn(0, Vector2i(12, 10), 200)
	check(sim.action_allowed(0, Vector2i(14, 10), "clear_path"), "clear path allowed on a barricade")
	check(not w.is_walkable(Vector2i(14, 10)), "barricade blocks movement")
	check(sim.order_units([u], Vector2i(14, 10), "clear_path") == 1, "clear path accepted")
	run(6)
	check(w.terrain_at(Vector2i(14, 10)) == ".", "barricade cleared")
	check(absi(u.pos.x - 14) + absi(u.pos.y - 10) == 1, "worked from the next cell")

	# Barricade: costs 1 fund per 4 durability
	var funds := me.funds
	check(sim.order_units([u], Vector2i(16, 8), "barricade") == 1, "barricade accepted")
	run(12)
	check(w.terrain_at(Vector2i(16, 8)) == "x", "barricade built")
	check(w.durability[w.idx(Vector2i(16, 8))] == Rules.BARRICADE_STEP, "durability %d" % w.durability[w.idx(Vector2i(16, 8))])
	check(is_equal_approx(funds - me.funds, Rules.BARRICADE_STEP / Rules.BARRICADE_POINTS_PER_FUND) or me.funds < funds, "barricade cost funds")

	# Barricade (continuous) keeps strengthening it and stays under orders
	sim.order_units([u], Vector2i(16, 8), "barricade_cont")
	run(30)
	check(w.durability[w.idx(Vector2i(16, 8))] > Rules.BARRICADE_STEP * 2, "continuous barricade grew to %d" % w.durability[w.idx(Vector2i(16, 8))])
	check(u.ordered and u.job == "barricade_cont", "still on continuous barricade")

	# Dismantle the only river crossing: the far side becomes unreachable
	_fresh()
	me = sim.country(0)
	w = sim.world
	u = sim._spawn(0, Vector2i(17, 6), 300)
	check(sim.distance(u, Vector2i(25, 6)) > 0, "far bank reachable over the bridge")
	check(sim.order_units([u], Vector2i(20, 6), "dismantle") == 1, "dismantle accepted")
	run(15)
	check(w.terrain_at(Vector2i(20, 6)) == "~", "bridge dismantled")
	check(sim.distance(u, Vector2i(25, 6)) == -1, "far bank cut off")

	# Build Bridge: water next to land becomes a bridge again (no tax, to measure the cost)
	sim.set_tax(0, 0)
	funds = me.funds
	check(sim.action_allowed(0, Vector2i(20, 6), "bridge"), "bridge allowed on water by the bank")
	check(not sim.action_allowed(0, Vector2i(20, 10), "bridge") or w.is_walkable(Vector2i(19, 10)), "bridge needs a bank")
	check(sim.order_units([u], Vector2i(20, 6), "bridge") == 1, "bridge accepted")
	run(15)
	check(w.terrain_at(Vector2i(20, 6)) == "=", "bridge rebuilt")
	check(w.durability[w.idx(Vector2i(20, 6))] == Rules.BRIDGE_MAX, "bridge at full durability")
	check(funds - me.funds >= Rules.BRIDGE_NEW_COST * Rules.BRIDGE_MAX, "new bridge cost at least %d (spent %d)" % [Rules.BRIDGE_NEW_COST * Rules.BRIDGE_MAX, funds - me.funds])
	check(sim.distance(u, Vector2i(25, 6)) > 0, "far bank reachable again")

	# Dismantle (continuous): takes it down again and keeps watching
	sim.order_units([u], Vector2i(20, 6), "dismantle_cont")
	run(15)
	check(w.terrain_at(Vector2i(20, 6)) == "~" and u.job == "dismantle_cont", "continuous dismantle keeps watching")

	# Monsters come out of caves
	_fresh()
	w = sim.world
	sim._spawn_monsters(1.0)
	var m := sim.monster_stats()
	check(m.count == 1, "a monster came out of the cave")

	# ... but not onto a unit standing by the cave (they'd share the cell without a fight)
	_fresh()
	w = sim.world
	for d in World.N4:
		var by: Vector2i = Vector2i(10, 12) + d
		if w.is_walkable(by):
			sim._spawn(0, by, 50)
	sim._spawn_monsters(1.0)
	check(sim.monster_stats().count == 0, "no monster spawns onto a unit")

	# A leader's released unit fights an enemy standing in the gate
	_fresh()
	var gate := sim.world.castle_entrance(0)
	var intruder := sim._spawn(1, gate, 10)
	var lord := sim.country(0)
	lord.leader.strength = 10000
	lord.emit_cooldown = 0
	lord.population = 0
	sim._update_leaders()
	check(intruder.dead and sim._units_at(gate).all(func(e): return e.owner == 0 and not e.dead) \
		and not sim._units_at(gate).is_empty(), "released unit fights the enemy in the gate")

	# A released unit that merges with a gate guard isn't counted twice in the stats
	_fresh()
	sim._spawn(0, sim.world.castle_entrance(0), 30).order = "standby"   # a guard that stays put
	sim.country(0).leader.strength = 10000
	sim.country(0).emit_cooldown = 0
	sim.step()
	var live := sim.units.filter(func(e): return e.owner == 0 and not e.is_leader and not e.dead).size()
	check(sim.units.all(func(e): return not e.dead) and sim.stats(0).units == live,
		"merged units leave the list the same day (%d counted, %d alive)" % [sim.stats(0).units, live])

	_fresh()
	w = sim.world
	sim._spawn_monsters(1.0)
	m = sim.monster_stats()

	# Seal Cave: the cave is closed and costs strength
	u = sim._spawn(0, Vector2i(8, 12), 200)
	check(sim.order_units([u], Vector2i(10, 12), "seal") == 1, "seal accepted")
	run(20)
	check(w.terrain_at(Vector2i(10, 12)) != "o" and w.caves.is_empty(), "cave sealed")
	sim._spawn_monsters(1.0)
	check(sim.monster_stats().count <= m.count, "sealed cave makes no monsters")

	# A strong monster wrecks a village
	_fresh()
	w = sim.world
	var village := Vector2i(7, 4)
	sim._spawn(Simulation.MONSTER, Vector2i(9, 5), 500)
	run(15)
	check(w.village_at(village) == -1, "monster destroyed a village")

	# The drawn bridge tile follows durability, through repeated dismantle/rebuild
	_fresh()
	w = sim.world
	sim.set_tax(0, 0)
	sim.country(0).funds = 100000
	var layer := TerrainLayer.new()
	var spot := Vector2i(20, 6)
	var full_code := layer.code_at(w, spot)
	check(full_code != 0x7A, "full bridge drawn as a bridge (%x)" % full_code)
	u = sim._spawn(0, Vector2i(17, 6), 300)
	for cycle in 3:
		sim.order_units([u], spot, "dismantle")
		run(4)
		if w.terrain_at(spot) == "=":
			check(layer.code_at(w, spot) == 0x7A, "cycle %d: half-dismantled bridge drawn damaged" % cycle)
		run(15)
		check(w.terrain_at(spot) == "~" and layer.code_at(w, spot) >= 0x30 and layer.code_at(w, spot) < 0x60, "cycle %d: dismantled bridge drawn as water" % cycle)
		sim.order_units([u], spot, "bridge")
		run_until(func(): return w.terrain_at(spot) == "=", 20)
		check(layer.code_at(w, spot) == 0x7A, "cycle %d: unfinished bridge drawn damaged" % cycle)
		run_until(func(): return w.durability[w.idx(spot)] == Rules.BRIDGE_MAX, 20)
		check(w.durability[w.idx(spot)] == Rules.BRIDGE_MAX and layer.code_at(w, spot) == full_code, "cycle %d: repaired bridge drawn as a full bridge" % cycle)
	check(w.dirty.has(spot), "durability changes queue a redraw")
	layer.free()

	# A damaged bridge from the map ('b') repairs into a normal bridge
	_fresh()
	w = sim.world
	var lvl := Level.load_file("res://Levels/sample_valley.json")
	lvl.terrain[6] = lvl.terrain[6].substr(0, 20) + "bb" + lvl.terrain[6].substr(22)
	sim = Simulation.new(lvl, 1)
	w = sim.world
	layer = TerrainLayer.new()
	check(w.terrain_at(spot) == "=" and w.durability[w.idx(spot)] == Rules.BRIDGE_DAMAGED_START, "map 'b' loads as a damaged bridge")
	check(layer.code_at(w, spot) == 0x7A and w.is_walkable(spot), "damaged bridge drawn damaged, still walkable")
	u = sim._spawn(0, Vector2i(24, 6), 300)   # far bank, so the two repairers don't meet and merge
	sim.order_units([u], Vector2i(21, 6), "bridge")
	sim.order_units([sim._spawn(0, Vector2i(19, 6), 300)], spot, "bridge")
	run_until(func(): return w.durability[w.idx(spot)] == Rules.BRIDGE_MAX and w.durability[w.idx(Vector2i(21, 6))] == Rules.BRIDGE_MAX, 40)
	check(layer.code_at(w, spot) != 0x7A and layer.code_at(w, Vector2i(21, 6)) != 0x7A, "repaired map bridge drawn as a full bridge")
	layer.free()

	# AI countries seal caves near their land
	_fresh()
	w = sim.world
	sim.country(0).control = "ai"
	sim.reset_playbooks(0, "balanced")   # AI playbooks have the seal caves line
	u = sim._spawn(0, Vector2i(9, 11), 300)
	sim.world.claim_cell(Vector2i(8, 11), 0)
	run_until(func(): return w.caves.is_empty(), 60)
	check(w.caves.is_empty(), "AI unit sealed the nearby cave")

	# A defeated country's castle disappears
	_fresh()
	w = sim.world
	var red_castle: Vector2i = w.castles[1]
	sim._kill(sim.country(1).leader, 0)
	check(not sim.country(1).alive, "red eliminated")
	var gone := true
	for dy in 3:
		for dx in 3:
			var c := red_castle + Vector2i(dx, dy)
			gone = gone and w.castle_owner[w.idx(c)] == -1 and w.terrain_at(c) == "." and w.is_walkable(c)
	check(gone, "castle cells became open ground")

	print("FAILED: %d" % _fails if _fails else "ALL PASSED")
	quit(1 if _fails else 0)


func _fresh() -> void:
	sim = Simulation.new(Level.load_file("res://Levels/sample_valley.json"), 1)
	sim.country(1).leader.strength = 100
	sim.country(1).tax = 100
	sim.country(1).auto_tax = false
	sim.country(1).emit_cooldown = 1 << 30
	sim.country(0).emit_cooldown = 1 << 30


func run_until(done: Callable, max_days: int) -> void:
	for i in max_days:
		if done.call():
			return
		sim.step()


func run(days: int) -> void:
	for i in days:
		sim.step()


func check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		_fails += 1
