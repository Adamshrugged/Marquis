# Level format

A level is one JSON file: the map plus starting conditions. Load one by setting
`level_path` on the Game node, or from the command line:

```
godot --path . -- --level=res://Levels/sample_valley.json
```

The easiest way to make one is the map editor: in the game, Settings > Map editor, or
`godot --path . res://Scenes/Editor.tscn -- [--level=<path>]`. It saves to `user://levels/`
(on Windows `%APPDATA%\Godot\app_userdata\Marquis\levels`) and never overwrites the
built-in or converted levels; opening one of those and saving makes your own copy.

Converted Lord Monarch Online maps live in `DS7E_WIN/extracted/levels/`
(made by `python3 tools/lmo_map.py DS7E_WIN DS7E_WIN/extracted/levels Data/lmo_autotile.json`).
They are never committed.

## Example

See `sample_valley.json`. Minimal shape:

```json
{
  "format": 1,
  "name": "Sample Valley",
  "theme": "B_010",
  "day_limit": 1500,
  "player": 0,
  "countries": [
    { "id": 0, "castle": [3, 3], "funds": 5000, "tax": 10, "control": "player" },
    { "id": 1, "castle": [26, 14], "funds": 5000, "tax": 10, "control": "ai" }
  ],
  "terrain": [
    "^^^^^^^^",
    "^..~~..^",
    "^^^^^^^^"
  ]
}
```

## Fields

| Field | Required | Meaning |
|---|---|---|
| `name` | no | Shown to the player |
| `theme` | no | Art set only, no effect on rules. `B_010` Lord Monarch Night, `B_020` China Wars, `B_030` Food Panic, `B_040` Future Wars, `B_050` Fantasy Pastel. Default `B_010` |
| `day_limit` | no | Days to win in. Default 3000 |
| `player` | no | Country id the human controls. Default 0 |
| `countries` | yes | 1 to 4 countries, see below |
| `terrain` | yes | One string per row, one char per cell, all rows the same length. Any size |
| `territory` | no | Same shape as `terrain`. `.` = unowned, `0`-`3` = owned by that country |
| `villages` | no | `{ "owner": 0, "pos": [x, y] }` |
| `units` | no | Extra starting units: `{ "owner": 0, "pos": [x, y], "strength": 100 }`. Every country also starts with one unit outside its castle gate |
| `objects` | no | `{ "code": 16, "pos": [x, y] }`. Raw LMO tile codes with unknown meaning; drawn only |
| `tile_overrides` | no | `[x, y, code]`. Forces the drawn tile. Converted maps use this for the ~1% of cells the autotiler can't reproduce. Hand-made maps don't need it |

Coordinates are `[x, y]` with `[0, 0]` top-left.

### Country

| Field | Meaning |
|---|---|
| `id` | 0 green, 1 red, 2 white, 3 black (the id sets the colour) |
| `castle` | Top-left cell of the 3x3 castle. Those 9 cells become `C` automatically |
| `funds`, `tax` | Starting money and tax rate (0-30; higher values are cut to 30) |
| `leader` | Starting leader strength. Default 400 (a guess) |
| `control` | `player` or `ai` |
| `style` | AI personality: `balanced`, `aggressive`, `builder` or `turtle`. Default: picked from the game seed |

## Terrain chars

| Char | Terrain | Notes |
|---|---|---|
| `.` | Clear land | The only place villages can be built |
| `T` | Woods | Assumed to be LMO "wilderness" (needs Clear Land) |
| `~` | Water | |
| `^` | Mountain | |
| `=` | Bridge | |
| `b` | Damaged bridge | Not walkable. Build Bridge repairs it into a bridge (2 funds a point) |
| `x` | Barricade | |
| `o` | Cave | Target of "Seal Cave" |
| `*` | Rubble | Meaning is a guess |
| `C` | Castle | Set automatically from `countries` |

Edges and corners (shorelines, mountain ridges, woods borders) are drawn
automatically from the neighbouring cells, so you only write what each cell is.

## Not from the original

The `.MAP` files only hold terrain and theme. Starting `funds`, `tax` and
`day_limit` in converted maps are placeholders, not Lord Monarch's real values.
