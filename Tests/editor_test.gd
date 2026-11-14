extends SceneTree

## Map editor: LevelDoc edits, saving and loading, and the editor scene starting up.
## godot --headless --path . --script res://Tests/editor_test.gd

var failed := 0
const FILE := "user://editor_test_tmp.json"


func check(name: String, ok: bool) -> void:
	print(("PASS  " if ok else "FAIL  ") + name)
	if not ok:
		failed += 1


func _init() -> void:
	var d := LevelDoc.blank(20, 16)
	check("blank map has two countries", d.countries.size() == 2 and d.player == 0)
	check("blank map loads as a level", d.to_level() != null)

	check("paint woods", d.paint_terrain(Vector2i(10, 8), "T").size() == 1 and d.terrain_at(Vector2i(10, 8)) == "T")
	check("castle cells can't be painted", d.paint_terrain(Vector2i(3, 3), "~").is_empty())
	var filled := d.fill_terrain(Vector2i(10, 8), "^")
	check("fill one cell of woods", filled.size() == 1 and d.terrain_at(Vector2i(10, 8)) == "^")

	check("village on clear land", d.toggle_village(Vector2i(8, 8), 0) == "")
	check("village claims the land around it", d.territory_at(Vector2i(7, 7)) == 0 and d.territory_at(Vector2i(9, 9)) == 0)
	check("village needs clear land", d.toggle_village(Vector2i(10, 8), 0) != "")
	check("village needs the country", d.toggle_village(Vector2i(14, 2), 2) != "")
	check("can't paint water on a village", d.paint_terrain(Vector2i(8, 8), "~").is_empty())

	check("unit placed", d.toggle_unit(Vector2i(12, 4), 1, 250) == "" and d.unit_at(Vector2i(12, 4)) >= 0)
	check("unit on a mountain refused", d.toggle_unit(Vector2i(10, 8), 1, 100) != "")
	d.paint_terrain(Vector2i(12, 4), "~")
	check("painting water removes the unit", d.unit_at(Vector2i(12, 4)) < 0)

	check("new country from a castle", d.place_castle(2, Vector2i(16, 2)) == "" and not d.country(2).is_empty())
	check("castle can't overlap another", d.place_castle(3, Vector2i(16, 3)) != "")
	check("castle moved", d.place_castle(0, Vector2i(4, 12)) == "" and d.country(0).castle == Vector2i(3, 11))

	check("territory painted", d.paint_territory(Vector2i(1, 1), 1).size() == 1 and d.territory_at(Vector2i(1, 1)) == 1)
	check("territory only on clear land", d.paint_territory(Vector2i(10, 8), 1).is_empty())
	check("erase removes the village", d.erase_at(Vector2i(8, 8)) and d.village_at(Vector2i(8, 8)) < 0)
	check("its territory went with it", d.territory_at(Vector2i(7, 7)) < 0)

	d.toggle_village(Vector2i(12, 13), 1)
	d.toggle_unit(Vector2i(6, 6), 1, 300)
	check("remove the player's country", d.remove_country(0) == "" and d.player != 0)
	d.player = 1
	check("resize refuses to cut a castle", d.resize(10, 10) != "")
	check("resize grows", d.resize(24, 18) == "" and d.width == 24 and d.terrain[17].length() == 24)

	var snap := d.snapshot()
	d.paint_terrain(Vector2i(0, 0), "~")
	d.restore_from(snap)
	check("snapshot restores", d.terrain_at(Vector2i(0, 0)) == ".")

	d.name = "Editor Test"
	check("saved", d.save(FILE) == "")
	var err := []
	var back := LevelDoc.open(FILE, err)
	check("loads back", back != null)
	if back:
		check("same terrain after reload", back.terrain == d.terrain)
		check("same countries after reload", back.countries.size() == d.countries.size() and back.player == d.player)
		check("same villages and units after reload", back.villages.size() == d.villages.size() and back.units.size() == d.units.size())
		check("same territory after reload", back.territory == d.territory)
		var sim := Simulation.new(Level.load_file(FILE), 1)
		for i in 50:
			sim.step()
		check("the saved map plays", sim.day == 50)
	DirAccess.remove_absolute(FILE)

	var sample := LevelDoc.open("res://Levels/sample_valley.json")
	check("opens sample valley", sample != null and sample.to_level() != null)

	# The editor scene starts and draws without script errors
	var ed: Node = load("res://Scenes/Editor.tscn").instantiate()
	root.add_child(ed)
	await process_frame
	await process_frame
	check("editor scene starts", ed.doc != null and ed.world != null)
	ed.set_tool("terrain", "~")
	ed._begin_stroke()
	ed._apply(Vector2i(20, 20), true)
	ed._end_stroke()
	check("editor paints", ed.doc.terrain_at(Vector2i(20, 20)) == "~" and ed.world.terrain_at(Vector2i(20, 20)) == "~")
	ed.undo()
	check("editor undo", ed.doc.terrain_at(Vector2i(20, 20)) == ".")

	print("ALL PASSED" if failed == 0 else "%d FAILED" % failed)
	quit(failed)
