extends Control
class_name Minimap

## LMO's small map mode: the whole map in the top-right corner.
## Terrain uses the main map's tile codes (each 16x16 tile shrunk to a few pixels),
## kept in sync through TerrainLayer.cells_redrawn. Units are dots in country
## colours (leaders bigger), the white box is what the camera sees.
## Left-click or drag on it to move the camera. M toggles it.

const FIT := 192.0           # longest side of the map, in pixels
const PAD := 3               # frame around the map

var game                     # Scenes/game.gd
var _scale := 4              # pixels per cell
var _tiles: Image            # the tile sheet shrunk to _scale pixels per tile
var _img: Image
var _tex: ImageTexture


func setup(g) -> void:
	game = g
	var w: World = g.sim.world
	_scale = clampi(floori(FIT / maxi(w.width, w.height)), 2, 8)
	_tiles = g.terrain.sheet.duplicate()
	_tiles.resize(16 * _scale, 16 * _scale, Image.INTERPOLATE_LANCZOS)
	_img = Image.create(w.width * _scale, w.height * _scale, false, _tiles.get_format())
	for y in w.height:
		for x in w.width:
			_blit(Vector2i(x, y))
	_tex = ImageTexture.create_from_image(_img)
	g.terrain.cells_redrawn.connect(_on_cells_redrawn)

	custom_minimum_size = Vector2(_img.get_size() + Vector2i(PAD, PAD) * 2)
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	offset_left = -custom_minimum_size.x - 4
	offset_right = -4
	offset_top = g.HUD_TOP
	offset_bottom = g.HUD_TOP + custom_minimum_size.y
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = ""


func _blit(p: Vector2i) -> void:
	var code: int = game.terrain.drawn_code(p)
	_img.blit_rect(_tiles, Rect2i((code % 16) * _scale, (code / 16) * _scale, _scale, _scale), p * _scale)


func _on_cells_redrawn(cells: Array[Vector2i]) -> void:
	for p in cells:
		if game.sim.world.in_bounds(p):
			_blit(p)
	_tex.update(_img)


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	var s := float(_scale)
	var origin := Vector2(PAD, PAD)
	var map := Rect2(origin, Vector2(_img.get_size()))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.05, 0.07))
	draw_texture(_tex, origin)
	# Units: interpolated like the main map
	var t := clampf(game.unit_layer.day_fraction, 0.0, 1.0)
	for u in game.sim.units:
		if u.dead or u.is_leader:
			continue
		var c := origin + (Vector2(u.prev_pos).lerp(Vector2(u.pos), t) + Vector2(0.5, 0.5)) * s
		_dot(c, maxf(1.5, s * 0.4), u.owner)
	for k in game.sim.countries:
		if k.alive:
			_dot(origin + (Vector2(k.leader.pos) + Vector2(0.5, 0.5)) * s, s * 0.5 + 1.0, k.id)
	# What the camera sees
	var cam: Camera2D = game.camera
	var view := get_viewport_rect().size / cam.zoom
	var seen := Rect2(origin + (cam.get_screen_center_position() - view / 2) / game.CELL * s, view / game.CELL * s)
	seen = seen.intersection(map)
	if seen.has_area():
		draw_rect(seen, Color.WHITE, false, 1.0)


## A square dot with a 1px outline (light for the black country, dark otherwise).
func _dot(c: Vector2, r: float, owner: int) -> void:
	var col := UnitLayer.color_of(owner)
	var edge := Color(0.85, 0.85, 0.85) if col.get_luminance() < 0.3 else Color.BLACK
	draw_rect(Rect2(c - Vector2(r + 1, r + 1), Vector2(r + 1, r + 1) * 2), edge)
	draw_rect(Rect2(c - Vector2(r, r), Vector2(r, r) * 2), col)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_jump(event.position)
	elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		_jump(event.position)
	accept_event()


## Centre the camera on the map point under a minimap position.
func _jump(at: Vector2) -> void:
	var w: World = game.sim.world
	var cell := ((at - Vector2(PAD, PAD)) / _scale).clamp(Vector2.ZERO, Vector2(w.width, w.height))
	game.camera.position = cell * game.CELL
