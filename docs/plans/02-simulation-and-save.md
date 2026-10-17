# Phase 2 — Simulation and save

## Goal

A championship can be created, solved, advanced on a wall clock, caught up after a gap, and written to `user://save.json`, with no scene tree involved. Design: [GDD.md](../GDD.md) sections 3 through 8, 12, 13, and 14.

## Non-goals

- Any `Control` other than what phase 1 already shows. This phase does not add a HUD.
- Scrolling presentation (phase 4).
- The draft screen and the card buttons (phase 5). `Session` still exposes `choose_card` and `confirm_draft` so those screens have an API.
- Career unlocks and network code.
- GUT or GdUnit. One headless script is enough until the suite outgrows it.

## Dependencies

[AGENTS.md](../../AGENTS.md). Phase 1 is not required to run the checks. Do not call `Dock` from `sim/`.

The solver must stay a pure function of catalog, entry build, stage, and seed (GDD section 12). It must not read the system clock.

## Tasks

1. Resource types, typed `@export` fields, `class_name` on each:
   - `DriverDef`: id, display_name, cost, five stats.
   - `CarDef`: same shape.
   - `StageDef`: id, display_name, surface, five weights, `base_time_sec`, and four beats (`t_norm`, kind, stat name).
   - `CardDef`: id, label, stat deltas, `safe` flag.
   - `Catalog`: arrays of those resources, plus the ordered stage id list and the seven AI pairs from GDD section 5.
2. Author `.tres` files for every row in GDD sections 5, 6.1, and 7. One `data/catalog.tres` references them. Stats live in the resources, not in GDScript literals, so phase 6 tunes data.
3. `sim/entry.gd` (`class_name Entry`, `RefCounted`). Built by copying driver and car stats. Methods: `stat_block()`, `apply_card(card)`, `apply_spare_parts(unspent)`. Never mutate a `DriverDef` or `CarDef`.
4. `sim/stage_solver.gd`. `solve(entry, stage, seed) -> StageResult`. Implement GDD section 6.2 in that random-number order: four incident rolls, then three sector jitters. `StageResult` is a `RefCounted` with `finish_time`, `sector_times`, and incidents `{t_norm, kind, penalty}`.
5. `sim/standings.gd`. Sort a stage's results by `finish_time` ascending, then entry id ascending. Award points from GDD section 4. Championship order is points descending, total time ascending, entry id ascending.
6. `sim/service_offer.gd`.
   - Build three cards for an entry: exactly one safe card, matching the next stage's highest weight (GDD section 7).
   - Fill two general cards from the pool with the deterministic draw `hash(championship_seed, stage_index, "service")`.
   - Drop a general card once that entry has raised the same stat three times.
   - `pick_ai(offer, next_stage) -> card_id`: highest dot product of delta with next-stage weights, tie breaks to the lowest card id.
7. `sim/championship.gd` (`RefCounted`) holds seed, phase, stage index, entries, open offers, committed results, and recap. Phases: `idle`, `draft`, `stage_reveal`, `service`, `recap`, `finished`.
   - `start_draft()` from idle.
   - `confirm_draft(driver_id, car_id, now_unix)` validates the budget (GDD section 5), rejects a pair over 10, applies spare parts, builds the seven AI entries, stores a random `seed` (`randi()`, not the clock), solves stage 0, enters `stage_reveal`. Checks that lock golden times pass an explicit seed into the championship instead of calling the random path.
   - Solving happens at reveal start and is stored on the championship. Catch-up must not solve the same stage again.
