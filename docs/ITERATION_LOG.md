# Iteration log

Branch: `improve-mechanics` (worktree `KuyaCraft-improve`). Started from `97a9e84`.
Procedure: [ITERATION_LOOP.md](ITERATION_LOOP.md). Machine notes: no Python; `-PerfBudget 40`; timing is
noisy, so compare A/B, alternating, medians of three.

## Backlog

Ranked by value. Items marked *verified* were confirmed against the code during the skill evaluation
on 2026-09-14.

0. **Crowd liveness** — fixed in iteration 8 (squeeze, push, detour searches; simulation version 14).
   - **Now unblocked:** the two search speedups that deadlocked crowds in iteration 5.
     - **Group search.** One search per group removed a 600-tick wait for 12 units ordered around a
       wall.
     - **Budget accounting.** Stop charging the per-tick path budget for stale heap pops (~45% of it).
     - Retry either against both crowd-lab scenario sets, not only the crowd suite.
   - **Still open:** two enemies meeting head-on in the wrong lane of a two-cell gap never give way,
     because enemies never squeeze. The 65% floor leaves enough room that no lab case jams on it, but a
     70% floor does.

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
- **Bot strategy around control points** (found in iteration 8).
  - The bot goes for the unowned point nearest its headquarters, so its army can walk off a capture
    seconds from done. That now decides both balance matches by 7:17.
  - Fixing only that (finish a capture under way, else the point nearest the army) produces
    stalemates: both bots answer every hold, never attack a base, and hit the 25-minute cap even at
    35 units against 14.
  - Options: (a) keep the fix and add a base attack when clearly ahead (e.g. twice the enemy's
    visible army); (b) keep the fix and let only one of claim or retake preempt a base attack;
    (c) leave the bot as it is.
  - Recommendation: (a). It is the smallest rule that makes bot matches finish for a reason a player
    would recognise. Decide together with control-win pacing, since both change match length.
- **Crowd deadlock at chokepoints** — decided 2026-09-15: "a bit" of allied overlap plus gentle pushing
  between allies. Implemented in iteration 8. Still to confirm in play: whether a 65% floor looks right
  on screen (`G.PRESS` in `src/sim/geometry.lua`; 70% overlaps less but jams the largest counterflows).
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

### 8. Crowd lock-ups: squeeze, push and detour searches — kept (user-directed, newest)

**Why.** The user decided backlog item 0: "a bit" of allied overlap and gentle pushing between
allies, iterated on.

**Tooling** (scratchpad, not committed): `crowd-lab` runs 14 crowd cases twice each, with the
fixture's staggered searches and with every route ready on tick 1. It reports arrival, deadlock,
closest allied distance, squeezed unit-ticks, direction reversals and walked/direct distance. A
second set of 12 perturbed cases (sizes, widths, offsets, mixed-size counterflow) was used only to
check tunings, never to choose them. `crowd-dump` explains a stall unit by unit.

**Iterations inside the iteration.**
1. **Squeeze past any moving ally after 6 ticks, 60% floor, push 12.** The tick-1 counterflow
   arrived (never before), but staggered counterflow deadlocked and crowds slowed ~20%. The push
   ignored lanes and shoved units into enemy traffic, and units squeezed into idle allies at their
   destination.
2. **Lanes for pushes, squeeze only past moving allies, sweep of 18 settings.** Push is essential
   (without it 26–36% of unit-ticks stay squeezed). A 70% floor deadlocks counterflows. The best
   setting on set 1 still failed 1–2 unseen cases in set 2.
3. **Dump:** the jam was allies squeezing *into* the queue ahead until the whole queue sat at the
   floor. **Fix:** squeeze only past an ally not heading the same way.
4. **Dump of the last stubborn case** (mixed-size 50v50): 84 of 95 stuck units had *no path*. Every
   congested unit restarted its detour search every 20 ticks with its path emptied, so none of ~85
   searches sharing a 64-expansion budget ever finished. The same happened with squeeze and push
   switched off: an old bug, not caused by this work. **Fix:** leave a running search alone and keep
   walking the old path.
5. **Result:** only squeeze after 10 ticks / 65% / push 8 passed all 52 cases. Chosen.
6. **Cost:** operation counts in the 240-unit benchmark showed +48% spacing checks and +59% distance
   checks from the push pass. Rewritten for the miss (box test first, radii from content, status
   check only on overlap), the overhead fell to ~2%, with identical attacks and movement.

**Bot side effect, investigated and not fixed.** Both balance matches now end at 7:16–7:17 by
control (were 14:03 and 9:17). The bot picks the unowned point nearest its headquarters, so an army
109/200 into a capture walked off to cross the map, and the hold ran out. The fix (finish a capture
under way, else go to the point nearest the army; unit test proven to fail on the old bot) made both
matches run to the 25-minute cap: 23 holds started, all 23 broken, and at 23:28 player 1 had 35
units to 14 without ever attacking a base, because both bots always go for points first. Reverted:
it needs a strategy decision (when a bot should attack a base rather than a point), which belongs
with the control-pacing question.

**Learned.**
- Crowd outcomes are chaotic in the tuning numbers: neighbouring settings differ by whole deadlocks.
  Choose on one scenario set and confirm on another, or the choice is luck.
- A stall's cause is rarely the one guessed. Twice the dump showed a different mechanism, the second
  time in pathfinding rather than steering.
- Wall-clock A/B on this laptop could not separate a 50% cost from noise, and the sampling profiler
  ran for over ten minutes and was stopped. Wrapped call counts, with identical behaviour counts, gave a
  stable answer in one run each.

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

