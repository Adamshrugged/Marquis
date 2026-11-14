extends Node2D

## Runs a Simulation in real time and draws it.
##
## Keys: Space pause, +/- speed, [ ] tax down/up, Home centre on your leader,
## M minimap, Tab status window, G graphs, P playbook, F1/F2/F3 map overlays (territory, tax
## routes, threats), Esc cancels an order, else closes a window, else opens settings.
## Camera (Scripts/camera.gd): WASD/arrows, window edges, right-drag, wheel zoom.
## Orders (Scripts/view/orders_ui.gd): click a unit, click a destination, pick an
## action, or right-click the destination for the obvious action. Shift queues.
## Job board (Scripts/view/plans_ui.gd): B plan villages, C plan clearing, X erase.
## Command line: godot --path . -- --level=<path> [--seed=<n>]

const CELL := 32
const SPEEDS: Array[float] = [2.0, 4.0, 8.0, 16.0, 32.0]
## Screen space the HUD takes: windows sit below HUD_TOP, above HUD_BOTTOM from the bottom
const HUD_TOP := 88
const HUD_BOTTOM := 52

## Level JSON to load
@export_file("*.json") var level_path: String = "res://Levels/sample_valley.json"
@export var speed_index: int = 2

@onready var camera: Camera2D = $Camera2D
@onready var hud: Control = $UI/GuiBattle

var sim: Simulation
var terrain: TerrainLayer
var unit_layer: UnitLayer
var orders: OrdersUI
var plans: PlansUI
var minimap: Minimap
var unit_window: UnitWindow
var status_window: StatusWindow
var overlay: MapOverlay
var graphs: GraphsWindow
var settings: SettingsWindow
var playbook: PlaybookWindow
var paused := false
## Whether the order menu stops time (a setting)
var menu_pauses := true
var _summary_shown := false
var _day_progress := 0.0


func _ready() -> void:
	var seed := 1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--level="):
			level_path = arg.trim_prefix("--level=")
		elif arg.begins_with("--seed="):
			seed = int(arg.trim_prefix("--seed="))
	if get_tree().root.has_meta("level_path"):   # set by the map editor's Play button
		level_path = get_tree().root.get_meta("level_path")
	var level := Level.load_file(level_path)
	if level == null:
		get_tree().quit(1)
		return
	sim = Simulation.new(level, seed)

	terrain = TerrainLayer.new()
	terrain.z_index = -1
	add_child(terrain)
	terrain.build(sim.world, level.theme, CELL)
	overlay = MapOverlay.new()      # above terrain, below units (drawn before them)
	add_child(overlay)
	unit_layer = UnitLayer.new()
	add_child(unit_layer)
	unit_layer.setup(sim, level.theme, CELL)
	orders = OrdersUI.new()
	add_child(orders)
	orders.setup(self)
	plans = PlansUI.new()           # after orders: it sees map clicks first while a tool is out
	add_child(plans)
	plans.setup(self)
	unit_window = UnitWindow.new()
	$UI.add_child(unit_window)
	unit_window.setup(self)
	minimap = Minimap.new()
	$UI.add_child(minimap)
	minimap.setup(self)
	overlay.setup(self)
	orders.add_bar_button("Graphs", "Land, strength and population over time (G)", func(): graphs.toggle())
	orders.add_bar_button("Settings", "Game speed, scrolling, minimap, UI scale (Esc)", func(): settings.toggle())
	status_window = StatusWindow.new()
	$UI.add_child(status_window)
	status_window.setup(self)
	graphs = GraphsWindow.new()
	$UI.add_child(graphs)
	graphs.setup(self)
	playbook = PlaybookWindow.new()
	$UI.add_child(playbook)
	playbook.setup(self)
	settings = SettingsWindow.new()
	$UI.add_child(settings)
	settings.setup(self)            # loads the saved settings and applies them

	camera.bounds = Rect2(0, 0, sim.world.width * CELL, sim.world.height * CELL)
	update_camera_margins()
	center_on_leader()
	hud.show_state(self)


func _process(delta: float) -> void:
	if sim == null:
		return
	if not is_paused() and not (menu_pauses and orders.menu_open) and sim.state == "playing":
		_day_progress += delta * SPEEDS[speed_index]
		while _day_progress >= 1.0:
			_day_progress -= 1.0
			sim.step()
			terrain.refresh(sim.world)
	unit_layer.day_fraction = _day_progress
	hud.show_state(self)
	if sim.state != "playing" and not _summary_shown:
		_summary_shown = true
		orders.cancel()
		status_window.hide()
		settings.hide()
		playbook.hide()
		graphs.show_summary()


## Time is stopped: by the player (Space) or while the settings or playbook are open.
func is_paused() -> bool:
	return paused or settings.visible or playbook.visible


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var me := sim.country(sim.player)
	match event.keycode:
		KEY_SPACE:
			paused = not paused
		KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
			speed_index = mini(speed_index + 1, SPEEDS.size() - 1)
		KEY_MINUS, KEY_KP_SUBTRACT:
			speed_index = maxi(speed_index - 1, 0)
		KEY_BRACKETLEFT:
			if me: sim.set_tax(me.id, me.tax - 5)
		KEY_BRACKETRIGHT:
			if me: sim.set_tax(me.id, me.tax + 5)
		KEY_HOME:
			center_on_leader()
		KEY_M:
			settings.set_option("minimap", not minimap.visible)
		KEY_TAB:
			status_window.toggle()
		KEY_G:
			graphs.toggle()
		KEY_P:
			playbook.toggle()
		KEY_F1, KEY_F2, KEY_F3:
			overlay.toggle(MapOverlay.KEYS.find(event.keycode))
		KEY_ESCAPE:
			# OrdersUI has already taken Esc if there was an order to cancel
			if settings.visible:
				settings.hide()
			elif playbook.visible:
				playbook.hide()
			elif graphs.visible:
				graphs.hide()
			elif status_window.visible:
				status_window.hide()
			else:
				settings.toggle()


func show_minimap(on: bool) -> void:
	minimap.visible = on
	update_camera_margins()


## Let the camera scroll each map edge clear of the HUD: the top bar, the bottom
## button bar and hint lines, the unit window on the left, the minimap on the right.
func update_camera_margins() -> void:
	var bar: Control = orders.button_bar
	camera.margin_top = HUD_TOP + 16
	camera.margin_bottom = HUD_BOTTOM + maxf(bar.size.y, 32.0) + 16
	camera.margin_left = 4 + UnitWindow.WIDTH + 16
	camera.margin_right = (minimap.custom_minimum_size.x + 4 + 16) if minimap.visible else 24.0


func center_on_leader() -> void:
	var me := sim.country(sim.player)
	if me:
		camera.position = (Vector2(me.leader.pos) + Vector2(0.5, 0.5)) * CELL
