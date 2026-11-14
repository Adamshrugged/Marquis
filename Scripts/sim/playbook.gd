extends RefCounted
class_name Playbook

## Playbooks [G, modern]: the rules Auto units and automatic tax follow, editable
## by the player. See Docs/RULES.md (Playbooks).
## A unit line is {on, min, max, action, dist}; max and dist -1 mean no limit.
## A tax line is {below, tax}; tax -1 keeps the current rate.

const MAX_LINES := 20
const MAX_TAX_LINES := 6
## [action, label], in the editor's order
const ACTIONS := [
	["plans", "Job board"], ["clear", "Clear woods"], ["build", "Build village"],
	["attack", "Attack units"], ["destroy", "Destroy villages"], ["seal", "Seal caves"],
	["clear_path", "Clear barricades"], ["guard", "Guard castle"], ["army", "Join the army"],
	["home", "Go home"],
]
## Actions found by the one shared search around the unit (the others have their own)
const SURVEYED := ["clear", "build", "attack", "destroy", "seal", "clear_path"]
## Distance choices in the editor (-1: anywhere)
const DISTANCES := [2, 4, 6, 8, 10, 12, 16, 20, 30, -1]
## Village work is for units below army size (where upkeep starts [M])
const WORK_MAX := Rules.RAID_STRENGTH - 1


static func line(action: String, dist: int = -1, min_size: int = 0, max_size: int = -1) -> Dictionary:
	return {"on": true, "min": min_size, "max": max_size, "action": action, "dist": dist}


static func applies(l: Dictionary, strength: float) -> bool:
	return l.on and strength >= l.min and (l.max < 0 or strength <= l.max)


## Unit playbook a country starts with. Close to the old fixed Auto: nearby work
## first (4 steps, then 12), strong units join the army, then anything anywhere,
## except that small units never go far to fight.
## AI countries also guard their castle, seal caves and clear barricades.
static func default_units(style_name: String, ai: bool) -> Array:
	var st: Dictionary = Rules.STYLES[style_name]
	var march: int = st.march
	var lines := []
	if ai:
		lines.append(line("guard", st.defend))
	else:
		lines.append(line("plans", -1, 0, WORK_MAX))
	for d in [4, Rules.SEARCH_RADIUS]:
		lines.append(line("clear", d, 0, WORK_MAX))
		if ai:
			lines.append(line("seal", d))
		lines.append(line("attack", d))
		lines.append(line("build", d, 0, WORK_MAX))
		lines.append(line("destroy", d))
		if ai:
			lines.append(line("clear_path", d))
	lines.append(line("army", -1, march + 1))
	lines.append(line("clear", -1, 0, WORK_MAX))
	lines.append(line("attack", -1, march + 1))
	lines.append(line("build", -1, 0, WORK_MAX))
	lines.append(line("destroy", -1, march + 1))
	return lines


## Tax playbook a country starts with: the old automatic tax.
static func default_tax(style_name: String) -> Dictionary:
	var st: Dictionary = Rules.STYLES[style_name]
	return {"lines": [{"below": Rules.AUTO_FUNDS_LOW, "tax": st.tax_high},
		{"below": Rules.AUTO_FUNDS_HIGH, "tax": -1}], "otherwise": st.tax_low}


## Tax rate from a tax playbook at these funds (current: the rate now).
static func tax_rate(book: Dictionary, funds: float, current: int) -> int:
	for l in book.lines:
		if funds < l.below:
			return current if l.tax < 0 else l.tax
	return book.otherwise


static func action_name(action: String) -> String:
	for a in ACTIONS:
		if a[0] == action:
			return a[1]
	return action.capitalize()


## "Size 31-100: Clear woods within 4"
static func describe(l: Dictionary) -> String:
	var size := ""
	if l.min > 0 and l.max >= 0:
		size = "Size %d-%d: " % [l.min, l.max]
	elif l.min > 0:
		size = "Size %d+: " % l.min
	elif l.max >= 0:
		size = "Size up to %d: " % l.max
	var where := "" if l.action in ["army", "home"] or l.dist < 0 else " within %d" % l.dist
	return size + action_name(l.action) + where


## A clean copy of player-edited lines: known actions, sane numbers, at most MAX_LINES.
static func sanitize(lines: Array) -> Array:
	var out := []
	for l in lines:
		if out.size() >= MAX_LINES or not l is Dictionary or not ACTIONS.any(func(a): return a[0] == l.get("action")):
			continue
		var mx := int(l.get("max", -1))
		var mn := maxi(int(l.get("min", 0)), 0)
		out.append({"on": bool(l.get("on", true)), "min": mn, "max": -1 if mx < 0 else maxi(mx, mn),
			"action": l.action, "dist": maxi(int(l.get("dist", -1)), -1)})
	return out


static func sanitize_tax(book: Dictionary) -> Dictionary:
	var lines := []
	for l in book.get("lines", []):
		if lines.size() < MAX_TAX_LINES and l is Dictionary:
			var t := int(l.get("tax", -1))
			lines.append({"below": maxi(int(l.get("below", 0)), 0), "tax": -1 if t < 0 else mini(t, 100)})
	return {"lines": lines, "otherwise": clampi(int(book.get("otherwise", 10)), 0, 100)}
