extends TileMapLayer
class_name TerrainLayer

## Draws the World. Each cell resolves to an LMO tile code (0-255), which
## indexes the theme's 16x16 M sheet. Edge variants come from the autotile
## table built by tools/lmo_map.py; this must match render() there.
##
## Art: <lmo_dir>/extracted/BG/<theme>M.png (made by tools/lmo_extract.py).
## Without it, flat placeholder colours are drawn instead.

const AUTOTILE_PATH := "res://Data/lmo_autotile.json"
const SRC_TILE := 16

## Cells redrawn by refresh() (the minimap follows these)
signal cells_redrawn(cells: Array[Vector2i])

var lmo_dir := "res://DS7E_WIN"
var sheet: Image             # the 256x256 tile sheet in use (LMO art or placeholder)
var _table: Dictionary
var _theme := ""


func build(world: World, theme: String, cell_size: int) -> void:
	_load_table()
	if tile_set == null or theme != _theme:   # the map editor rebuilds often; keep the art loaded
		tile_set = _make_tileset(theme)
		_theme = theme
	scale = Vector2.ONE * cell_size / SRC_TILE
	clear()
	for y in world.height:
		for x in world.width:
			_draw_cell(world, Vector2i(x, y))
	world.dirty.clear()


## Redraw cells the simulation changed.
func refresh(world: World) -> void:
	if world.dirty.is_empty():
		return
	for p in world.dirty:
		_draw_cell(world, p)
	var cells := world.dirty.duplicate()
	world.dirty.clear()
	cells_redrawn.emit(cells)


## Tile code drawn at a cell (as last set by build/refresh).
func drawn_code(p: Vector2i) -> int:
	var a := get_cell_atlas_coords(p)
	return a.y * 16 + a.x


func _draw_cell(world: World, p: Vector2i) -> void:
	var c := code_at(world, p)
	set_cell(p, 0, Vector2i(c % 16, c / 16))


func _load_table() -> void:
	if _table.is_empty():
		_table = JSON.parse_string(FileAccess.get_file_as_string(AUTOTILE_PATH))


## Tile code for one cell. Precedence: override, object, village, castle, terrain.
func code_at(world: World, p: Vector2i) -> int:
	_load_table()
	var i := world.idx(p)
	if world.overrides.has(i):
		return world.overrides[i]
	if world.objects.has(i):
		return world.objects[i]
	if world.village_owner[i] >= 0:
		return 0x08 + world.village_owner[i]
	var co := world.castle_owner[i]
	if co >= 0:
		var off: Vector2i = p - world.castles[co]
		var code = _table.castle[off.y][off.x]
		return 0x14 + co if code == null else int(code)
	var t := world.terrain_at(p)
	if t == "=" and world.durability[i] < Rules.BRIDGE_MAX:
		return 0x7A   # damaged or unfinished bridge
	if _table.same.has(t):
		return int(_table.masks[t].get(str(_mask(world, p, _table.same[t])), _table.default[t]))
	if t == "." and world.territory[i] >= 0:
		return 0x0C + world.territory[i]
	return int(_table.fixed.get(t, 0))


func _mask(world: World, p: Vector2i, same: String) -> int:
	var m := 0
	for n in World.N8.size():
		var q: Vector2i = p + World.N8[n]
		if not world.in_bounds(q) or world.terrain_at(q) in same:
			m |= 1 << n
	return m


func _make_tileset(theme: String) -> TileSet:
	var img := _load_theme(theme)
	sheet = img
	var src := TileSetAtlasSource.new()
	src.texture = ImageTexture.create_from_image(img)
	src.texture_region_size = Vector2i(SRC_TILE, SRC_TILE)
	for code in 256:
		src.create_tile(Vector2i(code % 16, code / 16))
	var ts := TileSet.new()
	ts.tile_size = Vector2i(SRC_TILE, SRC_TILE)
	ts.add_source(src, 0)
	return ts


func _load_theme(theme: String) -> Image:
	var path := ProjectSettings.globalize_path("%s/extracted/BG/%sM.png" % [lmo_dir, theme])
	if FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img and img.get_width() == 256 and img.get_height() == 256:
			return img
	push_warning("TerrainLayer: no LMO art at %s, using placeholder colours" % path)
	return _placeholder_sheet()


static func placeholder_color(code: int) -> Color:
	if code == 0x00: return Color("4f8a3c")
	if code <= 0x04: return Color("2d5a27")
	if code <= 0x07: return Color("5a4632")
	if code <= 0x0b: return Color("c8b48c")
	if code <= 0x0f: return [Color("5fa04a"), Color("a0584a"), Color("b8b8a8"), Color("4a4a5a")][code - 0x0c]
	if code < 0x20: return Color("9a9a9a")
	if code < 0x30: return Color("8a6a3a")
	if code < 0x60: return Color("2f5fa8")
	if code < 0x70: return Color("8a6038")
	if code < 0x7a: return Color("9a9a9a")
	return Color("6a4a2a")


static func _placeholder_sheet() -> Image:
	var img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	for code in 256:
		var r := Rect2i((code % 16) * SRC_TILE, (code / 16) * SRC_TILE, SRC_TILE, SRC_TILE)
		img.fill_rect(r, placeholder_color(code))
		# 1px darker edge so cells stay readable
		var edge := placeholder_color(code).darkened(0.25)
		img.fill_rect(Rect2i(r.position.x, r.position.y + SRC_TILE - 1, SRC_TILE, 1), edge)
		img.fill_rect(Rect2i(r.position.x + SRC_TILE - 1, r.position.y, 1, SRC_TILE), edge)
	return img