8. `sim/session.gd` autoload `Session`. It extends `Node` because an autoload has to. It owns one `Championship` and the settings `{time_scale, muted}`, instances no canvases, and emits `phase_changed`, `choice_applied`, `recap_ready`, and `championship_finished`. Every other file in `sim/` extends `RefCounted`.
   - `advance(now_unix)` applies GDD section 3: scale elapsed by `time_scale`, honor pause, clamp a backward step, loop phase boundaries until `now` falls inside the open phase.
   - Leaving a service with no player choice applies the safe card (`applied_by: "default"`) and appends a recap row. AI cards resolve here too, from the offers stored when the service opened.
   - Stage 8's reveal ends in `finished` (no service).
   - If catch-up crossed a boundary, enter `recap` instead of the live phase, and resume that phase when `dismiss_recap()` runs.
   - `choose_card(card_id)` is legal only in `service`, only for an offered id, and may be replaced until the window ends.
   - `pause()` / `resume(now_unix)` use `pause_started_unix` as in GDD section 14.
   - `abandon()` returns to idle and drops the championship object. Settings remain.
9. `sim/save_game.gd` reads and writes `user://save.json` (GDD section 14).
   - Save on phase change, card choice, pause, resume, draft confirm, abandon, and from a method `Session.save_now()` that phase 1's quit path can call once `Session` exists. In this phase, call it from the check script; wire the window notification in phase 3 if the autoload order makes `Dock` able to call `Session.save_now()` without a cycle. Prefer `Session` connecting to `SceneTree` `NOTIFICATION_WM_CLOSE_REQUEST` itself so `Dock` stays free of save knowledge.
   - Unknown newer `version`: do not overwrite; `Session.load_error` explains it.
   - Older version with no migrator: copy to `user://save.backup.json`, then idle.
10. `sim/timing.gd` holds `STAGE_REVEAL_SEC` and `SERVICE_SEC` only.
11. Debug `time_scale` defaults to `1`. The check script may set it. No slider until phase 3, and that slider is `OS.is_debug_build()` only.

## Files

| Path | Purpose |
| --- | --- |
| `res://data/driver_def.gd`, `car_def.gd`, `stage_def.gd`, `card_def.gd`, `catalog.gd` | Resource types |
| `res://data/**/*.tres` | GDD tables |
| `res://data/catalog.tres` | Single preload for `Session` |
| `res://sim/entry.gd`, `stage_solver.gd`, `standings.gd`, `service_offer.gd`, `championship.gd`, `timing.gd`, `save_game.gd` | Rules |
| `res://sim/session.gd` | Autoload `Session` |
| `res://sim/checks/run_checks.gd` | `extends SceneTree`, headless entry |

Register the autoload in [project.godot](../../project.godot). The row in [AGENTS.md](../../AGENTS.md) already names `res://sim/session.gd`.

## Acceptance

Run:

```
godot --headless --path . -s res://sim/checks/run_checks.gd
```

The process exits `0` only if every check passes. Checks:

- Every stage's weights sum to 1 (tolerance `0.001`), and there are eight stages and eight field slots after a legal draft.
- `pip` + `teapot` (cost 4) gains `+6` reliability. `miso` + `dart` (cost 12) is rejected and does not start a championship.
- `solve` twice with the same arguments returns equal times, sectors, and incidents. A second championship with the same seed and the same draft replays those times.
- After the first solve, mutating the entry's stats does not change the stored `StageResult`.
- The first service offer contains exactly one `safe` card, and it matches stage 2's top stat (pace, Coastal Tarmac).
- The AI picker agrees with an independently computed dot product on that offer.
- A service window whose `phase_started_unix` is far in the past resolves the safe card onto the player, records `applied_by: "default"`, and does not leave the phase clock behind `now`.
- While paused, `advance` does not cross a boundary. After resume, the remaining duration is intact.
- A `now` earlier than `phase_started_unix` does not change stage index.
- Save, then load into a fresh `Session` logic path (new `SaveGame` read): seed, phase, stats, and owned card ids match.
- A file with `"version": 99` is left byte-for-byte unmodified.

Golden `finish_time` values: run the solver once during implementation, paste the eight player times for seed `1` and the `pip` + `teapot` draft into the check, and fail the check if they drift. That locks GDD section 6.2 against accidental edits.
