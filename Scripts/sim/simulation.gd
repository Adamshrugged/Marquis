extends RefCounted
class_name Simulation

## The whole game state and its daily update. No rendering here, so it can run
## headless (see Tests/sim_smoke.gd). Rules: Docs/RULES.md.

const MONSTER := 4        # owner id of cave monsters; not a country
## Ordered jobs that never end by themselves: queued orders wait behind them
const STAYING_JOBS := ["defend", "reinforce", "barricade_cont", "dismantle_cont"]
## Jobs done from a cell next to the target (the target itself can't be stood on)
const ADJACENT_JOBS := ["barricade", "barricade_cont", "bridge", "clear_path", "dismantle", "dismantle_cont", "seal"]

var world: World
var countries: Array[Country] = []
var units: Array[Unit] = []
var day := 0
var day_limit: int
var player: int
var state := "playing"   # playing, won, lost
var result := ""
var rng := RandomNumberGenerator.new()

var _by_id := {}         # country id -> Country
var _occ := {}           # cell idx -> Array[Unit]
var _reserved := {}      # cell idx -> Unit working towards it
var _next_id := 1
# Search scratch space, reused between searches (_stamp marks visited cells)
var _seen: PackedInt32Array
var _parent: PackedInt32Array
var _dist: PackedInt32Array
var _stamp := 0
var _danger: PackedInt32Array   # = _stamp: a cell this search plans around
# The playbook survey's own search state (see _survey_start)
var _sv_seen: PackedInt32Array
var _sv_parent: PackedInt32Array
var _sv_dist: PackedInt32Array
var _sv_stamp := 0
var _sv_danger: PackedInt32Array
var _sv_queue: PackedInt32Array
var _sv_head := 0
var _sv_start := 0
var _sv_unit: Unit
var _sv_want := {}               # kind -> furthest steps any line wants it
var _sv_found := {}              # kind -> [cell where the work is done, target cell, steps]
var _stats := {}
# Distance maps per country, refreshed every Rules.FIELD_DAYS
var _home_field := {}    # owner -> PackedInt32Array, steps to the nearest own village
var _enemy_field := {}   # owner -> PackedInt32Array, steps to the nearest enemy castle centre
var _raid_field := {}    # owner -> distance to the nearest enemy village
var _castle_field := {}  # country id -> distance to its castle centre (shared by everyone)
var _breach_field := {}  # owner -> same, but barricades and rubble count as passable (AI only)
## Samples for the history graphs, oldest first: {day, land, strength, population},
## each an Array with one number per entry of `countries`. One every `history_every`
## days (it doubles, thinning old samples, if there would be more than HISTORY_MAX).
var history: Array[Dictionary] = []
var history_every := HISTORY_DAYS
const HISTORY_DAYS := 10
const HISTORY_MAX := 400


func _init(level: Level, seed: int = 1) -> void:
	rng.seed = seed
	world = World.from_level(level)
	var n := world.width * world.height
	_seen.resize(n)
	_danger.resize(n)
	_sv_danger.resize(n)
	_parent.resize(n)
	_dist.resize(n)
	_sv_seen.resize(n)
	_sv_parent.resize(n)
	_sv_dist.resize(n)
	day_limit = level.day_limit
	player = level.player
	for c in level.countries:
		var k := Country.new()
		k.id = c.id
		k.color = c.color
		k.control = c.control
		k.funds = c.funds
		k.tax = c.tax
		k.auto_tax = k.control == "ai"
		if c.style in Rules.STYLES:
			k.style = c.style
		elif k.control == "ai":
			k.style = Rules.AI_STYLES[rng.randi_range(0, Rules.AI_STYLES.size() - 1)]
		k.playbook = Playbook.default_units(k.style, k.control == "ai")
		k.tax_book = Playbook.default_tax(k.control == "ai")
		k.leader = _spawn(k.id, world.castle_center(k.id), c.leader)
		k.leader.is_leader = true
		k.leader.order = "standby"
		countries.append(k)
		_by_id[k.id] = k
	# [M] each country starts with a unit just outside its castle (seen in LMO)
	for k in countries:
		var spot := _outside_gate(k.id)
		if spot.x >= 0:
			_spawn(k.id, spot, Rules.START_UNIT)
	for u in level.units:
		if world.is_walkable(u.pos) and country(u.owner) != null:
			_merge_at(_spawn(u.owner, u.pos, u.strength))
	_record_history()


## The nearest walkable cell outside the castle, starting from the gate.
func _outside_gate(owner: int) -> Vector2i:
	var start := world.castle_entrance(owner)
	var seen := {start: true}
	var queue: Array[Vector2i] = [start]
	var head := 0
	while head < queue.size():
		var p := queue[head]
		head += 1
		if world.castle_owner[world.idx(p)] < 0:
			return p
		for d in World.N4:
			var q := p + d
			if world.is_walkable(q) and not seen.has(q):
				seen[q] = true
				queue.append(q)
	return Vector2i(-1, -1)


func country(id: int) -> Country:
	return _by_id.get(id)


func style(k: Country) -> Dictionary:
	return Rules.STYLES[k.style]


func step() -> void:
	if state != "playing":
		return
	day += 1
	for u in units:
		u.prev_pos = u.pos
	for k in countries:
		k.upkeep = 0.0
		k.decay = 0.0
	if day % Rules.FIELD_DAYS == 1:
		_build_fields()
		_prune_plans()
	_watch_threats()
	_grow_villages()
	_tick_caves()
	for u in units.duplicate():
		if not u.dead:
			_update_unit(u)
	_update_leaders()
	# After the leaders too: a unit they release can merge or fight at the gate
	units.assign(units.filter(func(u): return not u.dead))
	_collect_taxes()
	_check_end()
	if day % history_every == 0 or state != "playing":
		_record_history()


# --- Villages -------------------------------------------------------------

## Each village acts every Rules.CELL_DAYS days, in turn by cell [E]. It grows by its
## own territory neighbours + 1. Once full ((territory + 1) x 16) it claims a clear
## neighbour, or else takes over another country's territory; with no land to claim,
## or at 200+ population, its whole population leaves as one unit. Tax has no part in it.
func _grow_villages() -> void:
	for i in world.villages.keys():
		if (i + day) % Rules.CELL_DAYS != 0:
			continue
		var owner := world.village_owner[i]
		var p := world.pos(i)
		if not country(owner).alive:
			# A beaten country's village changes hands, with its territory (no growth) [E]
			var to := _heir(country(owner))
			if to == MONSTER:
				world.destroy_village(p)
			else:
				world.hand_over_village(p, to)
			continue
		var n := world.territory_count(p, owner)
		var pop := world.village_pop[i] + n + 1
		world.village_pop[i] = pop
		if pop < (n + 1) * Rules.POP_PER_TERRITORY:
			continue
		world.village_pop[i] = minf(pop, Rules.VILLAGE_POP_MAX)
		if _expand(p, owner) and world.village_pop[i] < Rules.VILLAGE_RELEASE_POP:
			continue
		_release(i, owner)


## Claim the first clear neighbour, or else the first neighbour that is another
## country's territory [E].
func _expand(p: Vector2i, owner: int) -> bool:
	for d in World.N8:
		if world.claim_cell(p + d, owner):
			return true
	for d in World.N8:
		if world.claim_cell(p + d, owner, true):
			return true
	return false


## A full village's population leaves as one unit (or joins an own unit standing
## there); the village keeps 1 [E].
func _release(i: int, owner: int) -> void:
	var p := world.pos(i)
	var pop := world.village_pop[i]
	for e in _units_at(p):
		if e.owner == owner and not e.dead:
			e.strength = minf(e.strength + pop, Rules.MAX_VALUE)
			world.village_pop[i] = 1
			return
	if not _units_at(p).is_empty() or not _slot_free() or pop < 2:
		return
	world.village_pop[i] = 1
	var u := _spawn(owner, p, pop - 1)
	u.order = country(owner).default_order


## Room for another unit on the map (Rules.MAX_UNITS, everyone together) [E].
func _slot_free() -> bool:
	var n := 0
	for u in units:
		if not u.dead:
			n += 1
	return n < Rules.MAX_UNITS


# --- Units ----------------------------------------------------------------

## A unit's day: two ticks [E]. Each tick it pays upkeep (walking or not), then fights
## an enemy next to it if there is one, or else acts: the first tick works, walks or
## picks a job, the second works or walks on. A step or a turn takes a tick, so a
## unit walks up to two cells a day.
func _update_unit(u: Unit) -> void:
	if _defeated(u):
		_hand_over(u)
		if u.dead:
			return
	for t in Rules.TICKS_PER_DAY:
		if u.owner != MONSTER and not _upkeep(u):
			_kill(u)
			return
		if u.owner != MONSTER:
			_erase_enemy_land(u)
		if _fight_round(u):
			if u.dead:
				return
			continue
		if u.owner == MONSTER:
			_monster_tick(u)
		elif t == 0:
			_act(u)
		elif u.work > 0:
			if not u.watching:
				_work_tick(u)
		elif not u.path.is_empty():
			_step(u)
		if u.dead:
			return


