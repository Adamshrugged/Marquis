extends Node2D
class_name PlansUI

## The job board [G, modern]: mark what should happen and Auto units do it.
##   B  Build tool: click a cell for one village, or drag a box to fill it with the
##      densest layout (villages two cells apart). Woods under a village get cleared first.
##   C  Clear tool: click or drag over woods to have them cleared.
##   X  Erase tool: click or drag to take plans off the board.
##   1/2/3 while a tool is out: priority of what you mark next (Normal, High, Urgent).
##      Marking over plans of the same kind changes their priority.
##   Right-click, Esc or the tool's key again puts the tool away.
## Buttons for the three tools sit bottom left. Plans are always drawn on the map
## (above terrain, below units): a house outline for villages, hatching for
## clearing, coloured by priority, with a dot once a unit is on its way.

enum Tool { NONE, BUILD, CLEAR, ERASE }
const TOOL_KEYS := {KEY_B: Tool.BUILD, KEY_C: Tool.CLEAR, KEY_X: Tool.ERASE}
const TOOL_LABELS := ["", "Build", "Clear", "Erase"]
const TOOL_TIPS := ["",
	"Plan villages: click a cell, or drag a box to lay out villages (B)",
	"Plan clearing: click or drag over woods (C)",
	"Erase plans: click or drag (X)"]
const PRIORITY_COLORS := [Color(0.85, 0.95, 1.0), Color(1.0, 0.72, 0.25), Color(1.0, 0.35, 0.3)]
const ERASE_COLOR := Color(1.0, 0.3, 0.25)

var game                          # Scenes/game.gd
var tool := Tool.NONE
var priority := 0
var _buttons: Array[Button] = []
var _left_down := false
var _drag_start := Vector2i(-1, -1)
var _hover := Vector2i(-1, -1)
var _ghost: Array[Vector2i] = []  # cells the tool would mark (or erase) right now
var _ghost_key := ""
var _flash := ""
var _flash_until := 0


func setup(g) -> void:
	game = g
	z_index = -1                  # with the terrain: drawn after it, before the overlay and units
	var bar := HBoxContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar.offset_bottom = -g.HUD_BOTTOM
	bar.offset_left = 8
	g.get_node("UI").add_child(bar)
	for t in [Tool.BUILD, Tool.CLEAR, Tool.ERASE]:
		var b := Button.new()
		b.text = TOOL_LABELS[t]
		b.tooltip_text = TOOL_TIPS[t]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func(): set_tool(Tool.NONE if tool == t else t))
		bar.add_child(b)
		_buttons.append(b)


func active() -> bool:
	return tool != Tool.NONE


func set_tool(t: int) -> void:
	tool = t as Tool
	if tool != Tool.NONE:
		game.orders.cancel()
	_left_down = false
	_ghost_key = ""
	for i in _buttons.size():
		_buttons[i].set_pressed_no_signal(tool == i + 1)


func flash(text: String) -> void:
	_flash = text
	_flash_until = Time.get_ticks_msec() + 2500


# --- Input ----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if game.sim.state != "playing":
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if TOOL_KEYS.has(event.keycode):
			var t: int = TOOL_KEYS[event.keycode]
			set_tool(Tool.NONE if tool == t else t)
			get_viewport().set_input_as_handled()
		elif tool != Tool.NONE:
			match event.keycode:
				KEY_ESCAPE:
					set_tool(Tool.NONE)
					get_viewport().set_input_as_handled()
				KEY_1, KEY_2, KEY_3:
					priority = event.keycode - KEY_1
					_ghost_key = ""
					flash("Priority: %s" % Rules.PLAN_PRIORITIES[priority])
					get_viewport().set_input_as_handled()
		return
	if tool == Tool.NONE or not event is InputEventMouseButton:
		return
	var cell := _cell(make_input_local(event).position)
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_left_down = true
			_drag_start = cell
		elif _left_down:
			_left_down = false
			_apply(_box(_drag_start, cell))
		get_viewport().set_input_as_handled()
	elif event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed:
		# Not marked handled: the camera needs the release to end its drag
		if game.camera.drag_distance < 6.0:
			set_tool(Tool.NONE)


func _apply(box: Rect2i) -> void:
	var sim: Simulation = game.sim
	var cells := _targets(box)
	var n := 0
	match tool:
		Tool.ERASE:
			n = sim.remove_plans(sim.player, cells)
			flash("%d plan%s erased" % [n, "" if n == 1 else "s"] if n > 0 else "No plans there")
			return
		Tool.BUILD:
			n = sim.add_plans(sim.player, cells, "build", priority)
			if n == 0:
				flash("No room for a village: needs clear land or woods, not next to one of yours")
			else:
				flash("%d village%s planned (%s). Auto units build them as funds allow, %d each" \
					% [n, "" if n == 1 else "s", Rules.PLAN_PRIORITIES[priority].to_lower(), Rules.VILLAGE_COST])
		Tool.CLEAR:
			n = sim.add_plans(sim.player, cells, "clear", priority)
			flash("%d woods planned for clearing (%s)" % [n, Rules.PLAN_PRIORITIES[priority].to_lower()] \
				if n > 0 else "No woods there to clear")
	_ghost_key = ""


## Cells the current tool would act on in a box.
func _targets(box: Rect2i) -> Array[Vector2i]:
	var sim: Simulation = game.sim
	var out: Array[Vector2i] = []
	if box.size.x <= 0 or box.size.y <= 0:
		return out
	if tool == Tool.BUILD:
		if box.size == Vector2i.ONE:
			if sim.plan_allowed(sim.player, box.position, "build"):
				out.append(box.position)
			return out
		return sim.layout_villages(sim.player, box)
	for y in range(box.position.y, box.end.y):
		for x in range(box.position.x, box.end.x):
			var p := Vector2i(x, y)
			if tool == Tool.CLEAR and sim.plan_allowed(sim.player, p, "clear"):
				out.append(p)
			elif tool == Tool.ERASE and not sim.plan_at(sim.player, p).is_empty():
				out.append(p)
	return out


