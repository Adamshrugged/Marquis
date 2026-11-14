extends Control

## Battle HUD. A compact top bar in Lord Monarch Online's style (teal framed
## panels, navy value boxes), modelled on LMO's progress and bar-graph windows:
##   Treasury: funds, the tax bar [M] (dragging sets the rate and turns automatic
##     tax off; Auto turns it back on), whether villages are paying. Hovering or
##     dragging the bar previews income and village growth at that rate.
##   Time: days passed / limit with a progress bar, game speed or PAUSED.
##   Your country: leader strength (bar), villages, population, land, units.
##   Countries: a colour block per country with land and strength bars (defeated
##     ones greyed), plus the monsters.
## At the bottom: the orders hint line and a keys line.
## Entry point: show_state(game), called every frame by Scenes/game.gd.

const BAR_HEIGHT := 84
const TEAL := Color(0.13, 0.46, 0.45)
const TEAL_LIGHT := Color(0.56, 0.86, 0.8)
const TEAL_DARK := Color(0.03, 0.15, 0.16)
const NAVY := Color(0.04, 0.06, 0.2)
const CAPTION := Color(0.86, 1.0, 0.95)
const WARN := Color(1, 0.6, 0.5)

var _game                      # Scenes/game.gd, set on the first show_state()
var _status: Label
var _funds: Label
var _tax_slider: HSlider
var _tax_value: Label
var _tax_auto: Button
var _tax_note: Label
var _day: Label
var _day_bar: ProgressBar
var _speed: Label
var _speed_icon: Icon
var _leader_bar: ProgressBar
var _leader: Label
var _villages: Label
var _pop: Label
var _land: Label
var _units: Label
var _strip: CountryStrip
var _preview: PanelContainer     # tax preview under the slider
var _preview_text: Label
var _preview_key := ""
var _hover_x := -1.0             # mouse x over the tax slider, or -1
var _drag_from := -1             # tax rate when a drag on the slider began, or -1


func _ready() -> void:
	var bar := PanelContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.offset_bottom = BAR_HEIGHT
	bar.mouse_filter = Control.MOUSE_FILTER_STOP   # clicks on the bar don't reach the map
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(0.06, 0.25, 0.26)
	frame.border_color = TEAL_DARK
	frame.border_width_bottom = 2
	frame.set_content_margin_all(3)
	bar.add_theme_stylebox_override("panel", frame)
	add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	bar.add_child(row)
	_build_treasury(_section(row, 300))
	_build_time(_section(row, 190))
	_build_country(_section(row, 262))
	var strip_box := _section(row, 0)
	strip_box.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_strip = CountryStrip.new()
	_strip.size_flags_vertical = Control.SIZE_EXPAND_FILL
	strip_box.add_child(_strip)

	# Bottom: hint line and keys line
	_status = Label.new()
	_status.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_status.offset_top = -48
	_status.offset_left = 6
	_status.add_theme_font_size_override("font_size", 14)
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_status.add_theme_color_override("font_outline_color", Color.BLACK)
	_status.add_theme_constant_override("outline_size", 5)
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_status)

	_preview = PanelContainer.new()
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(NAVY, 0.95)
	psb.border_color = TEAL_LIGHT
	psb.set_border_width_all(1)
	psb.set_corner_radius_all(3)
	psb.set_content_margin_all(6)
	_preview.add_theme_stylebox_override("panel", psb)
	_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_text = Label.new()
	_preview_text.add_theme_font_size_override("font_size", 14)
	_shadow(_preview_text)
	_preview.add_child(_preview_text)
	_preview.hide()
	add_child(_preview)