## Standing on another country's territory turns it back into clear land [E] (not
## villages or castles).
func _erase_enemy_land(u: Unit) -> void:
	var i := world.idx(u.pos)
	var t := world.territory[i]
	if t >= 0 and t != u.owner and world.village_owner[i] < 0 and world.castle_owner[i] < 0:
		world.unclaim_cell(u.pos)


## Upkeep for one tick [E]: on any castle centre or its own village a unit pays
## strength / 2048 funds; elsewhere, or without the funds, it loses strength / 256 + 1.
## A leader in its own castle pays nothing. False when the unit is used up.
func _upkeep(u: Unit) -> bool:
	var k := country(u.owner)
	var i := world.idx(u.pos)
	var centre := world.is_castle_centre(i)
	if u.is_leader and centre and world.castle_owner[i] == u.owner:
		return true
	if centre or world.village_owner[i] == u.owner:
		var cost := floorf(u.strength / Rules.UPKEEP_THRESHOLD)
		if k.funds >= cost:
			k.funds -= cost
			k.upkeep += cost
			return true
	var loss := floorf(u.strength / Rules.DECAY_DIVISOR) + 1
	k.decay += minf(loss, u.strength)
	if loss >= u.strength:
		return false
	u.strength -= loss
	return true


## The first tick's action: work, walk, or pick a job.
func _act(u: Unit) -> void:
	if u.work > 0:
		if not u.watching:
			_work_tick(u)
		else:
			u.work -= 1
			if u.work == 0:
				_start_work(u)   # look at the target again
		return
	if u.path.is_empty():
		if u.job != "" and _at_site(u):
			_start_work(u)
			return
		if not u.order.begins_with("auto"):
			return
		if u.idle > 0:
			u.idle -= 1
			return
		_choose_job(u)
		if u.path.is_empty():
			if u.job != "":
				_start_work(u)  # target is where it already stands
			return
	_step(u)


## One tick on the path: turn to face the next cell, or step into it [E].
func _step(u: Unit) -> void:
	var next: Vector2i = u.path[0]
	if not world.is_walkable(next):
		if u.ordered:
			var route := _route_for(u, u.job_target, u.job)
			if route.is_empty() and not _at_site(u):
				_job_done(u)
			else:
				u.path.assign(route.get("path", []))
		else:
			_drop_job(u)
		return
	if next - u.pos != u.facing:
		u.facing = next - u.pos   # turning takes the tick
		return
	if _units_at(next).any(func(e): return e.owner != u.owner and not e.dead):
		return   # fought from here, a round each tick (_fight_round)
	var vo := world.village_at(next)
	if vo >= 0 and vo != u.owner:
		_attack_village(u, next)   # takes the day; the unit moves in once it falls
		return
	_move(u, next)
	u.path.pop_front()
	_merge_at(u)


## An idle Auto unit follows its country's playbook: the first line that applies to
## its size and finds something to do wins. Otherwise it goes home.
func _choose_job(u: Unit) -> void:
	var k := country(u.owner)
	var builders := 0
	for o in _reserved.values():
		if o.owner == u.owner and o.job == "build":
			builders += 1
	var can_afford := k.funds - k.reserve - builders * Rules.VILLAGE_COST >= Rules.VILLAGE_COST
	# How far the shared search must look for each kind of work the lines want
	var reach := {}
	for l in k.playbook:
		if l.action in Playbook.SURVEYED and Playbook.applies(l, u.strength):
			var d: int = 9999 if l.dist < 0 else l.dist
			reach[l.action] = maxi(reach.get(l.action, 0), d)
	var surveying := false
	var home := world.village_at(u.pos) == u.owner
	for n in k.playbook.size():
		var l: Dictionary = k.playbook[n]
		if not Playbook.applies(l, u.strength):
			continue
		var found := {}
		match l.action:
			"plans":
				found = _plan_job(u, k, l.dist, can_afford)
			"guard":
				found = _guard_job(u, k, l.dist)
			"army":
				found = _army_job(u, k)
			"home":
				if home:
					_set_line(u, k, n)
					u.idle = Rules.IDLE_RETHINK_DAYS
					return
				found = _follow(u, _home_field.get(u.owner), "home")
			_:
				if not surveying:
					_survey_start(u, reach, can_afford)
					surveying = true
				found = _survey_find(l.action, l.dist)
		if not found.is_empty():
			_set_line(u, k, n)
			_take_job(u, found)
			return
	_set_line(u, k, -1)
	if k.control == "ai" and _breach_field.has(u.owner):
		# The way to the enemy needs a bridge or a barricade cleared: anyone can do that work
		var breach := _breach(u, _breach_field[u.owner])
		if not breach.is_empty():
			_take_job(u, breach)
			return
	# Otherwise: go home. Small units rest longer; big ones check on the army sooner
	if home:
		u.idle = Rules.IDLE_RETHINK_DAYS * (3 if u.strength <= style(k).march else 1)
		return
	var back := _follow(u, _home_field.get(u.owner), "home")
	if back.is_empty():
		u.idle = Rules.IDLE_RETHINK_DAYS
		return
	_take_job(u, back)


func _set_line(u: Unit, k: Country, n: int) -> void:
	u.line = n
	u.line_text = "Otherwise: go home" if n < 0 else "Line %d: %s" % [n + 1, Playbook.describe(k.playbook[n])]


func _take_job(u: Unit, found: Dictionary) -> void:
	u.job = found.kind
	u.job_target = found.target
	u.path = found.path
	if u.job in ["clear", "build", "clear_path", "bridge", "seal"]:
		_reserved[world.idx(u.job_target)] = u
	if u.path.is_empty() and u.job != "" and not _at_site(u):
		_drop_job(u)


## Enemies near the castle: units within `dist` steps of the gate (-1: any) come
## back and stand in it, where they fight at x2.
func _guard_job(u: Unit, k: Country, dist: int) -> Dictionary:
	if not k.threat:
		return {}
	var gate := world.castle_entrance(k.id)
	var off := u.pos - gate
	if dist >= 0 and absi(off.x) + absi(off.y) > dist:
		return {}
	if u.pos == gate:
		var here: Array[Vector2i] = []
		return {"path": here, "target": gate, "kind": "guard"}
	var route := _route(u, gate)
	if route.is_empty():
		return {}
	route.kind = "guard"
	route.target = gate
	return route


func _watch_threats() -> void:
	for k in countries:
		if not k.alive or not k.playbook.any(func(l): return l.on and l.action == "guard"):
			k.threat = false
			continue
		var was := k.threat
		k.threat = false
		var centre := world.castle_center(k.id)
		for e in units:
			# Units in their own castle (leader, gate guards) aren't coming for anyone
			if e.owner != k.id and not e.dead and world.castle_owner[world.idx(e.pos)] != e.owner:
				var off := e.pos - centre
				if absi(off.x) + absi(off.y) <= Rules.THREAT_RADIUS:
					k.threat = true
					break
		if k.threat and not was:
			# Wake idle units so they can respond now, not in up to 10 days
			for u in units:
				if u.owner == k.id and u.order == "auto" and u.work == 0 and u.job in ["", "home", "rally"]:
					_drop_job(u)
					u.idle = 0


## The playbook's shared search: breadth-first from the unit, recording the nearest
## of each kind of work in `reach` ({kind: max steps}). It only grows as far as the
## lines being checked need (_survey_find), so a unit with work next door doesn't
## scan the whole map for its "anywhere" lines. Built-in checks: clear woods next to
## own land; build where allowed with funds to spare, leaving room for planned
## villages; attack units it outweighs by 20% (even odds on own land, never a
## leader); destroy villages whose population it outweighs by 20%; seal caves near
## own land if strong enough; clear barricades and rubble.
## Own scratch arrays, so other searches in between (job board, army) don't disturb it.
func _survey_start(u: Unit, reach: Dictionary, can_afford: bool) -> void:
	_sv_unit = u
	_sv_want = reach.duplicate()
	if not can_afford:
		_sv_want.erase("build")
	# Work goes at strength / n per tick: too small a unit gets nowhere [E]
	if u.strength < Rules.SEAL_DIV:
		_sv_want.erase("seal")
	if u.strength < Rules.PULL_DIV:
		_sv_want.erase("clear_path")
	if u.strength < Rules.CLEAR_DIV:
		_sv_want.erase("clear")
	_sv_found = {}
	_sv_start = world.idx(u.pos)
	_sv_stamp += 1
	_sv_seen[_sv_start] = _sv_stamp
	for c in _danger_cells(u, Vector2i(-1, -1)):
		_sv_danger[c] = _sv_stamp
	_sv_dist[_sv_start] = 0
	_sv_queue = PackedInt32Array([_sv_start])
	_sv_head = 0