## The cells between two corners, kept on the map.
func _box(a: Vector2i, b: Vector2i) -> Rect2i:
	var w: World = game.sim.world
	var r := Rect2i(Vector2i(mini(a.x, b.x), mini(a.y, b.y)), (a - b).abs() + Vector2i.ONE)
	return r.intersection(Rect2i(0, 0, w.width, w.height))


func _cell(at: Vector2) -> Vector2i:
	return Vector2i(floori(at.x / game.CELL), floori(at.y / game.CELL))


# --- Drawing and hints ----------------------------------------------------

func _process(_delta: float) -> void:
	if tool != Tool.NONE and game.sim.state != "playing":
		set_tool(Tool.NONE)
	_hover = _cell(get_global_mouse_position())
	if tool != Tool.NONE:
		var start := _drag_start if _left_down else _hover
		var key := "%s|%s|%d|%d|%d" % [start, _hover, tool, priority, game.sim.day]
		if key != _ghost_key:
			_ghost_key = key
			_ghost.clear()
			if game.sim.world.in_bounds(_hover):
				_ghost = _targets(_box(start, _hover))
	queue_redraw()


func _draw() -> void:
	var sim: Simulation = game.sim
	var me := sim.country(sim.player)
	if me == null:
		return
	var c: float = game.CELL
	for i in me.plans:
		var plan: Array = me.plans[i]
		var p := sim.world.pos(i)
		_draw_plan(p, plan[0], PRIORITY_COLORS[plan[1]], 1.0, sim.plan_taken(p))
	if tool == Tool.NONE or not sim.world.in_bounds(_hover):
		return
	for p in _ghost:
		if tool == Tool.ERASE:
			var m := (Vector2(p) + Vector2(0.5, 0.5)) * c
			var r := c * 0.3
			draw_line(m + Vector2(-r, -r), m + Vector2(r, r), ERASE_COLOR, 3.0)
			draw_line(m + Vector2(-r, r), m + Vector2(r, -r), ERASE_COLOR, 3.0)
		else:
			_draw_plan(p, "build" if tool == Tool.BUILD else "clear", PRIORITY_COLORS[priority], 0.6, false)
	var box := _box(_drag_start if _left_down else _hover, _hover)
	var col := Color(1, 1, 1, 0.85) if not _ghost.is_empty() else ERASE_COLOR
	draw_rect(Rect2(Vector2(box.position) * c, Vector2(box.size) * c), col, false, 2.0)


## A planned village: a house outline. Planned clearing: hatching. Dot: a unit is on its way.
func _draw_plan(p: Vector2i, kind: String, col: Color, alpha: float, taken: bool) -> void:
	var c: float = game.CELL
	var a := Vector2(p) * c
	var inner := Rect2(a + Vector2(3, 3), Vector2(c - 6, c - 6))
	var line := Color(col, 0.95 * alpha)
	var dark := Color(0, 0, 0, 0.6 * alpha)
	draw_rect(inner, Color(col, 0.16 * alpha))
	if kind == "build":
		var roof := PackedVector2Array([a + Vector2(c * 0.22, c * 0.5), a + Vector2(c * 0.5, c * 0.24),
			a + Vector2(c * 0.78, c * 0.5)])
		var body := Rect2(a + Vector2(c * 0.3, c * 0.5), Vector2(c * 0.4, c * 0.28))
		for pass_outline in [true, false]:
			var lc := dark if pass_outline else line
			var w := 4.0 if pass_outline else 2.0
			draw_polyline(roof, lc, w)
			draw_rect(body, lc, false, w)
	else:
		# Three diagonal strokes across the cell
		var o := inner.position
		var s := inner.size.x
		for seg in [[Vector2(s / 2, 0), Vector2(0, s / 2)], [Vector2(s, 0), Vector2(0, s)],
				[Vector2(s, s / 2), Vector2(s / 2, s)]]:
			draw_line(o + seg[0], o + seg[1], dark, 3.5)
			draw_line(o + seg[0], o + seg[1], line, 1.5)
	draw_rect(inner, dark, false, 3.0)
	draw_rect(inner, line, false, 1.5)
	if taken:
		var m := a + Vector2(c - 7, 7)
		draw_circle(m, 4.0, Color(0, 0, 0, 0.8))
		draw_circle(m, 2.8, Color(0.5, 1.0, 0.55))


## One line for the HUD while a tool is out.
func hint() -> String:
	if Time.get_ticks_msec() < _flash_until:
		return _flash
	var pr: String = Rules.PLAN_PRIORITIES[priority]
	var what: String
	match tool:
		Tool.BUILD:
			what = "Plan villages (%s): click a cell or drag a box to lay them out" % pr
			if _left_down:
				what += "   %d village%s" % [_ghost.size(), "" if _ghost.size() == 1 else "s"]
		Tool.CLEAR:
			what = "Plan clearing (%s): click or drag over woods" % pr
			if _left_down:
				what += "   %d woods" % _ghost.size()
		Tool.ERASE:
			what = "Erase plans: click or drag"
			if _left_down:
				what += "   %d plan%s" % [_ghost.size(), "" if _ghost.size() == 1 else "s"]
	if tool != Tool.ERASE:
		what += "   1/2/3 priority"
	return what + "   right-click or Esc: done"
