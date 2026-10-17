# Phase 3 — Championship HUD

## Goal

The phase 1 strip shows a full solo championship as text: phase, clock, standings, and whether a service choice is waiting. Placeholder art stays. Design: [GDD.md](../GDD.md) sections 3, 9.2, and 13.

## Non-goals

- The scrolling stage (phase 4). A reveal is a label and the standings, not a car on a road.
- Real card rows and the draft columns (phase 5). This phase may call `confirm_draft` and `choose_card` through temporary text buttons so the clock can be exercised. Phase 5 replaces those buttons.
- Final theme, audio, and accessibility copy (phase 7).

## Dependencies

Phase 1 window (`Dock`, `main.tscn`) and phase 2 (`Session` signals, save, time scale).

## Tasks

1. Add `scenes/hud/strip.tscn` as the only child view of `main.tscn`. Swapping phase scenes is instancing a child and freeing the previous one. Do not `change_scene_to_file` (see [AGENTS.md](../../AGENTS.md)).
2. `scripts/hud/strip.gd` connects to `Session.phase_changed`, `recap_ready`, and `championship_finished`. It rebuilds the visible block for `idle`, `draft`, `stage_reveal`, `service`, `recap`, and `finished`.
3. Idle: a "Start championship" button calls `Session.start_draft()`.
4. Draft placeholder: two `OptionButton`s populated from `Catalog`, a budget label, and Confirm. Illegal pairs disable Confirm. This UI is throwaway; keep it in `scripts/hud/draft_placeholder.gd` so phase 5 can delete it without untangling the standings.
5. Reveal: one line of HUD copy from GDD section 9.2: position, gap to the car ahead (from the solved result; during this phase the gap can be the final gap, because interpolation arrives with the scroller), fictional stage clock scaled by the reveal fraction, and championship points from committed stages only. Points for the open stage appear when the reveal completes.
6. Service: label "Choice waiting", the three card ids, and a button per card that calls `choose_card`. Show the remaining service time.
7. Recap: a `RichTextLabel` or a `VBox` of the rows `Session` stored (stage name, position, card id, `applied_by`). Dismiss calls `dismiss_recap()`.
8. Finished: the final table (position, name, points, total time) and Dismiss to idle.
9. Pause toggles `Session.pause()` / `resume()`. Put it on the phase 1 settings cluster, replacing the skipped row from phase 1. Pause is hidden in `idle`, `draft`, and `finished`.
10. Debug builds only: a spin box for `time_scale` (1, 10, 60, 120) stored via `Session`. Release exports do not instance this control (`OS.is_debug_build()`).
11. Abandon sits in the settings cluster and calls `Session.abandon()` after a second click on the same button (the second click is the confirm; do not open a native dialog that would steal focus or spawn another window).
12. Ask `Dock` to rebuild the passthrough polygon after the strip's minimum rect changes. New buttons must sit inside the polygon.
13. On `NOTIFICATION_WM_CLOSE_REQUEST`, `Session` already saves if phase 2 wired it. Confirm quit from `Dock` still reaches that notification. If quit bypasses it, call `Session.save_now()` before `quit()`.

## Files

| Path | Purpose |
| --- | --- |
| `res://scenes/hud/strip.tscn` | Phase host |
| `res://scripts/hud/strip.gd` | Binds `Session` to labels |
| `res://scripts/hud/draft_placeholder.gd` | Temporary draft, removed in phase 5 |
| `res://scripts/boot/main.gd` | Instances the strip instead of the phase 1 label |

The phase 1 settings button stays. Extend that panel; do not add a second window.

## Acceptance

With embedding off, and `time_scale` at 60 or higher in a debug run:

- Start, draft `pip` + `teapot`, and watch stage index and standings advance without waiting a real hour.
- Pause stops the countdown label. Resume continues from the remaining time, not from zero.
- Quit mid-reveal, relaunch, and the same stage and standings return.
- Set the clock forward outside the app (or temporarily pass a far `now` in a debug button that is compiled only into debug builds) and the recap lists every skipped stage before the live phase shows.
- Keyboard focus stays in a text editor while the buttons are clicked with the mouse.
- The idle strip still does not run an animation.