## The nearest work of a kind within `limit` steps (-1: as far as the playbook wants
## it), as {path, target, kind (the job)}, or {}.
func _survey_find(kind: String, limit: int) -> Dictionary:
	if not _sv_want.has(kind):
		return {}
	var most: int = _sv_want[kind] if limit < 0 else mini(limit, _sv_want[kind])
	if not _sv_found.has(kind):
		_survey_grow(kind, most)
	var f: Array = _sv_found.get(kind, [])
	if f.is_empty() or f[2] > most:
		return {}
	var path: Array[Vector2i] = []
	var c: int = f[0]
	while c != _sv_start:
		path.push_front(world.pos(c))
		c = _sv_parent[c]
	return {"path": path, "target": world.pos(f[1]), "kind": "attack" if kind == "destroy" else kind}


## Grow the search until `kind` is found or the next cell is over `most` steps away
## (it stays queued for a later, further line). Each cell is checked for every kind
## of work wanted. Written inline over cell indices because it runs for every idle unit.
func _survey_grow(kind: String, most: int) -> void:
	var u := _sv_unit
	var owner := u.owner
	var strength := u.strength
	var want := _sv_want
	var found := _sv_found
	var w := world.width
	var nb := world.nb4
	var walkable := world.walkable
	var obstacle := world.obstacle
	var tcode := world.tcode
	var village_owner := world.village_owner
	var village_pop := world.village_pop
	var castle_owner := world.castle_owner
	var plans: Dictionary = country(owner).plans
	var open_work := want.has("seal") or want.has("clear_path")
	var stamp := _sv_stamp
	var start := _sv_start
	while not found.has(kind) and _sv_head < _sv_queue.size():
		var i := _sv_queue[_sv_head]
		var d := _sv_dist[i]
		if d > most:
			return
		_sv_head += 1
		var p := Vector2i(i % w, i / w)
		if not _reserved.has(i) or _reserved[i] == u:
			if open_work:
				for n in 4:
					var j := nb[i * 4 + n]
					if j < 0 or obstacle[j] == World.OBSTACLE_NONE or _reserved.has(j):
						continue
					if obstacle[j] == World.OBSTACLE_CLEARABLE:
						_found("clear_path", d, i, j)
					elif want.has("seal") and not found.has("seal") and _own_land_near(world.pos(j), owner, Rules.SEAL_NEAR):
						_found("seal", d, i, j)
			if tcode[i] == World.C_WOODS and want.has("clear") and not found.has("clear") and _next_to_own_land(p, owner):
				_found("clear", d, i, i)
			var vo := village_owner[i]
			if vo >= 0 and vo != owner and strength > village_pop[i] * 1.2:
				_found("destroy", d, i, i)
			if _occ.has(i) and want.has("attack") and not found.has("attack"):
				# Intruders on own land are worth fighting at even odds [G]
				var odds := 1.0 if world.territory[i] == owner else 1.2
				for e in _occ[i]:
					if e.owner != owner and not e.is_leader and strength > e.strength * odds:
						_found("attack", d, i, i)
						break
			if want.has("build") and not found.has("build") and world.can_build_village(p, owner) \
					and (plans.is_empty() or plans.has(i) or not _near_build_plan(plans, p)):
				_found("build", d, i, i)
		if i != start:
			# Enemy villages, castles and units end a branch: they're targets, not corridors
			var vo2 := village_owner[i]
			if vo2 >= 0 and vo2 != owner:
				continue
			var co := castle_owner[i]
			if co >= 0 and co != owner:
				continue
			if _occ.has(i) and _occ[i].any(func(e): return e.owner != owner):
				continue
		for n in 4:
			var j := nb[i * 4 + n]
			if j < 0 or walkable[j] == 0 or _sv_seen[j] == stamp or _sv_danger[j] == stamp:
				continue
			_sv_seen[j] = stamp
			_sv_parent[j] = i
			_sv_dist[j] = d + 1
			_sv_queue.append(j)


## Record the first (nearest) find of a kind, if the playbook wants it that far.
func _found(kind: String, d: int, at: int, target: int) -> void:
	if _sv_want.has(kind) and not _sv_found.has(kind) and d <= _sv_want[kind]:
		_sv_found[kind] = [at, target, d]


## Breadth-first search from the unit. scorer(p, dist) returns [score, kind]
## or [score, kind, target] (work on target from p), or null. Enemy villages, units and castles end a branch (they're targets,
## not corridors). Cells by enemies it can't beat are avoided (see _danger_cells),
## except around `goal`, the target it was sent to. Returns {path, target, kind} for the lowest score, or {}.
func _search(u: Unit, max_dist: int, scorer: Callable, goal := Vector2i(-1, -1)) -> Dictionary:
	var start := world.idx(u.pos)
	_stamp += 1
	for c in _danger_cells(u, goal):
		_danger[c] = _stamp
	_seen[start] = _stamp
	_dist[start] = 0
	var queue: PackedInt32Array = [start]
	var best := -1
	var best_score := INF
	var best_kind := ""
	var best_target := Vector2i(-1, -1)
	var head := 0
	while head < queue.size():
		var i: int = queue[head]
		head += 1
		var d: int = _dist[i]
		if d > best_score or d > max_dist:
			break
		var p := world.pos(i)
		var r = scorer.call(p, d)
		if r != null and r[0] < best_score:
			best_score = r[0]
			best = i
			best_kind = r[1]
			best_target = r[2] if r.size() > 2 else p
		if i != start and _blocks_search(p, u.owner):
			continue
		for n in 4:
			var j := world.nb4[i * 4 + n]
			if j < 0 or world.walkable[j] == 0 or _seen[j] == _stamp or _danger[j] == _stamp:
				continue
			_seen[j] = _stamp
			_parent[j] = i
			_dist[j] = d + 1
			queue.append(j)
	if best < 0:
		return {}
	var path: Array[Vector2i] = []
	var c := best
	while c != start:
		path.push_front(world.pos(c))
		c = _parent[c]
	return {"path": path, "target": best_target, "kind": best_kind}


## Strong idle units gather at the rally village, merging into one army.
## Once the army beats the target leader's castle strength, it marches.
func _army_job(u: Unit, k: Country) -> Dictionary:
	if k.target < 0 or not country(k.target).alive:
		return {}
	var needed: float = country(k.target).leader.strength * Rules.CASTLE_STRENGTH * style(k).margin
	if u.strength >= needed or k.rally.x < 0:
		u.waited = 0
		var march := _follow(u, _enemy_field.get(u.owner), "march")
		if march.is_empty() and _breach_field.has(u.owner):
			return _breach(u, _breach_field[u.owner])
		return march
	if u.pos == k.rally:
		u.waited += Rules.IDLE_RETHINK_DAYS
		# Too costly or too long to keep waiting: raid enemy villages meanwhile
		if u.strength >= Rules.RAID_STRENGTH or u.waited >= Rules.RAID_WAIT_DAYS:
			u.waited = 0
			return _follow(u, _raid_field.get(u.owner), "attack")
		return {}
	return _search(u, 9999, func(p: Vector2i, d: int):
		return [d, "rally"] if p == k.rally else null)


## No open way to the enemy: head downhill on the breach map and clear the
## first barricade in the way, or bridge the first stretch of water.
func _breach(u: Unit, field: PackedInt32Array) -> Dictionary:
	var i := world.idx(u.pos)
	if field[i] <= 0 or field[i] >= INT32_MAX:
		return {}
	var path: Array[Vector2i] = []
	var p := u.pos
	for n in 9999:
		var best := p
		for d in World.N4:
			var q := p + d
			if world.in_bounds(q) and field[world.idx(q)] < field[world.idx(best)]:
				best = q
		if best == p:
			return {}
		if not world.is_walkable(best):
			if _reserved.has(world.idx(best)):
				return {}
			if world.terrain_at(best) in "~b":
				if country(u.owner).funds < Rules.BRIDGE_NEW_COST or u.strength < Rules.BUILD_DIV:
					return {}
				return {"path": path, "target": best, "kind": "bridge"}
			if u.strength < Rules.PULL_DIV:
				return {}
			return {"path": path, "target": best, "kind": "clear_path"}
		p = best
		path.append(p)
		if field[world.idx(p)] == 0:
			break
	return {}


## Path downhill on a distance map to its nearest target.
func _follow(u: Unit, field, kind: String) -> Dictionary:
	if field == null:
		return {}
	var i := world.idx(u.pos)
	if field[i] <= 0 or field[i] >= INT32_MAX:
		return {}
	var path: Array[Vector2i] = []
	var p := u.pos
	while field[world.idx(p)] > 0:
		var best := p
		for d in World.N4:
			var q := p + d
			if world.is_walkable(q) and field[world.idx(q)] < field[world.idx(best)]:
				best = q
		if best == p:
			return {}
		p = best
		path.append(p)
	return {"path": path, "target": p, "kind": kind}


