extends Node2D
class_name MapEditor

## The map editor (Scenes/Editor.tscn). Paint terrain and territory, place castles,
## villages and starting units, set each country up, save, and play the map at once.
## Data lives in a LevelDoc; this draws it with the game's own TerrainLayer.
##
## Mouse: left paints / places, right-drag scrolls, wheel zooms. WASD/arrows scroll.
## Keys: 1-9 terrain, T territory, V village, C castle, U unit, E erase, F fill,
## G grid, Ctrl+Z undo, Ctrl+Y redo, Ctrl+S save, F5 play.
## Opened from the game's Settings window, or: godot --path . res://Scenes/Editor.tscn -- [--level=<path>]

const CELL := 32
const PANEL_W := 270
const SAVE_DIR := "user://levels"
const LEVEL_DIRS := [["Mine", "user://levels"], ["Built-in", "res://Levels"], ["LMO", "res://DS7E_WIN/extracted/levels"]]
const TERRAIN_NAMES := {".": "Clear land", "T": "Woods", "~": "Water", "^": "Mountain", "=": "Bridge",
	"b": "Damaged bridge", "x": "Barricade", "o": "Cave", "*": "Rubble"}
const TOOLS := ["territory", "village", "castle", "unit", "erase"]
const TOOL_NAMES := {"territory": "Territory (T)", "village": "Village (V)", "castle": "Castle (C)",
	"unit": "Unit (U)", "erase": "Erase (E)"}
const TOOL_KEYS := {KEY_T: "territory", KEY_V: "village", KEY_C: "castle", KEY_U: "unit", KEY_E: "erase"}
const BRUSHES := [1, 3, 5]
const UNDO_LIMIT := 100

var doc: LevelDoc
var world: World
var terrain: TerrainLayer
var marks: Node2D
var camera: Camera2D

## "terrain" (with `brush_char`) or one of TOOLS
var tool := "terrain"
var brush_char := "T"
var brush := 1
var fill := false
var country_id := 0
var unit_strength := 100.0
var show_grid := false
var unsaved := false

var _undo: Array[LevelDoc] = []
var _redo: Array[LevelDoc] = []
var _before: LevelDoc          # state when the current stroke began
var _stroke_changed := false
var _painting := false
var _last_cell := Vector2i(-1, -1)
var _hover := Vector2i(-1, -1)
var _message := ""
var _discard_armed := ""      # "open" / "new": a second click discards unsaved changes

# UI
var _tool_buttons := {}       # key ("terrain:T" or tool) -> Button
var _country_buttons: Array[Button] = []
var _name: LineEdit
var _levels: OptionButton
var _level_paths: Array[String] = []
var _path_label: Label
var _brush: OptionButton
var _fill: CheckBox
var _country_info: Label
var _human: CheckBox
var _style: OptionButton
var _funds: SpinBox
var _tax: SpinBox
var _leader: SpinBox
var _strength: SpinBox
var _remove: Button
var _theme: OptionButton
var _day_limit: SpinBox
var _width: SpinBox
var _height: SpinBox
var _grid: CheckBox
var _status: Label
var _syncing := false


func _ready() -> void:
	camera = Camera2D.new()
	camera.set_script(load("res://Scripts/camera.gd"))
	add_child(camera)
	terrain = TerrainLayer.new()
	terrain.z_index = -1
	add_child(terrain)
	marks = Node2D.new()
	marks.draw.connect(_draw_marks)
	add_child(marks)
	_build_ui()

	var start := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--level="):
			start = arg.trim_prefix("--level=")
	var root := get_tree().root
	if root.has_meta("editor_level"):
		start = root.get_meta("editor_level")
		root.remove_meta("editor_level")
	var err := []
	doc = LevelDoc.open(start, err) if start != "" else null
	if doc == null:
		doc = LevelDoc.blank(48, 48)
	_after_load()
	if not err.is_empty():
		_say(err[0])


func _after_load() -> void:
	_undo.clear()
	_redo.clear()
	unsaved = false
	rebuild()
	camera.position = Vector2(doc.width, doc.height) * CELL / 2.0
	_sync_ui()


