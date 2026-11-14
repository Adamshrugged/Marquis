extends Node2D
class_name MapOverlay

## Information drawn over the map (above terrain, below units), one at a time:
##   Territory (F1): each country's land outlined in its colour, lightly shaded.
##   Tax routes (F2): where the player's tax can come from. Cells walkable from the
##     castle gate are shaded green; own villages get a ring: green = paying, yellow =
##     reachable but not paying yet (routes are rechecked every Rules.TAX_ROUTE_DAYS)
##     or tax stopped, red = cut off now (it may pay until the next recheck). A red X marks what blocks the way next to the
##     reachable area: enemy villages, barricades/rubble, water a bridge would cross.
##     A banner says when no tax comes in at all (leader away, rate too low).
##   Threats (F3): red where enemy units and monsters could strike soon, stronger
##     the more they outweigh your units nearby.
## Pressing the key of the shown overlay (or picking Off) hides it. Redrawn once a
## game day; the minimap is left alone.

enum Kind { OFF, TERRITORY, TAX, THREAT }
const NAMES := ["Off", "Territory", "Tax routes", "Threats"]
const KEYS := [KEY_NONE, KEY_F1, KEY_F2, KEY_F3]
const LEGENDS := [
	"",
	"Territory (F1): each country's land, outlined in its colour",
	"Tax routes (F2): green area reachable from your castle gate. Village rings: green paying,\nyellow not paying yet, red cut off. Red X: what blocks the route (enemy village, barricade, water)",
	"Threats (F3): enemy units and monsters, within %d steps. Redder where they outweigh your units nearby",
]
const THREAT_RADIUS := 5         # steps an enemy's threat reaches
const GUARD_RADIUS := 3          # steps your own units count as protection
const THREAT_SOFTEN := 30.0      # strength added to yours, so tiny enemies show faintly
const PAYING := Color(0.35, 1.0, 0.4)
const PENDING := Color(1.0, 0.85, 0.2)
const CUT := Color(1.0, 0.25, 0.2)

signal changed(kind: int)

var game                         # Scenes/game.gd
var kind := Kind.OFF
var _drawn_day := -1
var _legend: PanelContainer
var _legend_text: Label
var _banner: Label
var _picker: OptionButton


func setup(g) -> void:
	game = g
	var ui: CanvasLayer = g.get_node("UI")
	_legend = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.06, 0.12, 0.85)
	sb.border_color = Color(0.56, 0.86, 0.8, 0.8)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.set_content_margin_all(6)
	_legend.add_theme_stylebox_override("panel", sb)
	_legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_legend.add_child(box)
	_banner = Label.new()
	_banner.add_theme_font_size_override("font_size", 17)
	_banner.add_theme_color_override("font_color", Color(1, 0.55, 0.45))
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_banner)
	_legend_text = Label.new()
	_legend_text.add_theme_font_size_override("font_size", 13)
	_legend_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_legend_text)
	_legend.hide()
	_legend.resized.connect(_place_legend)
	ui.add_child(_legend)

	g.orders.add_bar_label("Map:")
	_picker = OptionButton.new()
	for i in NAMES.size():
		_picker.add_item(NAMES[i], i)
	_picker.tooltip_text = "Map overlay: territory borders (F1), tax routes (F2), threat zones (F3)"
	_picker.focus_mode = Control.FOCUS_NONE
	_picker.item_selected.connect(func(i): set_kind(i))
	g.orders.button_bar.add_child(_picker)


## Show an overlay (Kind), or hide it with Kind.OFF.
func set_kind(k: int) -> void:
	kind = k as Kind
	_picker.select(kind)
	_drawn_day = -1
	visible = kind != Kind.OFF
	queue_redraw()
	_update_legend()
	changed.emit(kind)


## The overlay key: show that overlay, or hide it if it's the one shown.
func toggle(k: int) -> void:
	set_kind(Kind.OFF if kind == k else k)


func _process(_delta: float) -> void:
	if kind != Kind.OFF and game.sim.day != _drawn_day:
		_drawn_day = game.sim.day
		queue_redraw()
		_update_legend()


