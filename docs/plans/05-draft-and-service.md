# Phase 5 — Draft and service

## Goal

The choices in [GDD.md](../GDD.md) sections 5, 7, and 9.2 are real controls in the strip: a budget draft, three service cards, a default when the player is away, and a final table. Placeholder shapes are still fine.

## Non-goals

- New stats, extra stages, or career locks (phase 6).
- Illustrated mechanics and card art (phase 7).
- Changing solver math. If a card does something the solver cannot see, the card is wrong, not the solver.

## Dependencies

Phase 2 offer API and phase 3 strip. Phase 4 is not required to play the choices, but the service view should not fight the stage view: only one of them is instanced.

## Tasks

1. Delete `scripts/hud/draft_placeholder.gd` and its nodes. Replace with `scenes/draft/draft_view.tscn`.
   - Two columns, drivers and cars, built from `Catalog`. Each row shows name, cost, and the two highest stats.
   - A live total: spent, remaining, spare-parts reliability if confirmed now.
   - A one-line "good at" label: the two highest summed stats of the selected pair.
   - The stage 1 hint from GDD section 6.1 (Gravel Valley, grip).
   - Confirm calls `Session.confirm_draft`. Confirm stays disabled while the pair costs more than 10 or a column has no selection.
2. `scenes/service/service_view.tscn`.
   - Three cards in a row: label, delta, and a selected state.
   - Clicking a card calls `choose_card`. Clicking another card replaces the pick. The selected card shows a check. The safe card is labeled as the default if time runs out ("If you step away: this one").
   - Next-stage hint: surface and top stat.
   - Remaining time, mm:ss, from `Session`.
   - While no card is selected, pulse the card row's modulate over about two seconds (GDD section 9.2). Stop the tween once a card is selected or the phase ends. A selected-but-not-yet-expired window does not pulse.
3. Recap rows from phase 3 now use card labels and stage display names, not raw ids. Include `applied_by` so a default is visible ("Snow Lane: checked the pressures, you were away").
4. Finished view: full table, winner line, Dismiss, and Start again (idle, then the player starts a new draft themselves; do not auto-open the draft).
5. Abandon stays the two-click control from phase 3. Copy should say the championship will be cleared and the window setup will not.
6. Layout pass at 144 px and 220 px. Cards may be icon plus one word at compact height; cozy shows the full label. Both heights remain inside the passthrough polygon. Ask `Dock` to refresh after the view swap.
7. No new save fields. Picks, defaults, and owned card ids already round-trip in phase 2. Add a headless check only if a new rule appears (it should not).

## Files

| Path | Purpose |
| --- | --- |
| `res://scenes/draft/draft_view.tscn` | Budget draft |
| `res://scripts/draft/draft_view.gd` | Selection and confirm |
| `res://scenes/service/service_view.tscn` | Three cards |
| `res://scripts/service/service_view.gd` | Pick, hint, pulse |
| `res://scripts/hud/strip.gd` | Hosts the new views, drops the placeholder |

## Acceptance

- Every legal pair in the starter roster can be confirmed, and every illegal pair cannot.
- Unspent points on `pip` + `teapot` show `+6` reliability before confirm, and the standings entry has that reliability after confirm.
- During service, the pick can be changed, and the last pick is the one stored after the window closes.
- With no pick, catch-up or a sped-up clock applies the safe card and the recap says the player was away.
- Stage 8 ends on the final table and does not open a service.
- The pulse is absent during a reveal and absent after a card is selected.
- Mouse-only, no focus steal, both height presets.
