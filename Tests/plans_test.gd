extends SceneTree

## The job board (plans) on Sample Valley. Prints PASS/FAIL per check.
## godot --headless --path . --script res://Tests/plans_test.gd

var _fails := 0
var sim: Simulation


func _init() -> void:
	# Where plans may go
	_fresh()
	check(sim.plan_allowed(0, Vector2i(12, 9), "build"), "village plan on clear land")
	check(sim.plan_allowed(0, Vector2i(11, 3), "build"), "village plan on woods")
	check(not sim.plan_allowed(0, Vector2i(8, 4), "build"), "no village plan next to an own village")
	check(not sim.plan_allowed(0, Vector2i(13, 6), "build"), "no village plan on a mountain")
	check(sim.plan_allowed(0, Vector2i(10, 2), "clear"), "clearing plan on woods")
	check(not sim.plan_allowed(0, Vector2i(12, 9), "clear"), "no clearing plan on clear land")

	# Planned villages can't touch; marking again changes the priority; erase
	check(sim.add_plans(0, [Vector2i(12, 9)], "build") == 1, "village planned")
	check(sim.add_plans(0, [Vector2i(13, 9)], "build") == 0, "no planned village next to another")
	check(sim.add_plans(0, [Vector2i(12, 9)], "build", 2) == 1 and sim.plan_at(0, Vector2i(12, 9)) == ["build", 2],
		"marking again sets the priority")
	check(sim.remove_plans(0, [Vector2i(12, 9), Vector2i(1, 1)]) == 1 and sim.plan_at(0, Vector2i(12, 9)).is_empty(),
		"plan erased")

	# Box layout: villages two apart, none touching, all allowed
	var picks := sim.layout_villages(0, Rect2i(9, 7, 6, 5))
	var touching := false
	for a in picks:
		for b in picks:
			if a != b and absi(a.x - b.x) <= 1 and absi(a.y - b.y) <= 1:
				touching = true
	check(picks.size() >= 4 and not touching, "box layout: %d villages, none touching" % picks.size())
	check(sim.add_plans(0, picks, "build") == picks.size(), "the whole layout can be planned")

	# An Auto unit builds a planned village and the plan goes away
	_fresh()
	var me := sim.country(0)
	var funds := me.funds
	sim._spawn(0, Vector2i(10, 8), 200)
	sim.add_plans(0, [Vector2i(16, 4)], "build")
	run(40)
	check(sim.world.village_at(Vector2i(16, 4)) == 0, "planned village built")
	check(sim.plan_at(0, Vector2i(16, 4)).is_empty(), "plan done, off the board")
	check(me.funds < funds, "the village cost funds")

	# A village planned on woods: cleared first, then built
	_fresh()
	sim._spawn(0, Vector2i(10, 8), 200)
	sim.add_plans(0, [Vector2i(11, 3)], "build")
	run(80)
	check(sim.world.village_at(Vector2i(11, 3)) == 0, "woods cleared, then the village built")

	# Clearing far from own land (Auto alone wouldn't go there)
	_fresh()
	sim._spawn(0, Vector2i(10, 8), 200)
	sim.add_plans(0, [Vector2i(5, 8)], "clear")
	run(40)
	check(sim.world.terrain_at(Vector2i(5, 8)) == ".", "planned woods cleared")
	check(sim.plan_at(0, Vector2i(5, 8)).is_empty(), "clearing plan done")

	# Priority: an urgent plan further away comes before a normal one next door
	_fresh()
	_only_standby()
	var u := sim._spawn(0, Vector2i(8, 8), 200)
	sim.add_plans(0, [Vector2i(6, 8)], "clear", 0)
	sim.add_plans(0, [Vector2i(11, 3)], "clear", 2)
	var near_day := -1
	var far_day := -1
	for d in 80:
		sim.step()
		if near_day < 0 and sim.world.terrain_at(Vector2i(6, 8)) == ".":
			near_day = d
		if far_day < 0 and sim.world.terrain_at(Vector2i(11, 3)) == ".":
			far_day = d
	check(far_day >= 0 and near_day > far_day, "urgent cleared first (day %d), then normal (day %d)" % [far_day, near_day])
	check(not u.dead, "worker still alive")

	# Only Auto units take plans
	_fresh()
	_only_standby()
	var s := sim._spawn(0, Vector2i(8, 8), 200)
	s.order = "standby"
	sim.add_plans(0, [Vector2i(5, 8)], "clear")
	run(30)
	check(sim.world.terrain_at(Vector2i(5, 8)) == "T", "standby units leave plans alone")

	# Plans that can't be done any more are dropped
	_fresh()
	sim.add_plans(0, [Vector2i(6, 10)], "clear")
	sim.world.set_terrain(Vector2i(6, 10), ".")
	run(11)
	check(sim.plan_at(0, Vector2i(6, 10)).is_empty(), "plan on woods cleared some other way is dropped")

	print("FAILED: %d" % _fails if _fails else "ALL PASSED")
	quit(1 if _fails else 0)


func _fresh() -> void:
	sim = Simulation.new(Level.load_file("res://Levels/sample_valley.json"), 1)
	# Keep the enemy out of these checks
	sim.country(1).leader.strength = 100
	sim.country(1).tax = 100
	sim.country(1).auto_tax = false
	sim.country(1).emit_cooldown = 1 << 30


## No other of the player's units do any work (new ones included).
func _only_standby() -> void:
	sim.country(0).default_order = "standby"
	for o in sim.units:
		if o.owner == 0 and not o.is_leader:
			o.order = "standby"


func run(days: int) -> void:
	for i in days:
		sim.step()


func check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		_fails += 1