func _update_legend() -> void:
	if kind == Kind.OFF:
		_legend.hide()
		return
	_legend_text.text = LEGENDS[kind] % THREAT_RADIUS if kind == Kind.THREAT else LEGENDS[kind]
	var note := ""
	if kind == Kind.TAX:
		var sim: Simulation = game.sim
		note = sim.no_tax_reason(sim.player, sim.country(sim.player).tax)
	_banner.text = note
	_banner.visible = note != ""
	_legend.show()
	_legend.reset_size()
	_place_legend()


## Below the top bar, centred between the unit window and the minimap.
func _place_legend() -> void:
	var left := 4.0 + UnitWindow.WIDTH + 8.0
	var right: float = get_viewport_rect().size.x - (game.minimap.size.x + 12.0 if game.minimap.visible else 4.0)
	_legend.position = Vector2(maxf(4.0, left + (right - left - _legend.size.x) / 2), game.HUD_TOP + 4)


func _draw() -> void:
	match kind:
		Kind.TERRITORY: _draw_territory()
		Kind.TAX: _draw_tax()
		Kind.THREAT: _draw_threats()


# --- Territory ----------------------------------------------------------------

## Whose a cell is: territory, or a village or castle on it.
func _land_owner(w: World, i: int) -> int:
	if w.village_owner[i] >= 0:
		return w.village_owner[i]
	if w.castle_owner[i] >= 0:
		return w.castle_owner[i]
	return w.territory[i]


func _draw_territory() -> void:
	var w: World = game.sim.world
	var c: float = game.CELL
	var owners := PackedInt32Array()
	owners.resize(w.width * w.height)
	for i in owners.size():
		owners[i] = _land_owner(w, i)
	for i in owners.size():
		var o := owners[i]
		if o < 0:
			continue
		var col := UnitLayer.color_of(o)
		var at := Vector2(w.pos(i)) * c
		draw_rect(Rect2(at, Vector2(c, c)), Color(col, 0.22))
	# Borders: each cell edge facing different (or no) land, inset so neighbours' lines sit side by side
	var inset := 2.0
	for pass_outline in [true, false]:
		for i in owners.size():
			var o := owners[i]
			if o < 0:
				continue
			var col := UnitLayer.color_of(o)
			var dark := col.get_luminance() < 0.3
			var line: Color
			if pass_outline:
				line = Color(1, 1, 1, 0.75) if dark else Color(0, 0, 0, 0.7)
			else:
				line = col if dark else col.lightened(0.3)
			var width := 6.0 if pass_outline else 3.0
			var p := w.pos(i)
			var a := Vector2(p) * c
			for d in 4:
				var q: Vector2i = p + World.N4[d]
				if w.in_bounds(q) and owners[w.idx(q)] == o:
					continue
				var e := _edge(a, c, d, inset)
				draw_line(e[0], e[1], line, width)


## The inset edge of a cell on side d (N4 order: N, E, S, W).
func _edge(a: Vector2, c: float, d: int, inset: float) -> Array:
	match d:
		0: return [a + Vector2(0, inset), a + Vector2(c, inset)]
		1: return [a + Vector2(c - inset, 0), a + Vector2(c - inset, c)]
		2: return [a + Vector2(0, c - inset), a + Vector2(c, c - inset)]
	return [a + Vector2(inset, 0), a + Vector2(inset, c)]


# --- Tax routes ---------------------------------------------------------------

