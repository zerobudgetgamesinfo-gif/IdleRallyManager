# Phase 8 — Multiplayer later

## Goal

Write down the boundary a future async championship has to respect, and check that phases 2 and 5 did not cross it. This phase does not add a socket, a room code, Steam, or a second player.

Design: [GDD.md](../GDD.md) section 12.

## Non-goals

- A lobby, an account, a relay server, or NAT punch-through.
- Live input during a reveal.
- Rewriting the solo flow "to be ready". If solo play needs a seam, the seam is a function signature, not a network stub that pretends to connect.
- Choosing the host architecture. Both options below stay open until someone builds them.

## Dependencies

Phase 2 solver and save. Read phase 5's `choose_card` path before signing the seam off. Phases 6 and 7 are irrelevant to this boundary.

## The seam

A championship that can be shared is fully described by:

| Field | Owner |
| --- | --- |
| `seed` | Assigned when the draft locks. Same value on every client. |
| Ordered stage ids | The catalog order. Clients refuse to start if their catalog hash differs. |
| Slot list | Eight slots. Each slot is a driver id, a car id, and a human-or-AI flag. |
| Card ids | For each slot, the card chosen at the end of each service, including defaults. |

Given those fields, `StageSolver.solve` on any machine returns the same `StageResult`. Wall-clock time only seeks the local animation (GDD section 6.3). It is not part of the shared state.

Human input after the draft is one card id per service window. A choice that arrives after the window's end is ignored; the default safe card is already the shared value. Clients may show a local pick immediately, and they replace it if the host's locked card differs when the window closes.

AI slots use `pick_ai` from phase 2. The host (or the solo `Session`, which is the only host in v1) stores the picked id at the moment the service opens, so a client that was closed still resolves the same card.

## Architectures, undecided

Both can sit on the same payload. Do not encode either into `Championship`.

1. **Cloud host.** A small server stores the table above and the phase end timestamps. Clients catch up with the same loop as GDD section 3. The server is the clock. A client being closed does not pause the room.
2. **Steam networking host.** One player's machine stores the table. If the host's app is closed, the room pauses, unless a later design moves the clock to the cloud. Solo pause must not be the only clock implementation; `advance(now)` already takes `now` as an argument so a host timestamp can replace the local clock.

`Session.advance` stays the local caller. A future `ChampionshipHost` would feed it saved fields and a `now`. That type is not added in this phase.

## Tasks

1. Review `sim/stage_solver.gd` and `sim/session.gd`. Confirm the solver does not call `Time`, `Input`, `DisplayServer`, or `FileAccess`. Confirm `seed` is stored on the championship at draft confirm and is part of the save.
2. Review service resolution. Confirm AI card ids are stored when the offer is built, and a defaulted player card is stored as a normal card id plus `applied_by`, not as a missing field that each client would re-roll.
3. Add a catalog hash helper: a stable string hash of stage ids, weights, and base times, in catalog order. Print it from the headless check. Do not upload it anywhere. The point is to have one function a future lobby can compare.
4. If a review finds the solver reading the clock or the scene tree, move that read into `Session` and extend the headless checks. That fix is in scope. A transport layer is not.
5. Leave this file as the record of the review: append a dated note with the catalog-hash function name and any fix. Do not delete the constraints above.

## Acceptance

- No new autoload, port, or third-party SDK.
- The headless suite still passes, including a check that two `solve` calls with the same seed and entry match after a fresh process start (already required in phase 2).
- A reader can point at one function that hashes the catalog and one struct (the save's championship object) that holds seed, entries, and card ids.
