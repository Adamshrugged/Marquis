extends RefCounted
class_name World

## The map's mutable state: terrain, territory, villages.
## Cells that change are queued in `dirty` for the renderer to redraw.

const BLOCKING := "~^xo*"  # terrain chars units can't walk on
## For the info panels: what each terrain char is called, and full durability of structures
const TERRAIN_NAMES := {".": "Clear land", "T": "Woods", "~": "Water", "^": "Mountain", "=": "Bridge",
	"b": "Bridge", "x": "Barricade", "o": "Cave", "*": "Rubble"}
const MAX_DURABILITY := {"=": Rules.BRIDGE_MAX, "b": Rules.BRIDGE_MAX, "x": Rules.BARRICADE_MAX, "*": Rules.MAP_BARRICADE}
const N8: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1),
	Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1),
]
const C_CLEAR := 46   # "."
const C_WOODS := 84   # "T"
const OBSTACLE_NONE := 0
const OBSTACLE_CLEARABLE := 1   # barricade or rubble
const OBSTACLE_CAVE := 2
const N4: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

var width: int
var height: int
var terrain: PackedStringArray        # terrain[y][x], see Levels/FORMAT.md
var territory: PackedInt32Array       # owner or -1
var village_owner: PackedInt32Array   # owner or -1
var village_pop: PackedFloat32Array
var castle_owner: PackedInt32Array    # owner of castle cells, -1 elsewhere
var castles: Dictionary = {}          # owner -> top-left Vector2i
var objects: Dictionary = {}          # idx -> tile code
var overrides: Dictionary = {}        # idx -> tile code (original-map fixes)
var villages: Dictionary = {}         # idx -> true, every village cell
var walkable: PackedByteArray         # 1 = units can stand here
var nb4: PackedInt32Array             # 4 neighbour indices per cell (N, E, S, W), -1 off the map
var tcode: PackedByteArray           # terrain char codes, same as `terrain` but fast to read
var obstacle: PackedByteArray         # fast lookup: OBSTACLE_* for barricade/rubble/cave cells
var durability: PackedInt32Array      # bridges, barricades, rubble
var caves: Dictionary = {}            # idx -> true
var new_bridges: Dictionary = {}      # idx -> true, bridges still being built from scratch
var dirty: Array[Vector2i] = []


static func from_level(level: Level) -> World:
	var w := World.new()
	w.width = level.width
	w.height = level.height
	w.terrain = level.terrain.duplicate()
	var n := w.width * w.height
	w.territory.resize(n)
	w.village_owner.resize(n)
	w.village_pop.resize(n)
	w.castle_owner.resize(n)
	w.territory.fill(-1)
	w.village_owner.fill(-1)
	w.castle_owner.fill(-1)
	for y in w.height:
		for x in w.width:
			w.territory[w.idx(Vector2i(x, y))] = level.territory_at(x, y)
	for c in level.countries:
		w.castles[c.id] = c.castle
		for dy in 3:
			for dx in 3:
				w.castle_owner[w.idx(c.castle + Vector2i(dx, dy))] = c.id
	for v in level.villages:
		var i := w.idx(v.pos)
		w.villages[i] = true
		w.village_owner[i] = v.owner
		w.village_pop[i] = Rules.POP_PER_TERRITORY
		w.territory[i] = v.owner
	for o in level.objects:
		w.objects[w.idx(o.pos)] = o.code
	for t in level.tile_overrides:
		w.overrides[w.idx(Vector2i(t.x, t.y))] = t.z
	w.walkable.resize(n)
	w.nb4.resize(n * 4)
	for i in n:
		var p := w.pos(i)
		for k in 4:
			var q: Vector2i = p + N4[k]
			w.nb4[i * 4 + k] = w.idx(q) if w.in_bounds(q) else -1
	w.tcode.resize(n)
	w.obstacle.resize(n)
	w.durability.resize(n)
	for i in n:
		w._update_walkable(i)
		var t := w.terrain_at(w.pos(i))
		if t == "b":
			# A damaged bridge is an ordinary bridge with low durability
			var p := w.pos(i)
			var row := w.terrain[p.y]
			w.terrain[p.y] = row.substr(0, p.x) + "=" + row.substr(p.x + 1)
			w.durability[i] = Rules.BRIDGE_DAMAGED_START
		elif t == "=":
			w.durability[i] = Rules.BRIDGE_MAX
		elif t in "x*":
			w.durability[i] = Rules.MAP_BARRICADE
		elif t == "o":
			w.caves[i] = true
		w.tcode[i] = w.terrain_at(w.pos(i)).unicode_at(0)
	return w


func idx(p: Vector2i) -> int:
	return p.y * width + p.x


func pos(i: int) -> Vector2i:
	return Vector2i(i % width, i / width)


