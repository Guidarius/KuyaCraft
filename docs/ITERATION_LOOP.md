# Autonomous improvement loop

Run one iteration of this document per loop firing, for example:

```
/loop Run one iteration of docs/ITERATION_LOOP.md
```

Each iteration picks **one** improvement, implements it, proves it, documents it and
commits it. The loop keeps its memory in `docs/ITERATION_LOG.md`, because conversation
context may be summarised between iterations. Read that log first, every time.

## What the project is

LoveRTS (repo KuyaCraft): a deterministic Warcraft 3-style RTS in LÖVE 11.5. 1v1 on
Twin Marches (192×192, unbuildable roads joining every gold mine to both bases, two
control points: own both for two minutes to win), two provisional factions, an
extractor-and-carrier gold economy, heroes with abilities, fog with line of sight, a bot,
replays and ENet lockstep multiplayer.

The user's direction, which every choice should serve:

- **Warcraft 3 feel.** Controls, feedback and readability should behave the way a
  Warcraft 3 or StarCraft player expects.
- **Reach goal: runs well on a Raspberry Pi 5.** Rank performance work by what a slow
  CPU/GPU pays for (per-tick allocations, draw calls, whole-map loops), but measure only
  on this Windows machine. Do not build Linux tooling.
- **The user makes the art, sound and music.** Never add placeholder art or audio. Leave
  hooks instead: events, cursor states, marker slots, named sound cues.
- **15–25 minute matches, with a way back into a lost game.**

## Hard rules

These come from `AGENTS.md` and from what has already gone wrong in this repo.

1. Authoritative gameplay lives in `src/sim` and never calls LÖVE, OS, filesystem, network
   or wall-clock APIs. Advance only through `Sim.step(world, commands)`.
2. Integer arithmetic, ticks, stable ids, explicit ordering. Never let `pairs` order decide
   gameplay.
3. Any change to simulation behaviour, world state or content is a **versioned break**: bump
   `Sim.VERSION` (with an entry in the comment history at the top of `src/sim/init.lua`)
   and/or `content.version`. New future-affecting state goes into
   `Sim.serializeAuthoritative` and must survive `Sim.snapshot`/`Sim.restore`.
4. **Never silently bless a changed result.** If a bot match, route timing or golden changes,
   explain why in STATUS.md and make it the intended consequence of the change, or revert.
   Never loosen a test threshold to get green; when a target legitimately moves (for
   example, the map was made larger on purpose), say so and show the new measurement.
5. Presentation reads simulation state and never changes it. Rendered tests assert
   `Sim.serializeCanonical` is unchanged across draws; keep that true.
6. Keep factions data-driven. Never mutate shared content at runtime.
7. Views are an explicit whitelist (`VIEW_FIELDS` in `src/sim/init.lua`). A player must never
   see another player's private state: orders, queues, XP, cooldowns, targets.
8. Commit every finished iteration on the working branch. Review the staged diff first.
   **Never push, merge, force-push, rewrite history or touch `master`.** Keep generated
   artifacts, logs and `assets/generated/` out of commits.
9. Report honestly. A test that was not run is "not run", not "passing". A single
   performance run is not evidence (see below).

## Facts about this machine and test suite

- Quick feedback: `scripts/test.ps1 -Suite quick -PerfBudget 40` (unit + simulation, about
  a minute).
- **Always pass `-PerfBudget 40`.** The default 10 ms budget is for a faster reference
  desktop.
- Performance is noisy here. p95 for identical code has ranged from 12 ms to 86 ms. Never
  judge a change from one run. Compare the parent commit and the change back to back,
  alternating, three times each, using a detached worktree of the parent
  (`git worktree add --detach <scratchpad>/baseline HEAD~1`; remove it afterwards). Report
  medians and the spread. Identical attack counts show that a change did not alter
  behaviour.
- `scripts/test.ps1 -Suite all` never exercises rendered code. After any change under
  `src/ui`, `src/app.lua`, `src/sprites.lua` or HUD code, run `scripts/test-ui.ps1` and
  `scripts/test-presentation.ps1` too. A new drawing path needs a rendered test that
  actually draws it: fixtures mostly use `open_fields`, which has no roads or control
  points.
- `ASSET ERROR Missing usable asset` lines are expected: `assets/generated/` is absent in
  this clone. Units render as magenta placeholder boxes. That is not a regression.
- Tests leak shared state. A failure in code you did not touch is often an earlier test's
  residue, so look for it before "fixing" the victim. `Sim.create`'s content copy exists for
  test isolation; do not remove it.
- Don't pipe test output through `Select-Object -First N`: it kills the test process and
  reports a false failure. Write output to a log in the scratchpad and search the log.
- Run suites one after another, never in parallel with a performance measurement.
- Stable test commands:
  - `-Suite quick`, `balance`, `determinism`, `network`, `scenario`, `crowd`, `soak`, `performance`
  - `scripts/test-ui.ps1`, `scripts/test-presentation.ps1`

### Verification by kind of change

| Change | Minimum verification |
|---|---|
| Docs only | none |
| UI or presentation only | quick, test-ui, test-presentation; inspect a captured screenshot |
| Bot (`src/bot.lua`) | quick, balance (bot matches change: report the new outcomes) |
| Simulation, content or map | quick, balance, determinism, network, scenario, crowd, soak, performance |
| Performance work | the above for its layer, plus an alternating 3×3 A/B against the parent |

