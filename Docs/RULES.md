# Marquis rules

How the simulation works, based on the Lord Monarch Online manual
(https://www.falcom.co.jp/monarch/manual/index_e.html) and on the LMO program itself
(`Docs/LMO_ENGINE.md`).

Every rule is tagged:
- **[M]** stated in the manual
- **[E]** read out of the LMO program (`DS7E_WIN.EXE`, see `Docs/LMO_ENGINE.md`)
- **[G]** guessed or simplified: no source gives a number or detail. These are
  constants in `Scripts/sim/rules.gd`, to tune by playing the original

## Time
- The game runs in days. Each map has 3000 days [M]. One simulation step = one day [G].
- A day is 2 ticks [E]. Upkeep, combat rounds, work and the leader happen once per
  tick; villages, caves and tax once every 8 days, each in turn [E].
- Units walk 1 cell per tick, so up to 2 a day; turning to face a new direction takes a
  tick, and woods cost nothing extra [E].
- Speed: default 8 days per second, adjustable [G].
- At most 64 units on the map at once, all countries and monsters together [E].
  Strength and funds stop at 100000 [E].

## Countries
- 4 countries per map, each with a castle and a leader [M]. Player = one of them.
- Each starts with one unit (strength 100 [G]) just outside its castle gate [M: seen in LMO].
  Levels can place more with `"units"`.
- Win: defeat every other leader within the day limit [M].
- Lose: your leader is defeated, or days run out [M].
- Defeating a leader (anywhere) hands you its villages, units and funds [M]. The funds
  come at once; the rest changes hands one at a time [E]: each unit the next time it
  acts (it goes on Auto, and can't be attacked until then), each village at its next
  8-day visit, with its territory around it (no growth that visit). If the winner is
  beaten meanwhile, the rest goes to whoever beat them. A leader beaten by monsters, or
  worn away by decay, leaves no heir: its units die and its villages become clear land,
  the same one at a time.
- The defeated country's castle disappears, leaving open ground [M: as in LMO].

## Castle
- 3x3. Only the entrance (bottom middle) and the centre are walkable [G].
- The leader stands in the centre. The castle can't be destroyed [M].
- Fighting from or against a castle centre follows its own damage rules (Combat) [E].
  The gate gives no bonus [E].

## Leader [E]
- **Population** = village population + strength of every unit but the leader.
- In its castle centre, each tick: if population is below half the leader's
  strength, a quarter of the leader's strength leaves through the gate as a new
  unit (only into an empty gate, with room for a unit). Otherwise, if the leader is
  weaker than the population, it grows by 1/8 of the gap. It never shrinks toward
  the population; it only loses strength by releasing units or fighting.
- Away from the castle it pays upkeep and decays like any unit (Units).
- Only obeys "move". Destroys enemy villages and fights enemies on its route.
  Doesn't clear land or build bridges [M].

## Villages (bases)
- Cost 100 funds [M]. Only on clear land (not woods, bridges, barricades) [M], anyone's
  territory or none [E].
- Not next to another village of the same country (8 neighbours) [M]; next to an enemy's is fine [M].
- The builder gives up to 200 of its strength; the village starts at half of that + 1.
  A builder with 200 or less is used up [E]. Building is instant [E].
- A new village has no land yet [E]. Villages in a map start at 100 population [E].
- Every 8 days each village grows by its own territory neighbours + 1 [E]. Tax has
  no effect on growth [E] (it takes population away, see Funds and tax).
- Once population reaches (territory neighbours + 1) x 16 [M] (it stops at 255 [E]):
  - it claims one clear, unowned neighbour as territory; if there is none, it takes
    over a neighbour that is another country's territory [E];
  - with no land left to claim, or at 200+ population, its whole population leaves
    as one unit (or joins an own unit standing there) and the village drops to 1 [E].
- Destroying your own village is instant; the unit takes in its population [E].
- Attacking an enemy village: both lose the smaller of the unit's strength and the
  village's population; at 0 the village becomes clear land. The unit moves in the
  next day [E]. The territory around a destroyed village stays [E].

## Funds and tax
- Tax bar under the HUD [M]: drag or click to set it (turns Auto off); Auto turns it
  back on. `[` / `]` change it by 1. A note says whether taxes are coming in.
  Hovering or dragging the bar previews income and village population change per
  day at that rate against the current one. The Tax routes map overlay (F2) shows
  which villages pay, which are cut off and what blocks the way.
- **Tax rate 0-30** [E]. Every 8 days, at the castle, each connected village pays
  rate x population / 256 funds, and that much population is taken from it [E].
- Tax only comes in with the leader in its castle centre and the cell just outside
  the gate open land (not water, a barricade or another country's land) [M][E].
- A village is connected if units could walk from the castle entrance to it without
  passing enemy villages or barricades [M]. Routes are found at each collection [E].
- Auto tax: the tax playbook (see Playbooks), checked at each collection. By default
  LMO's automatic tax [E]: player 20 - funds / 256 (in steps of 640 funds), AI 28, 24
  ... 4 below 1792 funds, else 0.
- Funds pay for villages, bridges, barricades, and upkeep [M].

## Units
- Size by strength: S up to 999, M 1000-9999, L 10000+ [M].
- Move 1 cell per tick (2 a day), a tick to turn; woods are no slower [E].
- Routes go round enemies the unit can't beat, and the cells next to them [E]: an enemy
  stronger than the unit's strength / 1.25, or on its castle centre stronger than
  strength / 2 (a unit) or / 4 (the leader). Not when the unit is sent to attack that
  enemy or its cell: then it goes. With no way round, the order is refused.
- Standing on another country's territory turns it back into clear land [E] (villages
  and castles excepted), which can cut that country's tax routes.
- **Upkeep and decay**, every tick, walking or not [E]:
  - on any castle centre or its own village it pays strength / 2048 funds (free
    below 2048) and loses nothing;
  - anywhere else, or with too few funds, it loses strength / 256 + 1. If that would
    take it to 0, the unit is gone.
  - So standing in the field a unit of 100 loses 2 a day, 1000 loses 10, 10000 loses 80.
  - The Status window (Tab) shows each country's upkeep and decay for the last day.
- Same-country units on the same cell merge (up to 100000) [M][E]. Survivor priority:
  leader, then ordered units, then the stronger [M].
- New units start with the default order, initially Auto [M].

## Combat [E]
- Each tick, before anything else, a unit attacks an enemy in one of the 4 cells
  next to it (the one it faces first). Units never step into an enemy's cell; they
  fight from next to it until one side is gone.
- Damage per round is strength / n + 1:
  - in the open: the attacker deals /8, the defender hits back /16;
  - against a unit on a castle centre: both deal /8;
  - from a castle centre (a leader hitting out): the attacker deals /4 and takes nothing.
- A unit is gone when a hit reaches its strength.

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
| Clear woods | Woods next to own land. Auto units prioritise this [M] | Not already taken by another unit. Strength 2+ |
| Build village | A spot where a village is allowed | 100 funds beyond what other builders have claimed. Leaves room for planned villages |
| Attack units | An enemy unit | Must outweigh it by 20% (even odds on own land). Never a leader |
| Destroy villages | An enemy village | Must outweigh its population by 20% |
| Seal caves | A monster cave within 6 of own land | Strength 8+ |
| Clear barricades | A barricade or rubble | Strength 32+ |
| Guard castle | Own castle gate, to stand in it (blocks the way in; the leader can't release units while it's there) | Only while an enemy is within 6 of the castle centre (units standing in their own castle don't count). Distance is from the gate |
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
- Lines "if funds are below X: set tax to Y" (0-30, or keep the current rate), checked
  from the top at each collection (every 8 days); a fixed last line "otherwise: tax Z".
  Up to 8 lines.
- Funds saved for a bridge don't count.
- Only while automatic tax is on. Moving the tax bar turns it off [M]; the Auto
  button, the checkbox in the Tax tab or editing a line turns it back on.
- Defaults are LMO's automatic tax [E]. Player: below 640 → 19, 1280 → 17, 1920 → 14,
  2560 → 12, 3200 → 9, 3840 → 7, 4480 → 4, 5120 → 2, otherwise 0 (LMO: 20 - funds / 256).
  AI (every style): below 256 → 28, 512 → 24 ... 1792 → 4, otherwise 0. The player
  starts with automatic tax off.

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

| Style | Attacks when the army is | Joins the army at | Comes back to defend from |
|---|---|---|---|
| balanced | 1.25x the target castle | 64 | 12 steps |
| aggressive | 1.0x | 40 | 8 |
| builder | 1.5x | 128 | 12 |
| turtle | 1.8x | 96 | 20 |

The target castle counts as 2x its leader's strength: a leader in its castle centre
hits out at /4 and takes /8 back, so an attacker needs about sqrt(3) times its
strength [E].

### Targets
- Every 10 days each AI picks the enemy that's cheapest to beat: castle strength
  (leader x2) scaled by distance. A castle only reachable through barricades or
  water counts 6x.
- The army gathers at the own village closest to that castle.

### Armies
- Units of 2048+ strength (where upkeep starts [M]) don't clear land or build.
- An army waiting at the rally point raids enemy villages once it's 2048+ strong or
  has waited 60 days, instead of paying upkeep for nothing.
- If the target can only be reached across water, the country saves 3030 funds
  (one bridge over water) before building more villages. Any idle unit with nothing in its
  playbook, not just the army, does that bridging or barricade-clearing work.

### Defence
- An enemy within 6 cells of an AI castle is a threat. Units standing in their own
  castle (leaders, gate guards) don't count, so castles built close together don't
  keep each other on alert forever. Idle units within the
  style's defend range go and stand in the castle gate, blocking the way in: the Guard castle line.
- Enemy units on the AI's own land are attacked at even odds (elsewhere it wants 20% more).

### Auto tax
- The tax playbook (LMO's AI tax by default): high while broke or saving for a bridge,
  0 from 1792 funds.

## Orders [M except where marked]
Who -> Where -> Does what. Click a unit (or drag a box), click a destination, pick
an action. Esc cancels. The game pauses while the menu is open [G] (a setting can turn that off).
If no selected unit can reach the destination, it keeps waiting for another.

Context right-click [G, modern]: with units selected, right-click a destination and
the obvious action happens, without the menu:

| Right-click on | Action |
|---|---|
| Enemy village | Destroy |
| Enemy unit or enemy castle (centre/gate) | Standby there (it fights whatever stands in the way) - "Attack" |
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
the hint line gives the distance and days (2 cells a day, turns take a tick), and a label by the cursor
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
| Destroy | Destroy the village there (own villages: instant, the unit takes in its population [E]) | Default order |
| Build | Build a village there (100 funds; the builder gives up to 200 strength) | Default order |
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
next cell. Every cell has a counter that starts at 100 when a map loads [E]: the
durability of bridges, barricades and rubble, and the work left on woods, caves,
water and damaged bridges. Work happens once per tick at strength / n, so big units
work fast and small ones may not manage it at all [E].

| Action | Target | Per tick [E] | Cost [M][E] | Done |
|---|---|---|---|---|
| Clear Land | Woods (stands on them) | work - strength/2 | none | work below 1 (needs strength 2+) |
| Barricade | Clear land, or a barricade | strength/16 | 1 fund per 4 points | Clear land: the cell's 100 is worked off, then the barricade stands with what's left over. A barricade: one round of strengthening |
| Barricade (continuous) | same | same | same | Keeps strengthening it up to 255 while funds last; stays |
| Build Bridge | Water next to walkable land, or a damaged bridge | strength/16 | water 30 funds a point (~101 points, ~3030 funds), damaged bridge 2 a point | It becomes a bridge whose durability is whatever was left over (small) |
| Clear Path | Barricade or rubble | durability - strength/32 | none | 0 (needs strength 32+). Your units don't do this on Auto unless you add the Clear barricades line [M default] |
| Dismantle | Bridge, or a damaged bridge | bridge: durability - strength/32; damaged: work + strength/32 | none | The bridge becomes a damaged bridge and **a unit on it is lost**. On a damaged bridge, one round making it harder to repair |
| Dismantle (continuous) | same | same | none | Then keeps adding repair work (up to 255) and pulls the bridge down again if rebuilt; stays |
| Seal Cave | Cave | work - strength/8 | none | below 0: the cave becomes mountain (needs strength 8+) |

- A damaged bridge (`b` in a level) can't be walked on [E]; Build Bridge repairs it.
- Bridges built in play are fragile: their durability is only the last tick's
  overshoot, so they come down quickly. Bridges in the map start at 100.
- Hover a cell to see its counter (durability or work left).

## Monsters
- Come out of caves on a timer, no chance involved [E]: every 8 days a cave's counter goes
  up by 10, and at 245 a monster of strength 200 comes out and the counter drops by 245.
  From the starting 100 the first comes after about 120 days, then one about every 200
  days per cave. Only if a unit slot is free (64 on the map). In LMO the monster appears
  on the cave itself; Marquis caves can't be stood on, so it steps out next to it.
- Sealing works the same counter down, so a cave close to its next monster takes longer.
- They don't hunt [E]: a monster walks straight ahead for 20-58 ticks, rests 0-10, and
  turns at random (to an open side) when blocked. Whatever it bumps into it fights,
  merges with (monsters, growing stronger [M]) or attacks (villages). Boxed in, it chips
  at a barricade next to it, 1 point a tick. No upkeep, no decay [E].
- A monster that defeats a leader eliminates that country with no heir [E].

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
