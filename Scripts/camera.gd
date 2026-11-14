extends Camera2D

## Right-drag to scroll (as in Lord Monarch), arrow keys or WASD to pan, the
## mouse at a window edge scrolls too. The wheel zooms toward the cursor, smoothly.
## The view stays over the map (see `bounds`).

@export var pan_speed: float = 600.0
@export var zoom_step: float = 1.15
@export var min_zoom: float = 0.25
@export var max_zoom: float = 3.0
## Scroll when the mouse is near a window edge (a settings menu can turn it off)
@export var edge_scroll := true
@export var edge_margin: float = 12.0
## Over a UI panel, edge scrolling only happens this close to the window edge
const EDGE_HARD := 2.0
## Seconds a zoom step takes
@export var zoom_time: float = 0.12

## The map, in world pixels. The view can't leave it (plus the margins); empty = no limit.
var bounds := Rect2()
## Screen pixels of slack around the map, so each edge can be scrolled clear of the HUD
## (Scenes/game.gd sets them from the panel sizes).
var margin_top := 24.0
var margin_bottom := 24.0
var margin_left := 24.0
var margin_right := 24.0

## Pixels moved during the current/last right-drag. A short one counts as a click.
var drag_distance := 0.0
var _dragging := false
var _target_zoom := 1.0
var _zoom_from := 1.0
var _zoom_t := 1.0               # 0..1 progress of the current zoom
var _anchor_screen := Vector2.ZERO
var _anchor_world := Vector2.ZERO


func _ready() -> void:
	_target_zoom = zoom.x
	_zoom_from = zoom.x


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_RIGHT:
				_dragging = event.pressed
				if event.pressed:
					drag_distance = 0.0
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					zoom_at(zoom_step, event.position)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					zoom_at(1.0 / zoom_step, event.position)
	elif event is InputEventMouseMotion and _dragging:
		drag_distance += event.relative.length()
		_pan(-event.relative / zoom)


## Zoom by a factor, keeping the world point under a screen position where it is.
func zoom_at(factor: float, screen_pos: Vector2) -> void:
	_target_zoom = clampf(_target_zoom * factor, min_zoom, max_zoom)
	_zoom_from = zoom.x
	_zoom_t = 0.0
	_anchor_screen = screen_pos
	_anchor_world = screen_to_world(screen_pos)


func screen_to_world(screen_pos: Vector2) -> Vector2:
	return position + (screen_pos - get_viewport_rect().size / 2) / zoom


func _process(delta: float) -> void:
	var dir := Vector2.ZERO
	# Keys don't scroll while typing in a text field (the playbook editor)
	if not get_viewport().gui_get_focus_owner() is LineEdit:
		dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
		dir += Vector2(
			float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
			float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	if edge_scroll and not _dragging:
		dir += _edge_dir()
	_pan(dir.limit_length(1.0) * pan_speed * delta / zoom.x)

	if _zoom_t < 1.0:
		_zoom_t = minf(1.0, _zoom_t + delta / zoom_time)
		var t := 1.0 - pow(1.0 - _zoom_t, 3.0)      # ease out
		zoom = Vector2.ONE * lerpf(_zoom_from, _target_zoom, t)
		position = _anchor_world - (_anchor_screen - get_viewport_rect().size / 2) / zoom
	_clamp()


## Move the view; a zoom in progress keeps its anchor point moving along.
func _pan(by: Vector2) -> void:
	position += by
	_anchor_world += by


## Direction to scroll when the mouse rests at a window edge. Not over a UI panel
## (the top bar, minimap, buttons...), unless pushed right against the window edge.
func _edge_dir() -> Vector2:
	var win := get_window()
	if not win.has_focus():
		return Vector2.ZERO
	var vp := get_viewport()
	var m := vp.get_mouse_position()
	var r := vp.get_visible_rect()
	if not r.has_point(m):
		return Vector2.ZERO
	if vp.gui_get_hovered_control() != null and r.grow(-EDGE_HARD).has_point(m):
		return Vector2.ZERO
	var d := Vector2.ZERO
	if m.x < r.position.x + edge_margin: d.x = -1
	elif m.x > r.end.x - edge_margin: d.x = 1
	if m.y < r.position.y + edge_margin: d.y = -1
	elif m.y > r.end.y - edge_margin: d.y = 1
	return d


## Keep the view over the map; centre the map on an axis where it's smaller than the view.
func _clamp() -> void:
	if not bounds.has_area():
		return
	var view := get_viewport_rect().size / zoom
	var lo := bounds.position - Vector2(margin_left, margin_top) / zoom
	var hi := bounds.end + Vector2(margin_right, margin_bottom) / zoom
	var p := position
	for a in 2:
		if hi[a] - lo[a] <= view[a]:
			p[a] = (lo[a] + hi[a]) / 2
		else:
			p[a] = clampf(p[a], lo[a] + view[a] / 2, hi[a] - view[a] / 2)
	position = p
