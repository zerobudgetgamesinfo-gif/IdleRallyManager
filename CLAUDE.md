# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

`AGENTS.md` is the authoritative engineering guide (style, layout, autoload table, overlay rules, version control). Read it first; this file only adds commands and the big picture. Design lives in `docs/GDD.md`; `docs/plans/00-roadmap.md` says which phase is in scope.

## Commands

Godot 4.7, GDScript only. There is no build or lint step.

```
# All headless checks (also spawns the UI runner in a child process)
godot --headless --path . -s res://sim/checks/run_checks.gd

# UI/scene checks alone (a -s script has no autoloads, so this is a scene)
godot --headless --path . res://sim/checks/ui_runner.tscn
```

There is no per-test filter: `run_checks.gd` calls each `_check_*` function from `_init()`. To run one, temporarily comment out the others. A new `sim/` rule needs a `_check_*` there.

The overlay must be tested with the editor's Game view "Embed Game on Next Play" unchecked; an embedded run hides window bugs.

## Architecture

- **Two autoloads only**: `Dock` (`scripts/dock/dock.gd`: window flags, screen edge, hit polygon, `user://window.cfg`) and `Session` (`sim/session.gd`: championship state, clock, `user://save.json`). Neither draws; rules never go in `Dock`, presentation never in `Session`.
- **`sim/` is pure rules**: `RefCounted`/`Resource` classes, no `Node` subclasses (`Session` is the exception). `Championship` holds the state machine and phases, `StageSolver` produces the timeline, `RevealPlayback` replays it, `Standings`/`Garage`/`ServiceOffer`/`SaveGame` cover the rest. Solvers never read the system clock; `Session` passes `now_unix` into `advance`, `confirm_draft`, `resume`. RNG is a `RandomNumberGenerator` seeded from the championship seed, drawn in the order the GDD specifies. `run_checks.gd` has golden finish times, so changing draw order or solver math will break them.
- **Data**: catalogs (drivers, cars, stages, cards) are typed `Resource` classes in `data/` saved as `.tres`, aggregated by `data/catalog.tres`. Saves store stable snake_case ids, never resource paths. Never write to `res://` at runtime.
- **UI**: `scenes/boot/main.tscn` is the permanent entry point (never `change_scene_to_file`). `scripts/boot/main.gd` is the window chrome and hosts the current phase view, which it switches by connecting `Session` signals (`phase_changed`, `choice_applied`, `recap_ready`, `championship_finished`). Phase views are `scenes/hud/strip.tscn`, `draft`, `service`, `stage`, with scripts under `scripts/<feature>/`. Signals go up, calls go down; use `%UniqueName` nodes.
- **Companion window**: borderless, always on top, no keyboard focus, click-through outside the strip. All of that stays in `Dock` (feature scenes never call `DisplayServer`). Height uses preset names (`compact`, `cozy`) persisted in `window.cfg`; focus heights per phase are temporary. No always-running animation or `TIME` shaders on a visible canvas item.
- **Untracked/ignored**: `.godot/` is ignored; commit `.uid` files. `docs/` has `.gdignore`. Leave `project.godot` to the editor unless a phase plan lists the keys.

## Agent skills

### Issue tracker

Issues and specs live in GitHub Issues (`gh` CLI). See `docs/agents/issue-tracker.md`.

### Domain docs

Single-context: one `GLOSSARY.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.
