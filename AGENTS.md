# Working on Idle Rally Manager

Godot 4.7, GDScript only. Read [GDD.md](docs/GDD.md) for design and [docs/plans/00-roadmap.md](docs/plans/00-roadmap.md) for which phase is in scope. This file is the engineering practice. When the engine already explains a practice, follow the linked page and apply the local rule under it.

## Version

- Target Godot 4.7. Do not add C#, GDExtension, or another engine.
- Use Godot 4 APIs. Godot 3 patterns (`yield`, `export var` without `@export`, `onready var` without `@onready`, `KinematicBody2D`, `move_and_slide` with a velocity argument) do not belong in this repo. Migration reference: [Upgrading to Godot 4](https://docs.godotengine.org/en/4.7/tutorials/migrating/upgrading_to_godot_4.html).

## Style

Follow the [GDScript style guide](https://docs.godotengine.org/en/4.7/tutorials/scripting/gdscript/gdscript_styleguide.html).

- Tabs for indentation. UTF-8, as in [.editorconfig](.editorconfig).
- `snake_case` for files, folders, functions, and variables. `PascalCase` for `class_name`, node names, and signals' types. `CONSTANT_CASE` for constants. Enum names are singular `PascalCase`; members are `CONSTANT_CASE`, one per line.
- Code order is the order in the style guide: metadata, docstring, signals, enums, constants, exports, variables, `@onready`, then methods.
- Static typing on new scripts: parameters, returns, and node references. Infer with `:=` when the right-hand side is obvious.
- Signal names are past-tense verbs (`phase_changed`, `card_chosen`).
- Prefix methods that only the class should call with `_`.

## Project layout

Follow [Project organization](https://docs.godotengine.org/en/4.7/tutorials/best_practices/project_organization.html).

```
res://
  scenes/boot/main.tscn       # main scene
  scenes/<feature>/           # one folder per feature scene
  scripts/dock/               # window and strip chrome
  scripts/hud/                # championship strip and phase blocks
  scripts/draft/              # budget draft view
  scripts/service/            # service park cards
  scripts/stage/              # reveal scroll; freed outside stage_reveal
  sim/                        # RefCounted rules, no Node subclass
  data/                       # .tres catalogs
  audio/                      # reveal loop and incident stinger; bus layout is res://default_bus_layout.tres
  ui/                         # Theme (app_theme.gd), Palette, Style helpers, fonts; reused across phases
  addons/                     # third-party code only
docs/                         # design and plans; .gdignore so Godot does not import them
```

- Source art sits beside the scene that uses it in `scenes/<feature>/art/`. Portraits live under `scenes/draft/art/` and are referenced from `DriverDef` and `CarDef`.
- Keep a scene's script next to unusual one-off scenes; put shared gameplay rules in `sim/` and shared window code in `scripts/dock/`.
- `snake_case` file names. Node names in `PascalCase`.
- Do not load files from `docs/`. The folder contains an empty `.gdignore`.

## Scenes

Follow [Scene organization](https://docs.godotengine.org/en/4.7/tutorials/best_practices/scene_organization.html) and [When to use scenes versus scripts](https://docs.godotengine.org/en/4.7/tutorials/best_practices/scenes_versus_scripts.html).

- A scene owns its children. It does not reach into a sibling scene with a hard `NodePath`.
- Signals travel up. Parents call down. The main scene connects `Session` signals to the visible phase scene.
- Prefer `%UniqueName` (scene unique names) over string paths passed to `get_node`.
- Set properties on a node before `add_child` when the setter would otherwise touch the tree. See [Logic preferences](https://docs.godotengine.org/en/4.7/tutorials/best_practices/logic_preferences.html).
- `preload` a scene constant when the path is fixed. `load` when the resource is optional or swapped at runtime.
- Keep `main.tscn` as the entry point: a root that hosts the current phase view. Do not `change_scene_to_file` away from it. The overlay window is the root window; swapping the main scene drops window setup.

## Data

Catalogs (drivers, cars, stages, cards) are custom `Resource` classes saved as `.tres` under `data/`. Follow [Resources](https://docs.godotengine.org/en/4.7/tutorials/scripting/resources.html).

- Give each resource `class_name` and typed `@export` fields.
- Ids are stable `snake_case` strings. Saves store ids, not resource paths, so a moved `.tres` does not break a file in `user://`.
- Do not put design data in autoload dictionaries.
- Runtime championship state is plain data owned by `Session`, serialized to `user://save.json`.
- Window placement and window settings go to `user://window.cfg` via `ConfigFile`: screen, edge, height preset, always-on-top, content scale choice, `exclude_from_capture`, `seen_intro`.
- Never write into `res://` at runtime.

[Data preferences](https://docs.godotengine.org/en/4.7/tutorials/best_practices/data_preferences.html) is still marked work-in-progress for 4.7. Use it as background. The local rule above wins where they differ: sim data is a `Resource` or a `RefCounted`, not a `Node`.

## Autoloads

Read [Autoloads versus regular nodes](https://docs.godotengine.org/en/4.7/tutorials/best_practices/autoloads_versus_regular_nodes.html) before adding one. The allowed set is:

| Autoload | Script | Responsibility |
| --- | --- | --- |
| `Dock` | `res://scripts/dock/dock.gd` | Window flags, screen edge, hit polygon, `user://window.cfg` |
| `Session` | `res://sim/session.gd` | Championship state, clock, `user://save.json`. No drawing. |

Add a row here in the same change that registers the autoload. Do not put presentation nodes inside `Session`. Do not put championship rules inside `Dock`.

Helper libraries that do not need a scene tree are `class_name` scripts with static functions, not autoloads.

## Companion window

Follow the overlay section of [Creating applications](https://docs.godotengine.org/en/4.7/tutorials/ui/creating_applications.html) and the per-platform notes on [Window](https://docs.godotengine.org/en/4.7/classes/class_window.html).

- Flags, passthrough, and docking stay inside `Dock`. Feature scenes do not call `DisplayServer` directly.
- The game must not take keyboard focus. Controls in the strip are mouse-operable.
- Test overlays with the editor's game embedding off (Game view, "Embed Game on Next Play" unchecked). An embedded run hides the bug.
- The idle strip does not animate forever. No shader that reads `TIME` on a visible canvas item. Low-processor mode only helps when the frame has nothing to redraw.
- Scale the strip with the window content scale. See [Multiple resolutions](https://docs.godotengine.org/en/4.7/tutorials/rendering/multiple_resolutions.html). Store preset names (`compact`, `cozy`), not a raw pixel height. `Dock` may temporarily use focus height (draft, service, recap, finished) from `Session.phase()`; that height is not persisted in `window.cfg`.

## Simulation

- Solvers take data in and return data. They do not read `Time.get_unix_time_from_system()` themselves. `Session` passes the clock in.
- Random draws use `RandomNumberGenerator` seeded from the championship seed, and they consume numbers in the order [GDD.md](docs/GDD.md) specifies.
- A new rule ships with a check under `res://sim/checks/` that runs with `godot --headless --path . -s res://sim/checks/run_checks.gd`. The running overlay is not the only test. `run_checks.gd` also starts `res://sim/checks/ui_runner.tscn` in a child process, because a `-s` script has no autoloads; run that scene alone with `godot --headless --path . res://sim/checks/ui_runner.tscn` when working on scenes.

## Version control

Follow [Version control systems](https://docs.godotengine.org/en/4.7/tutorials/best_practices/version_control_systems.html).

- Commit script, scene, resource, and `.uid` files. Godot 4.4+ writes a `.uid` beside many resources; those ids are how scenes find them.
- Do not commit `.godot/` or the import cache. The repo `.gitignore` already excludes `.godot/`.
- Leave `project.godot` to the editor unless the phase plan lists the keys to change.
- Do not commit `user://` files, exports, or credentials.

## Checks before handing work back

- The phase's acceptance list in `docs/plans/` is done, or the gap is written down.
- New `sim/` behavior has a headless check.
- An overlay change was run outside the embedded game view.
- No new autoload, folder, or save field exists without a line in this file or in the GDD save section.
