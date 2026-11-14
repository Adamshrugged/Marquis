extends PanelContainer
class_name SettingsWindow

## Settings, saved to `file` (user://settings.cfg) as soon as they change and
## loaded at start: game speed at start, whether the order menu pauses the game,
## edge scrolling, the minimap, UI scale (the window's content scale factor; capped
## so the HUD still fits the window). Esc with nothing to cancel opens it, as does
## the Settings button. The game pauses while it's open (Scenes/game.gd).

## Where settings are kept (tests point it elsewhere before the game starts)
static var file := "user://settings.cfg"
const SCALES: Array[float] = [1.0, 1.25, 1.5]
## The HUD needs at least this much room, in UI pixels
const MIN_UI := Vector2(1000, 560)

var game                         # Scenes/game.gd
var speed_index := 2
var menu_pauses := true
var edge_scroll := true
var minimap := true
var ui_scale := 1.0
var _speed: OptionButton
var _menu_pauses: CheckButton
var _edge: CheckButton
var _minimap: CheckButton
var _scale: OptionButton
var _scale_note: Label


func setup(g) -> void:
	game = g
	speed_index = g.speed_index
	mouse_filter = Control.MOUSE_FILTER_STOP
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	var title := Label.new()
	title.text = "Settings"
	title.add_theme_font_size_override("font_size", 20)
	box.add_child(title)
	box.add_child(HSeparator.new())
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 8)
	box.add_child(grid)

	_speed = OptionButton.new()
	for i in g.SPEEDS.size():
		_speed.add_item("%dx (%d days a second)" % [g.SPEEDS[i], g.SPEEDS[i]], i)
	_speed.item_selected.connect(func(i): set_option("speed", i))
	_row(grid, "Game speed at start", _speed, "Also sets the speed now. +/- change it during play")
	_menu_pauses = _check(grid, "Order menu pauses the game", "menu_pauses", "Time stops while the action menu is open")
	_edge = _check(grid, "Edge scrolling", "edge_scroll", "Scroll when the mouse is at a window edge")
	_minimap = _check(grid, "Show minimap", "minimap", "M toggles it too")
	_scale = OptionButton.new()
	for s in SCALES:
		_scale.add_item("%d%%" % roundi(s * 100))
	_scale.item_selected.connect(func(i): set_option("ui_scale", SCALES[i]))
	_row(grid, "UI scale", _scale, "Makes the whole view bigger (the map too)")
	_scale_note = Label.new()
	_scale_note.add_theme_font_size_override("font_size", 12)
	_scale_note.add_theme_color_override("font_color", Color(0.75, 0.8, 0.85))
	box.add_child(_scale_note)

	box.add_child(HSeparator.new())
	var bottom := HBoxContainer.new()
	box.add_child(bottom)
	var saved := Label.new()
	saved.text = "Saved automatically. The game is paused."
	saved.add_theme_font_size_override("font_size", 12)
	saved.add_theme_color_override("font_color", Color(0.75, 0.8, 0.85))
	saved.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(saved)
	var editor := Button.new()
	editor.text = "Map editor"
	editor.tooltip_text = "Leave this game and edit its map"
	editor.focus_mode = Control.FOCUS_NONE
	editor.pressed.connect(_open_editor)
	bottom.add_child(editor)
	var close := Button.new()
	close.text = "Close (Esc)"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(hide)
	bottom.add_child(close)

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.09, 0.12, 0.96)
	bg.border_color = Color(0.6, 0.6, 0.65)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(4)
	bg.set_content_margin_all(12)
	add_theme_stylebox_override("panel", bg)
	resized.connect(_place)
	get_window().size_changed.connect(_apply_scale)
	hide()
	load_settings()


func _row(grid: GridContainer, text: String, control: Control, tip: String) -> void:
	var l := Label.new()
	l.text = text
	l.tooltip_text = tip
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	grid.add_child(l)
	control.tooltip_text = tip
	control.focus_mode = Control.FOCUS_NONE
	grid.add_child(control)


func _check(grid: GridContainer, text: String, key: String, tip: String) -> CheckButton:
	var b := CheckButton.new()
	b.toggled.connect(func(on): set_option(key, on))
	_row(grid, text, b, tip)
	return b


func _open_editor() -> void:
	get_tree().root.set_meta("editor_level", game.level_path)
	get_tree().change_scene_to_file("res://Scenes/Editor.tscn")


func toggle() -> void:
	visible = not visible
	if visible:
		_sync()
		reset_size()
		_place()


func _place() -> void:
	var vp := get_viewport_rect().size
	position = ((vp - size) / 2).max(Vector2(4, game.HUD_TOP))


## Read the file (missing keys keep their defaults) and apply everything.
func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(file) == OK:
		speed_index = clampi(cfg.get_value("game", "speed", speed_index), 0, game.SPEEDS.size() - 1)
		menu_pauses = cfg.get_value("game", "menu_pauses", menu_pauses)
		edge_scroll = cfg.get_value("view", "edge_scroll", edge_scroll)
		minimap = cfg.get_value("view", "minimap", minimap)
		ui_scale = cfg.get_value("view", "ui_scale", ui_scale)
	game.speed_index = speed_index
	game.menu_pauses = menu_pauses
	game.camera.edge_scroll = edge_scroll
	game.show_minimap(minimap)
	_apply_scale()
	_sync()


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("game", "speed", speed_index)
	cfg.set_value("game", "menu_pauses", menu_pauses)
	cfg.set_value("view", "edge_scroll", edge_scroll)
	cfg.set_value("view", "minimap", minimap)
	cfg.set_value("view", "ui_scale", ui_scale)
	cfg.save(file)


## Change one setting, apply it now and save.
func set_option(key: String, value) -> void:
	match key:
		"speed":
			speed_index = value
			game.speed_index = value
		"menu_pauses":
			menu_pauses = value
			game.menu_pauses = value
		"edge_scroll":
			edge_scroll = value
			game.camera.edge_scroll = value
		"minimap":
			minimap = value
			game.show_minimap(value)
		"ui_scale":
			ui_scale = value
			_apply_scale()
	save_settings()
	_sync()


## The chosen scale, or less if the HUD wouldn't fit the window at that size.
func _apply_scale() -> void:
	var win := get_window()
	var fit := minf(win.size.x / MIN_UI.x, win.size.y / MIN_UI.y)
	var used := clampf(minf(ui_scale, fit), 1.0, ui_scale)
	win.content_scale_factor = used
	if _scale_note:
		_scale_note.text = "" if is_equal_approx(used, ui_scale) else \
			"UI scale limited to %d%% to fit the window; a bigger window allows more" % roundi(used * 100)
		_scale_note.visible = _scale_note.text != ""


## Show the current values without triggering changes.
func _sync() -> void:
	_speed.select(speed_index)
	_menu_pauses.set_pressed_no_signal(menu_pauses)
	_edge.set_pressed_no_signal(edge_scroll)
	_minimap.set_pressed_no_signal(minimap)
	var best := 0
	for i in SCALES.size():
		if is_equal_approx(SCALES[i], ui_scale):
			best = i
	_scale.select(best)
