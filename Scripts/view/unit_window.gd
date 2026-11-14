extends PanelContainer
class_name UnitWindow

## LMO's unit window: what's under the mouse on the map. A unit (portrait,
## strength graph, what it's doing; for a leader the way back to its castle),
## a village (population), a bridge/barricade/rubble (durability), a castle
## (its leader) or plain land (whose it is). Plus the player's default order.
## Hidden when the mouse is off the map or over another panel.

const WIDTH := 250.0
const STRENGTH_MAX := 65535.0    # top of the (log scale) strength graph
const JOB_WORDS := {"clear": "Clearing land", "build": "Building a village", "attack": "Attacking",
	"march": "Marching on the enemy", "rally": "Gathering to march", "home": "Going home",
	"guard": "Guarding the castle gate", "move": "Moving", "defend": "Defending",
	"reinforce": "Reinforcing", "destroy": "Destroying", "barricade": "Building a barricade",
	"barricade_cont": "Keeping up a barricade", "bridge": "Building a bridge",
	"clear_path": "Clearing a path", "dismantle": "Dismantling",
	"dismantle_cont": "Dismantling (continuous)", "seal": "Sealing a cave"}
const ORDER_WORDS := {"auto": "Auto", "standby": "Standby", "ordered": "Your order", "monster": "Monster"}

var game                         # Scenes/game.gd
var _title: Label
var _portrait: TextureRect
var _value: Label
var _bar: ProgressBar
var _fill: StyleBoxFlat
var _detail: Label
var _default: Label
var _key := ""                   # what's shown, to redo costly parts only when it changes
var _dist_text := ""


func setup(g) -> void:
	game = g
	position = Vector2(4, g.HUD_TOP)
	custom_minimum_size = Vector2(WIDTH, 0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	_title = _label(box, 18)
	_title.add_theme_color_override("font_outline_color", Color.BLACK)
	_title.add_theme_constant_override("outline_size", 4)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(row)
	_portrait = TextureRect.new()
	_portrait.custom_minimum_size = Vector2(48, 48)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_portrait.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_portrait)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(info)
	_value = _label(info, 14)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 10)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill = StyleBoxFlat.new()
	_bar.add_theme_stylebox_override("fill", _fill)
	info.add_child(_bar)
	_detail = _label(info, 14)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var sep := HSeparator.new()
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(sep)
	_default = _label(box, 14)
	hide()


