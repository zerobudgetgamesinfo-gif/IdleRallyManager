# Phase 7 — Polish and desktop integration

## Goal

The strip looks and sounds like the companion in [GDD.md](../GDD.md) sections 9 and 10, and it exports as a desktop app. Gameplay rules do not change here.

## Non-goals

- A new stat, a new solver term, or multiplayer.
- OS panel reservation (layer-shell, `_NET_WM_STRUT`, `SHAppBarMessage`). A short research note in the PR is enough if someone tries it. The shipped window remains a floating strip (GDD section 2).
- A system-tray icon. Godot's `StatusIndicator` is Windows and macOS only ([Creating applications](https://docs.godotengine.org/en/4.7/tutorials/ui/creating_applications.html)); the in-strip pulse stays the cue on every platform.

## Dependencies

Phase 6's tuned catalog. Art can be stubbed earlier, but this phase is where placeholders leave.

## Tasks

### Presentation

1. Replace the phase 4 rects with illustrated layers: sky, ground, road, player car, rival ticks. Side view, left to right, one palette per surface (GDD section 10). Source files live beside the scenes that use them (`scenes/stage/art/`), `snake_case` names.
2. Animal portraits for the roster, used in the draft and the standings. Simple vector-style textures are enough. Keep transparent pixels inside the passthrough polygon so Windows still draws them (GDD section 16).
3. Incident poses: slide, hop, wobble, each a short `AnimationPlayer` clip triggered by the existing crossing logic. Clips do not loop.
4. Service park: a still illustration behind the cards. It does not animate for the whole half hour. The card pulse remains the only repeating motion, and only while a choice is open.
5. First launch: three lines of copy in the idle strip ("A rally sits on your desktop", "Choices happen between stages", "You can step away"). Set a `seen_intro` bool in `window.cfg`. Do not put it in the championship save.

### Audio

6. Master bus default about -18 dB. Mute from the settings cluster, stored in `settings.muted`, applied on load.
7. A quiet loop during reveal only, started when the stage view enters the tree and stopped when it leaves. A short incident stinger on the same crossing that plays the pose. No music bed in the service park.
8. Leave `audio/driver/driver` on the platform default. Do not switch it to `Dummy`.

### Accessibility and input

9. Set `accessibility_name` and, where the control is an icon, `accessibility_description` on draft rows, cards, pause, quit, and the settings button. Godot's screen-reader path is AccessKit ([Creating applications](https://docs.godotengine.org/en/4.7/tutorials/ui/creating_applications.html)). The strip is still mouse-first because the window is unfocusable; names are for tools that walk the tree, not a promise of full keyboard play.
10. Do not encode state by color alone. The selected card keeps its check mark. The safe card keeps its "if you step away" words.

### Desktop

11. Side dock, optional, off by default. `window.cfg` key `edge` is `bottom` or `left`. Left uses the usable rect's left edge, height = usable height, width = the idle preset's long side (144 or 220), not focus height. If the strip is in a focus phase when the player switches to left, fall back to the preset width (choice layouts may stack or simplify). The drag handle moves to the inner edge. Hit polygon inset stays 8 px. If the layout cannot fit the three cards, the left edge falls back to a standings-only column and the cards stack. Skip the side dock rather than shipping a broken stack.
12. Manual content scale in settings (1.0, 1.25, 1.5, 2.0) because X11 and Windows do not report a scale reliably ([Multiple resolutions](https://docs.godotengine.org/en/4.7/tutorials/rendering/multiple_resolutions.html)). Multiply the preset by that factor. Default 1.0, and on Wayland/macOS offer "Match screen" using `DisplayServer.screen_get_scale` when it returns a useful value.
13. `exclude_from_capture` on the root window, default off, toggle in settings. The hint exists on Windows and macOS only; hide the toggle when the property does nothing. It is best-effort, not a privacy guarantee (Creating applications, overlay section).
14. HiDPI smoke test: cozy preset at scale 2 stays on the usable rect and the quit button remains inside the window.
15. Export presets for Linux, Windows, and macOS. Embed the PCK so the app is one executable where the platform allows it ([Creating applications](https://docs.godotengine.org/en/4.7/tutorials/ui/creating_applications.html), single-executable section). The custom user dir `idle-rally-manager` is already set in phase 1. Do not turn on portable mode.

### Still-image idle

16. After polish, repeat the canvas-redraw check from phase 1 with the final art visible and no championship running. A looping material or a forgotten `AnimationPlayer` autoplay fails the phase.

## Files

Touched scenes from phases 1, 3, 4, and 5, plus:

| Path | Purpose |
| --- | --- |
| `scenes/stage/art/` | Stage textures |
| `data` portraits on `DriverDef` / `CarDef` | `Texture2D` exports |
| `res://ui/theme.tres` | Shared fonts and minimum control sizes |
| `export_presets.cfg` | Generated by the editor when presets are saved; commit it |

## Acceptance

- Idle and service sit still apart from the choice pulse.
- A reveal is readable at compact height: position, gap, and the player car.
- Mute survives a restart. Unmuting during a reveal starts the loop without a second launch.
- Intro copy shows once per machine (`window.cfg`), not once per championship.
- Linux export runs the strip beside another app the same way the editor run did in phase 1.
- Windows or macOS, when a machine is available: transparent margins, quit, and (if the toggle is shown) exclude-from-capture. Missing hardware is a written gap, not a silent skip of the Linux checks.

## Status

Implemented and checked headless (`sim/checks/ui_checks.gd`, run by `run_checks.gd`): illustrated stage layers, portraits, incident poses, still service park, intro once, bus mute, reveal loop and stinger, accessibility names, side dock, content scale, exclude-from-capture setting, still idle audit, and the HiDPI cozy-at-2x geometry.

Run by hand on Windows outside the embedded view: bottom compact and cozy, left 144 and 220, and cozy at scale 2 through idle, draft, reveal, service, and a pick. Everything stays inside the window. Left compact (144) is tight: cards stack and text wraps, so left cozy is the better default for the side dock.

Gaps:

- Linux export and the Linux strip-beside-another-app run were not done. This machine is Windows with no export templates (`windows_release_x86_64.exe` is missing), so no export was produced. `export_presets.cfg` has Linux, Windows, and macOS presets with the PCK embedded and portable mode off; the Windows preset skips `rcedit` (`application/modify_resources=false`). Output goes to `build/`, which is ignored.
- Exclude-from-capture and transparent margins were not checked in a capture tool or on macOS.
- `ui/theme.tres` was not created. Controls keep the default theme with local overrides; no task above needs it.
- OS panel reservation was not tried, per the non-goals.
