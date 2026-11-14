# How Lord Monarch Online actually works

Read out of `DS7E_WIN/DS7E_WIN.EXE` with Ghidra 12.2 (decompiled, 792 functions).
Addresses are the functions in the exe, so each rule can be checked again.
Compare with `Docs/RULES.md`, which is what Marquis does now.

## Time
- The game runs in **ticks**. One **day = 2 ticks** (`FUN_0041b4f0`: the day counter goes
  up and the remaining days go down every second tick). Day limit 3000, plus bonus days
  carried over in campaign play.
- Each tick (`FUN_0040a5e0`):
  1. 143 map cells are updated (`FUN_0041d740`), round robin. The map has 2304 cells, so
     each village, cave and castle is visited about **every 16 ticks = 8 days**.
  2. 63 units are updated (`FUN_004204f0`), round robin over the 64 unit slots: in practice
     every unit, every tick.
  3. Country totals are recounted (`FUN_0041b370`).
- **At most 64 units on the map at once, all countries and monsters together.**
  New units only appear if a slot is free (`FUN_0041cdc0` returns 0x40 when full).
- A beaten unit plays a 4-tick death (`FUN_00420aa0` sets +0x10 flag 0x02, `FUN_00420af0`
  counts, `FUN_00420b30` removes it). It does nothing meanwhile. (An earlier reading took
  this for walking time; it isn't.)
- Strength, funds and population are all capped at 100000.

## Data layout (for further digging)
- Map: `DAT_0043453c`, 48x48 cells, 0x18 bytes each, column-major (index = x*48 + y).
  +0x00 unit slot on the cell (0x40 = none), +0x08 route distance (tax flood fill),
  +0x0c counter (population, durability or work left), +0x10 tile code.
- Units: `DAT_00434538`, 64 x 0x224 bytes. +0 x, +1 y, +2/+3 target, +4 owner (4 = monster),
  +8 strength, +0xd order (low 4 bits) and flags (0x10 player order, 0x20 leader),
  +0x10 flags (0x02 dying, 0x80 slot free), +0x14 path length, +0x18 path index (0x1f0 = no
  path, "arrived"), +0x1c path directions.
- Countries: `DAT_00434534`, 0x38 bytes each (index 4 = monsters). +4 flags (0x01 leader beaten, units changing hands; 0x40 defeated),
  +0x10 population total, +0x18 funds, +0x1c tax rate, +0x1e ally, +0x1f conqueror,
  +0x24 unit count, +0x28 unit strength, +0x2c village count, +0x30 village population.
- Tile codes: 0 clear, 1-4 woods, 5 cave, 8-11 village (8 + owner), 12-15 territory
  (12 + owner), 0x14-0x17 castle centre (0x14 + owner), 0x20-0x2f bridge, 0x30-0x5f water,
  0x60-0x6f mountain, 0x7a damaged bridge, 0x7b barricade.
- **Every cell's counter starts at 100 when a map loads** (`FUN_00405de0`). That is the
  starting population of villages, the durability of bridges and barricades, and the work
  needed to clear woods, seal a cave or bridge water.

## Countries and the leader
- **Population** (what the leader follows) = village population + strength of all
  non-leader units (`FUN_0041b370`). A country whose total reaches 0 is out.
- **Leader** (`FUN_004015a0`, runs every tick while the leader is in its castle centre):
  - If population < leader strength / 2: a unit of leader strength / 4 leaves through the
    gate, but only if the cell below the gate is empty and a unit slot is free. No cooldown.
  - Else if leader strength < population: it grows by (population - strength) / 8, up to 100000.
  - It never shrinks toward population; it only loses strength by releasing units or fighting.
- Away from its castle centre the leader pays upkeep and decays like any unit (below).

## Villages (`FUN_0041d870`, every ~8 days per village)
- No growth while the country's flag 0x01 is set (its leader was beaten; see Defeat).
- Each visit: population += (own territory cells among its 8 neighbours) + 1.
  **Tax has no effect on growth.**
- Once population >= (own territory neighbours + 1) x 16 (clamped to 255):
  - if a neighbouring cell is clear land: it becomes territory;
  - else if a neighbour is **another country's territory, it is taken over**;
  - after a claim the village stops here unless its population is 200+.
- Then (no room left, or 200+): the **whole population is released** as a unit of
  population - 1 (or added to an own unit standing on the village), and the village drops to 1.
- Building one (`FUN_0040b330`): 100 funds; allowed on clear land or territory (any owner's;
  the neighbour rule is checked in `FUN_0041e670`). The builder gives min(strength, 200), and
  the village starts at half of that + 1. A builder with no more than that is used up.
- Destroying your own village (`FUN_00421910`): instant; the unit takes in its population.
- Attacking an enemy village (`FUN_004208b0`, `FUN_004209a0`): both lose min(attacker
  strength, village population); at 0 the village becomes clear land. Allies' villages are spared.

## Tax and funds (`FUN_0041dc60`, at the castle centre, every ~8 days)
- **Tax rate is 0-30**, not a percentage (the slider maps to 0-30 in steps of 4 pixels).
- Collected only if the country's leader stands in its castle centre and the cell two below
  the centre (just outside the gate) is land (tile < 0x30) that isn't another country's.
- A flood fill from the castle marks connected cells; each connected own village pays
  **tax x population / 256 funds, and that much population is taken from the village**.
- Automatic tax:
  - player: 20 - funds / 256 (0 from 5120 funds up), recalculated at each collection;
  - AI: (7 - funds / 256) x 4 below 1792 funds (28, 24, ... 4), otherwise 0.

## Upkeep and decay (`FUN_0041a920`, every tick a unit acts)
- On **any castle centre or its own village**: pays strength / 2048 funds (rounded down,
  so free below 2048). If it pays, nothing else happens.
- Anywhere else, or if the funds run out: loses **strength / 256 + 1**. If that would take
  it to 0 or below, the unit is gone.

## Combat (`FUN_00420c60`, one round per tick, attacker next to defender)
- Open ground: attacker deals strength / 8 + 1, defender hits back strength / 16 + 1.
- Defender on a castle centre: both deal strength / 8 + 1.
- Attacker on a castle centre (a leader hitting out): deals strength / 4 + 1, takes nothing.
- Allies don't fight. Units with order 12 can't be attacked.
- Each country counts the strength it lost (+0x14).

## Merging (`FUN_00420610`)
- Refused if the total would exceed 100000.
- Survivor: leader, then a player-ordered unit, then order 3, then the stronger
  (the one already on the cell on a tie).

## Work (each action = one tick of work)
| Work | Function | Per action | Cost | Done when |
|---|---|---|---|---|
| Clear woods | `FUN_0040bc20` | counter - strength/2 | none | counter < 1 (100 to start) |
| Seal cave | `FUN_0040bb10` | counter - strength/8 | none | below 0; waits while a unit stands on the cave |
| Barricade (new or stronger) | `FUN_0040b440` | strength/16 | 1 fund per 4 points | max 255 |
| Clear barricade | `FUN_0040b840` | durability - strength/32 | none | 0 |
| Build bridge on water | `FUN_0040b680` | strength/16 | **30 funds per point** | ~100 points, so ~3000 funds |
| Repair damaged bridge | `FUN_0040b680` | strength/16 | 2 funds per point | counter used up (~100 points, ~200 funds) |
| Dismantle bridge | `FUN_0040b960` | durability - strength/32 | none | 0: becomes a damaged bridge, and **a unit on it dies** |
| Dismantle damaged bridge | `FUN_0040b960` | counter + strength/32, max 255 | none | makes it harder to repair |

## Upkeep timing
- Every unit handler (`FUN_00401000` leader, `FUN_00401770` Auto, `FUN_00403170` and
  `FUN_00402bc0` player-ordered) calls the upkeep function first, every tick, walking or
  not. A leader standing in its own castle centre skips it.

## Movement and paths
- Paths come from a breadth-first flood fill from the target (`FUN_0041a680`, distance in
  cell +0x08), every step costing 1: **woods are no slower than clear land**.
- Passable = tile code below 0x30 (`FUN_00405330`): clear land, woods, caves, villages,
  territory, castle centres and bridges. Water, mountains, barricades and damaged bridges
  are not.
- Before planning, `FUN_00405510` blocks cells holding: allies; own units the mover
  couldn't merge with (over 100000); and enemies it can't beat, with their 4 neighbours.
  "Can't beat" = the enemy has more than mover / 1.25, or, on its castle centre, more than
  mover / 2 (a unit) or mover / 4 (the leader). So units route around stronger enemies;
  this is where the manual's x2 / x4 castle numbers live.
- Each tick a unit either turns to face its next step (a tick) or takes one step: **one
  cell per tick, two a day**. Moving into an enemy = a combat round; into an own unit =
  merge; into an enemy village = attack it; into anything else occupied = the path is
  dropped.
- Standing on another country's territory turns it back into clear land (`FUN_00420a40`,
  called every tick by every unit handler). Allies' territory is spared.

