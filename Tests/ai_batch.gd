extends SceneTree

## Plays every level with every country on auto, over several seeds, and summarises.
## Games run in parallel on the worker thread pool (one game per core); --serial runs them one by one.
## godot --headless --path . --script res://Tests/ai_batch.gd -- [--seeds=2] [--only=B_000,S_105] [--serial]

var jobs := []      # [{name, level, seed}]
var results := []   # one Dictionary per job, same index
var done := 0
var lock := Mutex.new()


func _init() -> void:
	var seeds := 2
	var only := []
	var serial := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seeds="): seeds = int(a.trim_prefix("--seeds="))
		if a.begins_with("--only="): only = a.trim_prefix("--only=").split(",")
		if a == "--serial": serial = true
	var paths := ["res://Levels/sample_valley.json"]
	var lmo := "res://DS7E_WIN/extracted/levels"
	if DirAccess.dir_exists_absolute(lmo):
		for f in DirAccess.get_files_at(lmo):
			paths.append(lmo + "/" + f)
	for path in paths:
		var name: String = path.get_file().get_basename()
		if not only.is_empty() and not name in only:
			continue
		for seed in range(1, seeds + 1):
			# Each game gets its own Level copy, loaded here on the main thread
			jobs.append({"name": name, "level": Level.load_file(path), "seed": seed})
	results.resize(jobs.size())

	var t0 := Time.get_ticks_msec()
	if serial:
		for i in jobs.size():
			_play(i)
	else:
		var task := WorkerThreadPool.add_group_task(_play, jobs.size(), -1, true, "ai_batch")
		WorkerThreadPool.wait_for_group_task_completion(task)
	var wall := float(Time.get_ticks_msec() - t0) / 1000.0

	var stalls := 0
	var end_days := 0
	var wins := {}
	var slowest := 0.0
	print("")
	for r in results:
		print(r.line)
		slowest = maxf(slowest, r.ms)
		if r.winner == "none":
			stalls += 1
		else:
			end_days += r.day
			wins[r.winner] = wins.get(r.winner, 0) + 1
	var games := results.size()
	print("\nGAMES %d  stalls %d  avg end day %d  slowest %.1f ms/day  wins %s  (%.1fs wall%s)" % [games, stalls,
		end_days / max(1, games - stalls), slowest, wins, wall, ", serial" if serial else ""])
	quit()


## Plays job i to the end. Runs on a worker thread: touches only its own Simulation and results[i].
func _play(i: int) -> void:
	var job: Dictionary = jobs[i]
	var sim := Simulation.new(job.level, job.seed)
	sim.player = -1   # no human: the game only ends at the day limit or one country left
	for k in sim.countries:
		k.auto_tax = true
		k.control = "ai"
		sim.reset_playbooks(k.id, k.style)   # AI playbooks for the player too
	var t0 := Time.get_ticks_msec()
	while sim.state == "playing":
		sim.step()
		# Treat the player like any other country: stop when one country is left
		if sim.countries.filter(func(k): return k.alive).size() <= 1:
			break
	# Per-game ms/day is measured while other games share the CPU, so it reads higher than --serial
	var ms := float(Time.get_ticks_msec() - t0) / maxi(1, sim.day)
	var alive := sim.countries.filter(func(k): return k.alive)
	var winner: String = alive[0].color if alive.size() == 1 else "none"
	var styles := ", ".join(sim.countries.map(func(k): return "%s:%s" % [k.color.left(1).to_upper(), k.style]))
	results[i] = {
		"winner": winner, "day": sim.day, "ms": ms,
		"line": "%-16s seed %d  %-6s day %4d  %5.1f ms/day  %s" % [job.name, job.seed, winner, sim.day, ms, styles],
	}
	lock.lock()
	done += 1
	printraw("\r%d/%d games done" % [done, jobs.size()])
	lock.unlock()
