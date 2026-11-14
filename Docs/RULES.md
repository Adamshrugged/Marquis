# Marquis rules

How the simulation works, based on the Lord Monarch Online manual
(https://www.falcom.co.jp/monarch/manual/index_e.html).

Every rule is tagged:
- **[M]** stated in the manual
- **[G]** guessed or simplified: the manual gives no number or detail. These are
  constants in `Scripts/sim/rules.gd`, to tune by playing the original

## Time
- The game runs in days. Each map has 3000 days [M]. One simulation tick = one day [G].
- Speed: default 8 days per second, adjustable [G].

## Countries
- 4 countries per map, each with a castle and a leader [M]. Player = one of them.
- Each starts with one unit (strength 100 [G]) just outside its castle gate [M: seen in LMO].
  Levels can place more with `"units"`.
- Win: defeat every other leader within the day limit [M].
- Lose: your leader is defeated, or days run out [M].
- Defeating a leader in its castle hands you its villages, units and funds [M].
- The defeated country's castle disappears, leaving open ground [M: as in LMO].

## Castle
- 3x3. Only the entrance (bottom middle) and the centre are walkable [G].
- The leader stands in the centre. The castle can't be destroyed [M].
- Units in the castle fight at x2 strength, the leader at x4 [M] (manual says "2 or 3" for units).

## Leader
- Strength follows the country's total village population, but changes gradually [M].
  Target = population x 0.25, never below 100. Each day it moves 1/32 of the gap,
  at least 1 [G].
- If population drops below half the leader's strength, a quarter of the leader's
  strength leaves the castle as new units [M].
- Only obeys "move". Destroys enemy villages and fights enemies on its route.
  Doesn't clear land or build bridges [M].
- Funds are only collected while the leader is in the castle centre [M].

## Villages (bases)
- Cost 100 funds [M]. Only on clear land (not woods, bridges, barricades) [M].
- Not next to another village of the same country (8 neighbours) [M]; next to an enemy's is fine [M].
- Territory appears around a new village [M]: its clear, unowned 8 neighbours [G].
- Population cap = (territory cells + 1) x 16 [M].
- Below the cap, population grows. Chance per day = growth_rate x (100 - tax) / 100 [G].
  Low tax = more units, high tax = fewer [M].
- At the cap, the village tries to claim one more neighbouring cell [M]. If it can't,
  it releases a unit: strength = half its population [G].
- Units standing on their own village don't lose strength [M].

## Funds and tax
- Tax bar under the HUD [M]: drag or click to set it (turns Auto off); Auto turns it
  back on. `[` / `]` change it by 5. A note says whether taxes are coming in.
  Hovering or dragging the bar previews income and village growth per day at that
  rate against the current one. The Tax routes map overlay (F2) shows which villages
  pay, which are cut off and what blocks the way.
- Auto tax [G]: the tax playbook (see Playbooks). By default high when funds < 300,
  low from 1500 (rates per AI style, below).
- Tax 0-100%. Income per day = total population of connected villages x tax / 6000 [G].
- A village is connected if units could walk from the castle entrance to it without
  passing enemy villages or barricades [M]. Routes are rechecked every 10 days [G].
- Funds pay for villages, bridges, barricades, and upkeep [M].
- Upkeep: units over 2048 strength cost (strength - 2048) / 512 funds per day [M threshold, G amount].
  With no funds, they lose strength even on a village [M].

## Units
- Size by strength: S up to 999, M 1000-9999, L 10000+ [M].
- Move 1 cell per day; woods take 2 days [G].
- Off a village, lose 1 strength every 2 days [G]. Reaching 0 = gone [M].
- Same-country units on the same cell merge [M]. Survivor priority: leader, then
  ordered units, then the stronger [M].
- New units start with the default order, initially Auto [M].

## Playbooks [G, modern]
Auto units and automatic tax follow each country's playbooks: short "if this, do
that" lists, checked from the top, first match wins (FF12 gambit style). The player
edits theirs in the Playbook window (P, or the Playbook button). Every change
applies at once; the game pauses while the window is open.

### Unit playbook
- An idle Auto unit reads the lines from the top and takes the first one that
  applies to its size and finds something to do. It finishes that task before
  reading the playbook again, even if its size changes on the way. If the task
  becomes impossible, it reads the playbook again.
- Units under a player order ignore the playbook until the order is done. The leader
  never uses it.
- A line: **size** range (strength; blank = any), **action**, **distance** in steps
  from the unit (blank = anywhere), and an **on/off** switch. Up to 20 lines. The
  same action can appear more than once with different sizes or distances.
- Fixed last line, **otherwise: go home**: walk to the nearest own village and wait,
  rechecking every 10 days (30 for units at or below the style's army size).
- The unit window shows which line a unit is following ("Line 6: Clear woods within 12").

| Action | Finds | Built-in checks (not editable) |
|---|---|---|
| Job board | The nearest job board task (priorities count, see Job board) | Below 2048 strength. Village plans need funds |
| Clear woods | Woods next to own land. Auto units prioritise this [M] | Not already taken by another unit |
| Build village | A spot where a village is allowed | 100 funds beyond what other builders have claimed. Leaves room for planned villages |
| Attack units | An enemy unit | Must outweigh it by 20% (even odds on own land). Never a leader |
| Destroy villages | An enemy village | Must outweigh its population by 20% |
| Seal caves | A monster cave within 6 of own land | Strength over 40; costs 20 |
| Clear barricades | A barricade or rubble | |
| Guard castle | Own castle gate, to stand in it (x2 there) | Only while an enemy is within 6 of the castle centre (units standing in their own castle don't count). Distance is from the gate |
| Join the army | Gather at the rally village, march when big enough (see AI: Targets and Armies) | The country needs a target |
| Go home | The nearest own village, to wait there | |

"Outweigh" uses the unit's strength when it decides.

Default player playbook (copies the old fixed Auto closely; that one took whichever
job was nearest, with small preferences, so a strict list can't match it exactly):

| # | Size | Action | Distance |
|---|---|---|---|
| 1 | up to 2047 | Job board | anywhere |
| 2-5 | | Clear woods (up to 2047), Attack units, Build village (up to 2047), Destroy villages | 4 |
| 6-9 | | the same four | 12 |
| 10 | 65+ | Join the army | |
| 11-14 | | Clear woods (up to 2047), Attack units (65+), Build village (up to 2047), Destroy villages (65+) | anywhere |

So small units never go further than 12 steps to fight. 64 is the balanced style's
army size; AI styles use theirs (table below).

### Tax playbook
- Lines "if funds are below X: set tax to Y%" (or keep the current rate), checked
  every day from the top; a fixed last line "otherwise: tax Z%". Up to 6 lines.
- Funds saved for a bridge don't count, and paying upkeep with under 1500 funds
  counts as broke.
- Only while automatic tax is on. Moving the tax bar turns it off [M]; the Auto
  button, the checkbox in the Tax tab or editing a line turns it back on.
- Default (balanced): below 300 → 40%, below 1500 → keep, otherwise 10%. AI styles
  use their rates (table below). The player starts with automatic tax off.

### Presets
The window can load the player's default or any AI style's playbooks as a
starting point. AI countries use their style's preset.

### AI countries [G]
- Same unit behaviour as the player's Auto units: their style's playbooks, which add
  Guard castle at the top (within the style's defend range), Seal caves and Clear
  barricades at 4 and 12 steps. Plus the built-in planning below.

## AI [G]
### Personalities
Each AI country gets a style, picked from the game seed unless the level sets
`"style"` (see `Levels/FORMAT.md`). The player's Auto behaves as balanced.

| Style | Attacks when the army is | Joins the army at | Comes back to defend from | Auto tax rich/broke |
|---|---|---|---|---|
| balanced | 1.25x the target castle | 64 | 12 steps | 10% / 40% |
| aggressive | 1.0x | 40 | 8 | 15% / 50% |
| builder | 1.5x | 128 | 12 | 5% / 35% |
| turtle | 1.8x | 96 | 20 | 10% / 40% |

### Targets
- Every 10 days each AI picks the enemy that's cheapest to beat: castle strength
  (leader x4) scaled by distance. A castle only reachable through barricades or
  water counts 6x.
- The army gathers at the own village closest to that castle.

### Armies
- Units of 2048+ strength (where upkeep starts [M]) don't clear land or build.
- An army waiting at the rally point raids enemy villages once it's 2048+ strong or
  has waited 60 days, instead of paying upkeep for nothing.
- If the target can only be reached across water, the country saves 240 funds
  (one bridge) before building more villages. Any idle unit with nothing in its
  playbook, not just the army, does that bridging or barricade-clearing work.

### Defence
- An enemy within 6 cells of an AI castle is a threat. Units standing in their own
  castle (leaders, gate guards) don't count, so castles built close together don't
  keep each other on alert forever. Idle units within the
  style's defend range go and stand in the castle gate (x2 there): the Guard castle line.
- Enemy units on the AI's own land are attacked at even odds (elsewhere it wants 20% more).

### Auto tax
- The tax playbook: high while broke, while saving for a bridge, or while paying
  upkeep without a 1500-fund cushion; low when well off.

## Orders [M except where marked]
Who -> Where -> Does what. Click a unit (or drag a box), click a destination, pick
an action. Esc cancels. The game pauses while the menu is open [G] (a setting can turn that off).
If no selected unit can reach the destination, it keeps waiting for another.

Context right-click [G, modern]: with units selected, right-click a destination and
the obvious action happens, without the menu:

| Right-click on | Action |
|---|---|
| Enemy village | Destroy |
| Enemy unit or enemy castle (centre/gate) | Standby there (entering it fights) - "Attack" |
| Woods | Clear Land |
| Water by walkable land, or a damaged bridge | Build Bridge |
| Barricade or rubble | Clear Path |
| Cave | Seal Cave |
| Own village | Defend |
| Clear land where a village can go (and 100 funds) | Build |
| Anything else walkable | Standby ("Move") |

Checked top to bottom. With only the leader selected it moves there. If nothing
applies or no selected unit can get there, the right-click cancels ("Can't go there").
A right-click with nothing selected cancels; a right-drag only scrolls.
While picking a destination the map shows the route (first 5 units of a group),
the hint line gives the distance and days (woods take 2), and a label by the cursor
says what a right-click would do.

Order queues [G, modern]: hold Shift when confirming an order (menu choice or
right-click) to queue it. The selection stays, so several can be chained.
- A unit busy with an order does the queued ones in turn when it finishes, routing
  from where it is. A unit without an order starts the Shift-order at once.
- A queued order that no longer makes sense when its turn comes (woods already
  cleared, no funds to build, can't get there) is skipped.
- Standby counts as finished on arrival, so it works as a waypoint.
- Defend, Reinforce and the continuous orders never finish by themselves: anything
  queued behind them waits until the unit gets a new order.
- A new order without Shift replaces the queue. The leader has no queue.
- The selected unit's (or hovered unit's) current and queued targets are numbered
  on the map and linked by a line.

| Action | Does | Afterwards |
|---|---|---|
| Standby | Go there and wait | Stays |
| Auto | Go there, then decide on its own | Auto |
| Defend | Build a village there if possible, then guard it | Stays |
| Reinforce | Go there and merge into the unit there, which keeps its orders | Stays if nothing to join |
| Destroy | Destroy the village there (own villages take 4 days [G]) | Default order |
| Build | Build a village there (100 funds) | Default order |
| Clear Land | Clear the woods there | Default order |

- Leader: only moves. Recall (R) sends it back to the castle centre.
- Overall orders: "Order new units" (units without orders) or "Order all" (overrides).
- Default order: what units do when they leave a village, Auto or Standby. Set in
  the Playbook window ("New units").

## Job board [G, modern]
Instead of ordering units one by one, mark what should happen and Auto units do it.
- Tools (buttons bottom left, or keys): **B** plan villages, **C** plan clearing,
  **X** erase plans. Right-click, Esc or the key again puts the tool away.
- Village plans: click a cell, or drag a box to fill it with the densest layout
  (villages two cells apart, on whichever alignment fits the most). Allowed where a
  village could be built, woods included (they're cleared first), and not next to
  another planned village.
- Clearing plans: click or drag over woods. Anywhere, not just next to your land.
- Priority: 1/2/3 with a tool out (Normal, High, Urgent). Marking over plans of the
  same kind changes theirs.
- Auto units below army size (2048) take the nearest plan when they reach the Job
  board line of their playbook (the first line by default). Each priority level
  counts as 12 steps closer. One unit per plan.
- Village plans wait until there are funds (100 each, beyond what other builders
  have claimed). Auto building elsewhere leaves room for planned villages.
- A plan goes away once done, or when it can't be done any more (checked every
  10 days). Marking plans wakes idle Auto units.
- Drawn on the map: a house outline (village) or hatching (clearing), coloured by
  priority (white, orange, red), with a green dot once a unit is on its way.

## Structures [M except where marked]
Barricades, bridges and caves can't be stood on, so units work on them from the
next cell.

| Action | Target | Effect |
|---|---|---|
| Barricade | Clear land, or a barricade | +32 durability [G] per 4 days [G], 1 fund per 4 durability. Blocks everyone |
| Barricade (continuous) | same | Keeps strengthening it (max 255 [G]) while funds last; stays |
| Build Bridge | Water next to walkable land, or a damaged bridge | +1 durability per day. New: 30 funds per point all the way to 8 [G]. Repair: 2 per point. Walkable from 1 |
| Clear Path | Barricade or rubble | Removes 4 + strength/16 durability per day [G]. Your units don't do this on Auto unless you add the Clear barricades line [M default] |
| Dismantle | Bridge | Removes 1 + strength/256 durability per day [G], then it's water. Waits while someone stands on it |
| Dismantle (continuous) | same | Then keeps watching and pulls it down again if rebuilt; stays |
| Seal Cave | Cave | 10 days, costs 20 strength [G]. The cave becomes mountain |

- Barricades and rubble placed in a map start with 64 durability; bridges with 8,
  damaged bridges (`b` in a level) with 2 [G].
- A bridge below full durability (damaged, half-built or half-dismantled) is drawn
  with the damaged-bridge tile; at full durability it's drawn as a normal bridge.
- Hover a bridge, barricade or rubble to see its durability.

## Monsters
- Come out of caves (0.4% chance per cave per day [G], strength 40 [G], at most 10
  alive on a map [G]) [M].
- Attack every unit and village they can reach within 10 steps, otherwise wander [G].
  Merge when they meet and grow stronger [M]. Don't lose strength over time [G].
- A monster that defeats a leader eliminates that country with no heir [G].

## AI countries [G]
- Auto units clear barricades and rubble and seal caves near their land (playbook lines).
- If an army has no open route to its target castle, it plans one through barricades,
  and across water if needed, then clears the first barricade or bridges the first
  water cell on the way.


## Notes on specific maps
- "Moon and Stars" (B_103) is a novelty map: every country's villages are in sealed
  pockets and the castles share a lake. You win by bridging across from the unit
  you start with and rushing your leader into an enemy castle. AI countries don't
  move their leaders, so with no player the map runs to the day limit.
