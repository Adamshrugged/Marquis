---
name: hud-layout
description: Screen regions taken by Marquis HUD/view panels at 1152x648, and how view windows are wired (who creates them, input routing)
metadata:
  type: project
---

Screen budget at the default 1152x648 window (as of 2026-10-09, after the Batch 1 top-bar redesign):
- y 0-84 full width: LMO-style teal top bar built in code in Scripts/gui_battle.gd (Treasury with tax slider/Auto, Time, Your country, country strip). GUIBattle.tscn is just the root Control.
- `game.HUD_TOP` (88) / `game.HUD_BOTTOM` (52) constants in Scenes/game.gd: windows sit below HUD_TOP; OrdersUI button bar sits HUD_BOTTOM above the bottom.
- UnitWindow at (4, HUD_TOP), 250 wide. Minimap top-right from HUD_TOP. StatusWindow centred between x=262 and width-210 at HUD_TOP.
- Bottom ~48 px: status Label, 2 lines (orders hint, keys), mouse ignored.
- Camera margins (camera.margin_top/bottom/left/right) come from game.update_camera_margins(): top bar, bottom bar + hint lines, unit window width on the left, minimap width on the right (re-run when the minimap is toggled via game.show_minimap). User wants every map edge scrollable fully clear of the HUD.
- Batch 2 (2026-10-09) additions: OrdersUI.button_bar (bottom right) now ends with Status, "Map:" overlay picker (MapOverlay), Graphs, Settings; it spans ~x 217-1145 at 1152 wide, so it's full. Overlay legend sits top-centre under the bar; GraphsWindow and SettingsWindow are centred panels. Bottom keys line is font 14 and nearly full width (measure with ThemeDB.fallback_font before adding keys).
- Esc chain: OrdersUI takes Esc only if busy() (selection/menu); else game.gd closes settings/graphs/status, else opens settings.

**Why:** new panels kept colliding; these numbers were checked against screenshots.
**How to apply:** place new UI relative to HUD_TOP/HUD_BOTTOM and re-screenshot.

Wiring: game.gd creates OrdersUI, UnitWindow, Minimap, StatusWindow in code and adds them to the `UI` CanvasLayer (no scene changes). Map clicks go through `_unhandled_input`, so any Control with MOUSE_FILTER_STOP blocks them (the top bar is STOP). TerrainLayer emits `cells_redrawn` from refresh() for anything mirroring the map. Screenshot capture tip: see [[capture-screens]].
