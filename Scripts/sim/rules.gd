extends RefCounted
class_name Rules

## Tunable game constants. [M] = from the LMO manual, [E] = read out of the LMO
## program (Docs/LMO_ENGINE.md), [G] = guess. See Docs/RULES.md.

# Time
const TICKS_PER_DAY := 2             # [E] upkeep, combat and work happen per tick
const CELL_DAYS := 8                 # [E] villages and castles act every 8 days
const CELL_START := 100              # [E] every cell's counter when a map loads (work left, durability)
const MAX_VALUE := 100000            # [E] cap on strength and funds
const MAX_UNITS := 64                # [E] units on the map at once, all countries and monsters

# Villages
const VILLAGE_COST := 100            # [M]
const POP_PER_TERRITORY := 16        # [M] full at (territory + 1) * 16
const VILLAGE_POP_MAX := 255         # [E] a full village's population is clamped to this
const VILLAGE_RELEASE_POP := 200     # [E] from here a village sends out units even after claiming land
const BUILDER_GIVES := 200           # [E] a builder gives up to this; the village starts at half + 1

# Funds and tax
const TAX_MAX := 30                  # [E] the tax bar runs 0-30
const TAX_DIVISOR := 256             # [E] each village pays tax x population / 256, taken from its population
const UPKEEP_THRESHOLD := 2048       # [M][E] on a base, upkeep per tick = strength / 2048 funds
const DECAY_DIVISOR := 256           # [E] elsewhere, strength / 256 + 1 lost per tick

# Units
const SIZE_M := 1000                 # [M]
const SIZE_L := 10000                # [M]
const SEARCH_RADIUS := 12            # [G] auto job search, in steps
const IDLE_RETHINK_DAYS := 10        # [G]
const FIELD_DAYS := 10               # [G] how often 'go home' / 'march' maps refresh

# Leader and castle
const LEADER_START := 400            # [G] default if the level doesn't say
const START_UNIT := 100              # [G] strength of the unit each country starts with outside its castle [M]
const LEADER_GROW := 8               # [E] grows by 1/8 of the gap to the population per tick

# Combat [E], damage per round (one round per tick) is strength / divisor + 1
const HIT_OPEN := 8                  # attacker in the open
const HIT_BACK := 16                 # defender hitting back in the open
const HIT_CASTLE := 8                # both, when the defender stands on a castle centre
const HIT_FROM_CASTLE := 4           # attacker on a castle centre; it takes no damage

# Route planning [E]: units plan around enemies they can't beat, i.e. stronger than
# their strength / this (on a castle centre: / 2 for a unit, / 4 for the leader)
const AVOID_OPEN := 1.25
const AVOID_CASTLE := 2.0
const AVOID_LEADER := 4.0

# Work [E], per action (one action per tick)
const CLEAR_DIV := 2                 # clear woods: work left - strength / 2
const SEAL_DIV := 8                  # seal cave: work left - strength / 8
const BUILD_DIV := 16                # barricade, bridge: + strength / 16
const PULL_DIV := 32                 # clear barricade, dismantle bridge: - strength / 32
const BRIDGE_NEW_COST := 30          # [M][E] funds per point, bridging water
const BRIDGE_REPAIR_COST := 2        # [M][E] funds per point, repairing a damaged bridge
const BARRICADE_POINTS_PER_FUND := 4 # [M][E] 1 fund per 4 points
const DURABILITY_MAX := 255          # [E] barricades and damaged bridges
const SEAL_NEAR := 6                 # [G] AI seals caves this close to its land
const WATCH_DAYS := 5                # [G] continuous orders recheck their target this often

# Caves and monsters [E]
const CAVE_GROW := 10                # a cave's counter goes up this much every CELL_DAYS days
const CAVE_SPAWN := 245              # ... and from here a monster comes out, taking this off it
const MONSTER_START := 200           # strength of a new monster
const MONSTER_WALK_MIN := 20         # ticks a monster walks straight ahead
const MONSTER_WALK_MAX := 58
const MONSTER_REST_MAX := 10         # ticks it then rests (0 to this)

# AI [G]
## Personalities. margin: army strength vs the target castle's strength before
## attacking. march: strength a unit needs to join the army. defend: how far units
## come back to guard a threatened castle.
const STYLES := {
	"balanced":   {"margin": 1.25, "march": 64, "defend": 12},
	"aggressive": {"margin": 1.0, "march": 40, "defend": 8},
	"builder":    {"margin": 1.5, "march": 128, "defend": 12},
	"turtle":     {"margin": 1.8, "march": 96, "defend": 20},
}
const AI_STYLES := ["aggressive", "builder", "turtle", "balanced"]
const RAID_STRENGTH := 2048          # armies this big raid enemy villages while they wait (upkeep starts here [M])
const RAID_WAIT_DAYS := 60           # ... or once they've waited this long at the rally point
const THREAT_RADIUS := 6             # enemies this close to a castle centre are a threat
const UNREACHABLE_PENALTY := 3.0     # target choice: a castle needing barricades/bridges cleared counts this much more
const CASTLE_STRENGTH := 2.0         # army needed vs a leader in its castle: it hits from the castle, so about sqrt(3) x [E]

# Job board (plans) [G, modern]
const PLAN_PRIORITIES := ["Normal", "High", "Urgent"]
const PLAN_PRIORITY_STEPS := 12      # each priority level counts as this many steps closer
