# Phase 6 — Content and career

## Goal

The starter championship is worth playing, and the numbers in [GDD.md](../GDD.md) sections 5 through 7 either hold up or get tuned in data. Career unlocks start only after that loop is pleasant.

## Non-goals

- Replacing the solver with a new model. Tuning edits `.tres` weights, costs, and deltas. A formula change means updating GDD section 6.2 and the golden times in the headless check in the same change.
- Multiplayer.
- Final illustration (phase 7). Temperament can be a line of text before the portraits exist.

## Dependencies

Phases 4 and 5, so a human can watch a reveal and use the real draft. The headless checks from phase 2 still run after every data edit.

## Tasks

### Playtest the fixed catalog

1. Play one championship at `time_scale` 30 or higher, and one service window at `time_scale` 1 long enough to feel the half-hour choice. Write notes in `docs/playtests/` (one markdown file per session: draft chosen, who won, which choice felt fake, whether stage 8 still mattered). `docs/` stays under `.gdignore`.
2. Check the boring failures:
   - One pair wins from the draft with no card ever mattering.
   - Spare parts (`pip` + `teapot`) beats every specialist.
   - A stat capped at three upgrades makes the later services all look the same.
   - AI order never changes from seed to seed because every rival's cards are identical in effect. Some stability is good; a completely fixed podium is not.
3. Adjust costs, weights, or card deltas in `.tres` files. Re-run `godot --headless --path . -s res://sim/checks/run_checks.gd`. Update golden times when the solver inputs changed on purpose.
4. Add temperament lines on `DriverDef` (`temperament: String`) and show them on the standings rows. They do not enter `solve`.

### Add content only where the playtest ran out of choices

5. New cards are extra `CardDef` resources with new ids. Old ids stay. The "three raises and the general card leaves the pool" rule still applies.
6. Do not add a ninth stage in this phase unless the playtest notes say the workday is too short. If a stage is added, GDD section 6.1 and the points table's field size stay consistent (the field is still eight entries).

### Career, after the loop is fun

Start this half only when a playtest note says a full championship was enjoyable. Until then, stop at the tasks above.

7. `user://save.json` gains `"garage": { "reputation": 0, "unlocked_ids": [] }` at save version 2. Version 1 files migrate by adding an empty garage. Keep the backup rule from GDD section 14 for versions newer than the build.
8. Finishing a championship adds reputation equal to the player's points total (one number, no multipliers). Dismissing the final table commits it.
9. Unlock list, authored as data: two extra drivers and two extra cars, each with a reputation threshold. The starter roster in GDD section 5 stays unlocked at 0.
10. The draft hides locked rows and shows the threshold. AI pairs stay on the starter roster so a new unlock does not silently change the rival field.
11. Headless checks: a version-1 save migrates; reputation increases once per finish, not once per dismiss-and-reopen; a locked id cannot be drafted.

## Files

| Path | Purpose |
| --- | --- |
| `res://data/**/*.tres` | Tuning and any new cards |
| `docs/playtests/*.md` | Session notes, not imported by Godot |
| `res://data/driver_def.gd` | Optional `temperament` export |
| `res://sim/save_game.gd` | Version 2 migration, only if career starts |
| `res://scenes/draft/draft_view.tscn` | Locked rows, only if career starts |

## Acceptance

- The headless suite passes.
- A written playtest says who won and whether a service choice changed the next stage.
- If career shipped: a new profile starts with the original five drivers and four cars, a finished championship raises reputation once, and a save from before version 2 still loads.
