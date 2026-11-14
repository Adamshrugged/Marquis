extends SceneTree

## Barricades, bridges, Clear Path, Dismantle, Seal Cave and monsters on Sample Valley.
## godot --headless --path . --script res://Tests/structures_test.gd
##
## Sample Valley: barricade at (14,10), cave at (10,12), the river (x 20-21) is
## crossed only by the bridge at (20,6)-(21,6). Work goes at strength / n per tick
## and every counter starts at 100 [E].

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
	run_until(func(): return w.terrain_at(Vector2i(14, 10)) == ".", 20)
	check(w.terrain_at(Vector2i(14, 10)) == ".", "barricade cleared")
	check(absi(u.pos.x - 14) + absi(u.pos.y - 10) == 1, "worked from the next cell")

	# Barricade: on clear land the cell's counter is worked off first, then it stands
	# with what's left over. 1 fund per 4 points
	var funds := me.funds
	sim.set_tax(0, 0)
	check(sim.order_units([u], Vector2i(16, 8), "barricade") == 1, "barricade accepted")
	run_until(func(): return w.terrain_at(Vector2i(16, 8)) == "x", 20)
	var first := w.durability[w.idx(Vector2i(16, 8))]
	check(w.terrain_at(Vector2i(16, 8)) == "x" and first < u.strength / Rules.BUILD_DIV + 1, "barricade built (durability %d)" % first)
	check(funds - me.funds >= Rules.CELL_START / Rules.BARRICADE_POINTS_PER_FUND - 4 and funds - me.funds < 40,
		"barricade cost about 100 points / 4 (spent %d)" % (funds - me.funds))
	check(not u.ordered, "a single barricade order is done once it stands")

	# Barricade (continuous) keeps strengthening it and stays under orders
	sim.order_units([u], Vector2i(16, 8), "barricade_cont")
	run(20)
	check(w.durability[w.idx(Vector2i(16, 8))] > first + 100, "continuous barricade grew to %d" % w.durability[w.idx(Vector2i(16, 8))])
	check(u.ordered and u.job == "barricade_cont", "still on continuous barricade")

	# Dismantle the only river crossing: it becomes a damaged bridge and the far side is cut off
	_fresh()
	me = sim.country(0)
	w = sim.world
	me.funds = 100000
	me.default_order = "standby"   # between orders (on Auto it would go and build villages)
	sim.set_tax(0, 0)
	u = sim._spawn(0, Vector2i(17, 6), 300)
	check(sim.distance(u, Vector2i(25, 6)) > 0, "far bank reachable over the bridge")
	check(sim.order_units([u], Vector2i(20, 6), "dismantle") == 1, "dismantle accepted")
	run(15)
	check(w.terrain_at(Vector2i(20, 6)) == "b" and not w.is_walkable(Vector2i(20, 6)), "bridge dismantled into a damaged bridge")
	check(sim.distance(u, Vector2i(25, 6)) == -1, "far bank cut off")

	# Repair: a damaged bridge costs 2 funds a point
	funds = me.funds
	check(sim.action_allowed(0, Vector2i(20, 6), "bridge"), "a damaged bridge can be repaired")
	check(sim.order_units([u], Vector2i(20, 6), "bridge") == 1, "repair accepted")
	run(5)
	check(w.terrain_at(Vector2i(20, 6)) == "=" and funds - me.funds < 100, "bridge repaired cheaply (spent %d)" % (funds - me.funds))
	check(sim.distance(u, Vector2i(25, 6)) > 0, "far bank reachable again")

	# Build Bridge over water: 30 funds a point, about 100 points
	funds = me.funds
	check(sim.action_allowed(0, Vector2i(20, 7), "bridge"), "bridge allowed on water by the bank")
	check(not sim.action_allowed(0, Vector2i(10, 7), "bridge"), "no bridge on land")
	check(sim.order_units([u], Vector2i(20, 7), "bridge") == 1, "bridge accepted")
	run_until(func(): return w.terrain_at(Vector2i(20, 7)) == "=", 20)
	check(w.terrain_at(Vector2i(20, 7)) == "=", "new bridge built")
	check(funds - me.funds >= Rules.BRIDGE_NEW_COST * (Rules.CELL_START + 1), "new bridge cost at least %d (spent %d)" % [Rules.BRIDGE_NEW_COST * (Rules.CELL_START + 1), funds - me.funds])

	# Dismantle (continuous): takes it down again and keeps working the damaged bridge
	sim.order_units([u], Vector2i(20, 6), "dismantle_cont")
	run(15)
	check(w.terrain_at(Vector2i(20, 6)) == "b" and u.job == "dismantle_cont", "continuous dismantle keeps at it")
	check(w.durability[w.idx(Vector2i(20, 6))] > 0, "... making the damaged bridge harder to repair (%d)" % w.durability[w.idx(Vector2i(20, 6))])

	# A unit standing on a bridge that comes down is lost [E]
	_fresh()
	w = sim.world
	var on := sim._spawn(0, Vector2i(20, 6), 50)
	on.order = "standby"
	u = sim._spawn(0, Vector2i(19, 6), 2000)
	u.order = "standby"
	sim.order_units([u], Vector2i(20, 6), "dismantle")
	run(4)
	check(w.terrain_at(Vector2i(20, 6)) == "b" and on.dead, "a unit on a dismantled bridge is lost")

	# Monsters come out of caves
	_fresh()
	w = sim.world
	var cave := w.idx(Vector2i(10, 12))
	for n in 14:
		sim._cave_tick(cave)
	check(sim.monster_stats().count == 0, "no monster for the first 14 cave visits")
	sim._cave_tick(cave)
	var m := sim.monster_stats()
	check(m.count == 1 and m.strength == Rules.MONSTER_START and w.durability[cave] == 5,
		"15th visit: a 200 monster comes out (counter %d)" % w.durability[cave])

	# ... but not onto a unit standing by the cave (they'd share the cell without a fight)
	_fresh()
	w = sim.world
	for d in World.N4:
		var by: Vector2i = Vector2i(10, 12) + d
		if w.is_walkable(by):
			sim._spawn(0, by, 50)
	_ripe_cave()
	check(sim.monster_stats().count == 0, "no monster spawns onto a unit")

	# The leader releases a quarter of its strength only into an empty gate [E]
	_fresh()
	var gate := sim.world.castle_entrance(0)
	var lord := sim.country(0)
	var intruder := sim._spawn(1, gate, 10)
	intruder.order = "standby"
	lord.leader.strength = 10000
	sim._update_leaders()
	check(lord.leader.strength == 10000 and sim._units_at(gate) == [intruder], "no release while someone stands in the gate")
	sim._kill(intruder)
	sim._update_leaders()
	var out: Array = sim._units_at(gate)
	check(out.size() == 1 and out[0].owner == 0 and out[0].strength == 2500 and lord.leader.strength == 7500,
		"a quarter leaves through the empty gate (%s)" % [out.map(func(e): return e.strength)])

	# Seal Cave: the cave becomes mountain, at no cost in strength
	_fresh()
	w = sim.world
	_ripe_cave()
	m = sim.monster_stats()
	u = sim._spawn(0, Vector2i(8, 12), 200)
	check(sim.order_units([u], Vector2i(10, 12), "seal") == 1, "seal accepted")
	run(20)
	check(w.terrain_at(Vector2i(10, 12)) == "^" and w.caves.is_empty(), "cave sealed")
	run(Rules.CELL_DAYS * 2)
	check(sim.monster_stats().count <= m.count, "sealed cave makes no monsters")

	# A strong monster wrecks a village
	_fresh()
	w = sim.world
	var village := Vector2i(7, 4)
	for d in World.N4:
		if w.is_walkable(village - d) and w.village_at(village - d) < 0:
			var beast := sim._spawn(Simulation.MONSTER, village - d, 500)
			beast.facing = d
			beast.roam = 50
			break
	run(3)
	check(w.village_at(village) == -1, "monster destroyed a village")

	# Bridges are drawn damaged exactly while they're damaged
	_fresh()
	w = sim.world
	sim.set_tax(0, 0)
	sim.country(0).funds = 100000
	sim.country(0).default_order = "standby"
	var layer := TerrainLayer.new()
	var spot := Vector2i(20, 6)
	var full_code := layer.code_at(w, spot)
	check(full_code != 0x7A, "bridge drawn as a bridge (%x)" % full_code)
	u = sim._spawn(0, Vector2i(17, 6), 300)
	for cycle in 2:
		sim.order_units([u], spot, "dismantle")
		run_until(func(): return w.terrain_at(spot) == "b", 20)
		check(layer.code_at(w, spot) == 0x7A, "cycle %d: dismantled bridge drawn damaged" % cycle)
		sim.order_units([u], spot, "bridge")
		run_until(func(): return w.terrain_at(spot) == "=", 20)
		check(layer.code_at(w, spot) == full_code, "cycle %d: repaired bridge drawn as a bridge" % cycle)
	check(w.dirty.has(spot), "changes queue a redraw")
	layer.free()

	# A damaged bridge from the map ('b') blocks the way until repaired
	var lvl := Level.load_file("res://Levels/sample_valley.json")
	lvl.terrain[6] = lvl.terrain[6].substr(0, 20) + "bb" + lvl.terrain[6].substr(22)
	sim = Simulation.new(lvl, 1)
	w = sim.world
	sim.country(0).funds = 100000
	layer = TerrainLayer.new()
	sim.country(0).default_order = "standby"
	check(w.terrain_at(spot) == "b" and w.durability[w.idx(spot)] == Rules.CELL_START, "map 'b' loads as a damaged bridge")
	check(layer.code_at(w, spot) == 0x7A and not w.is_walkable(spot), "damaged bridge drawn damaged, not walkable")
	sim.order_units([sim._spawn(0, Vector2i(24, 6), 300)], Vector2i(21, 6), "bridge")
	sim.order_units([sim._spawn(0, Vector2i(19, 6), 300)], spot, "bridge")
	run_until(func(): return w.terrain_at(spot) == "=" and w.terrain_at(Vector2i(21, 6)) == "=", 40)
	check(layer.code_at(w, spot) != 0x7A and layer.code_at(w, Vector2i(21, 6)) != 0x7A, "repaired map bridge drawn as a bridge")
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
	sim.country(1).tax = Rules.TAX_MAX
	sim.country(1).auto_tax = false


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


## Brings Sample Valley's cave to its next monster.
func _ripe_cave() -> void:
	var i := sim.world.idx(Vector2i(10, 12))
	sim.world.durability[i] = Rules.CAVE_SPAWN - Rules.CAVE_GROW
	sim._cave_tick(i)
