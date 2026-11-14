extends PanelContainer
class_name PlaybookWindow

## The player's playbooks (Docs/RULES.md, Playbooks). Units tab: what idle Auto units
## do, a line per rule (on/off, size range, action, distance, move up/down, delete),
## checked from the top; the last line, go home, is fixed. Also the default order
## for new units and presets to start from. Tax tab: the automatic tax rules.
## Every change applies at once. P or the Playbook button toggles it; the game
## pauses while it's open (Scenes/game.gd).

const PRESETS := [["", "Your default"], ["balanced", "AI: balanced"], ["aggressive", "AI: aggressive"],
	["builder", "AI: builder"], ["turtle", "AI: turtle"]]
const NO_DISTANCE := ["army", "home"]

var game                         # Scenes/game.gd
var _lines: Array = []           # the unit playbook being edited (copies)
var _tax: Dictionary = {}
var _rows: VBoxContainer
var _tax_rows: VBoxContainer
var _add: Button
var _add_tax: Button
var _default: OptionButton
var _preset: OptionButton
var _auto_tax: CheckBox
var _otherwise: SpinBox


func setup(g) -> void:
	game = g
	mouse_filter = Control.MOUSE_FILTER_STOP
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	var title := Label.new()
	title.text = "Playbook"
	title.add_theme_font_size_override("font_size", 20)
	box.add_child(title)
	var tabs := TabContainer.new()
	tabs.focus_mode = Control.FOCUS_NONE
	box.add_child(tabs)
	_build_units(tabs)
	_build_tax(tabs)

	var bottom := HBoxContainer.new()
	box.add_child(bottom)
	var note := _note(bottom, "Changes apply at once. The game is paused.")
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var close := Button.new()
	close.text = "Close (Esc)"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(hide)
	bottom.add_child(close)

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.09, 0.12, 0.96)
	bg.border_color = Color(0.6, 0.6, 0.65)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(4)
	bg.set_content_margin_all(12)
	add_theme_stylebox_override("panel", bg)
	resized.connect(_place)
	hide()


func _build_units(tabs: TabContainer) -> void:
	var box := VBoxContainer.new()
	box.name = "Units"
	box.add_theme_constant_override("separation", 6)
	tabs.add_child(box)
	_note(box, "Idle Auto units check these lines from the top and do the first one that finds work.")
	var top := HBoxContainer.new()
	box.add_child(top)
	_label(top, "New units:")
	_default = OptionButton.new()
	_default.tooltip_text = "Default order: what units do when they leave a village"
	_default.focus_mode = Control.FOCUS_NONE
	for d in Simulation.DEFAULT_ORDERS:
		_default.add_item(d[1])
	_default.item_selected.connect(func(i): _me().default_order = Simulation.DEFAULT_ORDERS[i][0])
	top.add_child(_default)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(gap)
	_preset = OptionButton.new()
	_preset.focus_mode = Control.FOCUS_NONE
	for p in PRESETS:
		_preset.add_item(p[1])
	top.add_child(_preset)
	_button(top, "Load", "Replace both playbooks with this preset", func():
		game.sim.reset_playbooks(game.sim.player, PRESETS[_preset.selected][0])
		_sync())

	var head := HBoxContainer.new()
	box.add_child(head)
	for h in [["On", 30], ["#", 24], ["Size from", 64], ["to", 64], ["Action", 150], ["Within (steps)", 110]]:
		var l := _label(head, h[0])
		l.custom_minimum_size = Vector2(h[1], 0)
		l.add_theme_font_size_override("font_size", 12)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(620, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows)
	var foot := HBoxContainer.new()
	box.add_child(foot)
	_add = _button(foot, "Add line", "Add a line at the bottom", func():
		_lines.append(Playbook.line("clear", 4))
		_commit_units(true))
	_note(foot, "Size: unit strength (blank 'to' = no limit). Blank distance = anywhere.")


