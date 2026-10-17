# Phase 4 — Stage presentation

## Goal

During `stage_reveal`, the strip scrolls a side view of the stage. The picture is a playback of the result phase 2 already stored. Design: [GDD.md](../GDD.md) sections 6.3 and 10.

## Non-goals

- Final animal illustration, parallax paintings, and audio stingers (phase 7). Use flat shapes and labels.
- Physics bodies, `CharacterBody2D`, paths with collision, or a camera that the player drives.
- Changing a result because of what the animation did.
- Animating the service park beyond a static placeholder. Phase 5 owns that layout; this phase only leaves a still `ColorRect` behind the service HUD.

## Dependencies

Phase 3 strip host and `Session` reveal timing. The view reads the stored `StageResult` and the reveal fraction. It does not call `StageSolver`.

## Tasks

1. `scenes/stage/stage_view.tscn`, instanced by the strip only while the phase is `stage_reveal`. Free it when the phase changes so its process stops.
2. Layers, back to front, all `Node2D` or `ColorRect` children of one root:
   - Sky and ground, wider than the strip, shifted by `f * layer_speed`.
   - A road line.
   - One player marker.
   - Up to seven rival ticks. If 144 px compact height clips them, hide rival sprites and keep the position number from phase 3. Cozy height shows ticks.
3. `f` is the reveal fraction from `Session` (`elapsed / STAGE_REVEAL_SEC`, clamped 0 to 1). Set positions in `_process` from `f`. Do not integrate velocity, and do not store gameplay state on the nodes.
4. Gap interpolation (GDD section 6.3). Map `f` through the three sector times so a penalty in sector 2 shows up as that sector plays. At `f = 1` the on-screen order matches the solved order. Add a headless check that samples `f` at `0`, `0.5`, and `1` for a fixed result and asserts the final order. The check can live next to the presentation helper if the helper is a `RefCounted` (`sim/reveal_playback.gd`) with no nodes. Keep the math out of the scene script.
5. Incidents. When `f` crosses an incident `t_norm`, play a one-shot pose on the player marker (offset or rotation for a few seconds of wall time, scaled by `time_scale`). The pose ends by returning to the cruise transform. Use an `AnimationPlayer` that is not set to loop, or a tween that is created at the crossing and then freed. Do not leave a repeating tween alive for the whole half hour.
6. Redraw budget.
   - While the stage view is in the tree, set `OS.low_processor_usage_mode_sleep_usec` to `33333` (about 30 fps).
   - When the view leaves the tree, restore `100000`.
   - No shader uniform reads `TIME`. No particle node. No animated texture.
   - The ground scroll is the thing that invalidates the frame. That is expected during a reveal and not during service or idle.
7. Surface tint. A single `Color` per surface (gravel, tarmac, snow) on the ground rect, from the stage id. Phase 7 replaces the rect with art; the mapping can stay.
8. The phase 3 HUD line stays on top of the view, inside the passthrough polygon. Rebuild the polygon if the view adds controls. The road itself does not need to be a click target.

## Files

| Path | Purpose |
| --- | --- |
| `res://sim/reveal_playback.gd` | Pure `f` to positions and order |
| `res://sim/checks/run_checks.gd` | Extend with playback samples |
| `res://scenes/stage/stage_view.tscn` | Placeholder scroll |
| `res://scripts/stage/stage_view.gd` | Applies playback, one-shot incidents, fps cap |
| `res://scripts/hud/strip.gd` | Instances the view during reveal |

## Acceptance

- For a fixed save, scrubbing `time_scale` shows the player marker cross each incident once, at that beat's `t_norm` (log the crossing; do not require frame-perfect art).
- At the end of the reveal the position label matches `standings` for that stage.
- After the phase becomes `service`, Debug > Debug Canvas Item Redraws stays quiet except while the settings panel or the phase 5 pulse is moving. The stage view is not in the tree.
- Headless checks from phase 2 still pass, including the new playback samples.
- Compact and cozy presets both keep the HUD line inside the window.