func _build_treasury(box: VBoxContainer) -> void:
	var r1 := _row(box)
	r1.add_child(Icon.new("coin"))
	_caption(r1, "Funds")
	_funds = _value(r1, 16)
	_funds.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var r2 := _row(box)
	_caption(r2, "Tax")
	_tax_slider = HSlider.new()
	_tax_slider.min_value = 0
	_tax_slider.max_value = 100
	_tax_slider.step = 1
	_tax_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tax_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_tax_slider.focus_mode = Control.FOCUS_NONE
	_tax_slider.value_changed.connect(func(v): if _game: _game.sim.set_tax(_game.sim.player, int(v)))
	_tax_slider.mouse_entered.connect(func(): _hover_x = _tax_slider.get_local_mouse_position().x)
	_tax_slider.mouse_exited.connect(func(): _hover_x = -1.0)
	_tax_slider.gui_input.connect(_on_slider_input)
	r2.add_child(_tax_slider)
	_tax_value = _value(r2, 14)
	_tax_value.custom_minimum_size = Vector2(58, 0)
	_tax_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_tax_value.tooltip_text = "Tax rate (A: automatic)"
	_tax_auto = Button.new()
	_tax_auto.text = "Auto"
	_tax_auto.toggle_mode = true
	_tax_auto.focus_mode = Control.FOCUS_NONE
	_tax_auto.tooltip_text = "Adjust the tax rate automatically"
	_tax_auto.add_theme_font_size_override("font_size", 12)
	_tax_auto.toggled.connect(func(on): if _game: _game.sim.set_auto_tax(_game.sim.player, on))
	r2.add_child(_tax_auto)
	_tax_note = _caption(box, "")
	_tax_note.add_theme_font_size_override("font_size", 12)
	_tax_note.clip_text = true


func _build_time(box: VBoxContainer) -> void:
	var r1 := _row(box)
	r1.add_child(Icon.new("hourglass"))
	_caption(r1, "Day")
	_day = _value(r1, 15)
	_day.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_day_bar = _bar(box, Color(0.95, 0.8, 0.35))
	_day_bar.tooltip_text = "Days passed of the stage's limit"
	var r2 := _row(box)
	_speed_icon = Icon.new("speed")
	r2.add_child(_speed_icon)
	_caption(r2, "Speed")
	_speed = _value(r2, 15)
	_speed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_speed.tooltip_text = "Space pauses, +/- change the speed"


func _build_country(box: VBoxContainer) -> void:
	var r1 := _row(box)
	r1.add_child(Icon.new("crown"))
	_caption(r1, "Leader")
	_leader_bar = _bar(r1, Color(0.95, 0.85, 0.4))
	_leader_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_leader_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_leader_bar.tooltip_text = "Your leader's strength, against the strongest leader"
	_leader = _value(r1, 14)
	_leader.custom_minimum_size = Vector2(56, 0)
	_leader.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var r2 := _row(box)
	r2.add_child(Icon.new("house"))
	_caption(r2, "Villages")
	_villages = _value(r2, 14)
	_villages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_caption(r2, "Pop")
	_pop = _value(r2, 14)
	_pop.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var r3 := _row(box)
	r3.add_child(Icon.new("flag"))
	_caption(r3, "Land")
	_land = _value(r3, 14)
	_land.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_caption(r3, "Units")
	_units = _value(r3, 14)
	_units.size_flags_horizontal = Control.SIZE_EXPAND_FILL


# --- Building blocks --------------------------------------------------------

