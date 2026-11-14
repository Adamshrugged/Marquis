extends Node2D
class_name OrdersUI

## Giving orders, as in the manual: Who -> Where -> Does what.
##   Left-click a unit (or drag a box around several) -> left-click a destination
##   -> pick an action from the menu. The leader only moves, so it skips the menu.
##   Or right-click the destination: the obvious action there happens (woods are
##   cleared, an enemy attacked, ...) [G]. Right-click on nothing doable, or Esc, cancels.
##   Shift while confirming queues the order behind the current one and keeps the
##   selection, to chain several. R recalls the leader.
## While picking a destination: the path there, the days it takes and what a
## right-click would do. Queued targets of the selected units are numbered on the map.
## Buttons (`button_bar`, bottom right): overall orders (units without orders /
## every unit), recall leader, playbook window, status window; game.gd
## and the map overlay add theirs after. Esc with nothing to cancel is left to game.gd.

enum Mode { IDLE, PICK_TARGET }

const PICK_RADIUS := 0.7          # in cells, around a unit's drawn centre
const DRAG_MIN := 12.0            # pixels before a left-drag becomes a box select
const PREVIEW_UNITS := 5          # paths drawn for a group
const FONT_SIZE := 13             # cursor label

var game                          # Scenes/game.gd
var mode := Mode.IDLE
var selected: Array = []          # Units waiting for a destination
var target := Vector2i(-1, -1)
var menu_open := false
var button_bar: HBoxContainer

var _menu: PopupMenu
var _drag_from := Vector2.ZERO
var _left_down := false
var _hover_cell := Vector2i(-1, -1)
var _sel_version := 0
# Preview of the hovered destination, redone when the cell, selection, Shift or day changes
var _preview_key := ""
var _preview_action: Array = []   # [action, label] a right-click gives, or []
var _preview_ok := false          # some selected unit can get there
var _preview_paths: Array = []    # [unit, from cell, path] for the first few units
var _preview_dist := -1
var _preview_days := -1
var _preview_waits := 0           # units whose queue is stuck behind a staying order
var _flash := ""
var _flash_until := 0


func setup(g) -> void:
	game = g
	var ui: CanvasLayer = g.get_node("UI")
	_menu = PopupMenu.new()
	for i in Simulation.ACTIONS.size():
		_menu.add_item(Simulation.ACTIONS[i][1], i)
	_menu.id_pressed.connect(_on_action)
	_menu.popup_hide.connect(func(): menu_open = false)
	ui.add_child(_menu)

	var bar := HBoxContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	bar.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar.offset_bottom = -g.HUD_BOTTOM
	bar.offset_right = -8
	ui.add_child(bar)
	button_bar = bar
	add_bar_button("Order new units", "Order every unit that has no order (O)", func(): _select_all(false))
	add_bar_button("Order all", "Order every unit, overriding orders (Shift+O)", func(): _select_all(true))
	add_bar_button("Recall leader", "Bring the leader back to the castle (R)", recall_leader)
	add_bar_button("Playbook", "What Auto units do, the default order and automatic tax (P)", func(): game.playbook.toggle())
	add_bar_button("Status", "Every country at a glance (Tab)", func(): game.status_window.toggle())