func _draw_tax() -> void:
	var sim: Simulation = game.sim
	var w := sim.world
	var me := sim.country(sim.player)
	if me == null or not me.alive:
		return
	var c: float = game.CELL
	var reach := sim.tax_reach(me.id)
	var cells: Dictionary = reach.cells
	for i in cells:
		draw_rect(Rect2(Vector2(w.pos(i)) * c, Vector2(c, c)), Color(0.3, 1.0, 0.4, 0.16))
	# The edge of the reachable area
	for pass_outline in [true, false]:
		for i in cells:
			var p := w.pos(i)
			var a := Vector2(p) * c
			for d in 4:
				var q: Vector2i = p + World.N4[d]
				if w.in_bounds(q) and cells.has(w.idx(q)):
					continue
				var e := _edge(a, c, d, 1.0)
				draw_line(e[0], e[1], Color(0, 0, 0, 0.6) if pass_outline else Color(0.75, 1.0, 0.55, 0.9),
					4.0 if pass_outline else 2.0)
	# What stops the route from going further
	var blocks := {}
	for i in cells:
		var p := w.pos(i)
		for d in World.N4:
			var q: Vector2i = p + d
			if not w.in_bounds(q):
				continue
			var j := w.idx(q)
			if cells.has(j) or blocks.has(j) or w.castle_owner[j] >= 0:
				continue
			var vo := w.village_owner[j]
			var t := w.terrain_at(q)
			if (vo >= 0 and vo != me.id) or t in "x*" or (t == "~" and _water_gap(w, q, cells)):
				blocks[j] = true
	for j in blocks:
		var m := (Vector2(w.pos(j)) + Vector2(0.5, 0.5)) * c
		var r := c * 0.3
		for pass_outline in [true, false]:
			var col := Color(0, 0, 0, 0.8) if pass_outline else CUT
			var width := 6.0 if pass_outline else 3.0
			draw_line(m + Vector2(-r, -r), m + Vector2(r, r), col, width)
			draw_line(m + Vector2(-r, r), m + Vector2(r, -r), col, width)
	# Own villages (none pay while tax is stopped, whatever routes were last found)
	var paying := {} if sim.no_tax_reason(me.id, me.tax) != "" else me.connected
	for p in w.villages_of(me.id):
		var i := w.idx(p)
		var col := CUT if not reach.villages.has(i) else (PAYING if paying.has(i) else PENDING)
		var m := (Vector2(p) + Vector2(0.5, 0.5)) * c
		draw_arc(m, c * 0.62, 0, TAU, 24, Color(0, 0, 0, 0.8), 5.0)
		draw_arc(m, c * 0.62, 0, TAU, 24, col, 3.0)


## Water next to walkable land the route doesn't reach: a bridge here would extend it.
func _water_gap(w: World, q: Vector2i, cells: Dictionary) -> bool:
	for d in World.N4:
		var n: Vector2i = q + d
		if w.is_walkable(n) and not cells.has(w.idx(n)) and w.castle_owner[w.idx(n)] < 0:
			return true
	return false


# --- Threats ------------------------------------------------------------------

func _draw_threats() -> void:
	var sim: Simulation = game.sim
	var w := sim.world
	var n := w.width * w.height
	var enemy := PackedFloat32Array()
	enemy.resize(n)
	var mine := PackedFloat32Array()
	mine.resize(n)
	for u in sim.units:
		if u.dead:
			continue
		var in_castle := w.castle_owner[w.idx(u.pos)] == u.owner
		if u.owner == sim.player:
			var s: float = u.strength * (Rules.CASTLE_LEADER_MULT if u.is_leader else Rules.CASTLE_UNIT_MULT) \
				if in_castle else u.strength
			_spread(mine, w, u.pos, GUARD_RADIUS, s)
		elif not in_castle:
			# Leaders and gate guards sitting in their own castle aren't coming for anyone
			_spread(enemy, w, u.pos, THREAT_RADIUS, u.strength)
	var c: float = game.CELL
	for i in n:
		var e := enemy[i]
		if e <= 0.0:
			continue
		var danger := e / (e + mine[i] + THREAT_SOFTEN)
		var col := Color(1.0, 0.65 * (1.0 - danger), 0.1, 0.08 + 0.5 * danger)
		draw_rect(Rect2(Vector2(w.pos(i)) * c, Vector2(c, c)), col)


## Add strength around a cell, fading with steps (Manhattan distance) out to radius.
func _spread(field: PackedFloat32Array, w: World, at: Vector2i, radius: int, strength: float) -> void:
	for dy in range(-radius, radius + 1):
		var y := at.y + dy
		if y < 0 or y >= w.height:
			continue
		var span := radius - absi(dy)
		for dx in range(-span, span + 1):
			var x := at.x + dx
			if x < 0 or x >= w.width:
				continue
			var d := absi(dx) + absi(dy)
			field[y * w.width + x] += strength * (1.0 - float(d) / (radius + 1))