const INT32_MAX := 2147483647

## Multi-source breadth-first distance maps over walkable cells.
func _build_fields() -> void:
	_castle_field.clear()
	for o in countries:
		if o.alive:
			_castle_field[o.id] = _distance_map(PackedInt32Array([world.idx(world.castle_center(o.id))]))
	for k in countries:
		if not k.alive:
			continue
		var homes: PackedInt32Array = []
		var enemy_villages: PackedInt32Array = []
		for i in world.villages:
			if world.village_owner[i] == k.id:
				homes.append(i)
			else:
				enemy_villages.append(i)
		_home_field[k.id] = _distance_map(homes)
		_raid_field[k.id] = _distance_map(enemy_villages)
		k.target = _pick_target(k)
		k.reserve = 0.0
		if k.target < 0:
			continue
		var field: PackedInt32Array = _castle_field[k.target]
		_enemy_field[k.id] = field
		if k.control == "ai" and field[world.idx(world.castle_entrance(k.id))] >= INT32_MAX:
			# Plan a way in through barricades; if even that fails, across water too
			var castle := PackedInt32Array([world.idx(world.castle_center(k.target))])
			var breach := _distance_map(castle, "x*")
			if breach[world.idx(world.castle_entrance(k.id))] >= INT32_MAX:
				breach = _distance_map(castle, "x*~b")
				k.reserve = Rules.BRIDGE_NEW_COST * (Rules.CELL_START + 1)   # save up for a bridge
			_breach_field[k.id] = breach
		else:
			_breach_field.erase(k.id)
		k.rally = Vector2i(-1, -1)
		var best := INT32_MAX
		for i in homes:
			if field[i] < best:
				best = field[i]
				k.rally = world.pos(i)


## The enemy that's cheapest to beat: castle strength, scaled by distance.
## Castles only reachable through barricades or water cost extra.
func _pick_target(k: Country) -> int:
	var gate := world.idx(world.castle_entrance(k.id))
	var best := -1
	var best_cost := INF
	for o in countries:
		if not o.alive or o.id == k.id:
			continue
		var dist: int = _castle_field[o.id][gate]
		var cost := o.leader.strength * Rules.CASTLE_STRENGTH
		if dist >= INT32_MAX:
			cost *= Rules.UNREACHABLE_PENALTY * 2.0
		else:
			cost *= 1.0 + dist / 48.0
		if cost < best_cost:
			best_cost = cost
			best = o.id
	return best


## `through`: terrain chars treated as passable too (to plan a way through barricades).
func _distance_map(sources: PackedInt32Array, through: String = "") -> PackedInt32Array:
	var dist := PackedInt32Array()
	dist.resize(world.width * world.height)
	dist.fill(INT32_MAX)
	var queue := sources.duplicate()
	for i in sources:
		dist[i] = 0
	var head := 0
	while head < queue.size():
		var i := queue[head]
		head += 1
		var p := world.pos(i)
		for d in World.N4:
			var q := p + d
			if not world.is_walkable(q) and not (through != "" and world.in_bounds(q) and world.terrain_at(q) in through):
				continue
			var j := world.idx(q)
			if dist[j] > dist[i] + 1:
				dist[j] = dist[i] + 1
				queue.append(j)
	return dist


## Cells a unit plans its way around [E]: enemies it can't beat and their 4 neighbours.
## Can't beat = stronger than its strength / 1.25, or on a castle centre than its
## strength / 2 (a unit) or / 4 (a leader). The goal, and an enemy standing on it, are
## never avoided: a unit sent to attack something goes. Monsters plan nothing.
func _danger_cells(u: Unit, goal: Vector2i) -> PackedInt32Array:
	var out := PackedInt32Array()
	if u.owner == MONSTER:
		return out
	var g := world.idx(goal) if world.in_bounds(goal) else -1
	for e in units:
		if e.dead or e.owner == u.owner or _defeated(e):
			continue
		var i := world.idx(e.pos)
		if i == g:
			continue
		var beats := u.strength / Rules.AVOID_OPEN
		if world.is_castle_centre(i):
			beats = u.strength / (Rules.AVOID_LEADER if e.is_leader else Rules.AVOID_CASTLE)
		if e.strength <= beats:
			continue
		out.append(i)
		for n in 4:
			var j := world.nb4[i * 4 + n]
			if j >= 0 and j != g:
				out.append(j)
	return out


func _blocks_search(p: Vector2i, owner: int) -> bool:
	var vo := world.village_at(p)
	if vo >= 0 and vo != owner:
		return true
	var co := world.castle_owner[world.idx(p)]
	if co >= 0 and co != owner:
		return true
	for e in _units_at(p):
		if e.owner != owner:
			return true
	return false


func _own_land_near(p: Vector2i, owner: int, r: int) -> bool:
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var q := p + Vector2i(dx, dy)
			if world.in_bounds(q) and world.territory_of(q) == owner:
				return true
	return false


func _next_to_own_land(p: Vector2i, owner: int) -> bool:
	var w := world.width
	for dy in range(maxi(p.y - 1, 0), mini(p.y + 2, world.height)):
		for dx in range(maxi(p.x - 1, 0), mini(p.x + 2, w)):
			if world.territory[dy * w + dx] == owner:
				return true
	return false


## Arrived at the job: start working if it can be done, else the job ends.
## Continuous orders with nothing to do watch their target instead.
func _start_work(u: Unit) -> void:
	var k := country(u.owner)
	u.watching = false
	if u.job in ADJACENT_JOBS:
		u.facing = u.job_target - u.pos
	var t := u.job_target
	var ok := false
	match u.job:
		"clear":
			ok = world.terrain_at(u.pos) == "T"
		"build":
			ok = world.can_build_village(u.pos, u.owner) and k.funds >= Rules.VILLAGE_COST
		"defend":
			# Build a village here if possible, then guard it
			ok = world.village_at(u.pos) != u.owner and world.can_build_village(u.pos, u.owner) \
				and k.funds >= Rules.VILLAGE_COST
		"destroy":
			# Enemy villages are attacked on the way in; an own village is taken back in
			ok = world.village_at(u.pos) == u.owner
		"home", "guard":
			u.idle = Rules.IDLE_RETHINK_DAYS
		"barricade", "barricade_cont":
			ok = world.can_barricade(t) and not (world.terrain_at(t) == "x" \
				and world.durability[world.idx(t)] >= Rules.DURABILITY_MAX)
		"bridge":
			ok = world.can_bridge(t)
		"clear_path":
			ok = world.terrain_at(t) in "x*"
		"dismantle", "dismantle_cont":
			ok = world.terrain_at(t) == "=" or (world.terrain_at(t) == "b" \
				and world.durability[world.idx(t)] < Rules.DURABILITY_MAX)
		"seal":
			ok = world.terrain_at(t) == "o"
	if ok:
		u.work = 1
	elif u.job in ["barricade_cont", "dismantle_cont"]:
		_watch(u)
	else:
		_job_done(u)


func _watch(u: Unit) -> void:
	u.work = Rules.WATCH_DAYS
	u.watching = true


## One tick of work. When the job is done (or can't go on) a continuous order
## watches its target, anything else ends.
func _work_tick(u: Unit) -> void:
	if _work_action(u):
		return
	u.work = 0
	if u.dead:
		return
	if u.job in ["barricade_cont", "dismantle_cont"]:
		_watch(u)
		return
	_prune_plan(country(u.owner), world.idx(u.pos))
	_job_done(u)
	if u.strength <= 0:
		_kill(u)