func _build_tax(tabs: TabContainer) -> void:
	var box := VBoxContainer.new()
	box.name = "Tax"
	box.add_theme_constant_override("separation", 6)
	tabs.add_child(box)
	_auto_tax = CheckBox.new()
	_auto_tax.text = "Automatic tax (moving the tax bar turns it off)"
	_auto_tax.focus_mode = Control.FOCUS_NONE
	_auto_tax.toggled.connect(func(on): game.sim.set_auto_tax(game.sim.player, on))
	box.add_child(_auto_tax)
	_note(box, "Checked from the top at each collection (every %d days). Rates run 0-%d.\nFunds saved for a bridge don't count." % [Rules.CELL_DAYS, Rules.TAX_MAX])
	_tax_rows = VBoxContainer.new()
	box.add_child(_tax_rows)
	var other := HBoxContainer.new()
	box.add_child(other)
	_label(other, "Otherwise: tax")
	_otherwise = _spin(other, 0, Rules.TAX_MAX, "")
	_otherwise.value_changed.connect(func(v):
		_tax.otherwise = int(v)
		_commit_tax(false))
	_add_tax = _button(box, "Add line", "Add a line above 'otherwise'", func():
		var last: int = _tax.lines.back().below if not _tax.lines.is_empty() else 0
		_tax.lines.append({"below": last + 512, "tax": 10})
		_commit_tax(true))


# --- Showing and editing ------------------------------------------------------

func toggle() -> void:
	visible = not visible
	if visible:
		_sync()
		reset_size()
		_place()


func _place() -> void:
	var vp := get_viewport_rect().size
	position = ((vp - size) / 2).max(Vector2(4, game.HUD_TOP))


func _me() -> Country:
	return game.sim.country(game.sim.player)


## Copy the country's playbooks into the editor and redraw it.
func _sync() -> void:
	var me := _me()
	_lines = me.playbook.duplicate(true)
	_tax = me.tax_book.duplicate(true)
	for i in Simulation.DEFAULT_ORDERS.size():
		if Simulation.DEFAULT_ORDERS[i][0] == me.default_order:
			_default.select(i)
	_auto_tax.set_pressed_no_signal(me.auto_tax)
	_otherwise.set_value_no_signal(_tax.otherwise)
	_redraw_units()
	_redraw_tax()


func _commit_units(redraw: bool) -> void:
	game.sim.set_playbook(game.sim.player, _lines)
	# Show what the units follow: Playbook.sanitize may have corrected a line
	# (sizes below 0, "to" below "from")
	var kept := _me().playbook
	if kept != _lines:
		_lines = kept.duplicate(true)
		redraw = true
	if redraw:
		_redraw_units()


func _commit_tax(redraw: bool) -> void:
	game.sim.set_tax_book(game.sim.player, _tax)
	_auto_tax.set_pressed_no_signal(true)
	if redraw:
		_redraw_tax()


func _redraw_units() -> void:
	for c in _rows.get_children():
		c.queue_free()
	for n in _lines.size():
		_unit_row(n)
	var last := HBoxContainer.new()
	_rows.add_child(last)
	var fixed := _label(last, "      Otherwise: go home (to the nearest own village and wait)")
	fixed.add_theme_color_override("font_color", Color(0.75, 0.8, 0.85))
	_add.disabled = _lines.size() >= Playbook.MAX_LINES


