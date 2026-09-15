# Iteration log

Branch: `improve-mechanics` (worktree `KuyaCraft-improve`). Started from `97a9e84`.
Procedure: [ITERATION_LOOP.md](ITERATION_LOOP.md). Machine notes: no Python; `-PerfBudget 40`; timing is
noisy, so compare A/B, alternating, medians of three.

## Backlog

Ranked by value. Items marked *verified* were confirmed against the code during the skill evaluation
on 2026-09-14.

1. **Order acknowledgement parity** (UI, *verified*).
   - A second "accepted" tone plays when an order executes, so the input delay is audible
     (`src/ui/command_feedback.lua`).
   - Stop, Hold and stance from hotkeys or the command card get only a generic click, with no
     acknowledgement flash or cue (`src/ui/actions.lua`).
   - Warcraft 3 answers once, on the click.
2. **Stunned or rooted idle units can be shoved aside** by allied yielding (sim bug, *verified* by two
   independent readers): `yieldable()` in `src/sim/movement.lua` never asks whether the unit can move.
3. **Fog and minimap repaint** draws one rectangle per cell: 36,864 on 192×192 whenever fog changes.
   Replace with ImageData and `replacePixels`, with incremental writes. Measure with the UI benchmark on
   Twin Marches.
4. **Bots never take control points**, so no bot match exercises the control win or the retake.
5. **Bots never raid carrier routes**, so the comeback mechanism is unmeasured.
6. **First-step delay after an order.**
   - A unit whose straight-line probe fails waits for A*, and all searches share 256 expansions per
     tick. That is worse on 192×192.
   - Give new orders priority over reroutes, and measure click to first movement.
7. **Worst-tick spikes**: group-move claim scans, max step 100–270 ms.
8. **Inspection coverage**: rendered cases for neutral camp creatures and enemy buildings.
9. **Control-point edge cases**: a defeated holder, deaths inside the circle mid-capture, the
   headquarters falling on the same tick a hold completes.
10. **Formation-preserving group moves.**
11. **Network latency** (needs the user, and two PCs to validate):
    - Remove the host echo round trip, i.e. peer-to-peer input exchange.
    - Per-match input delay chosen from ping.

## Questions for the user

- **Input delay and netcode:** replacing "host finalizes ordered batches" with peer-to-peer input
  exchange contradicts ROADMAP.md.
  - Options: keep host-finalized, or exchange peer to peer.
  - Recommendation: peer to peer, after measuring stalls.
- **Natural expansion income:** on 192×192 the natural pays ~61% of a near mine without an outpost
  (it was 90%).
  - Options: leave it, move the natural closer, or change carrier numbers.
  - Recommendation: playtest first.
- **Capture-point defaults are unconfirmed:** 10 s capture, ownership persists, workers count.

## Iterations

### 1. Acknowledge every order once, on the click

**Why.** Two separate code readings during the skill evaluation found the same two faults:
- A second "accepted" tone played when an order executed, so multiplayer players could hear
  the ~200 ms input delay.
- Stop, Hold and stance from the command card, their hotkeys or the HUD played only a generic
  UI click, with no unit flash or acknowledgement.

Warcraft 3 answers every order once, on the click.

**Change.**
- `Actions.order` issues an order and acknowledges it exactly like a right-click, through
  `Input.acknowledge`. Stop, Hold, stance and the HUD stance button all use it, and
  `Actions.activate` skips the generic click for acknowledged actions.
- `command_feedback.resolve` no longer plays anything for accepted orders. Rejections and
  learned upgrades keep their cues.

**Measured.** Nothing to time: this is presentation only, with no simulation or content change.

**Verified.**
- The extended command-card test failed against the old code ("Stop was not acknowledged like a
  right-click order") and passes now.
- quick 74/74.
- `scripts/test-ui.ps1` and `scripts/test-presentation.ps1` both exit 0.

**Not verified.** No listening review: all cues are still synthesized placeholders.

**Learned.** The `accepted` event still drives the pending-order bookkeeping. Only its sound was
the problem.