## One action [E]: work goes at strength / n per tick, so big units work fast.
## Counters start at Rules.CELL_START. Returns true while the job goes on.
func _work_action(u: Unit) -> bool:
	var k := country(u.owner)
	var s := int(u.strength)
	var t := u.job_target
	var i := world.idx(t)
	var c := world.durability[i]
	match u.job:
		"clear":
			# Woods: work left - strength / 2; no cost
			var here := world.idx(u.pos)
			var step := s / Rules.CLEAR_DIV
			if world.terrain_at(u.pos) != "T" or step == 0:
				return false
			if world.durability[here] - step >= 1:
				world.set_durability(u.pos, world.durability[here] - step)
				return true
			world.set_terrain(u.pos, ".")
			world.set_durability(u.pos, Rules.CELL_START)
		"build", "defend":
			# The builder gives up to 200 of its strength; the village starts at half + 1
			if world.village_at(u.pos) != u.owner and world.can_build_village(u.pos, u.owner) \
					and k.funds >= Rules.VILLAGE_COST:
				k.funds -= Rules.VILLAGE_COST
				var gives := mini(s, Rules.BUILDER_GIVES)
				world.place_village(u.pos, u.owner, gives / 2 + 1)
				u.strength -= gives
		"destroy":
			# Own village: instant, the unit takes in its population
			var here := world.idx(u.pos)
			if world.village_owner[here] == u.owner:
				u.strength = minf(u.strength + world.village_pop[here], Rules.MAX_VALUE)
				world.destroy_village(u.pos)
		"barricade", "barricade_cont":
			# Clear land: works down the cell's counter, then a barricade stands with
			# what's left over. A barricade: + strength / 16, up to 255. 1 fund per 4 points.
			if not world.can_barricade(t) or not _units_at(t).is_empty():
				return false
			var fresh := world.terrain_at(t) != "x"
			var add := mini(s / Rules.BUILD_DIV, Rules.DURABILITY_MAX - (0 if fresh else c))
			var cost := add / Rules.BARRICADE_POINTS_PER_FUND
			if add <= 0 or k.funds < cost:
				return false
			k.funds -= cost
			if not fresh:
				world.set_durability(t, c + add)
				return u.job == "barricade_cont"
			if add <= c:
				world.set_durability(t, c - add)
				return true
			world.set_terrain(t, "x")
			world.set_durability(t, add - c - 1)
			return u.job == "barricade_cont"
		"bridge":
			# Water: 30 funds a point, ~100 points. Damaged bridge: 2 a point. The
			# finished bridge keeps what's left over as its durability.
			if not world.can_bridge(t):
				return false
			var water := world.terrain_at(t) == "~"
			var add := mini(s / Rules.BUILD_DIV, c + (1 if water else Rules.DURABILITY_MAX))
			var cost := add * (Rules.BRIDGE_NEW_COST if water else Rules.BRIDGE_REPAIR_COST)
			if add <= 0 or k.funds < cost:
				return false
			k.funds -= cost
			if add < c:
				world.set_durability(t, c - add)
				return true
			world.set_terrain(t, "=")
			world.set_durability(t, add - c)
		"clear_path":
			# Barricade or rubble: durability - strength / 32; no cost
			if not world.terrain_at(t) in "x*":
				return false
			var take := s / Rules.PULL_DIV
			if c > 0:
				if take == 0:
					return false
				if take < c:
					world.set_durability(t, c - take)
					return true
			world.set_durability(t, 0)
			world.set_terrain(t, ".")
		"dismantle", "dismantle_cont":
			# Bridge: durability - strength / 32, then it's a damaged bridge and a unit
			# on it is lost. A damaged bridge: + strength / 32 work to repair, up to 255.
			var take := s / Rules.PULL_DIV
			if take == 0:
				return false
			if world.terrain_at(t) == "b":
				if c >= Rules.DURABILITY_MAX:
					return false
				world.set_durability(t, mini(c + take, Rules.DURABILITY_MAX))
				return u.job == "dismantle_cont"
			if world.terrain_at(t) != "=":
				return false
			if c - take > 0:
				world.set_durability(t, c - take)
				return true
			world.set_durability(t, 0)
			world.set_terrain(t, "b")
			for e in _units_at(t).duplicate():
				_kill(e, u.owner)
			return u.job == "dismantle_cont"
		"seal":
			# Cave: work left - strength / 8, done below 0; no cost
			if world.terrain_at(t) != "o" or s / Rules.SEAL_DIV == 0:
				return false
			if c - s / Rules.SEAL_DIV >= 0:
				world.set_durability(t, c - s / Rules.SEAL_DIV)
				return true
			world.set_terrain(t, "^")
	return false


func _at_site(u: Unit) -> bool:
	return work_spot(u.pos, u.job_target, u.job)


## Whether a job on target is done from p: next to it for structures, on it otherwise.
## The one place for this rule (orders, the order preview and routing use it).
static func work_spot(p: Vector2i, target: Vector2i, job: String) -> bool:
	if job in ADJACENT_JOBS:
		var d := p - target
		return absi(d.x) + absi(d.y) == 1
	return p == target


## A job ended. Player-ordered units start their next queued order [G], unless
## the order stays put by nature (STAYING_JOBS). Otherwise they follow the
## order's after-effect: standby/defend/reinforce stay put, auto thinks for
## itself, the rest return to the country's default order.
func _job_done(u: Unit) -> void:
	var was := u.job
	var was_ordered := u.ordered
	_drop_job(u)
	if not was_ordered:
		return
	if not was in STAYING_JOBS and _next_queued(u):
		return
	if was in ["standby", "defend", "reinforce", "move", "barricade_cont", "dismantle_cont"]:
		u.order = "standby"
		u.ordered = was != "move"
	else:
		u.order = "auto" if was == "auto" else country(u.owner).default_order
		u.ordered = false


func _drop_job(u: Unit) -> void:
	var i := world.idx(u.job_target) if u.job_target.x >= 0 else -1
	if i >= 0 and _reserved.get(i) == u:
		_reserved.erase(i)
	u.clear_job()


# --- Caves and monsters [E] -------------------------------------------------

## Each cave acts every Rules.CELL_DAYS days, in turn by cell: its counter goes up by
## 10, and from 245 a monster of strength 200 comes out (if there's room) and the
## counter drops by 245. No randomness. Sealing works the same counter down.
func _tick_caves() -> void:
	for i in world.caves.keys():
		if (i + day) % Rules.CELL_DAYS == 0:
			_cave_tick(i)


func _cave_tick(i: int) -> void:
	var c := mini(world.durability[i] + Rules.CAVE_GROW, Rules.DURABILITY_MAX)
	world.set_durability(world.pos(i), c)
	if c < Rules.CAVE_SPAWN or not _slot_free():
		return
	# Out onto a free cell next to the cave (in LMO, onto the cave itself)
	var cave := world.pos(i)
	for d in World.N4:
		var p: Vector2i = cave + d
		if world.is_walkable(p) and world.castle_owner[world.idx(p)] < 0 \
				and _units_at(p).all(func(e): return e.owner == MONSTER):
			world.set_durability(cave, c - Rules.CAVE_SPAWN)
			var m := _spawn(MONSTER, p, Rules.MONSTER_START)
			m.order = "monster"
			m.facing = d
			_merge_at(m)
			return


## A monster's tick [E]: it doesn't look for targets. It walks straight ahead for
## 20-58 ticks, rests 0-10, and turns at random (to an open side if it can) when
## blocked. What it bumps into it fights, joins (monsters) or attacks (villages).
## Boxed in, it chips at a barricade next to it, 1 point a tick.
func _monster_tick(u: Unit) -> void:
	if u.idle > 0:
		u.idle -= 1
		return
	if u.roam <= 0:
		u.roam = rng.randi_range(Rules.MONSTER_WALK_MIN, Rules.MONSTER_WALK_MAX)
		u.idle = rng.randi_range(0, Rules.MONSTER_REST_MAX)
		return
	u.roam -= 1
	var next := u.pos + u.facing
	if world.is_walkable(next):
		u.path.assign([next])
		_step(u)
		u.path.clear()
		return
	var open: Array[Vector2i] = []
	var walls: Array[Vector2i] = []
	for d in World.N4:
		if world.is_walkable(u.pos + d):
			open.append(d)
		elif world.in_bounds(u.pos + d) and world.terrain_at(u.pos + d) == "x":
			walls.append(d)
	if not open.is_empty():
		u.facing = open[rng.randi_range(0, open.size() - 1)]
	elif not walls.is_empty():
		var p := u.pos + walls[rng.randi_range(0, walls.size() - 1)]
		var c := world.durability[world.idx(p)] - 1
		if c > 0:
			world.set_durability(p, c)
		else:
			world.set_durability(p, 0)
			world.set_terrain(p, ".")


func owner_name(id: int) -> String:
	return "Monster" if id == MONSTER else country(id).color.capitalize()


# --- Combat ---------------------------------------------------------------

## One round against an enemy next to the unit, if there is one (looking ahead
## first) [E]. True if it fought.
func _fight_round(u: Unit) -> bool:
	var start := World.N4.find(u.facing)
	for n in 4:
		var d: Vector2i = World.N4[(maxi(start, 0) + n) % 4]
		for e in _units_at(u.pos + d):
			if e.owner != u.owner and not e.dead and not _defeated(e):
				u.facing = d
				_round(u, e)
				return true
	return false


## a attacks b, which hits back [E]. Damage is strength / n + 1: in the open the
## attacker deals /8 and takes /16; against a castle centre both deal /8; from a
## castle centre the attacker deals /4 and takes nothing.
func _round(a: Unit, b: Unit) -> void:
	if world.is_castle_centre(world.idx(a.pos)):
		_hit(a, b, Rules.HIT_FROM_CASTLE)
		return
	var back := Rules.HIT_CASTLE if world.is_castle_centre(world.idx(b.pos)) else Rules.HIT_BACK
	_hit(a, b, Rules.HIT_OPEN)
	if not b.dead:
		_hit(b, a, back)


