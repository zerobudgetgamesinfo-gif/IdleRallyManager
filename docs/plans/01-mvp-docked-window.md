# Phase 1 — Docked companion window

## Goal

Ship a strip along the bottom of the screen that can stay up while another app is in use. This is the MVP. Design: [GDD.md](../GDD.md) sections 9, 13, and 16. Practices: [AGENTS.md](../../AGENTS.md).

The player can see the strip, drag it to another monitor, change its height, toggle always-on-top, and quit, without the game taking the keyboard.

## Non-goals

- Championship rules, saves, and the solver (phase 2).
- Standings, draft, or service UI (phases 3 and 5).
- Scrolling art (phase 4) and final illustration (phase 7).
- A side edge, a tray icon, or an OS-reserved panel.
- A fullscreen transparent window. The window is only the strip, so the rest of the desktop is never covered by this process.

## Dependencies

Phase 0: [AGENTS.md](../../AGENTS.md) and the GDD. No sim types exist yet. The placeholder must not import `sim/`.

## Project settings

Set these in the editor, or edit [project.godot](../../project.godot) only for the keys listed here. Overlay behavior is specified in [Creating applications](https://docs.godotengine.org/en/4.7/tutorials/ui/creating_applications.html).

Application:

- `config/name` stays `IdleRallyManager`.
- `run/main_scene` = `res://scenes/boot/main.tscn`.
- `config/use_custom_user_dir` = true, `config/custom_user_dir_name` = `idle-rally-manager`.
- `run/low_processor_mode` = true.
- `run/low_processor_mode_sleep_usec` = `100000` (about 10 fps while idle).
- `boot_splash/bg_color` = transparent black `(0, 0, 0, 0)`.
- `boot_splash/show_image` = false.

Display:

- `window/size/viewport_width` = `1280`, `viewport_height` = `220`. The script replaces both on launch.
- `window/size/borderless` = true.
- `window/size/always_on_top` = true.
- `window/size/transparent` = true.
- `window/size/no_focus` = true.
- `window/per_pixel_transparency/allowed` = true.
- `window/energy_saving/keep_screen_on` = false.
- Stretch stays `canvas_items` / `expand` (already set).

Rendering:

- Switch the renderer from Forward+ to **GL Compatibility**. `config/features` should list `4.7` and `GL Compatibility`. `rendering/renderer/rendering_method` = `gl_compatibility`.
- Remove the Forward+ Windows driver line (`rendering_device/driver.windows="d3d12"`) so the project is not half-configured for a renderer it does not use.
- `viewport/transparent_background` = true.

Physics:

- `physics/2d/physics_engine` = `Dummy`.
- `physics/3d/physics_engine` = `Dummy`.

Leave the audio driver on the default. This phase plays no streams. Do not set the driver to `Dummy`; phase 7 adds audio on the normal driver.

## Tasks

1. Add the `Dock` autoload (`res://scripts/dock/dock.gd`) and register it. Document it in [AGENTS.md](../../AGENTS.md) if the table there is still missing the row (it already lists `Dock`; keep the path in sync).
2. In `Dock._enter_tree`, when `Engine.is_embedded_in_editor()` is false, apply flags and place the window before the first presented frame:
   - Read `user://window.cfg` with `ConfigFile`. Keys: `screen` (int, default `-1`), `preset` (`compact` or `cozy`, default `cozy`), `always_on_top` (bool, default true).
   - Resolve the screen: saved index if `DisplayServer.get_screen_count()` still contains it, otherwise the screen under the mouse, otherwise the primary screen.
   - Usable rect: `DisplayServer.screen_get_usable_rect(screen)`.
   - Height: `144` or `220` multiplied by the window content scale. Read the scale the way [Multiple resolutions](https://docs.godotengine.org/en/4.7/tutorials/rendering/multiple_resolutions.html) describes for the running platform. Fall back to `1.0` when the OS does not report one (X11 and Windows need a manual scale later; store the preset, not the pixels).
   - Position the window at the bottom of the usable rect, width equal to the usable width, height equal to the preset.
   - Re-apply `borderless`, `transparent`, `always_on_top` from the config, and `unfocusable` (`no_focus`) always on.
3. Rebuild `mouse_passthrough_polygon` whenever the window size or the layout changes. The polygon is the visible rounded rectangle, inset 8 px from the window edges. Those 8 px stay transparent and receive no clicks. An empty polygon would capture the whole window; do not clear it after the first layout.
   - On Windows, pixels outside the polygon are not drawn ([Window.mouse_passthrough_polygon](https://docs.godotengine.org/en/4.7/classes/class_window.html)). Keep every painted pixel inside the polygon.
4. Drag handle. A control along the top 16 px of the strip (`MouseDragHandle`, unique name). While the button is held, if `DisplayServer.get_screen_from_rect` of the pointer (or the screen at the mouse position) changes, re-dock to that screen's bottom edge and save. Ignore vertical dragging in this phase; the edge is always bottom.
5. DPI and usable-rect changes. Connect `Window.size_changed` and handle `NOTIFICATION_WM_DPI_CHANGE` and `NOTIFICATION_WM_WINDOW_FOCUS_IN` is irrelevant because the window is unfocusable. Also poll on a slow timer (about 2 s) for a taskbar resize: if the usable rect moved, snap the strip back to the bottom. The timer fires rarely; do not poll every frame.
6. Settings cluster, one button in the strip (`%SettingsButton`). The panel opens as a child of the strip, not as a second `Window` (extra windows are X11/XWayland only; see Creating applications, "Spawning multiple windows"). The panel contains:
   - Height preset, two choices.
   - Always-on-top checkbox. When off, clear the flag and let the strip sit in normal z-order.
   - Quit. Saves `window.cfg`, then `get_tree().quit()`.
   - Pause is omitted until `Session` exists (phase 3). Leave a disabled row or skip it. Do not invent a pause flag in `Dock`.
7. Placeholder picture. A `Panel` or `ColorRect` inside the polygon, with a short label ("Idle Rally Manager") so the strip is obvious on a busy desktop. No `AnimationPlayer`, no shader, no particle. The idle frame must be allowed to stop redrawing.
8. `main.tscn` root script only builds this placeholder and asks `Dock` to refresh the hit polygon after layout. It does not set window flags itself.
9. Save `window.cfg` on preset change, screen change, always-on-top change, and `NOTIFICATION_WM_CLOSE_REQUEST`.
10. Platform probe, once, logged with `print` in a debug build:
    - `DisplayServer.get_name()`.
    - Whether `always_on_top`, `unfocusable`, and a non-empty passthrough polygon stick after being set (`get_flag` / read-back).
    - Re-read the "implemented on" notes for `FLAG_ALWAYS_ON_TOP`, `FLAG_NO_FOCUS`, `FLAG_TRANSPARENT`, and `mouse_passthrough_polygon` on the 4.7 [Window](https://docs.godotengine.org/en/4.7/classes/class_window.html) page before treating a failure as an engine bug.
    - If native Wayland ignores always-on-top or passthrough, keep the strip usable (borderless, correct rect, in-strip quit) and write the result in a short comment at the top of `dock.gd`. Do not add a GDExtension in this phase.

## Files

| Path | Purpose |
| --- | --- |
| [project.godot](../../project.godot) | Keys listed above |
| `res://scripts/dock/dock.gd` | Autoload `Dock` |
| `res://scenes/boot/main.tscn` | Main scene |
| `res://scripts/boot/main.gd` | Placeholder layout |
| `user://window.cfg` | Created at runtime, not committed |

Update the autoload table in [AGENTS.md](../../AGENTS.md) only if the script path changes.

## Acceptance

Run the project with game embedding off (Game view, "Embed Game on Next Play" unchecked). An embedded run does not test the overlay.

On the Linux machine this repo is developed on:

- The strip sits on the bottom of the usable area, above the taskbar, on the primary screen.
- A browser or the editor keeps keyboard focus. Typing there still works while the strip is visible.
- Clicks outside the strip activate the other app.
- Clicks in the 8 px transparent margin also reach the other app. Clicks on the label and the settings button hit the game.
- Opening settings, switching compact/cozy, and quitting all work with the mouse only.
- Dragging the handle onto a second monitor, when one is attached, snaps the strip to that monitor's bottom edge. After a restart the same screen and preset return.
- With the strip idle, CPU stays near idle for this empty scene. If fans spin, turn on Debug > Debug Canvas Item Redraws and remove whatever is invalidating the frame.
- Debug log names the display server and whether always-on-top, no-focus, and passthrough read back as set.

Known limits, not failures of this phase:

- Exclusive fullscreen in another app covers the strip.
- A window manager that ignores always-on-top still passes if the strip is borderless, placed, and clickable, and the debug log records the missing flag.
- Windows clipping outside the passthrough polygon is expected. Verify the label is still visible when a Windows machine is available; do not block the Linux MVP on it.
