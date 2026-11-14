# Backlog

Improvements to tackle later, after Phase B (rules) is finished.

## Quality of life
- [x] **Minimap**: LMO's small map mode, the whole 48x48 map in a corner, click to jump there
- [x] **Unit window**: LMO's panel for the unit or area under the cursor: strength graph, leader strength, distance, durability, default orders
- [x] **Status window**: per-country breakdown: leader strength, area, unit population and count, village population and count, funds, tax rate
- [ ] **Tune the guessed numbers**: every [G] constant in `Scripts/sim/rules.gd`, after enough play to know what feels off compared with LMO

## Modernization

### Controls
- [x] **Context right-click**: select units, right-click a target and the obvious action happens (woods = Clear Land, enemy = attack, water by a bank = Build Bridge, own village = Defend). The LMO menu stays for everything else
- [x] **Order queues**: Shift+click to chain orders ("clear these 3 woods, then build here")
- [x] **Job board**: paint village blueprints (box auto-layout) and clearing areas with priorities; Auto units take the work
- [x] **Playbooks**: editable "if this, do that" lines for Auto units (size, action, distance) and automatic tax, FF12 gambit style
- [ ] **Armies**: units you mark as armies refill from nearby villages while in home territory (costs funds to create, about 1000 to test); workers don't merge into them. Plus **Hold** on villages (pay tax, never release units)
- [ ] **Smarter attacks**: count strength lost on the walk, and re-check the target on the way
- [x] **Camera comfort**: edge scrolling, WASD, zoom toward the cursor, smooth zoom

### Information
- [x] **Map overlays**: toggle territory borders, which villages pay tax and where the route is cut, enemy threat zones
- [x] **Order previews**: path line and arrival time before confirming, ghost of the action on the target
- [x] **Tax preview**: moving the tax bar shows projected income and growth
- [x] **History graphs**: land and strength per country over time, plus an end-of-stage summary

### UX
- [x] **Settings menu**: speed presets, whether the order menu pauses the game, edge scroll on/off

### Bigger features
- [x] **In-game map editor**: paint terrain, place castles, villages and units, save to the level JSON (Settings > Map editor; `Scenes/Editor.tscn`)
- [ ] **Replays**: the simulation is deterministic, so a replay is the seed plus the player's orders
- [ ] **Level browser and sharing**: pick from your own, converted LMO and community levels

## Phase C: making it shippable (planned)
- [ ] In-game LMO import: a "point to your LMO folder" setting, with the `.BZ` / `.256` / `.MAP` decoders ported from `tools/` to GDScript
- [ ] Music: the 22 LMO MIDI tracks (MIDI addon or converted on import)
- [ ] Stage progression: campaign order, unused days carry over, standings after each stage
- [ ] Save and load
- [ ] Fallback art for players without LMO (own art or a free tileset)