## Redraw everything from the doc.
func rebuild() -> void:
	var level := doc.to_level()
	if level == null:
		_say("This map can't be loaded by the game (see the log)")
		return
	world = World.from_level(level)
	terrain.build(world, doc.theme, CELL)
	camera.bounds = Rect2(0, 0, doc.width * CELL, doc.height * CELL)
	camera.margin_left = PANEL_W + 16
	camera.margin_bottom = 48
	marks.queue_redraw()


## Redraw only some cells after terrain or territory painting (much faster than rebuild).
func _redraw_cells(cells: Array[Vector2i]) -> void:
	if cells.size() > 400 or world == null:
		rebuild()
		return
	for p in cells:
		var ch := doc.terrain_at(p)
		var wch := "=" if ch == "b" else ch
		if world.terrain_at(p) != wch:
			world.set_terrain(p, wch)
		var dur := 0
		match ch:
			"b": dur = Rules.BRIDGE_DAMAGED_START
			"=": dur = Rules.BRIDGE_MAX
			"x", "*": dur = Rules.MAP_BARRICADE
		world.set_durability(p, dur)
		var i := world.idx(p)
		world.objects.erase(i)
		world.territory[i] = doc.territory_at(p)
	terrain.refresh(world)
	marks.queue_redraw()


# --- Input -----------------------------------------------------------------

## The button release may happen over the side panel, which would hide it from _unhandled_input.
func _input(event: InputEvent) -> void:
	if _painting and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_painting = false
		_end_stroke()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			get_viewport().gui_release_focus()
			_begin_stroke()
			_painting = true
			_last_cell = _cell_under_mouse()
			_apply(_last_cell, true)
	elif event is InputEventMouseMotion:
		var c := _cell_under_mouse()
		if c != _hover:
			_hover = c
			marks.queue_redraw()
			_update_status()
		if _painting and c != _last_cell and _drags():
			for q in _line(_last_cell, c):
				_apply(q, false)
			_last_cell = c
	elif event is InputEventKey and event.pressed and not event.echo:
		_key(event)


func _key(event: InputEventKey) -> void:
	if event.ctrl_pressed:
		match event.keycode:
			KEY_Z:
				if event.shift_pressed: redo()
				else: undo()
			KEY_Y: redo()
			KEY_S: save()
		return
	if event.keycode >= KEY_1 and event.keycode <= KEY_9:
		set_tool("terrain", LevelDoc.TERRAIN[event.keycode - KEY_1])
	elif TOOL_KEYS.has(event.keycode):
		set_tool(TOOL_KEYS[event.keycode])
	elif event.keycode == KEY_F:
		fill = not fill
		_sync_ui()
	elif event.keycode == KEY_G:
		show_grid = not show_grid
		_sync_ui()
		marks.queue_redraw()
	elif event.keycode == KEY_F5:
		play()


func _cell_under_mouse() -> Vector2i:
	var p := get_global_mouse_position() / CELL
	return Vector2i(floori(p.x), floori(p.y))


## Tools that keep painting while the mouse is dragged.
func _drags() -> bool:
	return tool == "erase" or (not fill and tool in ["terrain", "territory"])


func _apply(cell: Vector2i, first: bool) -> void:
	if not doc.in_bounds(cell):
		return
	var cells: Array[Vector2i] = []
	var msg := ""
	match tool:
		"terrain":
			if fill:
				cells = doc.fill_terrain(cell, brush_char)
			else:
				for q in _brush_cells(cell):
					cells.append_array(doc.paint_terrain(q, brush_char))
		"territory":
			if fill:
				cells = doc.fill_territory(cell, country_id)
			else:
				for q in _brush_cells(cell):
					cells.append_array(doc.paint_territory(q, country_id))
		"erase":
			var any := false
			for q in _brush_cells(cell):
				any = doc.erase_at(q) or any
			if any:
				_changed()
				rebuild()
			return
		"village":
			if first: msg = _rebuild_if_ok(doc.toggle_village(cell, country_id))
		"castle":
			if first: msg = _rebuild_if_ok(doc.place_castle(country_id, cell))
		"unit":
			if first: msg = _rebuild_if_ok(doc.toggle_unit(cell, country_id, unit_strength))
	if not cells.is_empty():
		_changed()
		_redraw_cells(cells)
	if msg != "":
		_say(msg)


