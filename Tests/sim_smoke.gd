extends SceneTree

## Headless run of a whole game with every country on auto.
## godot --headless --path . --script res://Tests/sim_smoke.gd -- --level=<path> [--seed=n] [--every=250]

func _init() -> void:
	var path := "res://Levels/sample_valley.json"
	var seed := 1
	var every := 250
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--level="): path = a.trim_prefix("--level=")
		if a.begins_with("--seed="): seed = int(a.trim_prefix("--seed="))
		if a.begins_with("--every="): every = int(a.trim_prefix("--every="))
	var level := Level.load_file(path)
	var sim := Simulation.new(level, seed)
	sim.player = -1   # no human: play until one country is left or the day limit
	for k in sim.countries:
		k.auto_tax = true   # the player too, so every country plays the same way
		k.control = "ai"
		sim.reset_playbooks(k.id, k.style)   # AI playbooks for the player too
	var t0 := Time.get_ticks_msec()
	while sim.state == "playing" and sim.countries.filter(func(k): return k.alive).size() > 1:
		sim.step()
		if sim.day % every == 0:
			var parts := []
			for k in sim.countries:
				var s := sim.stats(k.id)
				parts.append("%s v%d land%d u%d/%d L%d $%d%s" % [k.color.left(1).to_upper(), s.villages, s.territory,
					s.units, s.unit_strength, s.leader, s.funds, "" if k.alive else " X"])
			print("day %4d  %s" % [sim.day, "  |  ".join(parts)])
	print("END %s: %s  (%.1fs, %.2f ms/day)" % [sim.state, sim.result, (Time.get_ticks_msec() - t0) / 1000.0,
		float(Time.get_ticks_msec() - t0) / sim.day])
	quit()
