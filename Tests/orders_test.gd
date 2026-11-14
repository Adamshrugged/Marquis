extends SceneTree

## Player orders on Sample Valley. Prints PASS/FAIL per check.
## godot --headless --path . --script res://Tests/orders_test.gd

var _fails := 0
var sim: Simulation


func _init() -> void:
	_fresh()
	var me := sim.country(0)

	# Clear Land: woods become clear land, then the unit goes back to the default order
	var u := sim._spawn(0, Vector2i(10, 4), 200)
	check(sim.action_allowed(0, Vector2i(10, 2), "clear"), "clear allowed on woods")
	check(sim.order_units([u], Vector2i(10, 2), "clear") == 1, "clear order accepted")
	check(u.ordered and u.job == "clear", "unit is under orders")
	run(30)
	check(sim.world.terrain_at(Vector2i(10, 2)) == ".", "woods cleared")
	check(not u.ordered and u.order == me.default_order, "back to default order after clearing")

	# Build: a village appears and funds drop by 100
	_fresh()
	me = sim.country(0)
	u = sim._spawn(0, Vector2i(10, 8), 200)
	var funds_before := me.funds
	check(sim.order_units([u], Vector2i(12, 9), "build") == 1, "build order accepted")
	run(12)
	check(sim.world.village_at(Vector2i(12, 9)) == 0, "village built")
	check(me.funds < funds_before, "build cost funds")

	# Defend: builds a village and stays on it under orders
	_fresh()
	u = sim._spawn(0, Vector2i(10, 8), 300)   # keeps 100 after giving 200 to the village
	sim.order_units([u], Vector2i(14, 3), "defend")
	run(20)
	check(sim.world.village_at(Vector2i(14, 3)) == 0, "defend built a village")
	check(u.pos == Vector2i(14, 3) and u.ordered and u.order == "standby", "defender stays on the village")
	run(40)
	check(u.pos == Vector2i(14, 3), "defender still there 40 days later")

	# Destroy: own village removed
	var had := u.strength + sim.world.village_pop[sim.world.idx(Vector2i(14, 3))]
	sim.order_units([u], Vector2i(14, 3), "destroy")
	run(1)   # instant [E] (left on Auto it may build there again later)
	check(sim.world.village_at(Vector2i(14, 3)) == -1 and u.strength == had, "own village destroyed, the unit takes in its population")

	# Standby keeps a unit where it was sent
	_fresh()
	u = sim._spawn(0, Vector2i(10, 8), 200)
	sim.order_units([u], Vector2i(16, 10), "standby")
	run(30)
	check(u.pos == Vector2i(16, 10) and u.order == "standby", "standby holds position")

	# Reinforce: joins the unit already there, which keeps its order
	var holder := sim._spawn(0, Vector2i(16, 4), 100)
	sim.order_units([holder], Vector2i(16, 4), "standby")
	run(2)
	var helper := sim._spawn(0, Vector2i(12, 4), 50)   # (alone, the holder would decay to about 66 by the check)
	sim.order_units([helper], Vector2i(16, 4), "reinforce")
	run(15)
	check(helper.dead and not holder.dead, "reinforcement merged into the holder")
	check(holder.strength > 80 and holder.order == "standby", "holder kept its order and gained strength")

	# Unreachable and invalid targets
	check(not sim.action_allowed(0, Vector2i(20, 3), "standby"), "water is not a destination")
	check(not sim.action_allowed(0, Vector2i(10, 8), "clear"), "clear needs woods")
	check(not sim.action_allowed(0, Vector2i(10, 8), "bridge"), "no bridge on dry land")
	check(sim.order_units([u], Vector2i(13, 6), "standby") == 0, "mountain unreachable")
	check(sim.order_units([u], Vector2i(16, 10), "build") == 0 or sim.world.can_build_village(Vector2i(16, 10), 0), "invalid build refused")
	check(sim.order_units([u], Vector2i(16, 4), "clear") == 0, "clear refused on clear land")

	# Queues: clear woods, then build elsewhere, in that order
	_fresh()
	me = sim.country(0)
	u = sim._spawn(0, Vector2i(10, 4), 200)
	check(sim.order_units([u], Vector2i(11, 3), "clear") == 1, "first order accepted")
	check(sim.queue_order([u], Vector2i(12, 9), "build") == 1, "build queued")
	check(u.queue.size() == 1 and u.job == "clear", "still clearing, build waits in the queue")
	var built_day := -1
	var cleared_day := -1
	for d in 60:
		sim.step()
		if cleared_day < 0 and sim.world.terrain_at(Vector2i(11, 3)) == ".":
			cleared_day = d
		if built_day < 0 and sim.world.village_at(Vector2i(12, 9)) == 0:
			built_day = d
	check(cleared_day >= 0 and built_day > cleared_day, "cleared (day %d) then built (day %d)" % [cleared_day, built_day])
	check(u.queue.is_empty() and not u.ordered, "queue done, back to the default order")

	# Queued order that's no longer valid is skipped
	_fresh()
	u = sim._spawn(0, Vector2i(10, 4), 200)
	sim.order_units([u], Vector2i(16, 4), "standby")
	sim.queue_order([u], Vector2i(11, 3), "clear")
	sim.queue_order([u], Vector2i(16, 10), "standby")
	sim.world.set_terrain(Vector2i(11, 3), ".")   # someone else cleared it
	run(40)
	check(u.pos == Vector2i(16, 10) and u.queue.is_empty(), "skipped the cleared woods, went on to the next")

	# A new (unshifted) order clears the queue; idle units start a shift-order at once
	_fresh()
	u = sim._spawn(0, Vector2i(10, 4), 200)
	sim.order_units([u], Vector2i(16, 4), "standby")
	sim.queue_order([u], Vector2i(11, 3), "clear")
	sim.queue_order([u], Vector2i(9, 9), "standby")
	check(u.queue.size() == 2, "two orders queued")
	sim.order_units([u], Vector2i(8, 6), "standby")
	check(u.queue.is_empty() and u.job_target == Vector2i(8, 6), "new order replaced the queue")
	var idle := sim._spawn(0, Vector2i(10, 8), 100)
	check(sim.queue_order([idle], Vector2i(12, 8), "standby") == 1 and idle.job == "standby" \
		and idle.queue.is_empty(), "idle unit starts a queued order now")

	# Queued orders wait behind a continuous one
	sim.order_units([u], Vector2i(16, 8), "barricade_cont")
	sim.queue_order([u], Vector2i(9, 9), "standby")
	run(30)
	check(u.job == "barricade_cont" and u.queue.size() == 1, "queue waits behind a continuous barricade")

	# Context right-click actions
	_fresh()
	check(sim.context_action(0, Vector2i(10, 2)) == ["clear", "Clear Land"], "woods: clear")
	check(sim.context_action(0, Vector2i(24, 16))[0] == "destroy", "enemy village: destroy")
	check(sim.context_action(0, Vector2i(20, 9))[0] == "bridge", "water by the bank: bridge")
	check(sim.context_action(0, Vector2i(14, 10))[0] == "clear_path", "barricade: clear path")
	check(sim.context_action(0, Vector2i(10, 12))[0] == "seal", "cave: seal")
	check(sim.context_action(0, Vector2i(7, 4))[0] == "defend", "own village: defend")
	check(sim.context_action(0, Vector2i(12, 9))[0] == "build", "clear land: build")
	check(sim.context_action(0, Vector2i(13, 6)).is_empty(), "mountain: nothing")
	var foe := sim._spawn(1, Vector2i(16, 10), 50)
	check(sim.context_action(0, foe.pos) == ["standby", "Attack"], "enemy unit: attack")
	var path := sim.route_for(foe, Vector2i(16, 6), "standby")
	check(path.size() == 4 and sim.travel_days(path, foe.pos, Vector2i(0, -1)) == 2, "route preview: 2 cells a day")
	check(sim.travel_days(path, foe.pos, Vector2i(0, 1)) == 3, "turning round takes a tick")
	# Routes go round enemies the unit can't beat, unless sent to attack them [E]
	var wall := sim._spawn(0, Vector2i(16, 8), 500)
	wall.order = "standby"
	var round_it := sim.route_for(foe, Vector2i(16, 6), "standby")
	var near := [Vector2i(16, 8), Vector2i(16, 7), Vector2i(16, 9), Vector2i(15, 8), Vector2i(17, 8)]
	check(not near.any(func(p): return p in round_it), "route keeps away from a stronger enemy (%s)" % [round_it])
	check(not sim.route_for(foe, wall.pos, "standby").is_empty(), "... but goes when sent to attack it")
	sim._kill(wall)
	# Standing on another country's territory clears it [E]
	var land := Vector2i(-1, -1)
	for i in sim.world.territory.size():
		var q := sim.world.pos(i)
		if sim.world.territory[i] == 0 and sim.world.village_owner[i] < 0 and sim.world.castle_owner[i] < 0 \
				and sim.world.is_walkable(q) and sim._units_at(q).is_empty():
			land = q
			break
	var trespasser := sim._spawn(1, land, 50)
	trespasser.order = "standby"
	sim.step()
	check(sim.world.territory_of(land) == -1, "an enemy unit on green land clears it")
	sim._kill(trespasser)

	# Leader: moves out (no tax away from the castle), then recall brings it home
	_fresh()
	me = sim.country(0)
	run(12)
	check(sim.order_leader(0, Vector2i(8, 8)), "leader move accepted")
	run(20)
	check(me.leader.pos == Vector2i(8, 8), "leader arrived")
	var f := me.funds
	run(15)
	check(me.funds <= f, "no tax while the leader is away")
	check(sim.recall_leader(0), "recall accepted")
	run(20)
	check(me.leader.pos == sim.world.castle_center(0), "leader back in the castle centre")

	# Default order: new units from villages follow it
	_fresh()
	me = sim.country(0)
	me.default_order = "standby"
	run(300)
	var fresh_units := sim.units.filter(func(o): return o.owner == 0 and not o.is_leader)
	check(not fresh_units.is_empty() and fresh_units.all(func(o): return o.order == "standby"), "new units take the default order (%d units)" % fresh_units.size())

	# Tax: setting it by hand turns auto off; auto adjusts with funds; status explains
	_fresh()
	me = sim.country(0)
	sim.set_auto_tax(0, true)
	me.funds = 6000
	run(Rules.CELL_DAYS)
	check(me.tax == 0, "auto tax goes to 0 when rich (%d)" % me.tax)
	me.funds = 0
	run(Rules.CELL_DAYS)
	check(me.tax == 19, "auto tax goes high when broke (%d)" % me.tax)
	sim.set_tax(0, 20)
	check(me.tax == 20 and not me.auto_tax, "manual tax turns auto off")
	sim.set_tax(0, 150)
	check(me.tax == Rules.TAX_MAX, "tax capped at 30")
	run(11)
	check(sim.tax_status(0).begins_with("All"), "tax status: villages paying (%s)" % sim.tax_status(0))
	sim.order_leader(0, Vector2i(8, 8))
	run(10)
	check(sim.tax_status(0).contains("leader is away"), "tax status: leader away")

	# Beating a leader hands its villages, units and funds to the winner [M]
	_fresh()
	var green := sim.country(0)
	var red := sim.country(1)
	var red_units := sim.units.filter(func(u): return u.owner == 1 and not u.is_leader)
	var red_villages := sim.world.villages_of(1)
	var both_funds := green.funds + red.funds
	var attacker := sim._spawn(0, sim.world.castle_entrance(1), 500)
	while red.alive and not attacker.dead:
		sim._round(attacker, red.leader)
	check(not attacker.dead, "the attacker beats the leader")
	check(not red.alive and red.funds == 0, "the beaten country is out")
	check(is_equal_approx(green.funds, both_funds), "its funds change hands at once")
	check(red_villages.all(func(p): return sim.world.village_at(p) == 1), "its villages are still its own until visited [E]")
	var foe_unit: Unit = red_units[0]
	var beside := sim._spawn(0, foe_unit.pos + Vector2i(1, 0), 50)
	var before := foe_unit.strength
	sim._fight_round(beside)
	check(foe_unit.strength == before, "a beaten country's unit can't be attacked")
	sim._kill(beside)
	# The game is over (no enemies left), so drive the days by hand
	for n in Rules.CELL_DAYS:
		sim.day += 1
		sim._grow_villages()
		for x in sim.units.duplicate():
			if not x.dead:
				sim._update_unit(x)
	check(not red_villages.is_empty() and red_villages.all(func(p): return sim.world.village_at(p) == 0),
		"its villages change hands as they're visited (%s)" % [red_villages.map(func(p): return sim.world.village_at(p))])
	check(not red_units.is_empty() and red_units.all(func(u): return u.dead or (u.owner == 0 and u.order == "auto")),
		"its units change hands and go on Auto [E]")
	check(sim.world.castle_owner[sim.world.idx(sim.world.castle_center(1))] < 0, "its castle is gone")

	print("FAILED: %d" % _fails if _fails else "ALL PASSED")
	quit(1 if _fails else 0)


func _fresh() -> void:
	sim = Simulation.new(Level.load_file("res://Levels/sample_valley.json"), 1)
	# Keep the enemy out of these checks
	sim.country(1).leader.strength = 100
	sim.country(1).tax = Rules.TAX_MAX
	sim.country(1).auto_tax = false


func run(days: int) -> void:
	for i in days:
		sim.step()


func check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		_fails += 1