## Monsters and caves
- Caves (`FUN_0041dec0`, every ~8 days like other cells): the counter goes up by 10;
  at 245 or more it drops by 245 and a **monster of strength 200** appears on the cave
  itself, if the cave is empty and a unit slot is free. From the starting 100 the first
  comes after ~15 visits (~120 days), then one every ~25 visits (~200 days) per cave.
  No randomness. Sealing works the same counter down, so a cave close to spawning takes
  longer to seal.
- Monsters (`FUN_00402700`) pay no upkeep and never decay. They don't look for targets:
  they walk straight ahead for 20-58 ticks, rest 0-10, and turn at random (preferring open
  sides) when blocked. Whatever they bump into they fight, merge with (monsters), or
  attack (villages). With nowhere to go they chip at a barricade next to them, 1 point
  per tick.
- A leader beaten by monsters: the country's villages become clear land and its units die
  (`FUN_0041d870`, the order-12 handling in `FUN_00401770`).

## Defeat (country flag bit 0)
- When a leader's death completes (`FUN_00420b30`), its country gets flag 0x01 and records
  the conqueror (+0x1f), and all its units get order 12, which can't be attacked.
- From then on, as each village is visited, it changes to the conqueror's (no growth that
  visit), with its territory; as each unit acts, it changes owner and goes on Auto. With
  monsters as the conqueror, villages become clear land and units die.

## Auto units (`FUN_00401770`, job pick `FUN_004219b0`)
- Purely local: an Auto unit only looks at its 8 neighbours, in this order:
  1. a cave: seal it (order 11);
  2. an enemy village: attack it (4);
  3. with 100 funds, somewhere a village can go: build (5);
  4. woods, if the unit has 100+ strength (any strength under player orders): clear (8);
  5. (AI countries only) `FUN_0041e480`, not read;
  6. an own village next door: step onto it (1), so units drift along their villages.
- Otherwise `FUN_0041eb60` / `FUN_00421ae0` (not read) move it on.
- Country-level AI planning (targets, armies) not read yet.

## Still open
- The AI's country-level decisions and `FUN_0041e480`, `FUN_00421ae0`.
- Per-map starting funds, tax and leader strength (in the `.MAP` loaders).
