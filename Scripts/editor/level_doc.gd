extends RefCounted
class_name LevelDoc

## An editable level: the map editor's data. Holds the same things as a level JSON
## (see Levels/FORMAT.md) in a shape that's easy to change cell by cell, and turns
## back into a Level (to draw or play) or a JSON file.
## Castle cells are not stored as "C" here; the castle list stamps them when saved.

const TERRAIN := ".T~^=bxo*"     # paintable terrain (castle "C" comes from countries)
const THEMES := ["B_010", "B_020", "B_030", "B_040", "B_050"]
const THEME_NAMES := ["Lord Monarch Night", "China Wars", "Food Panic", "Future Wars", "Fantasy Pastel"]
const STYLES := ["", "balanced", "aggressive", "builder", "turtle"]
const MIN_SIZE := 8
const MAX_SIZE := 256

var name := "New Map"
var theme := "B_010"
var day_limit := 3000
var player := 0
var width := 0
var height := 0
var terrain := PackedStringArray()     # rows, chars from TERRAIN
var territory := PackedStringArray()   # rows, "." or owner digit
var countries: Array = []    # [{id, castle: Vector2i, funds, tax, leader, style}], sorted by id
var villages: Array = []     # [{owner, pos: Vector2i}]
var units: Array = []        # [{owner, pos: Vector2i, strength}]
var objects: Array = []      # [{code, pos: Vector2i}]  (converted LMO maps)
var tile_overrides: Array = []   # [Vector3i(x, y, code)]  (converted LMO maps)
## File this came from or was last saved to ("" = never saved)
var path := ""


## A blank map: clear land, green (the player) top-left, red bottom-right.
static func blank(w: int, h: int) -> LevelDoc:
	var d := LevelDoc.new()
	d.width = clampi(w, MIN_SIZE, MAX_SIZE)
	d.height = clampi(h, MIN_SIZE, MAX_SIZE)
	for y in d.height:
		d.terrain.append(".".repeat(d.width))
		d.territory.append(".".repeat(d.width))
	d.add_country(0, Vector2i(2, 2))
	d.add_country(1, Vector2i(d.width - 5, d.height - 5))
	return d


## Loads a level file. Returns null and sets `error` on failure.
static func open(file: String, error: Array = []) -> LevelDoc:
	var level := Level.load_file(file)
	if level == null:
		error.append("Could not open %s (see the log)" % file)
		return null
	var d := from_level(level)
	d.path = file
	return d


static func from_level(level: Level) -> LevelDoc:
	var d := LevelDoc.new()
	d.name = level.name
	d.theme = level.theme
	d.day_limit = level.day_limit
	d.player = level.player
	d.width = level.width
	d.height = level.height
	for y in level.height:
		d.terrain.append(level.terrain[y].replace("C", "."))
		if level.territory.is_empty():
			d.territory.append(".".repeat(level.width))
		else:
			# Pad or cut rows that don't match the map width
			d.territory.append((level.territory[y] + ".".repeat(level.width)).left(level.width))
	for c in level.countries:
		d.countries.append({"id": c.id, "castle": c.castle, "funds": c.funds, "tax": c.tax,
			"leader": c.leader, "style": c.style})
	d.countries.sort_custom(func(a, b): return a.id < b.id)
	for v in level.villages:
		d.villages.append({"owner": v.owner, "pos": v.pos})
	for u in level.units:
		d.units.append({"owner": u.owner, "pos": u.pos, "strength": u.strength})
	for o in level.objects:
		d.objects.append({"code": o.code, "pos": o.pos})
	d.tile_overrides = level.tile_overrides.duplicate()
	return d


## The level as a JSON-ready Dictionary (the file format).
func to_dict() -> Dictionary:
	var rows := Array(terrain)
	for c in countries:
		for dy in 3:
			var y: int = c.castle.y + dy
			rows[y] = rows[y].substr(0, c.castle.x) + "CCC" + rows[y].substr(c.castle.x + 3)
	var d := {
		"format": 1,
		"name": name,
		"theme": theme,
		"day_limit": day_limit,
		"player": player,
		"countries": countries.map(_country_dict),
		"terrain": rows,
	}
	if has_territory():
		d["territory"] = Array(territory)
	if not villages.is_empty():
		d["villages"] = villages.map(func(v): return {"owner": v.owner, "pos": [v.pos.x, v.pos.y]})
	if not units.is_empty():
		d["units"] = units.map(func(u): return {"owner": u.owner, "pos": [u.pos.x, u.pos.y], "strength": u.strength})
	if not objects.is_empty():
		d["objects"] = objects.map(func(o): return {"code": o.code, "pos": [o.pos.x, o.pos.y]})
	if not tile_overrides.is_empty():
		d["tile_overrides"] = tile_overrides.map(func(t): return [t.x, t.y, t.z])
	return d