func in_bounds(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < width and p.y < height


func terrain_at(p: Vector2i) -> String:
	return terrain[p.y][p.x]


func set_terrain(p: Vector2i, ch: String) -> void:
	var row := terrain[p.y]
	terrain[p.y] = row.substr(0, p.x) + ch + row.substr(p.x + 1)
	tcode[idx(p)] = ch.unicode_at(0)
	_update_walkable(idx(p))
	if ch == "o":
		caves[idx(p)] = true
	else:
		caves.erase(idx(p))
	_mark(p, true)


## Castle: only the centre and the entrance (bottom middle) are walkable.
func castle_center(owner: int) -> Vector2i:
	return castles[owner] + Vector2i(1, 1)


func castle_entrance(owner: int) -> Vector2i:
	return castles[owner] + Vector2i(1, 2)


func is_walkable(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < width and p.y < height and walkable[p.y * width + p.x] == 1


func _update_walkable(i: int) -> void:
	var p := pos(i)
	var t := terrain_at(p)
	obstacle[i] = OBSTACLE_CLEARABLE if t in "x*" else (OBSTACLE_CAVE if t == "o" else OBSTACLE_NONE)
	var co := castle_owner[i]
	var ok: bool
	if co >= 0:
		ok = p == castle_center(co) or p == castle_entrance(co)
	else:
		ok = not (terrain_at(p) in BLOCKING)
	walkable[i] = 1 if ok else 0


## Clear land a barricade can go on (or an existing barricade to strengthen).
func can_barricade(p: Vector2i) -> bool:
	var i := idx(p)
	if terrain_at(p) == "x":
		return true
	return terrain_at(p) == "." and village_owner[i] < 0 and castle_owner[i] < 0 and not objects.has(i)


## Water next to somewhere walkable, or a bridge that isn't at full durability.
func can_bridge(p: Vector2i) -> bool:
	var t := terrain_at(p)
	if t in "=b":
		return durability[idx(p)] < Rules.BRIDGE_MAX
	if t != "~":
		return false
	for d in N4:
		if is_walkable(p + d):
			return true
	return false


## Durability changes can change how a cell looks (damaged bridges).
func set_durability(p: Vector2i, value: int) -> void:
	durability[idx(p)] = value
	_mark(p, false)


## A defeated country's castle disappears, leaving open ground (as in LMO).
func remove_castle(owner: int) -> void:
	if not castles.has(owner):
		return
	var top: Vector2i = castles[owner]
	for dy in 3:
		for dx in 3:
			var p := top + Vector2i(dx, dy)
			castle_owner[idx(p)] = -1
			territory[idx(p)] = -1
			set_terrain(p, ".")


func move_days(p: Vector2i) -> int:
	return Rules.WOODS_MOVE_DAYS if terrain_at(p) == "T" else 1


func territory_of(p: Vector2i) -> int:
	return territory[idx(p)]


func village_at(p: Vector2i) -> int:
	return village_owner[idx(p)]


## Clear land, no village, not castle, no own village in the 8 neighbours.
## allow_woods: woods count as clear land (a planned village clears them first).
func can_build_village(p: Vector2i, owner: int, allow_woods := false) -> bool:
	var i := p.y * width + p.x
	var t := tcode[i]
	if (t != C_CLEAR and not (allow_woods and t == C_WOODS)) or village_owner[i] >= 0 or castle_owner[i] >= 0:
		return false
	if territory[i] >= 0 and territory[i] != owner:
		return false
	for dy in range(maxi(p.y - 1, 0), mini(p.y + 2, height)):
		for dx in range(maxi(p.x - 1, 0), mini(p.x + 2, width)):
			if village_owner[dy * width + dx] == owner:
				return false
	return not objects.has(i)


func place_village(p: Vector2i, owner: int, pop: float) -> void:
	var i := idx(p)
	villages[i] = true
	village_owner[i] = owner
	village_pop[i] = pop
	territory[i] = owner
	_mark(p, false)
	for d in N8:
		claim_cell(p + d, owner)


## Make a neighbouring cell territory. Only clear, unowned, non-castle land.
func claim_cell(p: Vector2i, owner: int) -> bool:
	if not in_bounds(p):
		return false
	var i := idx(p)
	if terrain_at(p) != "." or territory[i] >= 0 or castle_owner[i] >= 0 or village_owner[i] >= 0:
		return false
	territory[i] = owner
	_mark(p, false)
	return true


func territory_count(p: Vector2i, owner: int) -> int:
	var n := 0
	for d in N8:
		var q := p + d
		if in_bounds(q) and territory[idx(q)] == owner:
			n += 1
	return n


func village_cap(p: Vector2i) -> float:
	return (territory_count(p, village_owner[idx(p)]) + 1) * Rules.POP_PER_TERRITORY


## Remove a village. Its territory is freed unless another village of the
## same owner also borders it.
func destroy_village(p: Vector2i) -> void:
	var i := idx(p)
	var owner := village_owner[i]
	villages.erase(i)
	village_owner[i] = -1
	village_pop[i] = 0
	territory[i] = -1
	_mark(p, false)
	for d in N8:
		var q := p + d
		if in_bounds(q) and territory[idx(q)] == owner and not _borders_village(q, owner):
			territory[idx(q)] = -1
			_mark(q, false)


func transfer_owner(from: int, to: int) -> void:
	for i in territory.size():
		if territory[i] == from:
			territory[i] = to
			_mark(pos(i), false)
		if village_owner[i] == from:
			village_owner[i] = to
			_mark(pos(i), false)


func villages_of(owner: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for i in villages:
		if village_owner[i] == owner:
			out.append(pos(i))
	return out


func _borders_village(p: Vector2i, owner: int) -> bool:
	for d in N8:
		var q := p + d
		if in_bounds(q) and village_owner[idx(q)] == owner:
			return true
	return false


## A changed cell; terrain changes also change the edge tiles of its neighbours.
func _mark(p: Vector2i, with_neighbours: bool) -> void:
	overrides.erase(idx(p))
	dirty.append(p)
	if with_neighbours:
		for d in N8:
			var q := p + d
			if in_bounds(q):
				overrides.erase(idx(q))
				dirty.append(q)
