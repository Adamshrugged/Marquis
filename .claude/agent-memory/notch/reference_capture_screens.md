---
name: capture-screens
description: How to take verification screenshots and simulated-input checks of Marquis UI (temporary capture scene, mouse caveats, headless viewport size)
metadata:
  type: reference
---

Temporary capture scene: a Node script + .tscn in Tests/ instantiating res://Scenes/Game.tscn, stepping `game.sim.step()` ~200 days, `game.terrain.refresh(world)`, `game.paused = true`, set `game.camera.edge_scroll = false`, then `await RenderingServer.frame_post_draw` and `get_viewport().get_texture().get_image().save_png()`. Run windowed: `timeout 90 godot --path . res://Tests/_cap.tscn -- --level=...`. Delete the files after.

Mouse: the viewport mouse position follows the real OS cursor (warp_mouse is unreliable, likely Wayland), so hover-dependent shots lose the position. Fix that works: in the capture node's `_process`, every frame re-send `Input.parse_input_event(InputEventMouseMotion)` at the wanted screen point (canvas_transform * world pos) whenever `get_viewport().get_mouse_position()` drifts.

Simulated input checks must run windowed: headless has a tiny (~64 px) viewport, so screen<->world maths and clicks are wrong. OrdersUI reads click positions from the event (`make_input_local`), so pushed button events are reliable; wait a couple of frames between press/release. Related: [[hud-layout]].

Batch 2 findings: window focus is flaky between runs; call get_window().grab_focus() + Input.warp_mouse(pos) right before focus-dependent checks (edge scroll) and skip if has_focus() is false. gui_get_hovered_control() stays null while the real OS cursor is outside the window (Godot ignores hover then; can't be faked from script, even with x11 driver), so hover-over-UI checks must SKIP in that case. Settings tests: set `SettingsWindow.file` to a test path before instantiating Game.tscn so the user's user://settings.cfg isn't touched. Sample Valley's player is dead by ~day 300 without orders; use B_000 for long captures.