## One iteration

1. **Orient.** Run `git status` and `git log --oneline -5`. Read `docs/ITERATION_LOG.md`
   (create it from the template below if it is missing) and the last section of
   `STATUS.md`. If the tree has uncommitted changes you did not make, stop and report
   them rather than building on top.
2. **Choose one item.** Take it from the backlog in the log, or add a better one you found.
   Prefer, in order:
   - fixing a bug or a failing check
   - making an existing mechanic actually work end to end
   - Warcraft 3 feel gaps
   - performance on the per-tick or per-frame path
   - test coverage for untested paths
   - new features

   The item should fit one iteration: roughly one focused commit. Split anything bigger
   and log the rest.
3. **Investigate before editing.** Read the code involved and find the existing idiom. Write
   down what the change will do and how you will know it worked, as a measurable acceptance
   check.
4. **Implement** in the style of the surrounding code: the same comment voice, density and
   naming.
5. **Verify** per the table above. Add a regression test for changed behaviour. If
   verification fails and the cause is not quickly clear, revert the iteration
   (`git restore`) and log what was learned instead of committing a half-fix.
6. **Document.** Add a short section to `STATUS.md`: what changed, what was measured (with
   numbers), what was verified, and what was *not* verified. Update the relevant doc under
   `docs/` if a rule or number changed.
7. **Commit** with a message that says why, ending with the attribution line.
8. **Log it.** Append the iteration to `docs/ITERATION_LOG.md` and include it in the commit.
9. **Continue or stop** (see below). When continuing a `/loop`, schedule the next firing
   soon (about 60–120 s). The work is the thing being waited on, not the clock.

## Decisions that belong to the user

Do **not** decide these alone. Record them under "Questions for the user" in the log with
the options and a recommendation, then pick a different item:

- Balance numbers that change feel: unit stats, costs, income, capture or hold times, match
  length targets.
- New mechanics, factions, units, abilities or win conditions.
- Map layout changes beyond fixing a defect.
- Anything needing art, audio or voice.
- Removing or replacing an existing feature.

Engineering, bot competence, performance, UX parity with Warcraft 3 conventions, test
coverage and documentation accuracy are fair game.

## Starting backlog

Ranked by value. The log's copy is authoritative once it exists; re-rank as you learn.

1. **Bots never take control points.** They only retake, so no bot match exercises the
   control win or the retake. Teach the bot to contest points when ahead or stalled, then
   check both matches still finish and report the outcome and win reason.
2. **Bots never raid carrier routes.** Raidable income was meant to be the comeback
   mechanism, and it is unmeasured. Give the bot a raid behaviour and report whether a
   losing side recovers more often.
3. **Minimap and world fog repaint** draws one rectangle per cell: 36,864 on the 192×192
   map, on every fog change. Replace it with ImageData and `replacePixels`, or an equivalent.
   Measure with the UI benchmark (`--map twin_marches`) before and after.
4. **Worst-tick spikes.** The 240-unit benchmark's maximum step is 100–270 ms. The known
   cause is per-command group-move claim scans. Make them incremental, prove identical
   attack counts, and A/B the result.
5. **Inspection coverage.** The card for a neutral camp creature and for an enemy building is
   drawn but never captured or asserted. Add rendered cases.
6. **Formation-preserving group moves.** This is the one unfinished phase of
   `docs/AUDIT_MOVEMENT_AND_ABILITIES.md`; a group's shape is discarded on move.
7. **Warcraft 3 feel gaps.** Audit `docs/UI_UX_ROADMAP.md` and `docs/CONTROL_MOVEMENT.md`
   against Warcraft 3 behaviour: queued waypoint display, the hover tooltip for enemy
   stats, building placement feedback on roads, and so on. Implement the highest-value
   gap.
8. **Control-point edge cases.** Test: a defeated holder, a four-player hold, a hold begun on
   the same tick the headquarters falls, and units dying inside the circle mid-capture.
9. **Sprite batching and draw calls**, the Pi's binding limit. This is blocked until
   generated assets exist in the clone; do not fake it with placeholder atlases.
10. **Adaptive lockstep.** The input delay is fixed at three ticks and stalls above
    ~140 ms round trip. Only a local-process proof is possible here, so say so.

Known design questions already raised, not to be decided by the loop:

- On the 192×192 map, the natural pays ~61% of a near mine without an outpost (it was 90%).
- The asymmetric bot match ends at ~13:20, short of the 15-minute floor.
- The capture defaults (10 s capture, ownership persists, workers count) are unconfirmed.

## Stopping

Stop the loop, and say why in the log and in chat, when any of these happens:

- Two iterations in a row fail verification and are reverted.
- The remaining backlog items all need a user decision, hardware you don't have, or art.
- The same subsystem has been changed three iterations running without a measurable gain.
- About ten iterations have been committed since the user last spoke. Stop, summarise, and
  wait for review.

To end a dynamic `/loop`, stop scheduling further firings.

## `docs/ITERATION_LOG.md` template

```markdown
# Iteration log

Branch: <branch>   Started from: <commit>

## Backlog
1. ...

## Questions for the user
- <question> — options: ... — recommendation: ...

## Iterations
### <n>. <title> — <commit hash or "reverted">
- Why: ...
- Change: ...
- Measured: ...
- Verified: ... / Not verified: ...
- Learned: ...
```
