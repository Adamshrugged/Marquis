extends Node2D
class_name UnitLayer

## Draws every unit, sliding smoothly between cells within a day.
##
## Art: <lmo_dir>/extracted/CHR/C_<theme number>M.png, 16x16 frames, 16 per row.
## Rows come in pairs: even row = green | red, odd row = white | black,
## 8 frames per country in each row.
##   rows 0/2/4/6  S, M, L, leader walking: left, up, right, down x 2 frames
##   row 8         standing, facing front: S, M, L, leader x 2 frames
##   row 12        cave monster walking, same direction order (frames 0-7);
##                 frames 12-13 are a sparkle effect, drawn over working units
## Working units keep their own sprite, step in place facing the work, and sparkle.
## Without the art, coloured discs are drawn instead.

const SRC := 16
const TYPES := ["S", "M", "L", "leader"]
const DIR_FRAME := {Vector2i(-1, 0): 0, Vector2i(0, -1): 1, Vector2i(1, 0): 2, Vector2i(0, 1): 3}
const ROW_STAND := 8
const ROW_MONSTER := 12
const SPARKLE_COL := 12
const MONSTER_COLOR := Color("9b4dca")
const COLORS := [Color("3cb043"), Color("d03a2a"), Color("eeeeee"), Color("303040")]

var lmo_dir := "res://DS7E_WIN"
var day_fraction := 0.0      # 0..1 through the current day, for interpolation
var _sim: Simulation
var _cell: int
var _tex: Texture2D


func setup(sim: Simulation, theme: String, cell_size: int) -> void:
	_sim = sim
	_cell = cell_size
	var path := ProjectSettings.globalize_path("%s/extracted/CHR/C_%sM.png" % [lmo_dir, theme.trim_prefix("B_")])
	if FileAccess.file_exists(path):
		_tex = ImageTexture.create_from_image(Image.load_from_file(path))
	else:
		push_warning("UnitLayer: no LMO art at %s, using placeholder discs" % path)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var anim := int(Time.get_ticks_msec() / 250) % 2
	var t := clampf(day_fraction, 0.0, 1.0)
	for u in _sim.units:
		if u.dead:
			continue
		var at := Vector2(u.prev_pos).lerp(Vector2(u.pos), t) * _cell
		var working := u.work > 0 and not u.watching
		if _tex:
			draw_texture_rect_region(_tex, Rect2(at, Vector2(_cell, _cell)), _frame(u, anim))
			if working:
				var spark := Rect2((SPARKLE_COL + anim) * SRC, ROW_MONSTER * SRC, SRC, SRC)
				var size := Vector2(_cell, _cell) * 0.5
				draw_texture_rect_region(_tex, Rect2(at + Vector2(_cell * 0.5, -_cell * 0.15), size), spark)
		else:
			var r: float = _cell * (0.45 if u.is_leader else {"S": 0.25, "M": 0.33, "L": 0.42}[u.size_class()])
			var c := at + Vector2(_cell, _cell) / 2
			draw_circle(c, r + 1.5, Color.BLACK)
			draw_circle(c, r, MONSTER_COLOR if u.owner == Simulation.MONSTER else COLORS[u.owner])
			if working:
				draw_circle(c + Vector2(r, -r), 3.0 + anim, Color.YELLOW)


## The unit's standing frame (monsters: walking towards the viewer), or null without art.
func portrait(u: Unit) -> Texture2D:
	if _tex == null:
		return null
	var at := AtlasTexture.new()
	at.atlas = _tex
	if u.owner == Simulation.MONSTER:
		at.region = Rect2(DIR_FRAME[Vector2i(0, 1)] * 2 * SRC, ROW_MONSTER * SRC, SRC, SRC)
	else:
		var type := TYPES.find("leader" if u.is_leader else u.size_class())
		var row := ROW_STAND + (1 if u.owner >= 2 else 0)
		at.region = Rect2(((u.owner % 2) * 8 + type * 2) * SRC, row * SRC, SRC, SRC)
	return at


## Country colour for markers (monsters purple).
static func color_of(owner: int) -> Color:
	return MONSTER_COLOR if owner == Simulation.MONSTER else COLORS[owner]


func _frame(u: Unit, anim: int) -> Rect2:
	if u.owner == Simulation.MONSTER:
		return Rect2((DIR_FRAME.get(u.facing, 3) * 2 + anim) * SRC, ROW_MONSTER * SRC, SRC, SRC)
	var type := TYPES.find("leader" if u.is_leader else u.size_class())
	var row: int
	var frame: int
	if (u.work > 0 and not u.watching) or u.pos != u.prev_pos or not u.path.is_empty():
		row = type * 2
		frame = DIR_FRAME.get(u.facing, 3) * 2 + anim
	else:
		row = ROW_STAND
		frame = type * 2 + anim
	row += 1 if u.owner >= 2 else 0
	var col: int = (u.owner % 2) * 8 + frame
	return Rect2(col * SRC, row * SRC, SRC, SRC)