func _hit(from: Unit, to: Unit, div: int) -> void:
	var dmg := floorf(from.strength / div) + 1
	if dmg >= to.strength:
		_kill(to, from.owner)
	else:
		to.strength -= dmg


## Moving into an enemy village [E]: both lose the smaller of the unit's strength
## and the village's population.
func _attack_village(u: Unit, p: Vector2i) -> void:
	var i := world.idx(p)
	var owner := world.village_owner[i]
	var loss := minf(u.strength, world.village_pop[i])
	world.village_pop[i] -= loss
	u.strength -= loss
	if world.village_pop[i] <= 0:
		world.destroy_village(p)
	if u.strength <= 0:
		_kill(u, owner)


func _kill(u: Unit, by: int = -1) -> void:
	if u.dead:
		return
	u.dead = true
	_occ_remove(u)
	_drop_job(u)
	if u.is_leader:
		_eliminate(country(u.owner), by)


## Leader defeated. A killer takes over villages, units and funds.
## A beaten country [E]: its castle goes and the conqueror gets its funds at once; its
## villages and units change hands one at a time, each the next time it acts
## (_hand_over). Beaten by monsters or worn away by decay, they're wiped out instead.
func _eliminate(k: Country, by: int) -> void:
	k.alive = false
	world.remove_castle(k.id)
	var heir := country(by) if by >= 0 else null
	k.conqueror = heir.id if heir != null and heir.alive else MONSTER
	if heir != null and heir.alive:
		heir.funds = minf(heir.funds + k.funds, Rules.MAX_VALUE)
	k.funds = 0


## Who a beaten country's things go to now (its conqueror may have been beaten since).
func _heir(k: Country) -> int:
	var id := k.conqueror
	while id != MONSTER and not country(id).alive:
		id = country(id).conqueror
	return id


## A unit of a beaten country, as it acts: it joins the conqueror on Auto, or dies [E].
func _hand_over(u: Unit) -> void:
	var to := _heir(country(u.owner))
	_drop_job(u)
	if to == MONSTER:
		u.dead = true
		_occ_remove(u)
		return
	u.owner = to
	u.ordered = false
	u.queue.clear()
	u.order = "auto"
	_merge_at(u)


## Its units can't be attacked until they change hands [E].
func _defeated(u: Unit) -> bool:
	return u.owner != MONSTER and not country(u.owner).alive


# --- Leaders, tax, end ----------------------------------------------------

## A leader in its castle centre, each tick [E]: if the country's population
## (villages plus units) is below half its strength, a quarter of it leaves through
## the gate (only into an empty gate, with room for a unit); otherwise it grows by
## 1/8 of the gap up to the population. It never shrinks toward it.
func _update_leaders() -> void:
	_count_population()
	for t in Rules.TICKS_PER_DAY:
		for k in countries:
			var l := k.leader
			if not k.alive or l.pos != world.castle_center(k.id):
				continue
			if k.population < l.strength / 2.0:
				var s := floorf(l.strength / 4.0)
				var gate := world.castle_entrance(k.id)
				if s > 0 and _units_at(gate).is_empty() and _slot_free():
					l.strength -= s
					_spawn(k.id, gate, s).order = k.default_order
					k.population += s
			elif l.strength < k.population:
				l.strength = minf(l.strength + floorf((k.population - l.strength) / Rules.LEADER_GROW), Rules.MAX_VALUE)


## Each country's population as the leader sees it: village population plus the
## strength of every unit but the leader [E].
func _count_population() -> void:
	for k in countries:
		k.population = 0.0
	for i in world.villages:
		var k := country(world.village_owner[i])
		if k != null:
			k.population += world.village_pop[i]
	for u in units:
		if not u.dead and not u.is_leader and u.owner != MONSTER:
			country(u.owner).population += u.strength


## Tax, at each castle every Rules.CELL_DAYS days [E]. Automatic tax picks the rate
## first. Each connected village pays rate x population / 256 funds, and that much
## population is taken from it.
func _collect_taxes() -> void:
	for k in countries:
		if not k.alive or (world.idx(world.castle_center(k.id)) + day) % Rules.CELL_DAYS != 0:
			continue
		if k.auto_tax:
			# The tax playbook. Funds saved for a bridge don't count
			k.tax = Playbook.tax_rate(k.tax_book, k.funds - k.reserve, k.tax)
		if no_tax_reason(k.id, k.tax) != "":
			k.connected.clear()
			continue
		k.connected = tax_reach(k.id).villages
		for j in k.connected:
			var take := _tax_take(j, k.tax)
			k.funds = minf(k.funds + take, Rules.MAX_VALUE)
			world.village_pop[j] -= take


func _tax_take(i: int, rate: int) -> float:
	return floorf(rate * world.village_pop[i] / Rules.TAX_DIVISOR)


## Where tax can come from: cells walkable from the castle entrance without passing
## enemy villages or castles, and the own villages among them (in the order found).
## Returns {cells: {idx: true}, villages: {idx: true}}.
func tax_reach(owner: int) -> Dictionary:
	var start := world.idx(world.castle_entrance(owner))
	var seen := {start: true}
	var found := {}
	var queue: Array[int] = [start]
	var head := 0
	while head < queue.size():
		var p := world.pos(queue[head])
		head += 1
		for d in World.N4:
			var q := p + d
			if not world.is_walkable(q) or world.castle_owner[world.idx(q)] >= 0:
				continue
			var j := world.idx(q)
			if seen.has(j):
				continue
			seen[j] = true
			var vo := world.village_owner[j]
			if vo >= 0 and vo != owner:
				continue
			if vo == owner:
				found[j] = true
			queue.append(j)
	return {"cells": seen, "villages": found}


## Funds per day at a tax rate, from the villages paying now (their routes as last
## found; with none kept they're found afresh, as the next collection would): one
## collection every Rules.CELL_DAYS days. Zero when no tax comes in (no_tax_reason).
func tax_income(owner: int, rate: int) -> float:
	if no_tax_reason(owner, rate) != "":
		return 0.0
	var total := 0.0
	for j in _paying(owner):
		total += _tax_take(j, rate)
	return total / Rules.CELL_DAYS


func _paying(owner: int) -> Array:
	var k := country(owner)
	var paying: Dictionary = k.connected if not k.connected.is_empty() else tax_reach(owner).villages
	return paying.keys().filter(func(j): return world.village_owner[j] == owner)


## Village population gained per day over all of a country's villages at a tax
## rate: growth (own territory neighbours + 1 every Rules.CELL_DAYS days) less what
## the tax takes.
func growth_per_day(owner: int, rate: int) -> float:
	var total := 0.0
	for i in world.villages:
		if world.village_owner[i] == owner:
			total += world.territory_count(world.pos(i), owner) + 1
	if no_tax_reason(owner, rate) == "":
		for j in _paying(owner):
			total -= _tax_take(j, rate)
	return total / Rules.CELL_DAYS


func _check_end() -> void:
	var me := country(player)
	if me != null and not me.alive:
		state = "lost"
		result = "Your leader was defeated"
	elif countries.all(func(k): return k.id == player or not k.alive):
		state = "won"
		result = "All enemy leaders defeated on day %d" % day
	elif day >= day_limit:
		state = "lost"
		result = "Out of days"


# --- Tax --------------------------------------------------------------------

## Setting the tax by hand turns automatic tax off [M].
func set_tax(owner: int, value: int) -> void:
	var k := country(owner)
	k.tax = clampi(value, 0, Rules.TAX_MAX)
	k.auto_tax = false


func set_auto_tax(owner: int, on: bool) -> void:
	country(owner).auto_tax = on


# --- Playbooks [G, modern] ----------------------------------------------------

## Replace a country's unit playbook (cleaned up: see Playbook.sanitize). Idle Auto
## units think again now.
func set_playbook(owner: int, lines: Array) -> void:
	country(owner).playbook = Playbook.sanitize(lines)
	_wake_auto(owner)


## Replace a country's tax playbook and turn automatic tax on.
func set_tax_book(owner: int, book: Dictionary) -> void:
	var k := country(owner)
	k.tax_book = Playbook.sanitize_tax(book)
	k.auto_tax = true


## Back to a style's playbooks ("" = the country's own style, as it started).
func reset_playbooks(owner: int, style_name: String = "") -> void:
	var k := country(owner)
	var st := style_name if style_name in Rules.STYLES else k.style
	var ai := style_name != "" or k.control == "ai"
	set_playbook(owner, Playbook.default_units(st, ai))
	k.tax_book = Playbook.default_tax(ai)