func _unit_row(n: int) -> void:
	var l: Dictionary = _lines[n]
	var row := HBoxContainer.new()
	_rows.add_child(row)
	var on := CheckBox.new()
	on.button_pressed = l.on
	on.focus_mode = Control.FOCUS_NONE
	on.custom_minimum_size = Vector2(30, 0)
	on.tooltip_text = "Switch the line off without deleting it"
	on.toggled.connect(func(v):
		l.on = v
		_commit_units(false))
	row.add_child(on)
	_label(row, "%d" % (n + 1)).custom_minimum_size = Vector2(24, 0)
	_number(row, l.min, "0", func(v): l.min = v)
	_number(row, l.max, "no limit", func(v): l.max = v)
	var action := OptionButton.new()
	action.custom_minimum_size = Vector2(150, 0)
	action.focus_mode = Control.FOCUS_NONE
	for i in Playbook.ACTIONS.size():
		action.add_item(Playbook.ACTIONS[i][1])
		if Playbook.ACTIONS[i][0] == l.action:
			action.select(i)
	row.add_child(action)
	var dist := OptionButton.new()
	dist.custom_minimum_size = Vector2(110, 0)
	dist.focus_mode = Control.FOCUS_NONE
	for d in Playbook.DISTANCES:
		dist.add_item("anywhere" if d < 0 else "%d" % d)
	var at := Playbook.DISTANCES.find(l.dist)
	if at < 0:
		dist.add_item("%d" % l.dist)    # not one of the choices (a style's defend range)
		at = dist.item_count - 1
	dist.select(at)
	dist.disabled = l.action in NO_DISTANCE
	dist.item_selected.connect(func(i):
		l.dist = Playbook.DISTANCES[i] if i < Playbook.DISTANCES.size() else l.dist
		_commit_units(false))
	row.add_child(dist)
	action.item_selected.connect(func(i):
		l.action = Playbook.ACTIONS[i][0]
		dist.disabled = l.action in NO_DISTANCE
		_commit_units(false))
	var up := _button(row, "Up", "Move the line up", func(): _move(n, -1))
	up.disabled = n == 0
	var down := _button(row, "Down", "Move the line down", func(): _move(n, 1))
	down.disabled = n == _lines.size() - 1
	_button(row, "X", "Delete the line", func():
		_lines.remove_at(n)
		_commit_units(true))


func _move(n: int, by: int) -> void:
	var m := n + by
	if m < 0 or m >= _lines.size():
		return
	var l = _lines[n]
	_lines[n] = _lines[m]
	_lines[m] = l
	_commit_units(true)


func _redraw_tax() -> void:
	for c in _tax_rows.get_children():
		c.queue_free()
	for n in _tax.lines.size():
		var l: Dictionary = _tax.lines[n]
		var row := HBoxContainer.new()
		_tax_rows.add_child(row)
		_label(row, "%d.  If funds are below" % (n + 1))
		var below := _spin(row, 0, 1000000, "")
		below.step = 50
		below.value = l.below
		below.value_changed.connect(func(v):
			l.below = int(v)
			_commit_tax(false))
		var how := OptionButton.new()
		how.focus_mode = Control.FOCUS_NONE
		how.add_item("set tax to")
		how.add_item("keep the rate")
		how.select(1 if l.tax < 0 else 0)
		row.add_child(how)
		var rate := _spin(row, 0, Rules.TAX_MAX, "")
		rate.value = maxi(l.tax, 0)
		rate.visible = l.tax >= 0
		rate.value_changed.connect(func(v):
			l.tax = int(v)
			_commit_tax(false))
		how.item_selected.connect(func(i):
			l.tax = -1 if i == 1 else int(rate.value)
			rate.visible = i == 0
			_commit_tax(false))
		_button(row, "X", "Delete the line", func():
			_tax.lines.remove_at(n)
			_commit_tax(true))
	_add_tax.disabled = _tax.lines.size() >= Playbook.MAX_TAX_LINES


# --- Building blocks --------------------------------------------------------

func _label(parent: Control, text: String) -> Label:
	var l := Label.new()
	l.text = text
	parent.add_child(l)
	return l


func _note(parent: Control, text: String) -> Label:
	var l := _label(parent, text)
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color(0.75, 0.8, 0.85))
	return l


func _button(parent: Control, text: String, tip: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func _spin(parent: Control, lo: float, hi: float, suffix: String) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.suffix = suffix
	s.custom_minimum_size = Vector2(90, 0)
	parent.add_child(s)
	return s


## A whole-number field; blank means -1 (no limit). set_value gets the number.
func _number(parent: Control, value: int, blank: String, set_value: Callable) -> void:
	var e := LineEdit.new()
	e.custom_minimum_size = Vector2(64, 0)
	e.placeholder_text = blank
	e.text = "" if value < 0 or (value == 0 and blank == "0") else "%d" % value
	var apply := func(_t = null):
		var t := e.text.strip_edges()
		set_value.call(int(t) if t.is_valid_int() else -1)
		e.text = t if t.is_valid_int() else ""
		_commit_units(false)
	e.text_submitted.connect(func(t):
		apply.call(t)
		e.release_focus())
	e.focus_exited.connect(apply)
	parent.add_child(e)