## A teal framed panel with a light bevelled border.
func _section(parent: Control, width: float) -> VBoxContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(width, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = TEAL
	sb.border_color = TEAL_LIGHT
	sb.set_border_width_all(1)
	sb.border_width_top = 2
	sb.border_width_left = 2
	sb.shadow_color = TEAL_DARK
	sb.shadow_size = 1
	sb.shadow_offset = Vector2(1, 1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	p.add_theme_stylebox_override("panel", sb)
	parent.add_child(p)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(box)
	return box


func _row(parent: Control) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 5)
	parent.add_child(r)
	return r


func _caption(parent: Control, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", CAPTION)
	_shadow(l)
	parent.add_child(l)
	return l


## White text in a dark navy inset box.
func _value(parent: Control, font_size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	var sb := StyleBoxFlat.new()
	sb.bg_color = NAVY
	sb.border_color = TEAL_DARK
	sb.set_border_width_all(1)
	sb.border_width_bottom = 0
	sb.border_width_right = 0
	sb.content_margin_left = 5
	sb.content_margin_right = 5
	sb.set_corner_radius_all(2)
	l.add_theme_stylebox_override("normal", sb)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	_shadow(l)
	parent.add_child(l)
	return l


func _bar(parent: Control, col: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.custom_minimum_size = Vector2(0, 8)
	var bg := StyleBoxFlat.new()
	bg.bg_color = NAVY
	bg.border_color = TEAL_DARK
	bg.set_border_width_all(1)
	var fill := StyleBoxFlat.new()
	fill.bg_color = col
	b.add_theme_stylebox_override("background", bg)
	b.add_theme_stylebox_override("fill", fill)
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(b)
	return b


static func _shadow(l: Label) -> void:
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)


# --- Updating ---------------------------------------------------------------

func show_state(game) -> void:
	_game = game
	var sim: Simulation = game.sim
	var me := sim.country(sim.player)
	var s := sim.stats(sim.player)
	if me:
		_tax_slider.set_value_no_signal(me.tax)
		_tax_auto.set_pressed_no_signal(me.auto_tax)
		_tax_value.text = "%d%%%s" % [me.tax, " A" if me.auto_tax else ""]
		_tax_note.text = sim.tax_status(sim.player)
		_tax_note.add_theme_color_override("font_color", WARN if _tax_note.text.begins_with("No tax") else CAPTION)
		_tax_note.tooltip_text = _tax_note.text
	_funds.text = "$%s" % _thousands(int(s.funds))
	_day.text = "%d / %d" % [sim.day, sim.day_limit]
	_day_bar.max_value = maxi(sim.day_limit, 1)
	_day_bar.value = sim.day
	var paused: bool = game.is_paused()
	if sim.state != "playing":
		_speed.text = sim.state.to_upper()
	else:
		_speed.text = "PAUSED" if paused else "%dx" % game.SPEEDS[game.speed_index]
	_speed.add_theme_color_override("font_color", WARN if paused or sim.state == "lost" else Color.WHITE)
	_speed_icon.paused = paused

	var top_leader := 1.0
	for k in sim.countries:
		if k.alive:
			top_leader = maxf(top_leader, k.leader.strength)
	_leader_bar.max_value = top_leader
	_leader_bar.value = s.leader
	_leader.text = "%d" % s.leader
	_villages.text = "%d" % s.villages
	_pop.text = "%d" % s.population
	_land.text = "%d" % s.territory
	_units.text = "%d (%d)" % [s.units, s.unit_strength]
	_strip.update_from(sim)
	_show_preview(sim)

	var keys := "Space pause  +/- speed  WASD scroll  B/C/X plan  Right-click acts  Shift queues  R recall  Home leader  M map  Tab status  G graphs  P playbook  F1-F3 overlays  Esc settings"
	if sim.state != "playing":
		keys = "%s: %s   G graphs and summary   Esc settings" % [sim.state.to_upper(), sim.result]
	var hint: String = game.plans.hint() if game.plans.active() else game.orders.hint()
	_status.text = "%s\n%s" % [hint, keys]


# --- Tax preview ------------------------------------------------------------

func _on_slider_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover_x = event.position.x
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_hover_x = event.position.x
		if event.pressed and _game:
			_drag_from = _game.sim.country(_game.sim.player).tax
		elif not event.pressed:
			_drag_from = -1


## Tax rate the slider would take for a click at x (as Slider does it).
func _rate_at(x: float) -> int:
	var grab := float(_tax_slider.get_theme_icon("grabber").get_width())
	var ratio := clampf((x - grab / 2.0) / maxf(_tax_slider.size.x - grab, 1.0), 0.0, 1.0)
	return roundi(ratio * 100.0)


## While the mouse is on the tax bar: income and growth per day at the rate under
## the cursor (or being dragged to) against the current rate (or the one before the drag).
func _show_preview(sim: Simulation) -> void:
	var me := sim.country(sim.player)
	var dragging := _drag_from >= 0 and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if not dragging:
		_drag_from = -1
	if me == null or not me.alive or (_hover_x < 0 and not dragging):
		_preview.hide()
		_preview_key = ""
		return
	var rate: int = me.tax if dragging else _rate_at(_hover_x)
	var base: int = _drag_from if dragging else me.tax
	var key := "%d|%d|%d|%s" % [sim.day, rate, base, dragging]
	if key != _preview_key:
		_preview_key = key
		var lines := ["At %d%%:  %s" % [rate, _effect(sim, rate)]]
		lines.append("%s %d%%:  %s" % ["Was" if dragging else "Now", base, _effect(sim, base)])
		if me.leader.pos != sim.world.castle_center(me.id):
			lines.append("No tax comes in while the leader is away from the castle")
		lines.append("Low tax: villages grow faster, more units.  High: more funds.  [ ] keys too")
		_preview_text.text = "
".join(lines)
		_preview.reset_size()
	var r := _tax_slider.get_global_rect()
	_preview.position = Vector2(clampf(r.position.x - 40, 4, get_viewport_rect().size.x - _preview.size.x - 4), BAR_HEIGHT + 4)
	_preview.show()


func _effect(sim: Simulation, rate: int) -> String:
	return "%+.1f funds/day, growth %+.1f pop/day" % [sim.tax_income(sim.player, rate), sim.growth_per_day(sim.player, rate)]


static func _thousands(n: int) -> String:
	var t := str(absi(n))
	var out := ""
	while t.length() > 3:
		out = "," + t.right(3) + out
		t = t.left(t.length() - 3)
	return ("-" if n < 0 else "") + t + out


## Small drawn icons (the default font has no symbol glyphs).
class Icon extends Control:
	var kind: String
	var paused := false:
		set(v):
			if v != paused:
				paused = v
				queue_redraw()

	func _init(k: String) -> void:
		kind = k
		custom_minimum_size = Vector2(16, 16)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var o := Color(0.05, 0.08, 0.12)
		match kind:
			"coin":
				draw_circle(Vector2(8, 8), 7.0, o)
				draw_circle(Vector2(8, 8), 6.0, Color(0.98, 0.8, 0.25))
				draw_circle(Vector2(8, 8), 3.5, Color(0.85, 0.62, 0.12))
			"hourglass":
				draw_rect(Rect2(3, 1, 10, 2), o)
				draw_rect(Rect2(3, 13, 10, 2), o)
				draw_colored_polygon(PackedVector2Array([Vector2(4, 3), Vector2(12, 3), Vector2(8, 8)]), Color(0.9, 0.95, 1))
				draw_colored_polygon(PackedVector2Array([Vector2(8, 8), Vector2(12, 13), Vector2(4, 13)]), Color(0.95, 0.8, 0.35))
			"speed":
				if paused:
					draw_rect(Rect2(3, 2, 4, 12), Color(1, 0.6, 0.5))
					draw_rect(Rect2(9, 2, 4, 12), Color(1, 0.6, 0.5))
				else:
					draw_colored_polygon(PackedVector2Array([Vector2(1, 2), Vector2(8, 8), Vector2(1, 14)]), Color(0.7, 1, 0.75))
					draw_colored_polygon(PackedVector2Array([Vector2(8, 2), Vector2(15, 8), Vector2(8, 14)]), Color(0.7, 1, 0.75))
			"crown":
				var pts := PackedVector2Array([Vector2(1, 13), Vector2(1, 4), Vector2(5, 8), Vector2(8, 2),
					Vector2(11, 8), Vector2(15, 4), Vector2(15, 13)])
				draw_colored_polygon(pts, Color(0.98, 0.82, 0.25))
				pts.append(pts[0])
				draw_polyline(pts, o, 1.0)
			"house":
				draw_colored_polygon(PackedVector2Array([Vector2(1, 8), Vector2(8, 1), Vector2(15, 8)]), Color(0.85, 0.3, 0.2))
				draw_rect(Rect2(3, 8, 10, 7), Color(0.95, 0.88, 0.7))
				draw_rect(Rect2(7, 10, 3, 5), Color(0.4, 0.25, 0.1))
			"flag":
				draw_rect(Rect2(3, 1, 2, 14), Color(0.9, 0.9, 0.9))
				draw_colored_polygon(PackedVector2Array([Vector2(5, 2), Vector2(15, 5), Vector2(5, 9)]), Color(0.4, 0.95, 0.5))


## LMO's bar graph: a row per country, colour block, land bar, strength bar.
class CountryStrip extends Control:
	const BLOCK := 22.0
	var _rows: Array = []        # [colour, name, land, strength, alive, is_player]
	var _monsters := {}
	var _key := ""

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS

	func update_from(sim: Simulation) -> void:
		var key := "%d" % sim.day
		if key == _key:
			return
		_key = key
		_rows.clear()
		var tip := []
		for k in sim.countries:
			var s := sim.stats(k.id)
			var strength: float = s.leader + s.unit_strength
			_rows.append([UnitLayer.color_of(k.id), k.color.capitalize(), s.territory, strength, k.alive, k.id == sim.player])
			tip.append("%s%s: land %d, strength %d (leader %d + units %d)%s" % [k.color.capitalize(),
				" (you)" if k.id == sim.player else "", s.territory, strength, s.leader, s.unit_strength,
				"" if k.alive else ", defeated"])
		_monsters = sim.monster_stats()
		if _monsters.count > 0:
			tip.append("Monsters: %d, strength %d" % [_monsters.count, _monsters.strength])
		tooltip_text = "\n".join(tip)
		queue_redraw()

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		var fs := 11
		var head := 13.0
		var w := size.x
		var bar_w := (w - BLOCK - 8 - 8) / 2
		var land_x := BLOCK + 6
		var str_x := land_x + bar_w + 8
		_text(font, Vector2(land_x, 10), "Land", fs, Color(0.86, 1, 0.95))
		_text(font, Vector2(str_x, 10), "Strength", fs, Color(0.86, 1, 0.95))
		if _monsters.get("count", 0) > 0:
			var m := "Monsters %d (%d)" % [_monsters.count, _monsters.strength]
			var mw := font.get_string_size(m, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_rect(Rect2(w - mw - 14, 2, 9, 9), UnitLayer.color_of(Simulation.MONSTER))
			_text(font, Vector2(w - mw - 2, 10), m, fs, Color(0.95, 0.85, 1))
		if _rows.is_empty():
			return
		var max_land := 1.0
		var max_str := 1.0
		for r in _rows:
			max_land = maxf(max_land, r[2])
			max_str = maxf(max_str, r[3])
		var row_h := minf(14.0, (size.y - head) / _rows.size())
		for i in _rows.size():
			var r: Array = _rows[i]
			var y := head + i * row_h
			var alive: bool = r[4]
			var col: Color = r[0] if alive else Color(0.35, 0.38, 0.4)
			var h := row_h - 2
			draw_rect(Rect2(0, y, BLOCK, h), Color(0.03, 0.05, 0.1))
			draw_rect(Rect2(1, y + 1, BLOCK - 2, h - 2), col)
			if r[5]:
				draw_rect(Rect2(0, y, BLOCK, h), Color.WHITE, false, 1.0)
			_bar(Rect2(land_x, y, bar_w, h), r[2] / max_land, col.lightened(0.15), "%d" % r[2], alive)
			_bar(Rect2(str_x, y, bar_w, h), r[3] / max_str, col.lightened(0.15), "%d" % r[3] if alive else "defeated", alive)

	func _bar(r: Rect2, f: float, col: Color, label: String, alive: bool) -> void:
		draw_rect(r, Color(0.04, 0.06, 0.2))
		if alive and f > 0:
			draw_rect(Rect2(r.position, Vector2(maxf(1.0, r.size.x * clampf(f, 0, 1)), r.size.y)), col)
		var font := ThemeDB.fallback_font
		_text(font, r.position + Vector2(4, r.size.y - 2), label, 10,
			Color.WHITE if alive else Color(0.7, 0.7, 0.7))

	func _text(font: Font, at: Vector2, s: String, fs: int, col: Color) -> void:
		draw_string_outline(font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0, 0, 0, 0.9))
		draw_string(font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
