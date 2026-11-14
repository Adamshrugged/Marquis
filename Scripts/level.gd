extends RefCounted
class_name Level

## A map plus starting conditions, loaded from a level JSON file.
## Format: see res://Levels/FORMAT.md

const TERRAIN_CHARS := ".T~^=bxo*C"
const COLORS := ["green", "red", "white", "black"]

var name: String
var theme: String
var width: int
var height: int
var day_limit: int
var player: int
var countries: Array = []   # [{id, color, castle: Vector2i, funds, tax, control}]
var terrain: PackedStringArray  # terrain[y][x]
var territory: PackedStringArray  # same shape, "." or owner digit; may be empty
var villages: Array = []    # [{owner, pos: Vector2i}]
var objects: Array = []     # [{code, pos: Vector2i}]
var units: Array = []       # extra starting units [{owner, pos: Vector2i, strength}]
var tile_overrides: Array = []  # [Vector3i(x, y, code)]


static func load_file(path: String) -> Level:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("Level: cannot read %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return null
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		push_error("Level: %s is not a JSON object" % path)
		return null
	var level := Level.new()
	var err := level._parse(data)
	if err != "":
		push_error("Level: %s: %s" % [path, err])
		return null
	return level


func _parse(d: Dictionary) -> String:
	name = d.get("name", "Untitled")
	theme = d.get("theme", "B_010")
	day_limit = int(d.get("day_limit", 3000))
	player = int(d.get("player", 0))

	if not d.has("terrain") or d.terrain.is_empty():
		return "missing terrain"
	terrain = PackedStringArray(d.terrain)
	height = terrain.size()
	width = terrain[0].length()
	for y in height:
		if terrain[y].length() != width:
			return "terrain row %d has %d cells, expected %d" % [y, terrain[y].length(), width]
		for x in width:
			if not (terrain[y][x] in TERRAIN_CHARS):
				return "unknown terrain '%s' at %d,%d" % [terrain[y][x], x, y]

	if d.has("territory"):
		territory = PackedStringArray(d.territory)
		if territory.size() != height:
			return "territory has %d rows, expected %d" % [territory.size(), height]
		for y in height:
			# Pad or cut rows that don't match the map width (as the editor does)
			territory[y] = (territory[y] + ".".repeat(width)).left(width)

	if not d.has("countries") or d.countries.is_empty():
		return "no countries"
	for c in d.countries:
		var id := int(c.get("id", countries.size()))
		var castle := _vec(c.get("castle", null))
		if id < 0 or id > 3:
			return "country id %d out of range 0-3" % id
		if not get_country(id).is_empty():
			return "country id %d appears twice" % id
		if castle.x < 0 or castle.y < 0 or castle.x + 3 > width or castle.y + 3 > height:
			return "country %d castle %s does not fit on the map" % [id, castle]
		countries.append({
			"id": id,
			"color": c.get("color", COLORS[id]),
			"castle": castle,
			"funds": int(c.get("funds", 5000)),
			"tax": int(c.get("tax", 50)),
			"leader": int(c.get("leader", Rules.LEADER_START)),
			"style": c.get("style", ""),
			"control": c.get("control", "player" if id == player else "ai"),
		})
		# Castle footprint is always castle terrain
		for dy in 3:
			var row := terrain[castle.y + dy]
			terrain[castle.y + dy] = row.substr(0, castle.x) + "CCC" + row.substr(castle.x + 3)
	if get_country(player).is_empty():
		return "player %d has no country" % player

	for v in d.get("villages", []):
		var pos := _vec(v.get("pos", null))
		if not in_bounds(pos):
			return "village at %s is off the map" % pos
		var owner := int(v.get("owner", 0))
		if get_country(owner).is_empty():
			return "village at %s belongs to country %d, which isn't in the level" % [pos, owner]
		villages.append({"owner": owner, "pos": pos})
	for u in d.get("units", []):
		var pos := _vec(u.get("pos", null))
		if not in_bounds(pos):
			return "unit at %s is off the map" % pos
		var owner := int(u.get("owner", 0))
		if get_country(owner).is_empty():
			return "unit at %s belongs to country %d, which isn't in the level" % [pos, owner]
		units.append({"owner": owner, "pos": pos, "strength": float(u.get("strength", Rules.START_UNIT))})
	for o in d.get("objects", []):
		var pos := _vec(o.get("pos", null))
		if not in_bounds(pos):
			return "object at %s is off the map" % pos
		objects.append({"code": int(o.get("code", 0)), "pos": pos})
	for t in d.get("tile_overrides", []):
		tile_overrides.append(Vector3i(int(t[0]), int(t[1]), int(t[2])))
	return ""


func get_country(id: int) -> Dictionary:
	for c in countries:
		if c.id == id:
			return c
	return {}


func terrain_at(x: int, y: int) -> String:
	return terrain[y][x]


func territory_at(x: int, y: int) -> int:
	if territory.is_empty():
		return -1
	var ch := territory[y][x]
	return -1 if ch == "." else int(ch)


func in_bounds(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < width and p.y < height


static func _vec(v) -> Vector2i:
	if typeof(v) != TYPE_ARRAY or v.size() < 2:
		return Vector2i(-1, -1)
	return Vector2i(int(v[0]), int(v[1]))
