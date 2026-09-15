# Iteration log

Branch: `improve-mechanics` (worktree `KuyaCraft-improve`). Started from `97a9e84`.
Procedure: [ITERATION_LOOP.md](ITERATION_LOOP.md). Machine notes: no Python; `-PerfBudget 40`; timing is
noisy, so compare A/B, alternating, medians of three.

## Backlog

Ranked by value. Items marked *verified* were confirmed against the code during the skill evaluation
on 2026-09-14.

0. **Crowd liveness when a group starts together** (found in iteration 5). Chokepoint-100 and 50-vs-50
   counterflow deadlock at the gap as soon as units begin moving on the same tick: opposing units end
   up in each other's keep-right lane and nothing breaks the stand-off. This blocks both search
   speedups below.
   - **Group search.** One search per group removed a 600-tick wait for 12 units ordered around a
     wall.
   - **Budget accounting.** Stop charging the per-tick path budget for stale heap pops (~45% of it).

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
- **Control wins now decide bot matches early.**
  - Once bots take points (iteration 4), the mirror ends at 14:03 and the asymmetric match at 9:17,
    both by control and both below the 15-minute floor.
  - The asymmetric winner had the smaller army, so the hold works as a comeback, but it also shortens
    games.
  - Options: leave it; lengthen `holdTicks` (currently 2 minutes); require a minimum army or tech before
    a hold counts; or make the bot less eager (for example, only claim after the enemy base has survived
    an attack).
  - Recommendation: playtest before changing, since bot behaviour exaggerates it. If games feel too short,
    lengthen the hold to 3 minutes first.

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

### 2. A rooted or stunned ally is never shoved aside

**Why.** Two separate code readers, the knockback evaluations in both skill rounds, found it:
`yieldable()` in `src/sim/movement.lua` asked idle allies to step out of a passing unit's road
without checking `Stats.canMove`. So a rooted or stunned unit could be pushed around, even though its
own status holds it in place.

**Change.** `yieldable()` refuses any unit that cannot move. Simulation version 13.

**Measured.**
- All eight crowd arrival times are identical to before: open 318/321/393/445, chokepoints 340/460/1326,
  mixed 705, counterflow 849. Crowds without held units are unaffected.
- Bot matches changed, but because of iteration 4, which was in the same tree (see below).

**Verified.**
- The new crowd test ("a rooted or stunned ally is never shoved aside", for both root and stun) failed on
  the old code: a rooted ally was pushed at tick 31. It passes now.
- quick 74/74, crowd 16/16.
- determinism 5/5, plus 100,000-tick agreement across fresh processes at 30/60/144 FPS and default/tuned JIT.
- network 4/4, plus a real ENet pair.
- scenario 2/2, soak 1/1, balance 4/4.

These ran on a snapshot of the tree holding iterations 2–4 together.

### 4. Bots take control points, not only retake them

**Why.** No bot match had ever exercised the control win, and the bot's retake rule had never run in a
full match.

**Change.** `src/bot.lua` gets a claim target. With an army of at least six, an outpost and nothing to
defend, the army takes the nearest point the bot does not own. It comes after defending home, retaking,
expanding and clearing camps, and before marching on the enemy base. Once the bot owns every point it
moves on.

**Measured** (balance suite, one seed per matchup):

| Match | Before | After |
|---|---|---|
| Mirror | 17:33, headquarters win | **14:03, player 2 wins by control** |
| Asymmetric | 13:23, headquarters win | **9:17, player 1 wins by control** |

- In the mirror, first contact was 4:11 and both armies peaked near the food cap (71 and 74).
- In the asymmetric match, player 1 won with the *smaller* army (peak food 49 against 56) by holding
  both points.
- Both matches are now below the 15-minute pacing floor.

**Verified.**
- The new unit test failed on the old bot ("the bot did not send its army to the nearest control point
  it does not own") and passes now. It covers claiming, moving on to the second point, not parking on
  owned points, and retaking an enemy hold.
- quick 75/75, balance 4/4, with both replays re-verifying their final state.

**Not decided here.** Whether control wins should end matches this early. See Questions for the user.

### 5. Share one path search per group move — reverted

**Why.** Both responsiveness reviews suspected units stand still after an order while their A*
search runs. Measured with the new `S.firstSteps` scenario: workers ordered around a 56-cell wall
whose only gap is at the far end, under the fixture's 64-expansion budget.

| Group size | Ticks until every unit has a route (p95) |
|---:|---:|
| 1 | 53 |
| 12 | 607 |
| 24 | 1,201 |
| 48 | never, within 60 s |

A throwaway probe showed two separate causes:
- **Separate searches.** Each unit runs its own full search: one unit needed 1,835 expansions, and 12
  units needed 21,881.
- **Budget wasted on stale entries.** About 45% of the budget goes to popping stale heap entries that
  do no work.

**Change tried.**
- Group members starting within 6 cells of a groupmate already searching towards a slot within 6
  cells wait on that search.
- They then join its route where they can see it, with each segment checked for their own body and
  lane, and walk straight to their own slot.
- Leader death, a leader order change, a navigation change or an unsuitable route falls back to
  searching alone.

**Measured.**
- p95 dropped to 53 ticks for 12 and 24 units and 108 ticks for 48.
- One-directional chokepoints got faster: 100 units went from 1,326 to 1,229 ticks.

**Why it was reverted.**
- **50 versus 50 counterflow deadlocked** at the gap, with both sides holding the opposing lane. It
  had passed at 849 ticks.
- **Disabling sharing alone** restored exactly 849, so sharing was the cause.
- **Refusing shared routes through keep-right passages made things worse:** chokepoint 100 then
  deadlocked too. Followers waited for the leader and then all searched at once.

Per ITERATION_LOOP.md, a cause that isn't quickly clear gets reverted rather than committed as a
half-fix.

**Kept.** The measurement, as a reported (not asserted) crowd test, and a test that a group move
survives a snapshot and a unit dying mid-search.

**Learned.**
- Crowds at chokepoints and in counterflow currently resolve only because units start moving at
  staggered times. Each unit's search finishes when it finishes.
- Anything that makes groups start together exposes a local-steering deadlock: shared searches
  certainly, and probably also a faster path budget.
- **Crowd liveness under simultaneous starts has to be fixed first.** It is now backlog item 1, ahead
  of both search speedups.