## Why no tax comes in at this rate, or "" when it does. The one place for this
## rule [E]: tax only flows with the leader in the castle centre, the cell just
## outside the gate open land that isn't another country's, and a rate above 0.
func no_tax_reason(owner: int, rate: int) -> String:
	var k := country(owner)
	if k == null or not k.alive:
		return "No tax: your country is defeated"
	if k.leader.pos != world.castle_center(owner):
		return "No tax: leader is away from the castle"
	if not _gate_open(owner):
		return "No tax: the way out of the castle is blocked"
	if rate <= 0:
		return "No tax: rate is 0"
	return ""


## The cell just outside the castle gate: land (clear, woods, a cave or a bridge),
## not another country's village or territory [E].
func _gate_open(owner: int) -> bool:
	var p := world.castle_entrance(owner) + Vector2i(0, 1)
	if not world.in_bounds(p) or not world.terrain_at(p) in ".T=o":
		return false
	var i := world.idx(p)
	var vo := world.village_owner[i]
	var to := world.territory[i]
	return (vo < 0 or vo == owner) and (to < 0 or to == owner)


## Why tax is or isn't coming in, for the HUD.
func tax_status(owner: int) -> String:
	var k := country(owner)
	if not k.alive:
		return ""
	var why := no_tax_reason(owner, k.tax)
	if why != "":
		return why
	var total := 0
	for i in world.villages:
		if world.village_owner[i] == owner:
			total += 1
	var paying := 0
	for i in k.connected:
		if world.village_owner[i] == owner:
			paying += 1
	if total > paying:
		return "%d of %d villages paying (others are cut off)" % [paying, total]
	return "All %d villages paying" % total


# --- Player orders --------------------------------------------------------

## Order menu, in the manual's order. Names follow the Lord Monarch theme.
const ACTIONS := [
	["standby", "Standby"], ["auto", "Auto"], ["defend", "Defend"], ["reinforce", "Reinforce"],
	["destroy", "Destroy"], ["build", "Build"], ["barricade", "Barricade"],
	["barricade_cont", "Barricade (continuous)"], ["bridge", "Build Bridge"],
	["clear", "Clear Land"], ["clear_path", "Clear Path"], ["dismantle", "Dismantle"],
	["dismantle_cont", "Dismantle (continuous)"], ["seal", "Seal Cave"],
]
## Default orders: what new units do when they leave a village
const DEFAULT_ORDERS := [["auto", "Auto"], ["standby", "Standby"]]


## Whether an action makes sense at a target (greys out menu items).
func action_allowed(owner: int, target: Vector2i, action: String) -> bool:
	if not world.in_bounds(target):
		return false
	var t := world.terrain_at(target)
	match action:
		"barricade", "barricade_cont":
			return world.can_barricade(target)
		"bridge":
			return world.can_bridge(target)
		"clear_path":
			return t in "x*"
		"dismantle", "dismantle_cont":
			return t in "=b"
		"seal":
			return t == "o"
		"build":
			return world.can_build_village(target, owner) and country(owner).funds >= Rules.VILLAGE_COST
		"clear":
			return world.terrain_at(target) == "T"
		"destroy":
			return world.village_at(target) >= 0
		_:
			return world.is_walkable(target)


## Send units to a target to do an action, replacing their orders and queues.
## Returns how many can get there.
func order_units(list: Array, target: Vector2i, action: String) -> int:
	if list.is_empty() or not action_allowed(list[0].owner, target, action):
		return 0
	var sent := 0
	for u in list:
		if u.dead or u.is_leader:
			continue
		if _order_one(u, target, action):
			u.queue.clear()
			sent += 1
	return sent


## Shift-orders [G]: units busy with an order do this one after it (and after
## anything already queued); units without an order start it now.
## Returns how many took it.
func queue_order(list: Array, target: Vector2i, action: String) -> int:
	if list.is_empty() or not action_allowed(list[0].owner, target, action):
		return 0
	var taken := 0
	for u in list:
		if u.dead or u.is_leader:
			continue
		if u.ordered and u.job != "":
			u.queue.append([target, action])
			taken += 1
		elif _order_one(u, target, action):
			taken += 1
	return taken


## The order a unit will end up on: its last queued one, else its current job.
func last_order(u: Unit) -> String:
	return u.queue.back()[1] if not u.queue.is_empty() else (u.job if u.ordered else "")


## Start the next queued order that still makes sense. False when none is left.
func _next_queued(u: Unit) -> bool:
	while not u.queue.is_empty():
		var q: Array = u.queue.pop_front()
		if action_allowed(u.owner, q[0], q[1]) and _order_one(u, q[0], q[1]):
			return true
	return false


func _order_one(u: Unit, target: Vector2i, action: String) -> bool:
	var route := _route_for(u, target, action)
	if route.is_empty() and not work_spot(u.pos, target, action):
		return false
	_drop_job(u)
	u.ordered = true
	u.order = "ordered"
	u.line = -2
	u.job = action
	u.job_target = target
	u.path.assign(route.get("path", []))
	u.idle = 0
	if action in ["clear", "build", "defend"] or action in ADJACENT_JOBS:
		_reserved[world.idx(target)] = u
	return true


## What a right-click on target means for owner's units [G]: [action, label],
## or [] when nothing applies. Reachability is checked by the caller.
func context_action(owner: int, target: Vector2i) -> Array:
	if not world.in_bounds(target):
		return []
	var t := world.terrain_at(target)
	var vo := world.village_at(target)
	if vo >= 0 and vo != owner:
		return ["destroy", "Destroy"]
	for e in _units_at(target):
		if e.owner != owner and not e.dead:
			return ["standby", "Attack"]
	var co := world.castle_owner[world.idx(target)]
	if co >= 0 and co != owner and world.is_walkable(target):
		return ["standby", "Attack castle"]
	if t == "T":
		return ["clear", "Clear Land"]
	if world.can_bridge(target):
		return ["bridge", "Repair Bridge" if t in "=b" else "Build Bridge"]
	if t in "x*":
		return ["clear_path", "Clear Path"]
	if t == "o":
		return ["seal", "Seal Cave"]
	if vo == owner:
		return ["defend", "Defend"]
	if action_allowed(owner, target, "build"):
		return ["build", "Build"]
	if world.is_walkable(target):
		return ["standby", "Move"]
	return []


## Path a unit would take for an action, starting from `from` (its position by default).
func route_for(u: Unit, target: Vector2i, action: String, from := Vector2i(-1, -1)) -> Array[Vector2i]:
	var who := u
	if from.x >= 0 and from != u.pos:
		who = Unit.new()
		who.owner = u.owner
		who.pos = from
	var route := _route(who, target) if action == "move" else _route_for(who, target, action)
	var path: Array[Vector2i] = []
	path.assign(route.get("path", []))
	return path


## Days to walk a path from `from`, facing `facing`: a tick per step and per turn [E].
func travel_days(path: Array[Vector2i], from: Vector2i, facing := Vector2i(0, 1)) -> int:
	var ticks := 0
	for p in path:
		if p - from != facing:
			facing = p - from
			ticks += 1
		ticks += 1
		from = p
	return ceili(ticks / float(Rules.TICKS_PER_DAY))


## The leader only moves [M]. Returns false if it can't get there.
func order_leader(owner: int, target: Vector2i) -> bool:
	var l := country(owner).leader
	var route := _route(l, target)
	if route.is_empty() and l.pos != target:
		return false
	_drop_job(l)
	l.order = "ordered"
	l.ordered = true
	l.job = "move"
	l.job_target = target
	l.path.assign(route.get("path", []))
	return true


func recall_leader(owner: int) -> bool:
	return order_leader(owner, world.castle_center(owner))


## Walking distance in steps, or -1 if unreachable.
func distance(u: Unit, target: Vector2i) -> int:
	if u.pos == target:
		return 0
	var route := _route(u, target)
	return -1 if route.is_empty() else route.path.size()


## Route to where the job is done: the target, or next to it for structures.
func _route_for(u: Unit, target: Vector2i, job: String) -> Dictionary:
	if not job in ADJACENT_JOBS:
		return _route(u, target)
	return _search(u, 9999, func(p: Vector2i, d: int):
		return [d, "go"] if work_spot(p, target, job) else null, target)


func _route(u: Unit, target: Vector2i) -> Dictionary:
	if not world.in_bounds(target):
		return {}
	return _search(u, 9999, func(p: Vector2i, d: int): return [d, "go"] if p == target else null, target)


# --- Job board (plans) [G, modern] ---------------------------------------------
# The player marks what should happen; Auto units take the work. A plan is
# [kind, priority] on a cell: "build" a village (woods there are cleared first)
# or "clear" woods. Plans wait for funds and go away once done or impossible.

const PLAN_NAMES := {"build": "Village", "clear": "Clear woods"}


## Whether a plan of this kind can go on the cell. Funds aren't needed: plans wait for them.
func plan_allowed(owner: int, p: Vector2i, kind: String) -> bool:
	if not world.in_bounds(p) or country(owner) == null:
		return false
	match kind:
		"build":
			# Planned villages can't touch each other, like built ones
			return world.can_build_village(p, owner, true) and not _near_build_plan(country(owner).plans, p)
		"clear":
			return world.terrain_at(p) == "T"
	return false


