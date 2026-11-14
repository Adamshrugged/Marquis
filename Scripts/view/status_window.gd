extends PanelContainer
class_name StatusWindow

## LMO's status window: every country side by side. Leader strength, area,
## unit strength and count, village population and count, funds, tax rate,
## upkeep paid and strength lost away from base on the last day, plus each AI's
## style and the monsters. Tab or the Status button toggles it;
## the game keeps running. Refreshed once per game day.

const ROWS := [
	["leader", "Leader strength"], ["territory", "Area occupied"], ["unit_strength", "Unit strength"],
	["units", "Units"], ["population", "Village population"], ["villages", "Villages"],
	["funds", "Funds"], ["tax", "Tax rate"], ["upkeep", "Upkeep (funds/day)"], ["decay", "Decay (strength/day)"],
]

var game                         # Scenes/game.gd
var _cells := {}                 # "id:row key" -> Label
var _who := {}                   # country id -> Label (player / AI style / defeated)
var _monsters: Label
var _day: Label
var _shown := []                 # [day, player tax, auto tax] last drawn; tax can change while paused


func setup(g) -> void:
	game = g
	var sim: Simulation = g.sim
	var box := VBoxContainer.new()
	add_child(box)
	var top := HBoxContainer.new()
	box.add_child(top)
	var title := Label.new()
	title.text = "Status"
	title.add_theme_font_size_override("font_size", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	_day = Label.new()
	top.add_child(_day)
	box.add_child(HSeparator.new())

	var grid := GridContainer.new()
	grid.columns = 1 + sim.countries.size()
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 1)
	box.add_child(grid)
	grid.add_child(Label.new())
	for k in sim.countries:
		var head := _cell(grid, k.color.capitalize())
		head.add_theme_font_size_override("font_size", 18)
		head.add_theme_color_override("font_color", UnitLayer.color_of(k.id).lightened(0.4))
		head.add_theme_color_override("font_outline_color", Color.BLACK)
		head.add_theme_constant_override("outline_size", 4)
	grid.add_child(Label.new())
	for k in sim.countries:
		_who[k.id] = _cell(grid, "")
		_who[k.id].add_theme_font_size_override("font_size", 13)
	for r in ROWS:
		var name := Label.new()
		name.text = r[1]
		grid.add_child(name)
		for k in sim.countries:
			_cells["%d:%s" % [k.id, r[0]]] = _cell(grid, "")

	box.add_child(HSeparator.new())
	var bottom := HBoxContainer.new()
	box.add_child(bottom)
	_monsters = Label.new()
	_monsters.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(_monsters)
	var close := Button.new()
	close.text = "Close (Tab)"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(hide)
	bottom.add_child(close)

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.09, 0.12, 0.94)
	bg.border_color = Color(0.6, 0.6, 0.65)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(4)
	bg.set_content_margin_all(10)
	add_theme_stylebox_override("panel", bg)
	resized.connect(_place)
	hide()


## Below the HUD bar, centred between the unit window and the minimap.
func _place() -> void:
	var left := 4.0 + UnitWindow.WIDTH + 8.0
	var right := get_viewport_rect().size.x - 210.0
	position = Vector2(maxf(4.0, left + (right - left - size.x) / 2), game.HUD_TOP)


func _cell(grid: GridContainer, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	grid.add_child(l)
	return l


func toggle() -> void:
	visible = not visible
	if visible:
		_refresh()
		reset_size()
		_place()


func _process(_delta: float) -> void:
	if visible and _state() != _shown:
		_refresh()


func _refresh() -> void:
	var sim: Simulation = game.sim
	_shown = _state()
	_day.text = "Day %d/%d" % [sim.day, sim.day_limit]
	for k in sim.countries:
		var s := sim.stats(k.id)
		var who: Label = _who[k.id]
		if not k.alive:
			who.text = "defeated"
		elif k.id == sim.player:
			who.text = "you"
		else:
			who.text = "AI: %s" % k.style
		who.modulate = Color(1, 0.6, 0.5) if not k.alive else Color(0.8, 0.8, 0.8)
		for r in ROWS:
			var l: Label = _cells["%d:%s" % [k.id, r[0]]]
			if not k.alive:
				l.text = "-"
			elif r[0] == "funds":
				l.text = "$%d" % s.funds
			elif r[0] == "tax":
				l.text = "%d%s" % [k.tax, " auto" if k.auto_tax else ""]
			elif r[0] in ["upkeep", "decay"]:
				l.text = "%d" % k.get(r[0])
			else:
				l.text = "%d" % s[r[0]]
	var m := sim.monster_stats()
	_monsters.text = "Monsters: %d (strength %d)" % [m.count, m.strength] if m.count > 0 else "No monsters"


func _state() -> Array:
	var me: Country = game.sim.country(game.sim.player)
	return [game.sim.day, me.tax, me.auto_tax]
