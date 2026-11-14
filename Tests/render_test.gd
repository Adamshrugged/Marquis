extends SceneTree

## Every converted LMO map must draw exactly like the original .MAP.
## Needs DS7E_WIN/ (tools/lmo_map.py output); skips if it's missing.
## godot --headless --path . --script res://Tests/render_test.gd

func _init() -> void:
	var dir := "res://DS7E_WIN/extracted/levels"
	if not DirAccess.dir_exists_absolute(dir):
		print("SKIPPED: no converted LMO maps")
		quit()
		return
	var fails := 0
	var layer := TerrainLayer.new()
	for f in DirAccess.get_files_at(dir):
		var world := World.from_level(Level.load_file(dir + "/" + f))
		var raw := FileAccess.get_file_as_bytes("res://DS7E_WIN/MAP/" + f.get_basename() + ".MAP")
		var diff := 0
		for y in world.height:
			for x in world.width:
				if layer.code_at(world, Vector2i(x, y)) != raw[x * world.height + y]:
					diff += 1
		print("%s  %s %d cells differ" % ["PASS" if diff == 0 else "FAIL", f, diff])
		fails += int(diff > 0)
	layer.free()
	print("FAILED: %d" % fails if fails else "ALL PASSED")
	quit(1 if fails else 0)