func _country_dict(c: Dictionary) -> Dictionary:
	var out := {"id": c.id, "castle": [c.castle.x, c.castle.y],
		"funds": c.funds, "tax": c.tax, "leader": c.leader,
		"control": "player" if c.id == player else "ai"}
	if c.style != "":
		out["style"] = c.style
	return out


## A Level built from this doc, as the game would load it. Null if it doesn't parse.
func to_level() -> Level:
	var level := Level.new()
	if level._parse(to_dict()) != "":
		return null
	return level


## Write the JSON file. Returns "" or an error.
func save(file: String) -> String:
	DirAccess.make_dir_recursive_absolute(file.get_base_dir())
	var f := FileAccess.open(file, FileAccess.WRITE)
	if f == null:
		return "Cannot write %s (%s)" % [file, error_string(FileAccess.get_open_error())]
	f.store_string(to_json())
	f.close()
	path = file
	return ""


## JSON text with one map row, country or village per line, so files stay readable.
func to_json() -> String:
	var d := to_dict()
	var parts := []
	for key in d:
		var v = d[key]
		var text: String
		if v is Array and not v.is_empty():
			text = "[\n" + ",\n".join(v.map(func(e): return "    " + JSON.stringify(e))) + "\n  ]"
		else:
			text = JSON.stringify(v)
		parts.append("  %s: %s" % [JSON.stringify(key), text])
	return "{\n" + ",\n".join(parts) + "\n}\n"


## A copy, for undo.
func snapshot() -> LevelDoc:
	var d := LevelDoc.new()
	d.restore_from(self)
	return d


func restore_from(o: LevelDoc) -> void:
	name = o.name
	theme = o.theme
	day_limit = o.day_limit
	player = o.player
	width = o.width
	height = o.height
	terrain = o.terrain.duplicate()
	territory = o.territory.duplicate()
	countries = o.countries.duplicate(true)
	villages = o.villages.duplicate(true)
	units = o.units.duplicate(true)
	objects = o.objects.duplicate(true)
	tile_overrides = o.tile_overrides.duplicate()
	path = o.path


# --- Reading ---------------------------------------------------------------