## Put cells on the job board (kind "build" or "clear"); cells that already have a
## plan of that kind take the new priority. Returns how many were added or changed.
func add_plans(owner: int, cells: Array, kind: String, priority: int = 0) -> int:
	var k := country(owner)
	priority = clampi(priority, 0, Rules.PLAN_PRIORITIES.size() - 1)
	var n := 0
	for p in cells:
		if not world.in_bounds(p):
			continue
		var i := world.idx(p)
		var had: Array = k.plans.get(i, [])
		if not had.is_empty() and had[0] == kind:
			if had[1] != priority:
				k.plans[i] = [kind, priority]
				n += 1
			continue
		k.plans.erase(i)   # a plan of the other kind is replaced
		if plan_allowed(owner, p, kind):
			k.plans[i] = [kind, priority]
			n += 1
		elif not had.is_empty():
			k.plans[i] = had
	if n > 0:
		_wake_auto(owner)
	return n


## Take cells off the job board. Returns how many had a plan.
func remove_plans(owner: int, cells: Array) -> int:
	var k := country(owner)
	var n := 0
	for p in cells:
		if world.in_bounds(p) and k.plans.erase(world.idx(p)):
			n += 1
	return n


## [kind, priority] planned on the cell, or [].
func plan_at(owner: int, p: Vector2i) -> Array:
	var k := country(owner)
	if k == null or not world.in_bounds(p):
		return []
	return k.plans.get(world.idx(p), [])


## Some unit is on its way to work on the cell.
func plan_taken(p: Vector2i) -> bool:
	return world.in_bounds(p) and _reserved.has(world.idx(p))


## The densest village layout in a box: villages two cells apart (each one's land
## then touches the next one's), on whichever of the four alignments fits the most.
func layout_villages(owner: int, box: Rect2i) -> Array[Vector2i]:
	box = box.intersection(Rect2i(0, 0, world.width, world.height))
	var best: Array[Vector2i] = []
	for off in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
		var picks: Array[Vector2i] = []
		for y in range(box.position.y + off.y, box.end.y, 2):
			for x in range(box.position.x + off.x, box.end.x, 2):
				# Existing planned villages count too (a plan doesn't block its own cell)
				var p := Vector2i(x, y)
				if plan_allowed(owner, p, "build"):
					picks.append(p)
		if picks.size() > best.size():
			best = picks
	return best


## Drop plans that are done or can't be done any more.
func _prune_plans() -> void:
	for k in countries:
		for i in k.plans.keys():
			_prune_plan(k, i)


func _prune_plan(k: Country, i: int) -> void:
	if k.plans.has(i) and not plan_allowed(k.id, world.pos(i), k.plans[i][0]):
		k.plans.erase(i)


## A build plan in the 8 cells around p (p itself not counted).
func _near_build_plan(plans: Dictionary, p: Vector2i) -> bool:
	for d in World.N8:
		var q := p + d
		if world.in_bounds(q):
			var plan: Array = plans.get(world.idx(q), [])
			if not plan.is_empty() and plan[0] == "build":
				return true
	return false


## The plan this unit should take: the nearest, higher priorities first (each
## level counts as Rules.PLAN_PRIORITY_STEPS steps). Woods under a planned village
## are cleared first. Only for units below army size. `dist`: furthest plan in
## steps (-1: any). Returns {path, target, kind} or {}.
func _plan_job(u: Unit, k: Country, dist: int, can_afford: bool) -> Dictionary:
	if k.plans.is_empty() or u.strength >= Rules.RAID_STRENGTH:
		return {}
	var top := Rules.PLAN_PRIORITIES.size() - 1
	return _search(u, 9999 if dist < 0 else dist, func(p: Vector2i, d: int):
		var i := world.idx(p)
		var plan: Array = k.plans.get(i, [])
		if plan.is_empty() or (_reserved.has(i) and _reserved[i] != u):
			return null
		var score: int = d + (top - int(plan[1])) * Rules.PLAN_PRIORITY_STEPS
		if world.tcode[i] == World.C_WOODS:
			return [score, "clear"]
		if plan[0] == "build" and can_afford and world.can_build_village(p, u.owner):
			return [score, "build"]
		return null)


## New plans: idle Auto units think again now rather than in up to 30 days.
func _wake_auto(owner: int) -> void:
	for u in units:
		if u.owner == owner and not u.is_leader and not u.dead and u.order.begins_with("auto") \
				and u.work == 0 and u.job in ["", "home", "rally"]:
			_drop_job(u)
			u.idle = 0


# --- Occupancy ------------------------------------------------------------

func _spawn(owner: int, p: Vector2i, strength: float) -> Unit:
	var u := Unit.new()
	u.id = _next_id
	_next_id += 1
	u.owner = owner
	u.pos = p
	u.prev_pos = p
	u.strength = strength
	units.append(u)
	_occ_add(u)
	return u


func _move(u: Unit, p: Vector2i) -> void:
	_occ_remove(u)
	u.pos = p
	_occ_add(u)


## Same-country units on one cell merge. Survivor: leader, then ordered, then strongest.
func _merge_at(u: Unit) -> void:
	var here := _units_at(u.pos).filter(func(o): return o.owner == u.owner and not o.dead)
	if here.size() < 2:
		return
	here.sort_custom(func(a, b):
		if a.is_leader != b.is_leader: return a.is_leader
		if (a.job == "reinforce") != (b.job == "reinforce"): return b.job == "reinforce"
		if a.ordered != b.ordered: return a.ordered
		return a.strength > b.strength)
	var keep: Unit = here[0]
	for o in here.slice(1):
		keep.strength = minf(keep.strength + o.strength, Rules.MAX_VALUE)
		o.dead = true
		_occ_remove(o)
		_drop_job(o)


func _units_at(p: Vector2i) -> Array:
	return _occ.get(world.idx(p), [])


func _occ_add(u: Unit) -> void:
	var i := world.idx(u.pos)
	if not _occ.has(i):
		_occ[i] = []
	_occ[i].append(u)


func _occ_remove(u: Unit) -> void:
	var i := world.idx(u.pos)
	if _occ.has(i):
		_occ[i].erase(u)
		if _occ[i].is_empty():
			_occ.erase(i)


# --- History ----------------------------------------------------------------

## Land, strength (leader + units) and village population of every country today.
func _record_history() -> void:
	var n := countries.size()
	var slot := {}
	for c in n:
		slot[countries[c].id] = c
	var land := []
	var strength := []
	var population := []
	land.resize(n)
	land.fill(0)
	strength.resize(n)
	strength.fill(0.0)
	population.resize(n)
	population.fill(0.0)
	for i in world.territory.size():
		var c: int = slot.get(world.territory[i], -1)
		if c >= 0:
			land[c] += 1
	for i in world.villages:
		var c: int = slot.get(world.village_owner[i], -1)
		if c >= 0:
			population[c] += world.village_pop[i]
	for u in units:
		var c: int = slot.get(u.owner, -1)
		if c >= 0 and not u.dead:
			strength[c] += u.strength
	if not history.is_empty() and history.back().day == day:
		history.pop_back()
	history.append({"day": day, "land": land, "strength": strength, "population": population})
	if history.size() > HISTORY_MAX:
		# Keep every other sample (always the first and the latest)
		var last: Dictionary = history.back()
		var kept: Array[Dictionary] = []
		for h in history:
			if h.day % (history_every * 2) == 0:
				kept.append(h)
		if kept.back() != last:
			kept.append(last)
		history = kept
		history_every *= 2


# --- Stats for the HUD ----------------------------------------------------

## Per-country numbers for the HUD, cached for the current day.
func stats(id: int) -> Dictionary:
	var key := Vector2i(id, day)
	if not _stats.has(key):
		if _stats.size() > 16:
			_stats.clear()
		_stats[key] = _compute_stats(id)
	return _stats[key]


func monster_stats() -> Dictionary:
	var s := {"count": 0, "strength": 0.0}
	for u in units:
		if u.owner == MONSTER:
			s.count += 1
			s.strength += u.strength
	return s


func _compute_stats(id: int) -> Dictionary:
	var k := country(id)
	var s := {"villages": 0, "territory": 0, "units": 0, "unit_strength": 0.0,
		"population": 0.0, "funds": k.funds, "tax": k.tax,
		"leader": k.leader.strength if k.alive else 0.0, "alive": k.alive}
	for i in world.territory.size():
		if world.territory[i] == id:
			s.territory += 1
		if world.village_owner[i] == id:
			s.villages += 1
			s.population += world.village_pop[i]
	for u in units:
		if u.owner == id and not u.is_leader:
			s.units += 1
			s.unit_strength += u.strength
	return s