func _rebuild_if_ok(msg: String) -> String:
	if msg == "":
		_changed()
		rebuild()
		_sync_ui()
	return msg


func _brush_cells(c: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var r := brush / 2
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			out.append(c + Vector2i(dx, dy))
	return out


## Cells from a to b (excluding a), so fast drags leave no gaps.
func _line(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var n := maxi(absi(b.x - a.x), absi(b.y - a.y))
	for i in range(1, n + 1):
		var t := float(i) / n
		var q := Vector2i(roundi(lerpf(a.x, b.x, t)), roundi(lerpf(a.y, b.y, t)))
		if out.is_empty() or out[-1] != q:
			out.append(q)
	return out


# --- Undo ------------------------------------------------------------------

func _begin_stroke() -> void:
	_before = doc.snapshot()
	_stroke_changed = false


func _changed() -> void:
	_stroke_changed = true
	unsaved = true
	_discard_armed = ""


func _end_stroke() -> void:
	if _stroke_changed:
		_push_undo(_before)
	_before = null
	_update_status()


func _push_undo(state: LevelDoc) -> void:
	_undo.append(state)
	if _undo.size() > UNDO_LIMIT:
		_undo.pop_front()
	_redo.clear()


## Run a one-off change (resize, remove country...) with undo. `change` returns "" or why not.
func _do(change: Callable) -> void:
	var before := doc.snapshot()
	var msg: String = change.call()
	if msg != "":
		_say(msg)
		return
	_push_undo(before)
	unsaved = true
	rebuild()
	_sync_ui()


func undo() -> void:
	_step_history(_undo, _redo, "Undone")


func redo() -> void:
	_step_history(_redo, _undo, "Redone")


func _step_history(from: Array[LevelDoc], to: Array[LevelDoc], what: String) -> void:
	if from.is_empty():
		_say("Nothing to %s" % what.to_lower().trim_suffix("ne"))
		return
	to.append(doc.snapshot())
	doc.restore_from(from.pop_back())
	unsaved = true
	rebuild()
	_sync_ui()
	_say(what)


# --- Files -----------------------------------------------------------------

func save() -> bool:
	var file := doc.path
	if not file.begins_with(SAVE_DIR + "/"):
		file = _free_path(doc.name)   # never overwrite built-in or converted LMO levels
	var err := doc.save(file)
	if err != "":
		_say(err)
		return false
	unsaved = false
	_refresh_levels()
	_sync_ui()
	var w := doc.warnings()
	_say("Saved to %s" % ProjectSettings.globalize_path(file) + ("" if w.is_empty() else ". Note: " + w[0]))
	return true


## user://levels/<name>.json, numbered if another level already has that name.
func _free_path(title: String) -> String:
	var base := title.to_snake_case().validate_filename().replace(" ", "_")
	if base == "":
		base = "map"
	var file := "%s/%s.json" % [SAVE_DIR, base]
	var n := 2
	while FileAccess.file_exists(file):
		file = "%s/%s_%d.json" % [SAVE_DIR, base, n]
		n += 1
	return file


func open_selected() -> void:
	if _levels.selected < 0 or _level_paths.is_empty():
		return
	if not _may_discard("open"):
		return
	var err := []
	var d := LevelDoc.open(_level_paths[_levels.selected], err)
	if d == null:
		_say(err[0])
		return
	doc = d
	_after_load()
	_say("Opened %s" % doc.name)


func new_map() -> void:
	if not _may_discard("new"):
		return
	doc = LevelDoc.blank(int(_width.value), int(_height.value))
	_after_load()
	_say("New %dx%d map" % [doc.width, doc.height])


## Unsaved changes: the first click warns, a second one goes ahead.
func _may_discard(action: String) -> bool:
	if not unsaved or _discard_armed == action:
		_discard_armed = ""
		return true
	_discard_armed = action
	_say("Unsaved changes. Click again to discard them, or Save first.")
	return false


## Save, then start the game on this map. Settings > Map editor comes back here.
func play() -> void:
	if doc.to_level() == null:
		_say("This map can't be played yet")
		return
	if not save():
		return
	get_tree().root.set_meta("level_path", doc.path)
	get_tree().change_scene_to_file("res://Scenes/Game.tscn")


func _refresh_levels() -> void:
	_levels.clear()
	_level_paths.clear()
	for d in LEVEL_DIRS:
		if not DirAccess.dir_exists_absolute(d[1]):
			continue
		var files := Array(DirAccess.get_files_at(d[1])).filter(func(f): return f.get_extension() == "json")
		files.sort()
		for f in files:
			_levels.add_item("%s: %s" % [d[0], f.get_basename()])
			_level_paths.append(d[1] + "/" + f)
	var cur: int = _level_paths.find(doc.path) if doc else -1
	if cur >= 0:
		_levels.select(cur)


# --- Tools and countries ---------------------------------------------------

func set_tool(t: String, ch := "") -> void:
	tool = t
	if ch != "":
		brush_char = ch
	_sync_ui()
	marks.queue_redraw()


func select_country(id: int) -> void:
	country_id = id
	_sync_ui()


## Change a setting of the selected country (form fields; not undoable).
func _set_country(key: String, value) -> void:
	if _syncing:
		return
	var c := doc.country(country_id)
	if c.is_empty():
		return
	c[key] = value
	unsaved = true


# --- Drawing ---------------------------------------------------------------

func _draw_marks() -> void:
	if doc == null:
		return
	var font := ThemeDB.fallback_font
	if show_grid:
		var line := Color(0, 0, 0, 0.25)
		for x in doc.width + 1:
			marks.draw_line(Vector2(x * CELL, 0), Vector2(x * CELL, doc.height * CELL), line)
		for y in doc.height + 1:
			marks.draw_line(Vector2(0, y * CELL), Vector2(doc.width * CELL, y * CELL), line)
	marks.draw_rect(Rect2(0, 0, doc.width * CELL, doc.height * CELL), Color(1, 1, 1, 0.5), false, 2.0)
	for c in doc.countries:
		var col := UnitLayer.color_of(c.id)
		var r := Rect2(Vector2(c.castle) * CELL, Vector2(3, 3) * CELL)
		marks.draw_rect(r, col, false, 3.0)
		var label := "YOU" if c.id == doc.player else "AI"
		marks.draw_string_outline(font, r.position + Vector2(4, -6), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 4, Color.BLACK)
		marks.draw_string(font, r.position + Vector2(4, -6), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, col)
	for v in doc.villages:
		marks.draw_circle((Vector2(v.pos) + Vector2(0.85, 0.15)) * CELL, 4, UnitLayer.color_of(v.owner))
	for u in doc.units:
		var centre := (Vector2(u.pos) + Vector2(0.5, 0.5)) * CELL
		marks.draw_circle(centre, CELL * 0.36, Color.BLACK)
		marks.draw_circle(centre, CELL * 0.30, UnitLayer.color_of(u.owner))
		var s := str(int(u.strength))
		marks.draw_string_outline(font, centre + Vector2(-CELL / 2.0, 5), s, HORIZONTAL_ALIGNMENT_CENTER, CELL, 12, 3, Color.BLACK)
		marks.draw_string(font, centre + Vector2(-CELL / 2.0, 5), s, HORIZONTAL_ALIGNMENT_CENTER, CELL, 12, Color.WHITE)
	if doc.in_bounds(_hover):
		var size := 3 if tool == "castle" else (brush if _drags() else 1)
		var top := _hover - Vector2i(size / 2, size / 2)
		marks.draw_rect(Rect2(Vector2(top) * CELL, Vector2(size, size) * CELL), Color(1, 1, 0.4, 0.9), false, 2.0)


# --- UI --------------------------------------------------------------------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.anchor_bottom = 1.0
	panel.custom_minimum_size.x = PANEL_W
	panel.add_theme_stylebox_override("panel", _style_box())
	layer.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	scroll.add_child(box)

	var title := Label.new()
	title.text = "Map editor"
	title.add_theme_font_size_override("font_size", 20)
	box.add_child(title)

	# File
	_heading(box, "Map")
	_name = LineEdit.new()
	_name.placeholder_text = "Map name"
	_name.text_changed.connect(_on_name)
	box.add_child(_name)
	_levels = OptionButton.new()
	_levels.fit_to_longest_item = false
	_levels.clip_text = true
	_levels.focus_mode = Control.FOCUS_NONE
	var open_row := HBoxContainer.new()
	_levels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	open_row.add_child(_levels)
	open_row.add_child(_button("Open", "Open the chosen level", open_selected))
	box.add_child(open_row)
	var files := HBoxContainer.new()
	files.add_child(_button("New", "A blank map, sized by Width and Height below", new_map))
	files.add_child(_button("Save", "Save to your levels folder (Ctrl+S)", save))
	files.add_child(_button("Play", "Save and play this map now (F5)", play))
	files.add_child(_button("Undo", "Ctrl+Z", undo))
	files.add_child(_button("Redo", "Ctrl+Y", redo))
	box.add_child(files)
	_path_label = _small(box, "")

	# Tools
	_heading(box, "Paint")
	var group := ButtonGroup.new()
	var grid := GridContainer.new()
	grid.columns = 3
	box.add_child(grid)
	for i in LevelDoc.TERRAIN.length():
		var ch := LevelDoc.TERRAIN[i]
		var b := _toggle("%d %s" % [i + 1, TERRAIN_NAMES[ch].trim_suffix(" bridge") if ch == "b" else TERRAIN_NAMES[ch]],
			group, func(): set_tool("terrain", ch))
		b.tooltip_text = "%s (key %d)" % [TERRAIN_NAMES[ch], i + 1]
		b.add_theme_font_size_override("font_size", 12)
		grid.add_child(b)
		_tool_buttons["terrain:" + ch] = b
	var tools := GridContainer.new()
	tools.columns = 2
	box.add_child(tools)
	for t in TOOLS:
		var b := _toggle(TOOL_NAMES[t], group, func(): set_tool(t))
		tools.add_child(b)
		_tool_buttons[t] = b
	var brush_row := HBoxContainer.new()
	box.add_child(brush_row)
	var bl := Label.new()
	bl.text = "Brush"
	brush_row.add_child(bl)
	_brush = OptionButton.new()
	_brush.focus_mode = Control.FOCUS_NONE
	for b in BRUSHES:
		_brush.add_item("%dx%d" % [b, b])
	_brush.item_selected.connect(_on_brush)
	brush_row.add_child(_brush)
	_fill = CheckBox.new()
	_fill.text = "Fill area (F)"
	_fill.focus_mode = Control.FOCUS_NONE
	_fill.tooltip_text = "Terrain and Territory fill the whole connected area instead of painting"
	_fill.toggled.connect(_on_fill)
	brush_row.add_child(_fill)

	# Countries
	_heading(box, "Country")
	var cgroup := ButtonGroup.new()
	var crow := HBoxContainer.new()
	box.add_child(crow)
	for id in 4:
		var b := _toggle(Level.COLORS[id].capitalize(), cgroup, func(): select_country(id))
		b.add_theme_color_override("font_color", UnitLayer.color_of(id).lightened(0.3))
		b.add_theme_color_override("font_pressed_color", UnitLayer.color_of(id).lightened(0.5))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		crow.add_child(b)
		_country_buttons.append(b)
	_country_info = _small(box, "")
	var cgrid := GridContainer.new()
	cgrid.columns = 2
	box.add_child(cgrid)
	_human = CheckBox.new()
	_human.text = "Human player"
	_human.focus_mode = Control.FOCUS_NONE
	_human.tooltip_text = "The country you play. The others are run by the AI"
	_human.toggled.connect(_on_human)
	cgrid.add_child(_human)
	cgrid.add_child(Control.new())
	_style = OptionButton.new()
	_style.focus_mode = Control.FOCUS_NONE
	for s in LevelDoc.STYLES:
		_style.add_item("Random" if s == "" else s.capitalize())
	_style.item_selected.connect(func(i): _set_country("style", LevelDoc.STYLES[i]))
	_field(cgrid, "AI style", _style)
	_funds = _spin(0, 99999, 100, func(v): _set_country("funds", int(v)))
	_field(cgrid, "Funds", _funds)
	_tax = _spin(0, 100, 5, func(v): _set_country("tax", int(v)))
	_field(cgrid, "Tax %", _tax)
	_leader = _spin(1, 99999, 50, func(v): _set_country("leader", int(v)))
	_field(cgrid, "Leader", _leader)
	_strength = _spin(1, 99999, 10, func(v): unit_strength = v)
	_strength.value = unit_strength
	_strength.tooltip_text = "Strength of units placed with the Unit tool"
	_field(cgrid, "New units", _strength)
	_remove = _button("Remove this country", "Removes its castle, villages, units and territory",
		func(): _do(func(): return doc.remove_country(country_id)))
	box.add_child(_remove)

	# Map settings
	_heading(box, "Settings")
	var mgrid := GridContainer.new()
	mgrid.columns = 2
	box.add_child(mgrid)
	_theme = OptionButton.new()
	_theme.focus_mode = Control.FOCUS_NONE
	for n in LevelDoc.THEME_NAMES:
		_theme.add_item(n)
	_theme.item_selected.connect(_on_theme)
	_field(mgrid, "Art", _theme)
	_day_limit = _spin(100, 99999, 100, _on_day_limit)
	_field(mgrid, "Day limit", _day_limit)
	_width = _spin(LevelDoc.MIN_SIZE, LevelDoc.MAX_SIZE, 1, func(_v): pass)
	_field(mgrid, "Width", _width)
	_height = _spin(LevelDoc.MIN_SIZE, LevelDoc.MAX_SIZE, 1, func(_v): pass)
	_field(mgrid, "Height", _height)
	box.add_child(_button("Resize map", "Grow or shrink from the bottom-right corner",
		func(): _do(func(): return doc.resize(int(_width.value), int(_height.value)))))
	_grid = CheckBox.new()
	_grid.text = "Show grid (G)"
	_grid.focus_mode = Control.FOCUS_NONE
	_grid.toggled.connect(_on_grid)
	box.add_child(_grid)

	_heading(box, "Help")
	_small(box, "Left click paints or places. Right-drag or WASD scrolls, the wheel zooms.\n" +
		"Village, Unit: click again to remove. Castle: click where its centre goes; a new country is added if needed.\n" +
		"Each country also starts with one unit outside its castle gate (not shown).")

	_status = Label.new()
	_status.anchor_top = 1.0
	_status.anchor_bottom = 1.0
	_status.anchor_right = 1.0
	_status.offset_left = PANEL_W + 12
	_status.offset_top = -40
	_status.offset_right = -12
	_status.offset_bottom = -6
	_status.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status.add_theme_color_override("font_outline_color", Color.BLACK)
	_status.add_theme_constant_override("outline_size", 5)
	layer.add_child(_status)


func _on_name(t: String) -> void:
	if not _syncing:
		doc.name = t
		unsaved = true


func _on_brush(i: int) -> void:
	brush = BRUSHES[i]
	marks.queue_redraw()


func _on_fill(on: bool) -> void:
	fill = on
	marks.queue_redraw()


func _on_grid(on: bool) -> void:
	show_grid = on
	marks.queue_redraw()


func _on_human(on: bool) -> void:
	if _syncing or not on:
		return
	doc.player = country_id
	unsaved = true
	_sync_ui()
	marks.queue_redraw()


func _on_theme(i: int) -> void:
	if _syncing:
		return
	doc.theme = LevelDoc.THEMES[i]
	unsaved = true
	rebuild()


func _on_day_limit(v: float) -> void:
	if not _syncing:
		doc.day_limit = int(v)
		unsaved = true


## Show the doc and the current tool in the controls (without firing their signals).
func _sync_ui() -> void:
	if doc == null:
		return
	_syncing = true
	if _name.text != doc.name:
		_name.text = doc.name
	_refresh_levels()
	_path_label.text = ("Not saved yet" if doc.path == "" else ProjectSettings.globalize_path(doc.path)) + \
		(" (unsaved changes)" if unsaved else "")
	var key := "terrain:" + brush_char if tool == "terrain" else tool
	_tool_buttons[key].button_pressed = true
	_brush.select(BRUSHES.find(brush))
	_fill.button_pressed = fill
	_country_buttons[country_id].button_pressed = true
	var c := doc.country(country_id)
	var has := not c.is_empty()
	_country_info.text = ("Castle at %d,%d. %d villages, %d extra units." % [c.castle.x, c.castle.y,
		doc.villages.filter(func(v): return v.owner == country_id).size(),
		doc.units.filter(func(u): return u.owner == country_id).size()]) if has else \
		"Not on this map. Use the Castle tool to add it."
	for ctl in [_human, _style, _remove]:
		ctl.disabled = not has
	for spin in [_funds, _tax, _leader]:
		spin.editable = has
	if has:
		_human.button_pressed = doc.player == country_id
		_style.select(LevelDoc.STYLES.find(c.style))
		_funds.value = c.funds
		_tax.value = c.tax
		_leader.value = c.leader
	_theme.select(maxi(0, LevelDoc.THEMES.find(doc.theme)))
	_day_limit.value = doc.day_limit
	_width.value = doc.width
	_height.value = doc.height
	_grid.button_pressed = show_grid
	_syncing = false
	_update_status()


func _say(text: String) -> void:
	_message = text
	_update_status()


func _update_status() -> void:
	if _status == null or doc == null:
		return
	var line := ""
	if doc.in_bounds(_hover):
		line = "%d,%d  %s" % [_hover.x, _hover.y, TERRAIN_NAMES[doc.terrain_at(_hover)]]
		var owner := doc.castle_at(_hover)
		if owner >= 0:
			line += ", %s castle" % Level.COLORS[owner]
		var v := doc.village_at(_hover)
		if v >= 0:
			line += ", %s village" % Level.COLORS[doc.villages[v].owner]
		elif doc.territory_at(_hover) >= 0:
			line += ", %s territory" % Level.COLORS[doc.territory_at(_hover)]
		var u := doc.unit_at(_hover)
		if u >= 0:
			line += ", %s unit %d" % [Level.COLORS[doc.units[u].owner], int(doc.units[u].strength)]
	_status.text = line + ("\n" + _message if _message != "" else "")


func _heading(box: VBoxContainer, text: String) -> void:
	box.add_child(HSeparator.new())
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Color(0.6, 0.85, 0.85))
	box.add_child(l)


func _small(box: Container, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = PANEL_W - 30
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color(0.75, 0.8, 0.85))
	box.add_child(l)
	return l


func _button(text: String, tip: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(on_press)
	return b


func _toggle(text: String, group: ButtonGroup, on_press: Callable) -> Button:
	var b := _button(text, "", on_press)
	b.toggle_mode = true
	b.button_group = group
	b.clip_text = true
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return b


func _spin(lo: float, hi: float, step: float, on_change: Callable) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.custom_arrow_step = step
	s.rounded = true
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.value_changed.connect(on_change)
	return s


func _field(grid: GridContainer, text: String, control: Control) -> void:
	var l := Label.new()
	l.text = text
	grid.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(control)


func _style_box() -> StyleBoxFlat:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.09, 0.12, 0.96)
	bg.border_color = Color(0.6, 0.6, 0.65)
	bg.border_width_right = 1
	bg.set_content_margin_all(10)
	return bg
