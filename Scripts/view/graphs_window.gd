extends PanelContainer
class_name GraphsWindow

## History graphs: a line per country over the game so far (Simulation.history,
## a sample every 10 days), switching between Land, Strength (leader + units) and
## village Population. G or the Graphs button toggles it; the game keeps running.
## When the game ends it opens as the end-of-stage summary: the result, the day,
## and each country's final numbers above the graphs.

const METRICS := [["land", "Land"], ["strength", "Strength"], ["population", "Population"]]
const SUMMARY_COLS := ["Land", "Strength", "Population", "Villages", "Units", ""]

var game                         # Scenes/game.gd
var summary := false             # showing the end-of-stage summary
var _title: Label
var _result: Label
var _table: GridContainer
var _summary_box: VBoxContainer
var _chart: Chart
var _tabs: Array[Button] = []
var _close: Button
var _samples := -1               # history size last drawn


func setup(g) -> void:
	game = g
	custom_minimum_size = Vector2(660, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var box := VBoxContainer.new()
	add_child(box)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 20)
	box.add_child(_title)

	_summary_box = VBoxContainer.new()
	box.add_child(_summary_box)
	_result = Label.new()
	_result.add_theme_font_size_override("font_size", 15)
	_summary_box.add_child(_result)
	_table = GridContainer.new()
	_table.columns = 1 + SUMMARY_COLS.size()
	_table.add_theme_constant_override("h_separation", 22)
	_table.add_theme_constant_override("v_separation", 0)
	_summary_box.add_child(_table)
	_summary_box.add_child(HSeparator.new())

	var tabs := HBoxContainer.new()
	box.add_child(tabs)
	var group := ButtonGroup.new()
	for m in METRICS:
		var b := Button.new()
		b.text = m[1]
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func(): show_metric(m[0]))
		tabs.add_child(b)
		_tabs.append(b)
	_tabs[0].button_pressed = true
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.add_child(gap)
	_close = Button.new()
	_close.focus_mode = Control.FOCUS_NONE
	_close.pressed.connect(hide)
	tabs.add_child(_close)

	_chart = Chart.new()
	_chart.custom_minimum_size = Vector2(640, 260)
	_chart.sim = g.sim
	box.add_child(_chart)

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.09, 0.12, 0.96)
	bg.border_color = Color(0.6, 0.6, 0.65)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(4)
	bg.set_content_margin_all(10)
	add_theme_stylebox_override("panel", bg)
	resized.connect(_place)
	hide()


func toggle() -> void:
	if visible:
		hide()
		return
	_open(game.sim.state != "playing")


## The end-of-stage summary.
func show_summary() -> void:
	_open(true)


func show_metric(key: String) -> void:
	_chart.metric = key
	for i in METRICS.size():
		_tabs[i].set_pressed_no_signal(METRICS[i][0] == key)
	_chart.queue_redraw()


func _open(as_summary: bool) -> void:
	summary = as_summary
	var sim: Simulation = game.sim
	_summary_box.visible = summary
	_chart.custom_minimum_size.y = 200 if summary else 260
	if summary:
		_title.text = "Victory!" if sim.state == "won" else "Defeat"
		_title.add_theme_color_override("font_color", Color(1, 0.85, 0.35) if sim.state == "won" else Color(1, 0.55, 0.45))
		_result.text = "%s, with %d of %d days to spare." % [sim.result, sim.day_limit - sim.day, sim.day_limit] \
			if sim.state == "won" else "%s on day %d of %d." % [sim.result, sim.day, sim.day_limit]
		_fill_table()
		_close.text = "Close (G reopens)"
	else:
		_title.text = "History"
		_title.remove_theme_color_override("font_color")
		_close.text = "Close (G)"
	_refresh()
	show()
	reset_size()
	_place()


func _fill_table() -> void:
	for ch in _table.get_children():
		ch.queue_free()
	var sim: Simulation = game.sim
	_cell("", false)
	for h in SUMMARY_COLS:
		_cell(h, true)
	for k in sim.countries:
		var s := sim.stats(k.id)
		var name := _cell(k.color.capitalize() + (" (you)" if k.id == sim.player else ""), false)
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		name.add_theme_color_override("font_color", Chart.line_color(k.id).lightened(0.2))
		for v in [s.territory, s.leader + s.unit_strength, s.population, s.villages, s.units]:
			_cell("%d" % v if k.alive else "-", true)
		_cell("" if k.alive else "defeated", false).add_theme_color_override("font_color", Color(1, 0.6, 0.5))