func _label(parent: Control, font_size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _process(_delta: float) -> void:
	var cell := Vector2i((game.get_global_mouse_position() / game.CELL).floor())
	var vp := get_viewport()
	if vp.gui_get_hovered_control() != null or not vp.get_visible_rect().has_point(vp.get_mouse_position()) \
			or not game.sim.world.in_bounds(cell):
		hide()
		_key = ""
		return
	show_cell(cell)


## Fill the window for a map cell and show it.
func show_cell(cell: Vector2i) -> void:
	var sim: Simulation = game.sim
	var w := sim.world
	var i := w.idx(cell)
	var here: Array = sim.units.filter(func(u): return u.pos == cell and not u.dead)
	here.sort_custom(func(a, b): return a.is_leader if a.is_leader != b.is_leader else a.strength > b.strength)
	var key := ""
	if w.village_owner[i] >= 0:
		key = "v%s/%d" % [cell, -1 if here.is_empty() else here[0].id]
		if key != _key:
			_portrait.texture = null if here.is_empty() else game.unit_layer.portrait(here[0])
		_show_village(cell, here)
	elif not here.is_empty():
		key = "u%d@%s" % [here[0].id, here[0].pos]
		if key != _key:
			_portrait.texture = game.unit_layer.portrait(here[0])
		_show_unit(here[0], here.size() - 1)
	elif w.castle_owner[i] >= 0:
		var k := sim.country(w.castle_owner[i])
		key = "c%d" % k.id
		if key != _key:
			_portrait.texture = game.unit_layer.portrait(k.leader) if k.alive else null
		_title_for("%s castle" % k.color.capitalize(), k.id)
		_set_bar("Leader strength %d" % k.leader.strength, _log_fill(k.leader.strength), k.id)
		var at_home := k.leader.pos == w.castle_center(k.id)
		_detail.text = "The leader is in the castle: it hits out at strength / 4" if at_home \
			else "The leader is away"
	else:
		key = "t%s" % cell
		_show_land(cell)
	if key != _key and key.begins_with("t"):
		_portrait.texture = null
	_portrait.visible = _portrait.texture != null
	_key = key
	var me := sim.country(sim.player)
	var d := ""
	for o in Simulation.DEFAULT_ORDERS:
		if o[0] == me.default_order:
			d = o[1]
	_default.text = "Default order: %s" % d
	show()
	reset_size()


func _show_unit(u: Unit, others: int) -> void:
	var sim: Simulation = game.sim
	var kind := "leader" if u.is_leader else "unit (%s)" % u.size_class()
	_title_for("Monster" if u.owner == Simulation.MONSTER else "%s %s" % [sim.owner_name(u.owner), kind], u.owner)
	_set_bar("Strength %d" % u.strength, _log_fill(u.strength), u.owner)
	var lines := []
	lines.append(_doing(u))
	if u.is_leader:
		var key := "u%d@%s" % [u.id, u.pos]
		if key != _key:
			var home := sim.world.castle_center(u.owner)
			var dist := sim.distance(u, home)
			_dist_text = "In the castle" if u.pos == home else \
				("Can't reach the castle" if dist < 0 else "Castle: %d steps away" % dist)
		lines.append(_dist_text)
	elif u.owner != Simulation.MONSTER:
		lines.append("Order: %s" % ORDER_WORDS.get(u.order, u.order))
		if u.order == "auto" and u.line >= -1:
			lines.append(u.line_text)
	if others > 0:
		lines.append("+%d more unit%s here" % [others, "" if others == 1 else "s"])
	_detail.text = "\n".join(lines)


func _doing(u: Unit) -> String:
	if u.is_leader:
		return "Moving" if not u.path.is_empty() else "Waiting"
	if u.job != "":
		var words: String = JOB_WORDS.get(u.job, u.job.capitalize())
		if u.watching:
			words += " (watching)"
		elif u.work > 0:
			words += " (working)"
		return words
	if u.order == "standby":
		return "Standing by"
	return "Roaming" if u.owner == Simulation.MONSTER else "Idle"


func _show_village(cell: Vector2i, here: Array) -> void:
	var sim: Simulation = game.sim
	var w := sim.world
	var i := w.idx(cell)
	var owner := w.village_owner[i]
	var cap := w.village_cap(cell)
	_title_for("%s village" % sim.owner_name(owner), owner)
	_set_bar("Population %d (full at %d)" % [w.village_pop[i], cap], minf(1.0, w.village_pop[i] / cap), owner)
	var lines := []
	for u in here.slice(0, 5):
		var kind: String = "leader" if u.is_leader else ("monster" if u.owner == Simulation.MONSTER else u.size_class())
		lines.append("%s %s %d: %s" % [sim.owner_name(u.owner), kind, u.strength, _doing(u).to_lower()])
	if here.size() > 5:
		lines.append("+%d more" % (here.size() - 5))
	_detail.text = "No units here" if lines.is_empty() else "\n".join(lines)


func _show_land(cell: Vector2i) -> void:
	var sim: Simulation = game.sim
	var w := sim.world
	var i := w.idx(cell)
	var t := w.terrain_at(cell)
	var name: String = World.TERRAIN_NAMES.get(t, "Unknown")
	var land := w.territory[i]
	_title_for(name, -1)
	if World.COUNTERS.has(t):
		var c: Array = World.COUNTERS[t]
		_set_bar("%s %d" % [c[0], w.durability[i]], minf(1.0, float(w.durability[i]) / c[1]), -1)
	else:
		_value.hide()
		_bar.hide()
	_detail.text = "%s land" % sim.owner_name(land) if land >= 0 else "No one's land"


func _title_for(text: String, owner: int) -> void:
	_title.text = text
	_title.add_theme_color_override("font_color", Color.WHITE if owner < 0 else UnitLayer.color_of(owner).lightened(0.4))


func _set_bar(text: String, fill: float, owner: int) -> void:
	_value.text = text
	_value.show()
	_bar.value = clampf(fill, 0.0, 1.0) * 100.0
	_bar.show()
	_fill.bg_color = Color("c8b060") if owner < 0 else UnitLayer.color_of(owner)


## Strength graph: log scale, so S, M and L units all show.
func _log_fill(strength: float) -> float:
	return log(maxf(strength, 1.0) + 1.0) / log(STRENGTH_MAX + 1.0)