func add_bar_button(text: String, tip: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(action)
	button_bar.add_child(b)
	return b


## A caption in the button bar, on the same background as the buttons.
func add_bar_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_stylebox_override("normal", ThemeDB.get_default_theme().get_stylebox("normal", "Button"))
	l.mouse_filter = Control.MOUSE_FILTER_STOP     # blocks map clicks like the buttons
	button_bar.add_child(l)
	return l


## Something for Esc to cancel: a selection or the order menu.
func busy() -> bool:
	return mode != Mode.IDLE or menu_open


# --- Input ----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if game.sim.state != "playing":
		return
	if event is InputEventMouseButton:
		var at: Vector2 = make_input_local(event).position   # map position of the click
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_left_down = true
				_drag_from = at
			elif _left_down:
				_left_down = false
				var to := at
				if mode == Mode.IDLE and _drag_from.distance_to(to) > DRAG_MIN:
					_select_box(Rect2(_drag_from, to - _drag_from).abs())
				else:
					_click(to)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed:
			# Not marked handled: the camera needs the release to end its drag
			if game.camera.drag_distance < 6.0:
				if mode == Mode.PICK_TARGET:
					_context_click(_cell(at), event.shift_pressed)
				else:
					cancel()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				if busy():
					cancel()
					get_viewport().set_input_as_handled()
			KEY_R:
				recall_leader()
			KEY_O:
				_select_all(event.shift_pressed)


func _click(at: Vector2) -> void:
	var cell := _cell(at)
	if mode == Mode.IDLE:
		var u := _unit_near(at)
		if u:
			_select([u])
		return
	# Choosing a destination
	if not game.sim.world.in_bounds(cell):
		return
	target = cell
	if selected.size() == 1 and selected[0].is_leader:
		if game.sim.order_leader(game.sim.player, cell):
			flash("Leader moving")
			cancel()
		else:
			flash("The leader can't get there")
		return
	for i in Simulation.ACTIONS.size():
		_menu.set_item_disabled(i, not game.sim.action_allowed(game.sim.player, cell, Simulation.ACTIONS[i][0]))
	_menu.position = Vector2i(get_viewport().get_mouse_position())
	_menu.reset_size()
	menu_open = true
	_menu.popup()


func _on_action(id: int) -> void:
	menu_open = false
	if not _issue(target, Simulation.ACTIONS[id][0], Simulation.ACTIONS[id][1], Input.is_key_pressed(KEY_SHIFT)):
		flash("Can't get there. Pick another destination")  # [M] stays waiting for a destination


## Right-click while picking a destination: do the obvious thing there.
func _context_click(cell: Vector2i, shift: bool) -> void:
	var sim: Simulation = game.sim
	if _leader_only():
		if sim.world.in_bounds(cell) and sim.order_leader(sim.player, cell):
			flash("Leader moving")
		else:
			flash("The leader can't get there")
		cancel()
		return
	var ca := sim.context_action(sim.player, cell)
	if ca.is_empty() or not _issue(cell, ca[0], ca[1], shift):
		flash("Can't go there")
		cancel()


## Order (or with Shift, queue) the selection. False if nobody took it.
func _issue(cell: Vector2i, action: String, label: String, shift: bool) -> bool:
	var sim: Simulation = game.sim
	var waits := _stuck_count() if shift else 0
	var n: int = sim.queue_order(selected, cell, action) if shift else sim.order_units(selected, cell, action)
	if n == 0:
		return false
	var missed: int = selected.size() - n
	var text := "%d unit%s: %s%s%s" % [n, "" if n == 1 else "s", label, " queued" if shift else "",
		"" if missed == 0 else " (%d can't reach)" % missed]
	if waits > 0:
		text += ". Waits behind an order that doesn't end (%d unit%s): give a new order to move on" \
			% [waits, "" if waits == 1 else "s"]
	flash(text)
	if shift:
		_sel_version += 1     # keep the selection to chain more orders
	else:
		cancel()
	return true


## Selected units whose orders never end by themselves, so a queued order would wait.
func _stuck_count() -> int:
	return selected.filter(func(u): return game.sim.last_order(u) in Simulation.STAYING_JOBS).size()


func _leader_only() -> bool:
	return selected.size() == 1 and selected[0].is_leader


func cancel() -> void:
	mode = Mode.IDLE
	selected.clear()
	if menu_open:
		_menu.hide()
	menu_open = false


func recall_leader() -> void:
	if game.sim.recall_leader(game.sim.player):
		flash("Leader returning to the castle")
	else:
		flash("The leader can't get back to the castle")


func flash(text: String) -> void:
	_flash = text
	_flash_until = Time.get_ticks_msec() + 2500


# --- Selection ------------------------------------------------------------

func _select(units: Array) -> void:
	if units.is_empty():
		return
	selected = units
	mode = Mode.PICK_TARGET
	_sel_version += 1


func _select_all(override: bool) -> void:
	var list: Array = game.sim.units.filter(func(u): return u.owner == game.sim.player and not u.is_leader \
		and not u.dead and (override or not u.ordered))
	if list.is_empty():
		flash("No units to order")
		return
	_select(list)
	flash("%d units: pick a destination" % list.size())


func _select_box(r: Rect2) -> void:
	var list: Array = game.sim.units.filter(func(u): return u.owner == game.sim.player and not u.is_leader \
		and not u.dead and r.has_point(_drawn_center(u)))
	_select(list)


func _unit_near(at: Vector2) -> Unit:
	var best: Unit = null
	var best_d: float = PICK_RADIUS * game.CELL
	for u in game.sim.units:
		if u.owner != game.sim.player or u.dead:
			continue
		var d := _drawn_center(u).distance_to(at)
		if d < best_d:
			best_d = d
			best = u
	return best


func _drawn_center(u: Unit) -> Vector2:
	var t := clampf(game.unit_layer.day_fraction, 0.0, 1.0)
	return (Vector2(u.prev_pos).lerp(Vector2(u.pos), t) + Vector2(0.5, 0.5)) * game.CELL


func _cell(at: Vector2) -> Vector2i:
	return Vector2i(floori(at.x / game.CELL), floori(at.y / game.CELL))


func _me() -> Country:
	return game.sim.country(game.sim.player)


# --- Drawing and hints ----------------------------------------------------

func _process(_delta: float) -> void:
	var n := selected.size()
	selected = selected.filter(func(u): return not u.dead and u.owner == game.sim.player)
	if selected.size() != n:
		_sel_version += 1
	if mode == Mode.PICK_TARGET and selected.is_empty():
		cancel()
	_hover_cell = _cell(get_global_mouse_position())
	if mode == Mode.PICK_TARGET:
		var key := "%s|%d|%s|%d" % [_hover_cell, _sel_version, Input.is_key_pressed(KEY_SHIFT), game.sim.day]
		if key != _preview_key:
			_preview_key = key
			_update_preview(_hover_cell, Input.is_key_pressed(KEY_SHIFT))
	queue_redraw()


## What a right-click on the cell would do, and the routes there.
func _update_preview(cell: Vector2i, shift: bool) -> void:
	var sim: Simulation = game.sim
	_preview_paths.clear()
	_preview_ok = false
	_preview_dist = -1
	_preview_days = -1
	_preview_waits = _stuck_count() if shift else 0
	if not sim.world.in_bounds(cell):
		_preview_action = []
		return
	if _leader_only():
		_preview_action = ["move", "Move"] if sim.world.is_walkable(cell) else []
	else:
		_preview_action = sim.context_action(sim.player, cell)
	if _preview_action.is_empty():
		return
	var action: String = _preview_action[0]
	for u in selected.slice(0, PREVIEW_UNITS):
		var from: Vector2i = u.pos
		if shift and u.ordered and u.job != "":
			from = u.queue.back()[0] if not u.queue.is_empty() else u.job_target
		var path := sim.route_for(u, cell, action, from)
		var off := from - cell
		var there := absi(off.x) + absi(off.y) == 1 if action in Simulation.ADJACENT_JOBS else from == cell
		if path.is_empty() and not there:
			continue
		_preview_ok = true
		_preview_paths.append([u, from, path])
		if _preview_days < 0:
			_preview_dist = path.size()
			_preview_days = sim.travel_days(path)


func _draw() -> void:
	var c: float = game.CELL
	# Order markers above the player's ordered units
	for u in game.sim.units:
		if u.owner == game.sim.player and u.ordered and not u.dead:
			var top := _drawn_center(u) - Vector2(0, c * 0.55)
			draw_colored_polygon(PackedVector2Array([top + Vector2(-4, -6), top + Vector2(4, -6), top]), Color.YELLOW)
	var hovering: bool = mode == Mode.PICK_TARGET and game.sim.world.in_bounds(_hover_cell)
	if hovering:
		for i in _preview_paths.size():
			var p: Array = _preview_paths[i]
			var start: Vector2 = _drawn_center(p[0]) if p[1] == p[0].pos else (Vector2(p[1]) + Vector2(0.5, 0.5)) * c
			_draw_path(start, p[2], Color(1, 0.95, 0.4, 0.95) if i == 0 else Color(1, 1, 0.7, 0.6), 2.0 if i == 0 else 1.25)
	# Current and queued targets: of the selection, or of the unit under the mouse
	var shown: Array = selected
	if mode == Mode.IDLE:
		var u := _unit_near(get_global_mouse_position())
		shown = [u] if u else []
	var numbered := {}
	for u in shown:
		_draw_queue(u, numbered)
	for u in selected:
		var at := _drawn_center(u) - Vector2(c, c) / 2
		draw_rect(Rect2(at, Vector2(c, c)), Color.WHITE, false, 2.0)
	if hovering:
		var col := Color.YELLOW if _preview_ok else Color.RED
		draw_rect(Rect2(Vector2(_hover_cell) * c, Vector2(c, c)), col, false, 2.0)
		_draw_cursor_label()
	if _left_down and mode == Mode.IDLE:
		var to := get_global_mouse_position()
		if _drag_from.distance_to(to) > DRAG_MIN:
			draw_rect(Rect2(_drag_from, to - _drag_from).abs(), Color(1, 1, 1, 0.8), false, 1.5)


func _draw_path(start: Vector2, path: Array, col: Color, width: float) -> void:
	if path.is_empty():
		return
	var pts := PackedVector2Array([start])
	for p in path:
		pts.append((Vector2(p) + Vector2(0.5, 0.5)) * game.CELL)
	draw_polyline(pts, Color(0, 0, 0, col.a * 0.6), (width + 2.0) / _zoom(), true)
	draw_polyline(pts, col, width / _zoom(), true)


## A line from the unit through its current target and queued targets, numbered 1, 2, ...
func _draw_queue(u: Unit, numbered: Dictionary) -> void:
	var targets: Array[Vector2i] = []
	if u.ordered and u.job != "":
		targets.append(u.job_target)
	for q in u.queue:
		targets.append(q[0])
	if targets.is_empty():
		return
	var c: float = game.CELL
	var pts := PackedVector2Array([_drawn_center(u)])
	for t in targets:
		pts.append((Vector2(t) + Vector2(0.5, 0.5)) * c)
	draw_polyline(pts, Color(0, 0, 0, 0.45), 3.0 / _zoom(), true)
	draw_polyline(pts, Color(0.55, 0.9, 1.0, 0.85), 1.25 / _zoom(), true)
	var font := ThemeDB.fallback_font
	var s := 1.0 / _zoom()
	for i in targets.size():
		if numbered.has(targets[i]):
			continue
		numbered[targets[i]] = true
		var at: Vector2 = pts[i + 1]
		var r := 7.0 * s
		draw_circle(at, r + s, Color.BLACK)
		draw_circle(at, r, Color(0.15, 0.45, 0.6) if i == 0 and u.ordered and u.job != "" else Color(0.1, 0.3, 0.45))
		var num := str(i + 1)
		draw_set_transform(at, 0.0, Vector2(s, s))
		var w := font.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		draw_string(font, Vector2(-w / 2, 4), num, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)
		draw_set_transform(Vector2.ZERO)


## Small label by the cursor: what a right-click does here (red X if nothing).
func _draw_cursor_label() -> void:
	var font := ThemeDB.fallback_font
	var shift := Input.is_key_pressed(KEY_SHIFT)
	var text: String
	if not _preview_ok:
		text = "Can't go"
	else:
		text = ("+ " if shift else "") + str(_preview_action[1])
		if _preview_days > 0:
			text += "  %dd" % _preview_days
	var s := 1.0 / _zoom()
	draw_set_transform(get_global_mouse_position() + Vector2(16, 18) * s, 0.0, Vector2(s, s))
	var size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
	var x0 := 0.0
	var box := Rect2(Vector2(-4, -2), Vector2(size.x + 8, size.y + 4))
	if not _preview_ok:
		box.size.x += 14
		x0 = 14
	draw_rect(box, Color(0.04, 0.06, 0.18, 0.85))
	draw_rect(box, Color(1, 0.35, 0.3) if not _preview_ok else Color(0.55, 0.85, 0.8), false, 1.0)
	if not _preview_ok:
		var m := Vector2(1, size.y / 2)
		draw_line(m + Vector2(0, -5), m + Vector2(10, 5), Color(1, 0.3, 0.25), 2.0)
		draw_line(m + Vector2(0, 5), m + Vector2(10, -5), Color(1, 0.3, 0.25), 2.0)
	var base := Vector2(x0, font.get_ascent(FONT_SIZE))
	draw_string(font, base + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color.BLACK)
	draw_string(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE,
		Color(1, 0.75, 0.7) if not _preview_ok else Color.WHITE)
	draw_set_transform(Vector2.ZERO)


func _zoom() -> float:
	return game.camera.zoom.x


## One line for the HUD: what to do next, or what's under the mouse.
func hint() -> String:
	if Time.get_ticks_msec() < _flash_until:
		return _flash
	if mode == Mode.PICK_TARGET:
		var who := "Leader" if selected[0].is_leader else ("%d units" % selected.size() if selected.size() > 1 else "Unit")
		if not game.sim.world.in_bounds(_hover_cell):
			return "%s: pick a destination (Esc cancels)" % who
		if not _preview_ok:
			return "%s: can't go there. Pick a destination (right-click or Esc cancels)" % who
		var text := "%s: right-click to %s, left-click for every order, Shift queues" % [who, _preview_action[1]]
		if _leader_only():
			text = "Leader: click to move here"
		text += "   distance %d, about %d day%s" % [_preview_dist, _preview_days, "" if _preview_days == 1 else "s"]
		if _preview_waits > 0:
			text += "   (queued after an order that doesn't end: it waits)"
		return text
	return describe(_hover_cell)


func describe(cell: Vector2i) -> String:
	var sim: Simulation = game.sim
	var w := sim.world
	if not w.in_bounds(cell):
		return "Click a unit to give it orders, or drag a box around several"
	var parts := []
	for u in sim.units:
		if u.pos == cell and not u.dead:
			var what := "leader" if u.is_leader else ("" if u.owner == Simulation.MONSTER else "unit")
			var doing := u.job if u.job != "" else u.order
			parts.append("%s %s %d (%s)" % [sim.owner_name(u.owner), what, u.strength, doing])
	var i := w.idx(cell)
	if w.village_owner[i] >= 0:
		parts.append("%s village pop %d/%d" % [sim.country(w.village_owner[i]).color.capitalize(),
			w.village_pop[i], w.village_cap(cell)])
	elif w.castle_owner[i] >= 0:
		parts.append("%s castle" % sim.country(w.castle_owner[i]).color.capitalize())
	else:
		var names := {".": "clear land", "T": "woods", "~": "water", "^": "mountain", "=": "bridge",
			"b": "bridge", "x": "barricade", "o": "cave", "*": "rubble"}
		var t: String = names.get(w.terrain_at(cell), "?")
		var max_dur := {"=": Rules.BRIDGE_MAX, "b": Rules.BRIDGE_MAX, "x": Rules.BARRICADE_MAX, "*": Rules.MAP_BARRICADE}
		if max_dur.has(w.terrain_at(cell)):
			t += " (durability %d/%d)" % [w.durability[i], max_dur[w.terrain_at(cell)]]
			if w.terrain_at(cell) == "=" and w.durability[i] < Rules.BRIDGE_MAX:
				t = "damaged " + t + " - Build Bridge repairs it"
		if w.territory[i] >= 0:
			t += " (%s land)" % sim.country(w.territory[i]).color
		parts.append(t)
	var plan := sim.plan_at(sim.player, cell)
	if not plan.is_empty():
		var note: String = "a unit is on its way" if sim.plan_taken(cell) else "waiting for an Auto unit"
		if plan[0] == "build" and w.terrain_at(cell) == "T":
			note = "woods cleared first, " + note
		parts.append("planned: %s (%s, %s)" % [Simulation.PLAN_NAMES[plan[0]],
			Rules.PLAN_PRIORITIES[plan[1]].to_lower(), note])
	return "[%d,%d] %s" % [cell.x, cell.y, ", ".join(parts)]
