extends RefCounted
class_name Rules

## Tunable game constants. [M] = from the LMO manual, [G] = guess.
## See Docs/RULES.md.

# Villages
const VILLAGE_COST := 100            # [M]
const POP_PER_TERRITORY := 16        # [M] cap = (territory + 1) * 16
const GROWTH_RATE := 0.6             # [G] pop/day at 0% tax, scaled by (1 + pop/32)
const VILLAGE_START_POP := 4.0       # [G] if the builder brings less

# Funds
const TAX_DIVISOR := 6000.0          # [G] income/day = connected pop * tax / divisor
const TAX_ROUTE_DAYS := 10           # [G] how often village-to-castle routes are rechecked
const UPKEEP_THRESHOLD := 2048       # [M]
const UPKEEP_DIVISOR := 512.0        # [G] funds/day = (strength - threshold) / divisor

# Units
const DECAY_DAYS := 2                # [G] off-base units lose 1 strength per this many days
const WOODS_MOVE_DAYS := 2           # [G]
const SIZE_M := 1000                 # [M]
const SIZE_L := 10000                # [M]
const SEARCH_RADIUS := 12            # [G] auto job search, in steps
const IDLE_RETHINK_DAYS := 10        # [G]
const FIELD_DAYS := 10               # [G] how often 'go home' / 'march' maps refresh

# Work
const CLEAR_DAYS := 8                # [G]
const CLEAR_STRENGTH := 4            # [G]
const BUILD_DAYS := 4                # [G]

# Leader and castle
const LEADER_START := 400            # [G] default if the level doesn't say
const START_UNIT := 100              # [G] strength of the unit each country starts with outside its castle [M]
const LEADER_FOLLOW := 32.0          # [G] closes 1/n of the gap to its target per day
const LEADER_POP_SHARE := 0.25       # [G] target leader strength = population x this
const LEADER_FLOOR := 100            # [G] the leader never drifts below this
const LEADER_EMIT_COOLDOWN := 20     # [G] days between releases
const CASTLE_LEADER_MULT := 4        # [M]
const CASTLE_UNIT_MULT := 2          # [M] manual says "2 or 3"

# Structures
const BRIDGE_MAX := 8                # [G] durability of a finished bridge
const BRIDGE_DAMAGED_START := 2      # [G] durability of damaged bridges ('b') in a map
const BRIDGE_NEW_COST := 30          # [M] funds per durability point, new bridge
const BRIDGE_REPAIR_COST := 2        # [M] funds per durability point, repair
const BARRICADE_STEP := 32           # [G] durability added per build
const BARRICADE_DAYS := 4            # [G] days per build
const BARRICADE_POINTS_PER_FUND := 4 # [M] 1 fund per 4 durability
const BARRICADE_MAX := 255           # [G]
const MAP_BARRICADE := 64            # [G] durability of barricades and rubble in the map
const CLEAR_PATH_RATE := 4           # [G] durability removed per day, plus strength/16
const DISMANTLE_RATE := 1            # [G] durability removed per day, plus strength/256
const SEAL_DAYS := 10                # [G]
const SEAL_STRENGTH := 20            # [G]
const SEAL_NEAR := 6                 # [G] AI seals caves this close to its land
const WATCH_DAYS := 5                # [G] continuous orders recheck their target this often

# Monsters
const MONSTER_SPAWN_CHANCE := 0.004  # [G] per cave per day
const MONSTER_START := 40            # [G]
const MONSTER_MAX := 10              # [G] alive at once on a map
const MONSTER_SEARCH := 10           # [G] how far they look for something to attack

# AI [G]
## Personalities. margin: army strength vs the target castle's strength before
## attacking. march: strength a unit needs to join the army. defend: how far units
## come back to guard a threatened castle. tax_low/high: auto tax when rich/broke.
const STYLES := {
	"balanced":   {"margin": 1.25, "march": 64, "defend": 12, "tax_low": 10, "tax_high": 40},
	"aggressive": {"margin": 1.0, "march": 40, "defend": 8, "tax_low": 15, "tax_high": 50},
	"builder":    {"margin": 1.5, "march": 128, "defend": 12, "tax_low": 5, "tax_high": 35},
	"turtle":     {"margin": 1.8, "march": 96, "defend": 20, "tax_low": 10, "tax_high": 40},
}
const AI_STYLES := ["aggressive", "builder", "turtle", "balanced"]
const RAID_STRENGTH := 2048          # armies this big raid enemy villages while they wait (upkeep starts here [M])
const RAID_WAIT_DAYS := 60           # ... or once they've waited this long at the rally point
const THREAT_RADIUS := 6             # enemies this close to a castle centre are a threat
const UNREACHABLE_PENALTY := 3.0     # target choice: a castle needing barricades/bridges cleared counts this much more

# Job board (plans) [G, modern]
const PLAN_PRIORITIES := ["Normal", "High", "Urgent"]
const PLAN_PRIORITY_STEPS := 12      # each priority level counts as this many steps closer

# Automatic tax (AI countries, and the player's Auto button). Rates come from STYLES.
const AUTO_FUNDS_LOW := 300          # [G]
const AUTO_FUNDS_HIGH := 1500        # [G]