func _cell(text: String, right: bool) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if right else HORIZONTAL_ALIGNMENT_LEFT
	_table.add_child(l)
	return l


## Centred over the map area, below the top bar.
func _place() -> void:
	var vp := get_viewport_rect().size
	var top: float = game.HUD_TOP + 4
	var room: float = vp.y - game.HUD_BOTTOM - top
	position = Vector2(maxf(4.0, (vp.x - size.x) / 2), top + maxf(0.0, (room - size.y) / 2))


func _process(_delta: float) -> void:
	if visible and game.sim.history.size() != _samples:
		_refresh()


func _refresh() -> void:
	_samples = game.sim.history.size()
	_chart.queue_redraw()


## Line chart of one history metric, a line per country in its colour.
class Chart extends Control:
	const LEFT := 52.0
	const BOTTOM := 20.0
	const TOP := 22.0
	const RIGHT := 10.0
	var sim: Simulation
	var metric := "land"

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	## Country colour readable on the dark chart (the black country drawn grey-blue).
	static func line_color(id: int) -> Color:
		var col := UnitLayer.color_of(id)
		return Color(0.55, 0.6, 0.85) if col.get_luminance() < 0.3 else col

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		var fs := 12
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.04, 0.09))
		var plot := Rect2(LEFT, TOP, size.x - LEFT - RIGHT, size.y - TOP - BOTTOM)
		var hist := sim.history
		var last_day: int = maxi(hist.back().day if not hist.is_empty() else 0, 10)
		var top_value := 1.0
		for h in hist:
			for v in h[metric]:
				top_value = maxf(top_value, v)
		var step := _nice_step(top_value / 4.0)
		top_value = ceilf(top_value / step) * step
		# Grid and axis labels
		var v := 0.0
		while v <= top_value + 0.001:
			var y := plot.end.y - plot.size.y * v / top_value
			draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), Color(1, 1, 1, 0.12), 1.0)
			var label := _short(v)
			var lw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(font, Vector2(plot.position.x - lw - 6, y + 4), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.75, 0.8, 0.85))
			v += step
		for f in [0.0, 0.25, 0.5, 0.75, 1.0]:
			var x: float = plot.position.x + plot.size.x * f
			var d := "day %d" % roundi(last_day * f) if f == 0.0 else "%d" % roundi(last_day * f)
			var dw := font.get_string_size(d, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(font, Vector2(clampf(x - dw / 2, 0, size.x - dw), size.y - 5), d, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.75, 0.8, 0.85))
		draw_rect(plot, Color(1, 1, 1, 0.3), false, 1.0)
		# Lines, and a legend with the latest values
		var lx := plot.position.x
		for c in sim.countries.size():
			var k := sim.countries[c]
			var col := line_color(k.id)
			var pts := PackedVector2Array()
			for h in hist:
				pts.append(Vector2(plot.position.x + plot.size.x * h.day / last_day,
					plot.end.y - plot.size.y * h[metric][c] / top_value))
			if pts.size() >= 2:
				draw_polyline(pts, Color(0, 0, 0, 0.6), 4.0, true)
				draw_polyline(pts, col, 2.0 if k.id != sim.player else 3.0, true)
			elif pts.size() == 1:
				draw_circle(pts[0], 3.0, col)
			var latest: float = hist.back()[metric][c] if not hist.is_empty() else 0.0
			var text := "%s%s %s" % [k.color.capitalize(), " (you)" if k.id == sim.player else "",
				_short(latest) if k.alive else "(defeated)"]
			draw_rect(Rect2(lx, 5, 12, 12), col)
			draw_string(font, Vector2(lx + 16, 16), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs + 1, Color.WHITE)
			lx += 16 + font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs + 1).x + 18

	## 1, 2 or 5 times a power of ten, at least `raw`.
	func _nice_step(raw: float) -> float:
		var p := pow(10.0, floorf(log(maxf(raw, 1.0)) / log(10.0)))
		for m in [1.0, 2.0, 5.0, 10.0]:
			if m * p >= raw:
				return m * p
		return 10.0 * p

	func _short(v: float) -> String:
		if v >= 10000.0:
			return "%dk" % roundi(v / 1000.0)
		if v >= 1000.0:
			return "%.1fk" % (v / 1000.0)
		return "%d" % roundi(v)
