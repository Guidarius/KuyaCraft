---
name: loverts-conventions
description: Working rules for the LoveRTS game in the KuyaCraft repository — how its deterministic simulation, content, maps, bot, UI and tests are organised, which test suites a change needs, this machine's performance-measurement quirks, and how work is documented and committed. Use it whenever you change, test, measure, review or commit anything in this repo (src/sim, src/maps, src/bot.lua, src/ui, tests, scripts, STATUS.md), even a one-line edit, and whenever you plan work here. For general LÖVE, lockstep and Warcraft 3 / Brood War technique, also use the love2d-deterministic-rts skill.
---

# LoveRTS conventions

LoveRTS is a deterministic, Warcraft 3-inspired RTS in LÖVE 11.5 (LuaJIT). This skill is
the repo-specific layer: where things live, what must stay true, and how to prove a change.
General technique — LÖVE performance, lockstep design, Warcraft 3 and Brood War feel — is in
the personal `love2d-deterministic-rts` skill.

Read `AGENTS.md` first; it is short and it is the contract. `STATUS.md` records what has
been measured, and its last sections say what is currently open.

## Where things live

| Path | What it is |
|---|---|
| `src/sim/init.lua` | `Sim.create`, `Sim.step`, views, placement, serialization, `Sim.VERSION` and its history comment |
| `src/sim/*.lua` | movement, path (A* + string pulling), vision (shadowcasting), abilities, projectiles, carriers, control points, stats, fixed-point math |
| `src/content.lua` | factions, units, buildings, abilities and `rules`, with `version`; authored via `src/content_time.lua` (`T.ticks`, `T.cells`) |
| `src/content_validate.lua` | assertions every content change must satisfy |
| `src/maps/twin_marches.lua` | the default 192×192 map, authored for player one and rotated 180° |
| `src/bot.lua` | the bot; reads only a filtered view |
| `src/app.lua`, `src/ui/*` | presentation: drawing, HUD, input, selection, minimap, alerts |
| `tests/runner.lua` | test registration by suite; scenario files alongside |
| `docs/` | balance and pacing, resource flow, abilities, control and movement, command cards, the iteration loop |

## Invariants

These are what keep peers and replays in sync. Breaking one fails silently until a desync.

- `src/sim` never calls LÖVE, `os`, `io`, the network or wall-clock time. When unsure, run
  the personal skill's checker with this repo's runtime:
  `& (Get-LoveRuntime) "$env:USERPROFILE\.claude\skills\love2d-deterministic-rts\scripts\determinism-check" src/sim`
  after dot-sourcing `scripts/common.ps1`.
- The simulation advances only through `Sim.step(world, commands)`, and every player,
  bot, replay and peer goes through the same commands.
- Integers only, in 256 subunits per cell at 20 ticks per second. Iterate `w.order`, never
  `pairs(w.entities)`, whenever the order can affect an outcome.
- New future-affecting state belongs in `Sim.serializeAuthoritative` and must survive
  `Sim.snapshot` / `Sim.restore`. Derived state (`w.blocked`, lane caches) stays out and
  is proven recomputable by test.
- A view is an explicit whitelist (`VIEW_FIELDS`, `OWNER_FIELDS`). Adding a field to an
  entity does not expose it; decide deliberately what an enemy may see.
- Presentation never writes to the world. Rendered tests assert
  `Sim.serializeCanonical` is unchanged across draws.
- Content is shared and immutable at runtime.

## Versioned breaks

Any change to simulation behaviour or world state bumps `Sim.VERSION`, adding a line to the
version history at the top of `src/sim/init.lua`. Any content change bumps
`content.version`. Replays and snapshots from older versions are then rejected rather than
misreported as divergence. `src/build.lua` fingerprints `src/sim`, `src/maps` and the content
modules, so even a comment change there invalidates saved replays — expected, not a bug.

Never re-bless a changed result without saying why. When a bot match, route time or
golden changes, STATUS.md states the old and new numbers and the cause. Never loosen a
threshold to get green; if a target legitimately moves, say so and show the measurement.

## Which tests a change needs

Always pass `-PerfBudget 40` on this machine (the default 10 ms is for a faster desktop).

| Change | Run |
|---|---|
| Docs only | nothing |
| `src/ui`, `src/app.lua`, sprites, HUD | `scripts/test.ps1 -Suite quick -PerfBudget 40`, `scripts/test-ui.ps1`, `scripts/test-presentation.ps1`, and look at a capture |
| `src/bot.lua` | quick and `-Suite balance` (report the new match outcomes) |
| `src/sim`, content, maps | quick, then `balance`, `determinism`, `network`, `scenario`, `crowd`, `soak`, `performance` one after another |

- `-Suite all` and `-Suite quick` never execute rendered code. A new drawing path needs a
  rendered test that actually draws it. Most fixtures use `open_fields`, which has no
  roads or control points. `tests/presentation.lua` has a `capture(name, draw)` helper that
  writes `artifacts/ui-<name>-<width>.png`.
- `ASSET ERROR Missing usable asset` lines are expected: `assets/generated/` is absent
  until the user regenerates art. Units draw as magenta boxes.
- Tests share state. A failure in untouched code is often an earlier test's residue, so
  find the leak before patching the victim. `Sim.create` copies content for test isolation;
  keep it.
- Don't pipe test output through `Select-Object -First N`: it kills the process and
  reports a false failure. Redirect to a log file and search the log.
- Useful direct invocation for one test, where `$r` is `Get-LoveRuntime` from
  `scripts/common.ps1`:
  `& $r $ProjectRoot --test simulation --filter 'part of a test name'`.

## Measuring performance here

The development laptop is thermally limited, and identical code has measured anywhere from
12 to 86 ms p95. One run proves nothing:

1. Create a detached worktree of the parent commit in the scratchpad.
2. Alternate parent and change three times each on the same benchmark filter.
3. Report medians, the spread, and the attack/move counts. Identical counts are the proof
   that a change did not alter behaviour.
4. Remove the worktree.

Never run a measurement while another suite is running.

## The user's standing preferences

- Warcraft 3 and Brood War feel is the reference for controls and feedback.
- Running well on a Raspberry Pi 5 is the reach goal. Rank performance work by what a slow
  device pays, but validate only on Windows, and build no Linux tooling unless asked.
- The user makes all art, sound and music. Add hooks (events, cues, marker slots), never
  placeholder assets.
- Balance numbers, new mechanics, map layout and win conditions are the user's decisions.
  Propose them with a recommendation; state any defaults you had to choose.

## Documenting and committing

- Each finished piece of work adds a STATUS.md section: what changed, measured numbers, what
  was verified, and what was not. Update the doc under `docs/` whose rule or number changed.
- Commit by default when work is done, after reviewing the staged diff. Stage paths
  explicitly and keep `artifacts/`, `assets/generated/` and logs out.
- Work on a branch, never `master`. Never push, force-push or rewrite history unless the
  user asks.
- For long unattended improvement runs, follow `docs/ITERATION_LOOP.md`.