### 3. Fog repaint: one texture, incremental writes

**Why.** The minimap cache is also the world's fog layer. Every tick, `fogSignature` walked every
visible and every explored key. On almost every tick anything moved, the cache cleared a canvas and
drew one rectangle per unseen cell: 36,864 on Twin Marches.

**Change.**
- Fog is one pixel per cell in an `ImageData`, uploaded to one `Image` with `replacePixels`.
- Each tick touches only cells visible now or visible last tick, and uploads only if something changed.
- A change of map or perspective rebuilds it once, detected by the identity of the player's reused
  `visible` table. A view is rebuilt every tick, so comparing views would rebuild every tick.
- The `fog` field keeps its name, so world and minimap drawing are unchanged.

**Measured.** UI benchmark on Twin Marches at 1920×1080, three alternating runs of `8a24190` against
the change:

| Measure | Before | After | Median change |
|---|---|---|---|
| Minimap cache p95 | 10.7 / 13.5 / 13.3 ms | 0.21 / 0.24 / 0.32 ms | about 55× faster |
| Frame cadence p95 | 115 / 500 / 459 ms | 39 / 49 / 108 ms | |
| Draw submission p95 | 10.9 / 12.1 / 13.1 ms | 9.8 / 10.6 / 11.1 ms | |

**Verified.**
- **New rendered test:** every fog pixel must match the visible and explored sets at start, after 40
  ticks, with the hero sent far out and back, and after switching to player two and back.
- **Test strength:** the first version passed against a deliberately broken update, because no cell
  left sight in its 40 ticks. The hero round trip was added, and the strengthened test then failed the
  broken code ("fog pixel 21,6 has alpha 0, expected 0.6"). With the break reverted it passes.
- **Suites:** `scripts/test-ui.ps1` and `scripts/test-presentation.ps1` exit 0; quick 75/75.

**Also measured (the combined tree for iterations 2–4).** The control benchmark, alternating `8a24190`
against `332776d`:
- p95: 13.6 / 16.8 / 14.8 against 19.0 / 32.8 / 13.1 ms.
- p50: 5.1 / 3.8 / 5.4 against 6.1 / 5.0 / 6.0 ms.
- Attacks were identical (28,972) in all six runs, and every run was under the 40 ms gate.
- The single 126.5 ms failure in the heavy-suite run happened while other suites ran on the same
  machine.
- The medians are slightly higher after, within this machine's spread. A small real cost from the extra
  `canMove` check is possible and unproven.

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

## Loop stopped — 2026-09-15

After iteration 7 the loop stopped for lack of progress, per ITERATION_LOOP.md:
- Of the last three iterations, one was reverted (5), one stopped at a design question (6), and one
  added coverage without finding a defect (7).
- Every remaining high-value item needs a user decision or hardware this machine lacks:
  - **Crowd overlap** at chokepoints. This also gates both path-search speedups.
  - **Control-win pacing.**
  - **Peer-to-peer input and per-match input delay.** Needs the user and two PCs.
  - **Natural expansion income.**
  - **Sprite batching.** Needs generated art.
- The rest are low value or can't be measured reliably on this machine:
  - more inspection coverage
  - formations (large)
  - worst-tick spikes (this laptop's timing noise spans 12–86 ms for identical code)
  - carrier raids (change pacing on top of the open control-win question)

Committed and kept:
- 1: order acknowledgement
- 2: held units never shoved aside
- 3: fog repaint, about 55× cheaper
- 4: bots take control points
- 7: control edge-case coverage

### 7. Control-point edge cases — coverage, no defect found

**Why.** Control wins were new, and nothing tested the ways a wrong player could win.

**Change.** Tests only, five new simulation scenarios:
- a holder that loses its headquarters loses, and its hold counts for nothing
- a hold completing on the tick its owner's headquarters falls is not a control win
- a capture fades at half rate when its only capturing unit dies
- a third player holding every point wins by control
- a defeated player's surviving unit does not contest a capture

**Verified.**
- All pass; the simulation suite is 64/64.
- **Deliberate breaks:** counting dead units in the circle fails the capturer test (progress rose to 120
  instead of fading), and counting a defeated player's units fails the contest test (owner stayed 0).
  `control.lua` was restored with `git restore` and confirmed clean.

**Learned.**
- The defeated-holder and same-tick cases are each guarded twice: the headquarters check runs first, and
  `Control.step` refuses a defeated holder. No single break fails either test, so they guard the pair
  rather than either check alone.
- The rules already handled every case, so no code changed.

### 6. Diagnose the counterflow deadlock — stopped at a design question

**Why.** Backlog item 0 blocks every search speedup.

**Done.**
- A probe gives every unit its route on tick 1 and runs 50-vs-50 counterflow. It never finishes; 38
  units stay stuck.
- A second probe dumps each stalled front unit's straight step and which check rejects it:
  - terrain, midpoint terrain, lane cell and lane body clearance: all pass
  - the only blocker is an **allied** body at the compressed allied separation (120)
- On each side, two moving allies form a cross in which each one's next step passes through the other.
  Yielding only moves idle allies, so the cross never resolves.
- A unit rerouting at the gap mouth also briefly has no path and plugs the entrance.

**Not changed.** The obvious fix, bounded allied overlap for long-blocked movers, changes how crowds
look in chokepoints, which is the user's call ("crowd feel" is a human gate in STATUS.md). It is
recorded under Questions for the user with a recommendation.

**Learned.**
- Crowd liveness here depends on units never starting together.
- The allied-separation compression that makes crowds feel tight is also what lets them lock.

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