func in_bounds(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < width and p.y < height


func terrain_at(p: Vector2i) -> String:
	return terrain[p.y][p.x]


func territory_at(p: Vector2i) -> int:
	var ch := territory[p.y][p.x]
	return -1 if ch == "." else int(ch)


func has_territory() -> bool:
	for row in territory:
		if row.count(".") != row.length():
			return true
	return false


func country(id: int) -> Dictionary:
	for c in countries:
		if c.id == id:
			return c
	return {}


## Owner of the castle covering p, or -1.
func castle_at(p: Vector2i) -> int:
	for c in countries:
		if Rect2i(c.castle, Vector2i(3, 3)).has_point(p):
			return c.id
	return -1


func village_at(p: Vector2i) -> int:
	for i in villages.size():
		if villages[i].pos == p:
			return i
	return -1


func unit_at(p: Vector2i) -> int:
	for i in units.size():
		if units[i].pos == p:
			return i
	return -1


## Problems that would make the map play badly. Empty = fine.
func warnings() -> Array[String]:
	var out: Array[String] = []
	if countries.size() < 2:
		out.append("Only one country: the game is won at once. Add another castle.")
	for u in units:
		if terrain_at(u.pos) in World.BLOCKING or castle_at(u.pos) >= 0:
			out.append("A %s unit at %d,%d stands where units can't (it won't appear)" % [Level.COLORS[u.owner], u.pos.x, u.pos.y])
	for c in countries:
		var gate: Vector2i = c.castle + Vector2i(1, 3)
		if not in_bounds(gate) or terrain_at(gate) in World.BLOCKING or castle_at(gate) >= 0:
			out.append("%s's castle gate (bottom middle) is blocked" % Level.COLORS[c.id].capitalize())
	return out


# --- Editing ---------------------------------------------------------------
# Each returns the cells whose look changed (empty = nothing happened), or a message.

## Paint one cell. Castle and village cells keep their terrain (villages need clear land).
func paint_terrain(p: Vector2i, ch: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not in_bounds(p) or castle_at(p) >= 0 or terrain_at(p) == ch:
		return out
	if ch != "." and village_at(p) >= 0:
		return out
	_put(terrain, p, ch)
	_drop_overrides(p, true)
	for i in range(objects.size() - 1, -1, -1):
		if objects[i].pos == p:
			objects.remove_at(i)
	if ch != ".":
		_put(territory, p, ".")   # only clear land holds territory
	if ch in World.BLOCKING:
		var u := unit_at(p)
		if u >= 0:
			units.remove_at(u)
	out.append(p)
	return out


## Fill the area of the same terrain around p (4 directions). Returns the cells changed.
func fill_terrain(p: Vector2i, ch: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not in_bounds(p):
		return out
	var from := terrain_at(p)
	if from == ch:
		return out
	for q in _region(p, func(c: Vector2i): return terrain_at(c) == from and castle_at(c) < 0):
		out.append_array(paint_terrain(q, ch))
	return out


## owner -1 erases. Only clear land, never castle or another country's village.
func paint_territory(p: Vector2i, owner: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not in_bounds(p) or terrain_at(p) != "." or castle_at(p) >= 0 or territory_at(p) == owner:
		return out
	if village_at(p) >= 0:
		return out    # a village's own cell always belongs to it
	_put(territory, p, "." if owner < 0 else str(owner))
	out.append(p)
	return out


func fill_territory(p: Vector2i, owner: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not in_bounds(p) or terrain_at(p) != ".":
		return out
	var from := territory_at(p)
	if from == owner:
		return out
	for q in _region(p, func(c: Vector2i): return terrain_at(c) == "." and territory_at(c) == from and castle_at(c) < 0):
		out.append_array(paint_territory(q, owner))
	return out


## Place a village (and claim the clear land around it, as building one does in play),
## or remove the village already there. Returns "" or why not.
func toggle_village(p: Vector2i, owner: int) -> String:
	if not in_bounds(p):
		return "Off the map"
	var i := village_at(p)
	if i >= 0:
		var old: int = villages[i].owner
		villages.remove_at(i)
		_put(territory, p, ".")
		for d in World.N8:
			var q: Vector2i = p + d
			if in_bounds(q) and territory_at(q) == old and not _borders_village(q, old):
				_put(territory, q, ".")
		return ""
	if country(owner).is_empty():
		return "Place %s's castle first" % Level.COLORS[owner]
	if terrain_at(p) != "." or castle_at(p) >= 0:
		return "Villages go on clear land"
	if unit_at(p) >= 0:
		units.remove_at(unit_at(p))
	villages.append({"owner": owner, "pos": p})
	_put(territory, p, str(owner))
	for d in World.N8:
		var q: Vector2i = p + d
		if in_bounds(q) and terrain_at(q) == "." and territory_at(q) < 0 and castle_at(q) < 0:
			_put(territory, q, str(owner))
	return ""


## Move (or add) a country's castle so it's centred on p. Returns "" or why not.
func place_castle(id: int, center: Vector2i) -> String:
	var top := Vector2i(clampi(center.x - 1, 0, width - 3), clampi(center.y - 1, 0, height - 3))
	var rect := Rect2i(top, Vector2i(3, 3))
	for c in countries:
		if c.id != id and Rect2i(c.castle, Vector2i(3, 3)).intersects(rect):
			return "Too close to %s's castle" % Level.COLORS[c.id]
	if country(id).is_empty():
		add_country(id, top)
	else:
		country(id).castle = top
	# Nothing else stays under a castle
	for i in range(villages.size() - 1, -1, -1):
		if rect.has_point(villages[i].pos):
			villages.remove_at(i)
	for i in range(units.size() - 1, -1, -1):
		if rect.has_point(units[i].pos):
			units.remove_at(i)
	for y in range(top.y, top.y + 3):
		for x in range(top.x, top.x + 3):
			_put(territory, Vector2i(x, y), ".")
	return ""


func add_country(id: int, top: Vector2i) -> void:
	countries.append({"id": id, "castle": top, "funds": 5000, "tax": 10,
		"leader": Rules.LEADER_START, "style": ""})
	countries.sort_custom(func(a, b): return a.id < b.id)


## Remove a country with its villages, units and territory. Returns "" or why not.
func remove_country(id: int) -> String:
	if country(id).is_empty():
		return ""
	if countries.size() == 1:
		return "A map needs at least one country"
	countries.erase(country(id))
	villages = villages.filter(func(v): return v.owner != id)
	units = units.filter(func(u): return u.owner != id)
	for y in height:
		territory[y] = territory[y].replace(str(id), ".")
	if player == id:
		player = countries[0].id
	return ""


## Add a starting unit, or remove the one there. Returns "" or why not.
func toggle_unit(p: Vector2i, owner: int, strength: float) -> String:
	if not in_bounds(p):
		return "Off the map"
	var i := unit_at(p)
	if i >= 0:
		units.remove_at(i)
		return ""
	if country(owner).is_empty():
		return "Place %s's castle first" % Level.COLORS[owner]
	if terrain_at(p) in World.BLOCKING or castle_at(p) >= 0 or village_at(p) >= 0:
		return "Units need open ground"
	units.append({"owner": owner, "pos": p, "strength": strength})
	return ""


## Remove whatever is on a cell: a unit, else a village, else territory.
## Returns true if something went.
func erase_at(p: Vector2i) -> bool:
	if not in_bounds(p):
		return false
	if unit_at(p) >= 0:
		units.remove_at(unit_at(p))
		return true
	if village_at(p) >= 0:
		toggle_village(p, 0)
		return true
	return not paint_territory(p, -1).is_empty()


## New size; the top-left corner stays put. Returns "" or why not.
func resize(w: int, h: int) -> String:
	w = clampi(w, MIN_SIZE, MAX_SIZE)
	h = clampi(h, MIN_SIZE, MAX_SIZE)
	for c in countries:
		if c.castle.x + 3 > w or c.castle.y + 3 > h:
			return "%s's castle would be off the map; move it first" % Level.COLORS[c.id].capitalize()
	for y in h:
		if y < height:
			terrain[y] = (terrain[y] + ".".repeat(w)).left(w)
			territory[y] = (territory[y] + ".".repeat(w)).left(w)
		else:
			terrain.append(".".repeat(w))
			territory.append(".".repeat(w))
	terrain.resize(h)
	territory.resize(h)
	width = w
	height = h
	villages = villages.filter(func(v): return in_bounds(v.pos))
	units = units.filter(func(u): return in_bounds(u.pos))
	objects = objects.filter(func(o): return in_bounds(o.pos))
	tile_overrides = tile_overrides.filter(func(t): return in_bounds(Vector2i(t.x, t.y)))
	return ""


func _put(rows: PackedStringArray, p: Vector2i, ch: String) -> void:
	var row := rows[p.y]
	rows[p.y] = row.substr(0, p.x) + ch + row.substr(p.x + 1)


## Converted maps force some tiles; once a cell is repainted, its tiles are worked out again.
func _drop_overrides(p: Vector2i, with_neighbours: bool) -> void:
	if tile_overrides.is_empty():
		return
	var reach := 1 if with_neighbours else 0
	var keep: Array = []
	for t in tile_overrides:
		if absi(t.x - p.x) > reach or absi(t.y - p.y) > reach:
			keep.append(t)
	tile_overrides = keep


func _borders_village(p: Vector2i, owner: int) -> bool:
	for d in World.N8:
		var q: Vector2i = p + d
		var i := village_at(q)
		if i >= 0 and villages[i].owner == owner:
			return true
	return false


## Cells connected to start (4 directions) where `inside` holds.
func _region(start: Vector2i, inside: Callable) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not inside.call(start):
		return out
	var seen := {start: true}
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var p: Vector2i = queue.pop_back()
		out.append(p)
		for d in World.N4:
			var q: Vector2i = p + d
			if in_bounds(q) and not seen.has(q) and inside.call(q):
				seen[q] = true
				queue.append(q)
	return out
