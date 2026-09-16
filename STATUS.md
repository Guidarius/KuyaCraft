# Implementation status



This repository contains the accepted roadmap and a playable **prototype**, not a completed release. Milestones have explicit validation limits below.



## Delivered



- Project-local, checksum-pinned LÖVE 11.5 Windows x64 runtime and repeatable setup.

- Git initialization, Lua editor configuration, development rules, launch/test/replay scripts.

- Pure Lua authoritative simulation: 20 Hz ticks, integer positions and quantities, Park–Miller PRNG, stable IDs and ordering, bounded incremental A*, radius-aware local movement, snapshots, canonical encoding.

- One resource. Gold mines, extractors, carrier delivery, construction, recruitment, refunds, population limits. Workers build and nothing harvests; see the resource revision below.

- Combat, passive/toggle hero kits, mutually exclusive upgrades, revival, neutral camp behavior, fog, headquarters victory/draw.

- Two provisional factions, a simple visibility-limited bot, river-pass and open-fields maps.

- Selection, persistent attack-move, Hold (H), queued group destinations, build previews, control groups, camera, minimap, replay saving/playback, movement-lab map and F3 order inspector.

- ENet host/client sessions, completed input frames, three-tick lookahead, version/content/map/authoritative-source checks, periodic hashes, same-tick desync snapshots and comparison.

- Blender 5.1 saved-source pipeline: original stump-handed Bastion recipes, full source skeleton retained, sampled derived actions, eight directions, aligned color/team masks, versioned metadata, validated cache and atomic catalog publication. See tools/blender/README.md.

- Windows package script with pinned runtime and dependencies.



## Verified on this machine



Current control/movement revision: simulation version **3**. Full regression command: `scripts/test.ps1`; rendered regression: `scripts/test-presentation.ps1`.

- **60 tests passed, zero failed**, covering the existing simulation/content/network/asset suites plus order idempotence, attack cancellation, target retention, body clearance, crowd arrivals, congestion snapshots, command scheduling and long-running movement.
- Four fresh LÖVE processes each simulated **100,000 ticks**. SHA-256 checkpoints match every 100 ticks across 30/60/144 FPS schedules with the tuned JIT cache and a further 60 FPS process with default cache settings. This is checkpoint sampling, not an every-tick proof.
- Real ENet host and client in separate processes match at every 100-tick checkpoint through **600 ticks**, including Move, Hold and hero-toggle commands.
- A mirror bot match finished at tick **1928**; an asymmetric match finished at tick **1797**. Both complete recorded matches replay with matching checkpoints.
- The rendered suite passed scale, input capture, minimap drag, coordinate transforms, pause, commands, upgrades, recruitment and replay seeking, plus Hold and F3 drawing. Match and settings captures were visually inspected; the Hold label was shortened to fit the 720p action card.
- Scheduled input checks at 30/60/144 FPS execute offline commands after **one simulation tick** (50-67 ms sampled acknowledgement) and lockstep-stub commands after **four ticks** (200-233 ms), preserving backlog. These are local scheduling measurements, not internet latency estimates.
- Open arrivals with 1/10/50/100 units completed at ticks **348/419/658/932**. Chokepoints with 5/20/100 units completed at **407/1015/1640**; mixed-size 20-unit arrivals at **1900**; 50-versus-50 counterflow at **4079**. Body/terrain clearance, destination tolerance and search budgets passed throughout. Hold blockers, death in a choke, reversal and movement-lab obstacles passed.
- A seeded 100-unit, **10,000-tick** command soak passed; retained Lua heap at ticks 5,000/10,000 was **5,058/5,335 KiB**.

The active authoritative benchmark maintained **240 live units for 10,000 ticks**, with **29,352 attacks** and **5,796 moving ticks** for the lead unit. Sim.step measured **4.197 ms p50 / 6.711 ms p95 / 121.046 ms maximum**. Retained Lua heap at warmup/midpoint/end was **5,459/4,484/4,366 KiB**. It meets the 10 ms p95 gate on this machine; the maximum spike remains a performance limitation. This includes command application, navigation, local movement, visibility and combat, and excludes rendering, bots, transport and replay encoding.

The separate 240-unit, four-player idle visibility/acquisition fixture measured **3.159 ms p95 / 4.500 ms maximum** over 300 ticks. Neither measurement certifies stable 60 FPS or performance on other hardware.

A separate rendered 1080p battle started with 240 units and ran **600 ticks / 30.033 seconds / 1,621 frames**, observing 2,233 attacks. Sim.step measured **19.778 ms p95 / 46.407 ms maximum**, draw submission **15.042 ms p95**, and frame cadence **43.173 ms p95** (about **54 average FPS**). Maximum pre-step backlog was 0.290 seconds; no dt was discarded. This includes actual sprites, fog, minimap, effects and audio, excludes bots/network/replay recording, and does not replenish losses. It is a different, shorter workload than the warmed headless acceptance test; the rendered simulation p95 exceeds 10 ms and stable 60 FPS remains unmet. Peak effects were 43/256 and source slots 5/32; sampled Lua heap grew from 1,853 to 17,101 KiB without forced collection, so it is not retained-memory evidence.

Implementation and test rules: [docs/CONTROL_MOVEMENT.md](docs/CONTROL_MOVEMENT.md). Current evidence: `artifacts/control-full-test.log`, `control-performance.txt`, `control-presentation.log`, `control-render-benchmark.log`, `ui-benchmark.txt`, and `ui-battle.png`. Earlier package and asset measurements below are historical evidence for those deliveries; this control revision has not been packaged or tested on another PC.

Reference hardware: AMD Ryzen 5 5600G, NVIDIA GeForce RTX 3060, approximately 23.84 GiB OS-reported RAM. Rendered proof resolution: 1280×800. Runtime: LÖVE 11.5 Windows x64. Blender: 5.1.0.



## Performance revision — 2026-09-09

Simulation version **5**. This revision changes what periodic checkpoints hash and is a
deliberate, versioned break: replays recorded before it are rejected by `Replay.read`
rather than reported as divergence. No golden result was re-blessed; the bot match
outcomes below are unchanged from before the work.

**Measured on a different machine from the reference hardware above.** This clone was
developed on an Intel Core i5-6300U (2 cores / 4 threads, 2.4 GHz nominal, observed
running at ~0.8 GHz under sustained load) with 7.88 GiB RAM and integrated graphics —
roughly 3–4x slower than the Ryzen 5 5600G / RTX 3060 the earlier figures were taken on.
Absolute milliseconds below are therefore **not** comparable with the older sections;
only the before/after pairs, measured back to back on this machine, are meaningful.
Run-to-run spread on this thermally limited laptop is large (22–35 ms p95 for identical
code), so single-run differences under about 30% are not evidence of anything.

Rendered 1080p battle, 240 units, 600 ticks, sprites/fog/minimap/effects/audio enabled:

| Measure | Before | After |
|---|---|---|
| Frame cadence p95 | 72.52 ms | 33.95 ms |
| Frames delivered in 30 s | 1,199 | 1,509 |
| Draw submission p95 | 14.35 ms | 10.27 ms |
| Sampled Lua heap growth per 30 s | +3.5 MiB | +0.75 MiB |

The rendered benchmark now times each stage of the tick separately, because timing only
`Sim.step` hid most of the cost. After this revision: `step` 25.3 ms p95, `Sim.view`
5.5 ms, observation 0.4 ms, events 0.1 ms, feedback 0.3 ms, replay recording 0.04 ms p95
(50 ms on checkpoint ticks), minimap fog cache 0.6 ms. Draw calls are 483 p95 at 240
units, which is the next rendering limit and is not yet addressed.

Headless authoritative benchmarks on this machine: the 240-unit 10,000-tick control
benchmark measured **35.0 ms p95 / 516 ms maximum** with 29,352 attacks and 5,796 lead
moving ticks; the 128x112 240-unit balance benchmark measured **23.6 ms p95 / 107 ms
maximum** (previously 24.4 ms p95 / **217 ms** maximum on the same machine). Attack and
movement counts are identical before and after, which is the evidence that the changes
are behaviour-preserving. Neither meets the 10 ms p95 target on this hardware; the gate
is now a parameter (`scripts/test.ps1 -PerfBudget`) rather than a constant, and was run
at 40 ms here. It remains 10 ms by default for the reference desktop.

Verified after this revision: **81 tests passed, zero failed**; 100,000 ticks agree at
100-tick checkpoints across four fresh processes (30/60/144 FPS schedules plus default
JIT cache); real ENet host and client agree at every 100-tick checkpoint through 600
ticks; mirror and asymmetric bot matches finished at **660.85 s** and **634.55 s**,
identical to before the work.

### Simulation step work

A line profile chose the targets rather than intuition. `visibility()` was the largest
single cost in the step at roughly 22% of samples, because it rebuilt its row tables
every tick and prefix-summed the **entire map width** for every covered row: about
14,000 iterations per player per tick on a 128x112 map regardless of how little was
visible. It now tracks which rows are covered and the span of each. Per-phase p50 inside
`Sim.step`, measured with `--profile-sim phases` before and after on this machine:

| Phase | before | after |
|---|---|---|
| movement | 4.74 ms | 3.18 ms |
| combatOrders | 2.09 ms | 1.59 ms |
| visibility | 1.90 ms | 1.04 ms |
| combat | 0.38 ms | 0.33 ms |
| economy | 0.11 ms | 0.06 ms |
| finishOrders | 0.05 ms | 0.04 ms |
| **total** | **9.28 ms** | **6.24 ms** |

Also: the local-movement spatial index is built once per tick instead of twice; `nearest()`
walks ring perimeters instead of whole squares (it was cubic in the radius for a quadratic
number of candidates); and group-move command application no longer allocates a claims
table per command and a closure per entity. The remaining worst tick in a match is still a
240-unit group move, because each unit's destination search must not see its own
reservations and the reservation set changes as earlier commands in the same tick are
applied; making that incremental is the next available win and is not done.

### Presentation and game feel

Viewport culling and a hoisted depth comparator were added to the draw path. **Sprite
batching was not done and could not be**: `assets/generated/` is absent in this clone, so
every unit renders through the procedural placeholder path and there are no atlases to
batch, no masks to convert and nothing to measure. That work needs the Blender export to
be run first, and the 483 draw calls per frame reported above are placeholder geometry,
not the shipping sprite renderer.

WC3-style control and feedback added, all presentation-only and all covered by a new
`PASS gamefeel` rendered test: floating resource/rejection text, hit flash and screen
shake, runtime-generated cursor states, hover and ally/enemy ring colours, control-group
badges, an Alt-to-reveal health-bar policy, per-unit selection tiles with individual
health, an idle-worker counter and cycling hotkey, select-all-army, eased camera
centring, camera bookmarks, follow-hero, hero XP bar and level, production progress,
a unit stat card, an F4 performance overlay, an F10 generated hotkey list, a
victory/defeat banner with match statistics, and offline game speed. Game speed scales
only the wall-clock feed to the fixed 20 Hz accumulator, so replays and checkpoints are
identical at every speed and network play is pinned to 1x.

Three harness defects were fixed to get there. `scripts/test-network.ps1` always failed on
this machine because Windows PowerShell 5.1 returns `$null` from `Process.ExitCode`
unless the handle is cached first, so `$null -ne 0` failed the check even when both
peers reported success. The two p95 performance gates were hard-coded to 10 ms. And the
frame-delta clamp introduced here changed the documented backlog contract, which
`scripts/test.ps1` cannot catch at all: `tests/control_input.lua` only runs under
`--ui-test`. That test now asserts the new contract, but the coverage gap is real —
**`scripts/test.ps1` does not exercise any rendered code**, so `scripts/test-ui.ps1`
has to be run alongside it after presentation changes.

## Orders revision — simulation version 6

Rally points, patrol, follow, formation pacing, authoritative kill/loss tallies and a
`delivered` event carrying the exact amount and resource. This is a deliberate,
versioned break: replays recorded under version 5 are rejected by `Replay.read` rather
than misreported as divergence. Six regression scenarios were added
(`tests/order_scenarios.lua`), including one that drives all three new orders through a
recorded replay and re-verifies every checkpoint.

Formation pacing caps every member of a group move to the slowest member's speed while
that order stands. It is `rules.formationPacing` in content, on by default, and it
produced an unexpected second effect: in the 20-unit mixed-speed chokepoint fixture,
arrival improved from **1,900 to 868 ticks**. Capping the group stops fast units racing
ahead and jamming the choke against their own slower allies, so the whole group flows
through in order. Uniform-speed crowds are unaffected, as the cap is then a no-op:
open arrivals with 1/10/50/100 units remain **348/419/658/932**, chokepoints with
5/20/100 remain **407/1015/1640**, and 50-versus-50 counterflow remains **4079**.

Kills and losses are now counted by the simulation on both the player and the killing
entity. The interface previously inferred them from the events it happened to observe,
which under-reports a kill made outside your own sight.

The bot now groups each wave of attack-move orders under the tick that issued them, so
its armies travel at the pace of their slowest member and arrive together instead of
trickling into the enemy. Retreats are deliberately left ungrouped. Both matches keep the
same winner and take slightly longer: the mirror moved from **660.85 s to 701.95 s** and
the asymmetric from **634.55 s to 632.45 s**. A ~7% longer mirror is consistent with
cohesive arrivals producing decisive engagements rather than a stream of individual
deaths, but two matches on one seed is an observation, not a measurement of bot strength.

## Sight revision — line of sight

Sight is now blocked by terrain, buildings and forests. The implementation is recursive
shadowcasting over eight octants, with slopes held as integer numerator/denominator pairs
and compared by cross-multiplication rather than as floats, so it is exact on any
platform and keeps the guarantees the rest of the simulation relies on. A blocking cell
is itself visible: you see the wall, not past it.

Buildings now look out from the middle of their footprint instead of a corner. Without
that a building is blinded by its own body, because its sight originates inside a blocked
rectangle.

Five scenarios cover it (`tests/vision_scenarios.lua`), including one that proves line of
sight and the radial rule produce a **cell-for-cell identical field on open ground** —
that is what establishes the new rule as a restriction of the old behaviour rather than a
differently shaped field.

Cost, measured back to back in one session: radial visibility p50 **2.40 ms**, line of
sight **14.58 ms** uncached and **5.41 ms** with a per-observer field cache, in the
240-unit benchmark. Radial shares work between overlapping observers through a prefix
sum and line of sight cannot, because each field depends on its own origin; the cache
recovers half of that by replaying an observer's recorded field whenever neither its cell
nor the obstruction set has changed, which is every tick for a building and most ticks for
an idle economy. `rules.lineOfSight=false` returns to radial.

Both bot matches are almost unaffected, because the bots fight in the open: the mirror
moved from 701.95 s to **701.6 s** and the asymmetric is unchanged at **632.45 s**.

## Resource revision — simulation version 8

The worker economy is gone. Gold mines are inert; an **extractor** built on a mine's
footprint emits **carriers**, which walk a cached route to the nearest friendly drop-off,
deliver a fixed payload and are recycled. Nothing harvests, and **lumber is removed
entirely** — every lumber price was folded into gold one for one, so relative prices are
unchanged. The design and the arithmetic are in
[docs/RESOURCE_FLOW.md](docs/RESOURCE_FLOW.md); this is what was built and what it
measured.

This is a deliberate, versioned break. `Sim.VERSION` moved 7 → 8, content 3 → 4, and
replays and snapshots from earlier versions are rejected by `Replay.read` rather than
misreported as divergence. The goldens under `artifacts/` were regenerated on this change.
No golden was silently blessed.

Deleted: `src/sim/harvesting.lua` in full, including its bounded nearest-reachable
delivery and tree searches and forest succession; the lumber depot; and the state
`cargo`, `cargoType`, `harvestRemaining`, `economySearch`, `economyRetry`,
`dropoffVersion`, mine `slots` and `nextExtractTick`. The `harvest` command no longer
exists. Rallying a production building onto a mine is now simply a walk to it; rallying
onto one of your own units follows it.

Carriers are their own entity category, not units: not selectable, not in the collision
bins, no crowd resolution, no food, no orders, no vision. They pass through units and
through each other and collide only with terrain, with a lateral offset derived from the
carrier's id so a route reads as a stream rather than single file. They are ordinary
combat targets, and a carrier that dies destroys its gold rather than handing it over. One
cached A\* route per extractor is shared by every carrier it emits; no carrier ever calls
the pathfinder.

Two entity-count properties matter and were designed for rather than discovered: the
in-flight cap bounds carriers at nine per extractor whatever the route length, and
delivered carriers are recycled rather than accumulating as corpses, so `w.order` stays
bounded across a twenty-minute match that emits thousands of deliveries. Forests became
plain blocked terrain instead of nodes, which removes about **180 entities per match** on
Twin Marches that every per-entity loop in the step was paying for.

Measured, by two new scenarios in `tests/balance.lua` that build a real extractor and
count real deliveries rather than evaluating the formula:

| Case | Income |
|---|---:|
| Near mine | 600 gold/minute |
| Far mine | 344 gold/minute |
| Far mine with an outpost beside it | 600 gold/minute |

Distance costs income and an outpost buys it back in full, which is what the design asked
for.

One placement rule was relaxed to make this work: an extractor's footprint is exactly its
mine's, so seeing the mine is now sufficient, where every other building still needs every
footprint cell visible and walkable. Without that, mines set against forest — the home mine
on Twin Marches is one — could hide a cell of their own footprint and be unbuildable for no
reason a player could see.

The bot's economy was rewritten. It was "assign five workers per mine, establish a depot";
it is now "keep four to six workers, put an extractor on every visible gold mine within
reach of a drop-off, and expand earlier because an outpost is now worth building for what
it does to income". Its expansion trigger moved from 6:00 to 4:00.

Pacing, from `artifacts/balance-pacing-mirror.txt`: first extractor at **0:30**, war hall
1:01, outpost **5:44**, first contact **4:20**, match end **9:33**, with the winner holding
two extractors to the loser's one and four to five carriers on the road at the end. Only
two figures from the harvesting report survive for comparison — contact at 4:32 and a
roughly eleven-minute match — so contact is essentially unchanged and the match is somewhat
shorter. **The comeback mechanism the design hoped for did not appear.** The bot does not
raid carrier routes, so a losing bot still has no way back, and 15–25 minute pacing remains
unmet. Whether raidable income helps is a question for a bot that hunts carriers, or for a
playtest; it is not answered here.

Verification: full `scripts/test-all.ps1` green — **85 passed, 0 failed** headless,
100,000-tick determinism across 30/60/144 FPS schedules and default/tuned JIT caches, real
ENet host/client agreement, rendered suites at 1280×720, 1920×1080 and 2560×1080, and the
asset presentation suite. The `worker_loaded` asset recipe is now the carrier rather than a
worker carrying cargo, which is the same art doing the same job.

The perf gates were run with `-PerfBudget 45` because **this machine cannot hold a stable
number**. Three back-to-back runs of an identical tree produced p95 of **13.773, 13.013 and
19.038 ms**, and a later run of the same tree produced **45.668 ms**. The 10 ms budget is
not meaningful here; see the machine note under "Performance revision" above. Only
back-to-back A/B ratios taken in one sitting should be trusted from this hardware.

## Milestone gates



| Milestone | Current state | Remaining acceptance work |

|---|---|---|

| 0: Toolchain | Implemented and locally verified | Fresh setup on another Windows PC |

| 1: Kernel | Implemented; long-run and snapshot checks pass | Cross-PC evidence; broader randomized scenarios and durable gameplay fixtures |

| 2: Movement/network proof | Radius-aware movement, opposing crowds, obstacles and local processes pass | Human local-avoidance review; jitter/loss session soak tests |

| 3: Mirror match | Bot-to-bot complete match and replay verified | Human playtest; match pacing and economic tuning |

| 4: Match loop | Implemented core rules and controls | More camp/leash, fog-edge, upgrade-interaction, blocked-exit scenarios |

| 5: Art pipeline | Five source-rig-derived assets, 1,168 poses, v2 catalog, viewer, cached builds and local render checks pass | Human continuous-motion/style review; subpixel gait/contact refinement; cross-PC rendering comparison |

| 6: Second faction | Shared systems and contrasting provisional kits work | Demonstrate interesting, balanced human matchups |

| 7: Private alpha | Local two-process protocol and standalone packaging verified | Repeated full matches between two physical Windows PCs over LAN/direct-IP |

| 8: Expansion | 4-player simulation fixture and second map exist | Interactive 4-player networking, stronger bots, tail-latency optimization, roster expansion |



## Known prototype limitations



- Bot games finish in roughly 10–12 simulated minutes against a 15–25 minute target, but the duration is the symptom rather than the problem. `artifacts/balance-pacing-*.txt` shows both matches are **decided** at around five minutes: the loser peaks within a minute of first contact and declines monotonically for the remaining seven, while the winner grows to the food cap. Nearly half of each match is a foregone conclusion. Lengthening the match by making headquarters or units tougher would extend the one-sided phase rather than fix it; what is missing is a way back into a lost engagement. This wants playtesting to decide, not tuning to a duration number. The bot also has no retreat-and-regroup behaviour, no multi-front pressure and no difficulty setting.

- Unit collision uses soft allied compression, hard enemy/terrain clearance, persistent destination slots and bounded local steering/rerouting. The finite crowd fixtures pass; universal liveness and polished continuous-motion behavior are not proven. Terrain-unreachable slots can still fail explicitly.

- Combat now has integer windup, impact and recovery, cancellation semantics and phase-driven animation. Projectile travel remains outside the simulation.

- Passive mechanics are focused Lua implementations, not a generalized ability framework.

- Fog uses line-of-sight: terrain, buildings and forests block sight rather than being seen through. Implemented as recursive shadowcasting with integer rational slopes, so it carries the same determinism guarantees as the rest of the simulation. `rules.lineOfSight=false` restores the cheaper radial visibility, which shares work between overlapping observers and costs about 2.25x less with a large army. Filtered observation memory supplies last-seen enemy-building/resource/camp minimap markers.

- Native multiplayer is 1v1. The simulation accepts four players; interactive 4-player matches are not yet exposed.

- Desync reports identify the first **observed checkpoint**, preserve each peer's local state and replay, and allow subsystem-path comparison. Automatic exchange of both states and exact first-divergent-tick bisection are not implemented.

- Network tests cover in-process reordered/duplicate/delayed batches and real local reliable ENet. They do not constitute a long unreliable-network soak or public-service hardening.

- The v2 catalog maps shieldguards, unloaded/loaded workers, crossbows, and Warden to Blender sprites. Other faction units and buildings retain procedural presentation. Nonverbal synthesized sound, positional effects and volume settings are enabled. All five assets are published and validated.

- Generated atlases and editable recipe output are ignored by Git. Obtain the pinned local source library and run export-assets.ps1 after cloning to regenerate them; see tools/blender/README.md.

- Source updates can invalidate replays because compatibility includes the exact authoritative source fingerprint.

- Periodic replay/network checkpoints hash authoritative state only (`Sim.serializeAuthoritative`). Content, map, `w.blocked`, the lane cache and per-player `explored` are excluded as fixed, derived or render-only; a regression test recomputes `w.blocked` across construction and destruction and asserts it matches. `Sim.serializeCanonical` still encodes the whole world and is what the equivalence assertions and desync dumps use.

- Simulation views are an explicit field whitelist rather than a copy of the entity with private fields deleted afterwards, so a newly added private field is unobservable by default. Views share the immutable map and the player's live visibility tables by reference and must be treated as read-only.

- No public lobbies, NAT traversal, accounts, reconnect, host migration, ranked play, or persistent player saves.

- The Windows package is a fused `LoveRTS.exe` plus its runtime DLLs, verified only by launching it and running the unit suite against the packaged archive on this machine. It has not been run on a second PC, is unsigned (SmartScreen will warn on first run), and ships with procedural placeholder art unless `assets/generated` was present at packaging time.



## Next engineering work



1. Run the same package on a second Windows PC; compare full-match hashes and record hardware/network conditions.

2. Playtest the mirror matchup and tune toward the intended match duration.

3. Playtest the movement-lab map, opposing chokepoints and final-slot tolerance; tune movement quality from observed cases.

4. Review attack animation contact, audio mix and command latency with human players.

5. Extend content validation and ability-combination tests as faction rules grow.

6. Decide what a losing position should feel like, then give it a mechanism: the pacing report shows matches are decided at five minutes and take eleven to finish. Cheaper rebuilding, base defences that hold ground, or expansion income that rewards a pushed-back player are the candidates; each changes feel, so each needs a playtest rather than a number.
7. Reduce active-battle maximum-step spikes and rendered frame hitches; extend session/network soaks before increasing content scope. `Sim.step` is now about 90% of the rendered tick path, so the remaining work is inside it: per-command group-move claim scans, the square-scan `nearest`, whole-map visibility flushes, O(N^2) target acquisition and the brute-force firing-position search.
7. Batch sprite drawing and cull to the viewport. The rendered battle submits 483 draw calls per frame at 240 units with no `SpriteBatch`, `Mesh` or `Text` objects anywhere, which is the binding limit on a draw-call-bound GPU.



## Earlier asset pipeline evidence



See [the operational guide](tools/blender/README.md) and [verification record](docs/ASSET_PIPELINE_VERIFICATION.md). The local source hash is pinned in art/source/rig-library/source.json; all 65 bones and 120 original actions are retained. All delivered units have idle/move/attack/death, and both worker variants have work. Required visible palms are stump meshes with no finger weights.



- All 1,168 sampled poses pass common 128-pixel canvases and ground anchors (64,72). Seven atlas pages each have a matching team mask. All sampled death geometry is above ground; source gait retains less than 0.23 delivery pixel of boot penetration.

- 22 Python tooling tests pass, including interrupted publication, replacing corrupt active assets, worker compatibility, atlas gutters/alpha, cache isolation, and package filtering.

- Full cold roster render completed in 515.81 seconds on this machine. The final tooling rebuild took 416.69 seconds with Warden reused; the other four units reproduced the previous color/mask PNGs byte-for-byte. A subsequent five-unit cache validation/build took 1.05 seconds inside the builder. These times exclude any human authoring and are not cross-hardware guarantees.

- Standalone 60-versus-60 benchmark at 1920×1080/1x: 600 ticks, 1,787 drawn frames in 30.033 seconds, 910 attacks; no discarded dt. Sim.step CPU p95 2.226 ms; App.draw submission CPU p95 15.338 ms; actual update cadence p50 16.616 / p95 17.620 ms, maximum 185.372 ms. This is approximately 59.5 average FPS, with occasional longer frames, not a stable-60-FPS certification. Vsync was on; timing includes driver waits and normal garbage collection. No background production render ran during this measurement.

- Benchmark peak sampled texture memory was 167,270,400 bytes; Lua heap grew from about 1,363 to 6,909 KiB. Fixture includes actual HUD/fog/feedback, excludes bots/replay recording/audio, and starts with 60 units per side; deaths are not replenished (26 vs 33 remain).

- Runtime now shows filtered attack sparks, immediate crossbow tracers, death/ready rings and order markers. These cosmetic cues do not drive gameplay. Audio and broader HUD/gamefeel work remain outside this delivery.



Evidence artifacts: asset-final-audit.json, asset-final-roster-report.json, asset-cache-check.log, asset-python-tests.log, asset-presentation-report.txt and asset-benchmark-report.txt under artifacts. The source library is not included in the runtime package. Human artistic sign-off, continuous-motion playtesting and cross-PC verification remain unperformed.

Final asset package: `dist/LoveRTS-20260908-233352`. Its 31 active-catalog asset files were compared byte-for-byte, source blends and stale builds excluded, and all 27 bundled tests plus viewer/game input launches passed from the package directory. Archive SHA-256 is recorded in artifacts/asset-package-audit.json. No Blender process is invoked by the packaged game.



## Earlier UI, minimap and game-feel delivery — 2026-09-09



Implementation details and acceptance gates: [docs/UI_UX_ROADMAP.md](docs/UI_UX_ROADMAP.md).



Delivered: explicit menu/setup/lobby/results/replay flow; compact scalable bottom dock; clickable action cards, hero portrait/stance/revival/upgrades and production cancellation; RTS hotkeys with reserved number groups; input capture; tactical minimap orders and camera outline; filtered last-observed memory; queued orders and construction reservations; bounded rerouting; windup/impact/recovery; correlated command results; filtered effects/audio; settings and common-key rebinding. That delivery used simulation version 2; the current control revision uses version 3.



Verified locally:



- Full suite: 33 passed, zero failed. Fresh 30/60/144 FPS schedule processes again agree over 100,000 ticks at every 100-tick checkpoint. ENet processes agree through 600 ticks.

- Real ENet lobby test proves compatibility does not start gameplay; faction changes invalidate readiness; host start requires both players; finalized configurations agree.

- Rendered checks at 1280×720, 1920×1080 and 2560×1080, each exercising 80/100/125% UI scale. Checks cover modal and minimap capture, coordinates, pause, mouse commands, upgrades, recruitment, text focus, reserved group keys and replay seeking.

- Replay seek reconstructs the same state as a clean 120-tick recorded match, switches perspective and clears transient sound/effects/alerts. Player-two startup discards player-one observation memory.

- Separate menu, setup, multiplayer, settings, replay browser, upgrade and match captures were generated; representative match, settings, upgrade and active battle images were visually inspected.

- Later asset-frame edit passed the seven-unit-test suite, followed by a final 720p rendered regression after the network observation fix.



UI-delivery 240-unit active battle measurement (600 ticks / 30.018 seconds, 1,742 frames): simulation p95 **5.071 ms**, maximum **160.389 ms**; draw submission p95 **15.129 ms**; frame cadence p95 **23.087 ms**. This is about 58 average FPS with hitches, **not stable 60 FPS**. No dt was discarded. Peak pre-step accumulator was 0.428 seconds. The first mass-order workload and runtime/GC scheduling need further profiling.



Peak effects: 22/256; source slots: 5/32; reused minimap/terrain canvases: 2. Sampled Lua heap grew from 2,816 to 14,531 KiB during this bounded run; this is not a long-session memory stability proof. Benchmark includes actual minimap/fog, movement/combat, sprites, effects and audio; excludes bots, network and replay recording, and does not replenish deaths.



Remaining gates: human mouse-only base building, multitasking and alert comprehension; continuous-motion and audio-mix review; physical Windows DPI changes; complete sessions between two physical PCs; long-running memory/network soak; stable-60 optimization. Terrain-unreachable nearby destination slots can still fail A* reachability and produce a visible result; temporary crowding now keeps orders pending. These are explicit acceptance gaps, not claims of completed playtesting.



Evidence: artifacts/ui-regression.log, ui-rendered.log, ui-benchmark.txt, ui-battle.png and ui-<screen>-<width>.png. Run scripts/test-ui.ps1 -Benchmark to regenerate the rendered scenarios and measurement.


Final portable UI package: `D:\LoveRTS\dist\LoveRTS-20260909-001501`. SHA-256: `2288FC7F0D2618AAFDDA38053D2E55B07E852E3C1476D556146904648F623A06`. The final package passed the 720p rendered regression, including saved-replay discovery through a portable artifacts index and player-two observation isolation. The previous packaging pass ran all 33 unchanged simulation/unit/network tests successfully; subsequent changes only corrected presentation storage and test-fixture autosave. Settings and replay indexing prefer artifacts, with LÖVE save-directory fallback, so a restricted profile cannot silently lose them.



## Balance and pacing implementation — 2026-09-09

Implemented `marches-v1` (content 3, simulation 4). The complete numerical specification and remaining acceptance gates are in [docs/BALANCE_AND_PACING.md](docs/BALANCE_AND_PACING.md).

**This section is a historical record.** Its economy figures — worker harvesting, lumber, depots, two-resource costs and five-worker mine rates — were superseded by the resource revision above at simulation version 8. Combat, food, camp, revival and performance figures still stand.

Delivered:

- Default 128×112 Twin Marches map with paired terrain, resources, camps and authored starting formations; hero + five workers + completed HQ; 500 gold / 150 lumber.
- Weighted 80-food cap, reserved hero/production food, proposed unit costs/HP/speeds/attack periods, larger footprints, and one independent HQ advancement unlocking support/heavy troops.
- Five-worker mine assignments, physical hauling and extraction ceiling; lumber depots/outposts, bounded nearest-reachable delivery/tree searches, saved cargo/search progress, and observation-safe hidden depletion handling.
- Construction health growth that preserves damage, explicit refunds, earned-tier revival costs/times, revised hero upgrades, nonstacking support/base recovery, camp rewards/leash/reset.
- Short-range melee approaches for unit bodies and building edges. Subcell contacts retain ordinary collision checks, command cancellation and saved paths.
- Normalized 24-cell vertical camera field, 80–135% zoom, metadata-calibrated unit sizes, building/mine picking extents, food/unit HUD, depot/outpost controls, and HQ advancement controls.
- Bots use content costs, mixed production, mine staffing, technology, expansion, camps, walking retreats and visible base-defense threats.
- Sight coverage now uses integer row intervals, checked against a circular-visibility oracle. Ordered deep copying preserves codec validation/insertion semantics without serializing and parsing every filtered view. Canonical serialization itself is unchanged.
- `src/build.lua` fingerprints the new map and content conversion modules. Replays from older source/content/simulation combinations are rejected.

Verification actually performed on the local Windows development PC, AMD Ryzen 5 5600G, LÖVE 11.5:

- Full `scripts/test.ps1`: **79 passed, 0 failed**, including existing crowd/soak fixtures, old compact mirror/asymmetric fixtures and the new pacing scenarios. Fresh 100,000-tick processes agree at 100-tick checkpoints across 30/60/144 FPS schedules and default/tuned JIT caches. Two real ENet processes agree over 600 ticks.
- A final hidden-mine-depletion regression was added afterward. Current-source `scripts/test.ps1 -Suite simulation`: **39 passed, 0 failed**. Current-source `-Suite balance`: **4 passed, 0 failed**, regenerating both playable-profile replays and checking their complete final canonical states against playback. These counts are overlapping suites, not a claim that one run executed their sum.
- Intentional assertion-failure runner returned exit code **1**; normal test runs returned **0**.
- Rendered UI regression passed at **1280×720, 1920×1080 and 2560×1080**, each exercising 80/100/125% UI scale. Includes the new constant-world-field assertion, input capture, coordinate round trips, menus, upgrades, recruitment and replay seeking. Representative 1080p match captures were visually inspected.
- Earlier compact mechanics values are explicitly frozen in `tests/fixture_content.lua` / `tests/fixture_bot.lua`; they are not playable balance. Existing movement expectations were retained. No golden replay was silently blessed.

Measured gameplay:

| Measurement | Result |
|---|---|
| Gold, five workers, well-placed route | 600/minute |
| Gold, six workers, same route | 600/minute |
| Lumber, one worker, eight-cell origin-distance route | 50/minute |
| Shorter lumber route tested during calibration | 60/minute; efficient placement can exceed the ordinary-route target |
| Shieldguard duel, no auras/healing | 41 seconds, 1.4-second impact cadence |
| First war halls, current mirror fixture | 62.45 / 65.05 seconds |
| First combat troops | 83 / 86 seconds |
| HQ advancement complete | 364 seconds, both mirror players |
| Natural outposts complete, mirror | 493.25 / 516.65 seconds |
| Mirror match | Player 2 wins at 660.85 seconds (11:00.85) |
| Asymmetric match | Bastion wins at 634.55 seconds (10:34.55) |

Both current-profile match replays were simulated again to an identical final canonical state. These are two deterministic bot matchups with one seed, not a statistical balance study or six human playtests.

Performance:

- New profile, 128×112 map, 240 live mobiles, 2,000 active ticks: **7.648 ms simulation p95**, maximum **57.000 ms**; 6,280 attacks. Battle clearings were widened only in the stress fixture for deployment. Includes movement, combat, visibility and authoritative work; excludes rendering, bots and replay encoding.
- Existing 240-unit/10,000-tick control fixture: **5.500 ms p95**, preserving its clearance and memory gates.
- New-profile rendered stress, 1080p, minimap/sprites/fog/effects/audio enabled: 600 ticks, 1,705 frames / 30.032 seconds (about **56.8 average FPS**), **39.291 ms frame cadence p95**. Simulation p95 in this combined workload was **13.980 ms**; draw submission p95 **14.554 ms**. This does **not** pass stable 60 FPS or the combined-workload 10 ms simulation target. Peak backlog 0.310 s; no ticks discarded. Peak effects 48/256, source slots 3/32, two minimap canvases. Sampled heap 3,709→16,260 KiB is not a long-session memory proof.

Open acceptance gates:

- Bot matches currently finish around 10.5–11 minutes; **15–25-minute pacing is not yet achieved**. Economy, base defense, neutral activity and human decision time need playtesting before changing the proposed numerical profile.
- Natural and easy-camp approaches measure 7.25 / 6.00 seconds, below the proposed 10–15 / 8–12 ranges. Strategic base/center/flank routes meet their targets. Exact uniform base-plot/exit widths are not certified in this first authored layout.
- Stable 60 FPS and combined rendering/simulation timing need further profiling. Human camera/readability, audio, hard-camp strength, build-space and matchup review remain unperformed.
- Three mirror plus three asymmetric **human** matches, physical DPI changes and complete matches between two physical PCs remain unperformed.

Evidence: `artifacts/balance-release-tests.log`, `balance-current-simulation.log`, `balance-current-scenarios.log`, `balance-release-ui.log`, `balance-runner-failure.log`, `balance-routes.txt`, `balance-mirror.txt`, `balance-asymmetric.txt`, `balance-performance.txt`, `balance-ui-benchmark.txt`, `balance-ui-battle.png`. Playable replays: `balance-mirror.replay`, `balance-asymmetric.replay`, and the mirror alias `sample.replay`. Legacy codec fixture output is explicitly named `fixture-sample.replay`.

Portable balance build: `D:\LoveRTS\dist\LoveRTS-20260909-105528`. Archive SHA-256: `20AE518BD6BDE15CC89A95AC230ADF962902BFC354FC986923C814B69F7B9D36`.

Launched and tested from the package directory, outside the development checkout: **11 unit tests**, **39 simulation tests**, the **1280×720 rendered UI regression**, and startup of the current-profile `sample.replay` all passed. The executable, runtime, source archive and active assets were packaged successfully. Package logs/screenshots are under that package's `artifacts` directory. Use `Play.ps1` or the repository's `scripts/run.ps1` to start.


## Context-sensitive command cards and feedback - 2026-09-09

Delivered worker Build and hero ability submenus, full-selection action context, grey prerequisite states, individually red resource/food/XP costs, explicit permanent-upgrade choices, and short command/rejection visual cues. Audio now distinguishes selection, menu navigation, orders, cancellation, stance, upgrade and research; individual cues accept bundled files with a synthesized fallback. See [docs/COMMAND_CARDS.md](docs/COMMAND_CARDS.md).

Verification: 13 unit tests passed; the rendered UI suite passed at 1280x720, 1920x1080 and 2560x1080 with the existing scale checks. New tests cover selection permutations, costs/prerequisites, mouse/keyboard parity, hero choice submission, late acknowledgement isolation, bounded feedback and missing audio-file fallback. Build/ability/mixed-selection captures were generated and representative images visually inspected. Evidence is under `artifacts/command-card-*.log` and `ui-*-card-*.png`.

Gameplay simulation/content were unchanged; full gameplay, performance and cross-process suites were not rerun for this presentation delivery. Listening review, continuous human play and two-PC sessions remain unperformed. The cost display supports mana metadata; current content does not yet spend mana.
## Control, movement and ability revision — 2026-09-10

Simulation version **10**, content version **6**. Two deliberate versioned breaks in this
run: string-pulled paths (version 9) change movement results, and abilities (version 10)
add commands, a phase and entity state. Replays recorded before them are rejected rather
than misreported as divergence. No golden result was silently re-blessed.

Measured on the same thermally limited development laptop as the previous revision, whose
run-to-run spread is large; single-run differences under about 30% are not evidence.
Absolute milliseconds are not comparable with the reference-desktop figures further up.

### Verified on this machine

`scripts/test.ps1 -PerfBudget 40`: **97 passed, 0 failed**. Four fresh processes agree at
100-tick checkpoints over 100,000 ticks across 30/60/144 FPS schedules and default/tuned
JIT caches. A real local ENet pair agrees at every 100-tick checkpoint. `test-ui.ps1` and
`test-presentation.ps1` both exit 0.

The performance gate is 40 ms on this machine and 10 ms by default for the reference
desktop, as established in the previous revision. It is a parameter, not a constant.

| Measure | Before this run | After |
|---|---:|---:|
| Open diagonal straightness (walked / direct) | staircase | 1.000x |
| 100 units, open arrival | 932 ticks | 445 |
| 100 units, chokepoint | 1,640 ticks | 1,326 |
| 20 mixed units | 868 ticks | 705 |
| 50 versus 50 counterflow | 4,079 ticks | 849 |
| 240-unit active benchmark, p50 | 10.7 ms | 6.0 |
| 240-unit active benchmark, p95 | 27.6 ms | 16.4 |
| 240-unit active benchmark, maximum | 442 ms | 147 |

The benchmark figures are the median of three back-to-back runs each; the individual
p95 readings ranged 14.6–18.7 after and 15.5–45.0 before, which is the spread this
machine has. Attack counts are identical before and after every behaviour-preserving
change in this run (28,972 in the control benchmark, 6,372 in the balance one), which is
the evidence that they are behaviour-preserving.

### Delivered

- Warcraft 3 control rules that were wrong: A-click on an enemy now focuses it rather
  than attack-moving to the ground under it; Tab moves the command card between unit
  types and keeps the whole selection; the card follows the active subgroup and otherwise
  prefers a hero over a soldier over a worker rather than the lowest entity id; box
  selection takes your own units over anything else and never mixes a building into an
  army; Ctrl+click selects every visible unit of a type.
- Orders are answered before the simulation runs: the ordered units' circles brighten and
  an acknowledgement sound plays, resolved most-specific-first so faction voice lines slot
  in by naming alone. The `windup` event finally has a consumer.
- `src/sim/stats.lua` resolves speed, damage, armour, attack period, windup, range and
  sight. Every direct content read for gameplay now goes through it.
- String-pulled paths, path re-validation on navigation change, and prompt yielding.
- Abilities and status effects: `cast` and `ping` commands, a cast phase, mana, cooldowns,
  a status list, five target kinds and travelling projectiles. See
  [docs/ABILITIES.md](docs/ABILITIES.md).
- Target acquisition is bucketed into eight-cell blocks instead of scanning every hostile
  on the map once per damage-capable entity per tick.

### Still open after this run

- **Formation-preserving group moves.** Destination slots are still an outward ring search
  per unit, so a group's shape is discarded when it moves. Speed pacing holds a mixed army
  together; its arrangement is not preserved.
- **Auto-attacks do not travel.** The projectile mechanism exists and is used by abilities;
  enabling it for ranged attacks changes when every ranged trade lands and needs a
  playtest first.
- **Adaptive lockstep.** The network buffer is still a fixed three ticks and the match
  stalls above roughly 140 ms round trip rather than lengthening its turn.
- **Ability balance is unmeasured.** The four hero abilities exist to prove the four
  targeting kinds work end to end. Their numbers are a starting point for playtesting.
- Every human gate listed in the earlier sections remains open: continuous-motion review,
  crowd feel in chokepoints, combat readability, cross-PC play and stable-60 certification.


## Merge reconciliation — 2026-09-11

Integrated the local command-card delivery with the incoming control, ability, movement
and single-resource revisions. Preserved cost/rejection feedback and paired upgrade
menus, adapted Build to extractors, and retained active-subgroup cards, fixed spell
slots, targeting previews, pings, delivery statistics and viewport culling. Hero stance
uses Z so it does not compete with spell hotkeys. Added regression coverage for worker
subgroup menus, unique slots/hotkeys, fixed spell positions and blocked-order feedback.
No authoritative simulation or golden replay changes were made during reconciliation.

Verification on this Windows PC:

- Full `scripts/test.ps1` at its default 10 ms budget: 98 passed, 1 failed. The failure
  was an obsolete command-card expectation from before the economy/subgroup integration.
  After updating that expectation and adding integration assertions, the complete unit
  suite passed 13/13. The full suite was not repeated; all its gameplay tests passed.
  Active control/balance p95 measurements were 8.592 / 8.356 ms.
- Final determinism suite: 5/5, plus identical 100,000-tick checkpoints in four fresh
  processes at 30/60/144 FPS schedules and default/tuned JIT caches.
- Final network suite: 4/4, plus a real local ENet pair agreeing over 600 ticks.
- Rendered UI passed at 1280x720, 1920x1080 and 2560x1080. Final
  `scripts/test-presentation.ps1` passed its 720p UI regression and asset viewer.
  A representative 1080p capture was visually inspected. The first sandboxed UI run
  could not write the normal LÖVE fallback save directory; rerunning with that access
  passed, including the replay-fallback test.

Logs: `artifacts/merge-tests.log`, `merge-unit.log`, `merge-determinism.log`,
`merge-network.log`, `merge-ui.log`, and `merge-presentation.log`. These counts overlap;
they are separate runs. Human playtesting and two-physical-PC multiplayer were not run.
## Woodland pixel pilot — 2026-09-11

- Added isolated Mouse Builder source recipes, a derived 65-bone rig, idle/move/work,
  all eight independently rendered directions, and 32/48/64 nominal crown-height variants.
  256 poses per size; 768 frame entries. The source blend and production catalog hashes
  are unchanged. Reopening the derived blend confirms two 65-bone rigs and 123 actions.
- Added deterministic 32-color finishing, binary alpha, one-pixel outer outline and five
  discrete team shades; isolated nearest/integer comparison viewer with terrain swatches
  and a mixed crowd. The production game camera, zoom and simulation are unchanged.
- Optional Aseprite preparation/check/import supports tagged two-layer source files,
  preserved edit revisions, palette/mask validation and stale-baseline rejection.
  Installed Aseprite 1.3.17 round-tripped 256 frames with zero changes. No manual art
  cleanup is claimed; automated builds do not require an editor.
- Validation: 28 Python asset tests and 13 Lua unit tests pass; all three atlases validate;
  cached rebuild reused all variants. LÖVE pilot and production viewer smoke checks pass.
- Full scripts/test.ps1 run: 98 passed, 1 failed, active-unit p95 13.168 ms against 10 ms.
  Isolated unchanged-limit recheck also failed at 23.567 ms. This performance failure
  remains unresolved; the failed full run did not reach its separate-process follow-ups.
  No gameplay/golden tests were modified to excuse it.
- Contact-sheet inspection covers complete sample sequences and wrap transitions;
  human motion approval, final native resolution and other-PC testing remain outstanding.
  Other woodland species and full-game pixel alignment are subsequent work.

Workflow and review instructions: [Woodland pixel pilot](docs/art/WOODLAND_PIXEL_PILOT.md).

## Map revision: 192×192 Twin Marches and roads — simulation version 11

Twin Marches was rebuilt at **192×192** (from 128×112) for Warcraft 3-scale distances, and
maps gained a **road** layer, `map.unbuildable`: walkable ground nobody may build on. Roads
three cells wide join every gold mine to the others and to both headquarters, so no wall of
buildings can cut a mine off from the bases. `Sim.placement` refuses a road cell and the
build command revalidates through it, so the rule is authoritative; an extractor still goes
on its own mine. Roads change neither movement speed nor sight. Layout and measured routes:
[docs/BALANCE_AND_PACING.md](docs/BALANCE_AND_PACING.md#twin-marches).

This is a deliberate, versioned break: `Sim.VERSION` 10 → 11, and replays from earlier
versions or of the old map are rejected rather than misreported as divergence. The balance
replays under `artifacts/` were regenerated by the balance suite. No golden result was
silently blessed. The two strategic route assertions were rescaled by 1.5 with the map
width, because the longer march is the point of the change.

Also changed: the bot's distance thresholds (own-half mine reach, outpost reach, base threat
radius) scale with map width and never shrink below their 128-cell values, and its early
forward rally reads a new `anchors.forward` instead of fixed cells. The minimap, world
terrain and setup preview draw roads. The 240-unit balance benchmark now deploys in the
new center clearing.

### Measured on this machine

| Measure | 128×112 layout | 192×192 layout |
|---|---:|---:|
| Rally to enemy rally | 46.05 s | **76.30 s** (target 60–83) |
| Center to rally | 23.30 s | **38.65 s** (target 30–42) |
| Natural approach | 7.25 s | **9.95 s** (target 10–15) |
| First easy camp | 6.00 s | **8.35 s** (target 8–12) |
| Mirror bot match | 9:33, last recorded at version 8 | **16:04**, within the 15–25 min target |
| Asymmetric bot match | 10:34, last recorded at version 4 | **13:27**, 1.5 min short of the floor |
| First contact, mirror | 4:20, version 8 | 4:21 |
| 240-unit benchmark, Sim.step p95 / max | — | 17.147 / 268.455 ms, single run |

The mirror match is the first bot match to land inside the duration target, and it has the
shape the pacing section asked for: player one was behind on army from 5:00 to 12:00 and
won anyway. That is one seed and one matchup, so it is an observation, not evidence that the
comeback problem is solved. The benchmark is a single run on the thermally limited laptop,
in a different clearing from the old one, so it is not comparable with earlier figures.

The larger map moves income: with the doc's own trip formula the natural now pays about 61%
of a near mine without an outpost (it was 90%), so outposts matter much more. No economic
constant was changed; whether that is right is a playtest question.

### Verified

Run suite by suite with `scripts/test.ps1 -PerfBudget 40`, as established for this laptop:

- quick (unit + simulation) **68/68**, including three new tests: the 192-cell symmetry
  check now covers roads; a flood fill proves every gold mine and both headquarters are on
  one road network; and a war hall on a road is refused while an extractor on a paved mine
  is not.
- balance **4/4**: route report, mirror and asymmetric bot matches with replay
  re-verification, and the 240-unit benchmark above.
- determinism **5/5** plus 100,000-tick agreement across fresh processes at 30/60/144 FPS
  schedules and default/tuned JIT caches; network **4/4** plus real ENet host/client
  agreement; scenario **2/2**; crowd **15/15**; soak **1/1**.
- `scripts/test-ui.ps1` and `scripts/test-presentation.ps1` both exit 0.
- performance **1/2**: the 240-unit, 10,000-tick control benchmark measured 66.735 ms p95
  against the 40 ms budget, with exactly the recorded 28,972 attacks. It runs on a 48-cell
  fixture map, not Twin Marches, and on that path this revision changes only an empty
  road-key check in `Sim.create` and one view field. An alternating back-to-back run
  against the parent commit was still in progress when this was committed; its result is
  recorded with the next revision.

### Not done

- Most of the map is still rock, with play in corridors. Warcraft 3 maps are mostly open
  ground broken by tree lines; opening the two interior triangles is the obvious next layout
  pass.
- The minimap fog repaint draws one rectangle per cell, now 36,864 on this map (14,336
  before). It was 0.6 ms on the old map and was not re-measured here.
- Human playtesting, cross-PC play and the Pi remain untested, as before.

## Control points and open interior — simulation version 12

Owning every control point on the map for **two minutes** without a break now wins the
game, alongside destroying the enemy headquarters. Twin Marches' two interior rock
triangles were opened into fields with forest clumps, about 60% of the map now walkable,
and a control point sits in each, as rotations of each other. The rules and the choices
made where the request left room are in
[docs/BALANCE_AND_PACING.md](docs/BALANCE_AND_PACING.md#control-points).

Versioned break: `Sim.VERSION` 11 → 12 and content 6 → 7. `w.control` is new world state:
it is included in `Sim.serializeAuthoritative`, copied into every view because it is public,
and snapshots carry it. A control victory is `result.reason='control'`; a headquarters
victory is unchanged.

Presentation: owner-coloured rings on the ground with a fill that grows during a capture,
minimap rings, a public countdown banner under the resource bar, the reason on the
victory/defeat banner, and alerts for captures and holds. Events `captured`,
`control_started` and `control_broken` are there for audio to hook later.

**Previous revision's performance check.** The control benchmark that missed 40 ms was run
three times alternately against the parent commit (`3f7b956`): p95 before 85.9 / 18.4 /
12.4 ms, after 54.5 / 30.0 / 14.5 ms, with 28,972 attacks every run and a lower p50 after
in all three. The unchanged code alone ranged 12–86 ms, so this machine cannot separate
the two: no evidence of a regression, and no proof of its absence either.

### Measured on this machine

| Measure | Rock interior (version 11) | Open interior with control points |
|---|---:|---:|
| Walkable share of the map | mostly rock | 59.8% |
| Rally to enemy rally / center to rally | 76.30 / 38.65 s | 76.30 / 38.65 s |
| Mirror bot match | 16:04, headquarters | **17:33, headquarters** |
| Asymmetric bot match | 13:27 | **13:23**, headquarters |
| First contact, asymmetric | 4:21 | 3:59 |
| 240-unit balance benchmark p95 / max | 17.147 / 268.455 ms | 11.472 / 98.777 ms, single run |

Both matches were won by destroying the headquarters, and in both final states neither
control point was owned. The bots do not try to take points, so neither ever gave the
other a hold to answer; the bot's retake behaviour is therefore unexercised by a full
match and is covered only by reading it. Player one came back from behind in the mirror
again: behind on food from 6:00 through 14:00, ahead from 15:00. One seed per matchup, as before.

### Verified

- quick (unit + simulation) **74/74**: five new control scenarios (capture and keep,
  contest and unwind, exact two-minute win, a broken hold restarting from zero, snapshot
  continuation and checkpoint coverage) and a Twin Marches check that the points are paired,
  open, unbuildable and clear of camps, and that over half the map is walkable.
- balance **4/4**.

- determinism **5/5** plus 100,000-tick agreement across fresh processes at 30/60/144 FPS
  schedules and default/tuned JIT caches; network **4/4** plus real ENet host/client
  agreement; scenario **2/2**; crowd **15/15**; soak **1/1**.
- performance **2/2**. The control benchmark that missed the budget last revision measured
  35.016 ms p95 this time against 40 ms, with the same 28,972 attacks.
- `scripts/test-ui.ps1` and `scripts/test-presentation.ps1` both exit 0. The rendered suite
  now draws Twin Marches with one point owned and the other half captured by the enemy,
  then with both held, at 1280×720, 1920×1080 and 2560×1080, and asserts drawing leaves
  the simulation unchanged. The 1280 captures were inspected: an owner-coloured ring on the
  ground, owner-coloured minimap rings, and the countdown banner reading
  "You hold both control points 2:00" under the resource bar. The capture fill on the
  enemy's half-taken point is drawn off-screen in that frame, so it was not visually checked.

### Not done

- The bots never take control points, only retake them, so no bot match has ended by
  control and the retake behaviour has not run in a full match.
- The capture time, the fading of an empty point, and that workers count are defaults
  chosen here, not settled design; they want a playtest.
- The minimap fog repaint and human playtesting remain as listed in the previous revision.

## Inspecting enemy and neutral units

An enemy unit or building, a neutral camp creature, or a gold mine can now be selected with
a click to read it, as in Warcraft 3 and StarCraft, and never commanded. Box selection
already took one foreign thing when the box held nothing of yours; a click now does the
same, preferring your own unit under the pointer. Presentation only: the simulation and
content are unchanged, and it already rejected commands for units a player does not own.

- **One at a time.** Every click and box goes through `Selection.apply`: a foreign id
  replaces the selection, and shift-adding your own unit to an inspected one replaces it
  rather than mixing the two.
- **The card.** "Inspecting", then Enemy or Neutral and the name, health with a bar, mana
  when it has any, construction state, and the statistics anyone could look up: damage,
  range, speed, attack rate, sight and food. A mine shows its gold remaining. Nothing about
  orders, queues or experience, which a view does not carry for someone else's entity.
- **No commands.** The command card says "You cannot command enemy units." Right-click
  orders, rally points and ability casts now take only your own selected units, a right-click
  while inspecting says why nothing happened, and Ctrl+number will not bind an inspected
  unit to a control group.
- **Relation colours.** A selected foreign unit's ring, and a selected foreign building's
  outline, are red for an enemy and amber for a neutral instead of the friendly green.
- **Out of sight.** When an inspected thing walks into fog or dies, the selection lets go.
- Carriers and shots in flight can still be targeted but not selected.

Verified: quick **74/74**; `scripts/test-ui.ps1` at 1280×720, 1920×1080 and 2560×1080 and
`scripts/test-presentation.ps1` both exit 0. The rendered suite now clicks an enemy hero
brought into sight and asserts it is selected alone, offers no commands, sends no order
for a right-click, draws its card, is replaced by a shift-added own unit, that a mine can
be inspected, and that the selection empties once the enemy leaves sight. The 1280 capture
`artifacts/ui-inspect-1280.png` was inspected: red ring, "Enemy Beastkeeper", 900/900 HP,
mana 200/200, its damage, range, speed, attack rate, sight and food, and "You cannot
command enemy units." in the command card. Neutral camps and a foreign building's card were
drawn by code review only, not captured.

## Improvement loop, iteration 1: every order acknowledged once, on the click

The first item from [docs/ITERATION_LOG.md](docs/ITERATION_LOG.md). Two independent code
readings found the same two faults:

- **A second "accepted" tone** played when an order executed, so in multiplayer a player could
  hear the ~200 ms input delay.
- **Stop, Hold and stance** from the command card, their hotkeys or the HUD played a generic UI
  click, with no unit flash and no acknowledgement.

Warcraft 3 answers an order once, on the click.

`Actions.order` now issues an order and acknowledges it exactly like a right-click, through
`Input.acknowledge`, and all those paths use it. Accepted orders play nothing when they resolve.
Rejections and learned upgrades keep their cues.

Presentation only; no simulation, content or replay change.

Verified:
- The extended command-card test failed against the previous code and passes now.
- quick **74/74**.
- `scripts/test-ui.ps1` and `scripts/test-presentation.ps1` both exit 0.

Not verified: no listening review; all cues are still synthesized placeholders.

## Improvement loop, iteration 2: held units are never shoved aside — simulation version 13

An idle ally standing in a passing unit's road is asked to step aside. `yieldable()` never checked
whether that ally could move, so a rooted or stunned unit was pushed around against its own status.
Two independent code readers found it during the skill evaluation. `yieldable()` now refuses any unit
`Stats.canMove` rejects.

This is a versioned break (12 → 13).

All eight crowd arrival times are unchanged:
- open: 318 / 321 / 393 / 445 ticks
- chokepoints: 340 / 460 / 1,326
- mixed: 705
- counterflow: 849

So crowds without held units behave exactly as before.

Verified:
- The new crowd test failed on the old code (a rooted ally pushed at tick 31) and passes now, for
  both root and stun.
- quick **74/74**; crowd **16/16**.
- On a snapshot of the tree holding iterations 2–4:
  - determinism **5/5**, plus 100,000-tick agreement across fresh processes at 30/60/144 FPS and
    default/tuned JIT
  - network **4/4**, plus a real ENet pair
  - scenario **2/2**; soak **1/1**; balance **4/4**
  - the performance suite result for this snapshot is recorded with iteration 3, whose change is the
    one that needs a timing comparison

## Improvement loop, iteration 3: fog repaint from one texture

Fog, shared by the world and the minimap, used to clear a canvas and draw one rectangle for every
unseen cell (36,864 on Twin Marches) on almost every tick. Deciding whether to repaint also walked
every explored key.

It is now one pixel per cell in an `ImageData` uploaded with `Image:replacePixels`. Each tick writes
only the cells visible now or last tick, and a change of map or perspective rebuilds it once.
Presentation only.

UI benchmark, Twin Marches 1920×1080, three alternating runs against the parent commit:

| Measure | Before | After |
|---|---|---|
| Minimap cache p95 | 10.7 / 13.5 / 13.3 ms | **0.21 / 0.24 / 0.32 ms** |
| Frame cadence p95 | 115 / 500 / 459 ms | **39 / 49 / 108 ms** |
| Draw submission p95 | 10.9 / 12.1 / 13.1 ms | 9.8 / 10.6 / 11.1 ms |

Verified:
- **Test strength:** a new rendered test checks every fog pixel against the player's visible and
  explored sets (start, after ticks, the hero sent far out and back, a perspective switch there and
  back). It was strengthened after its first version passed against deliberately broken code; the
  strengthened version fails that code.
- **Suites:** `scripts/test-ui.ps1` and `scripts/test-presentation.ps1` exit 0; quick **75/75**.

Performance of the simulation after iterations 2 and 4, alternating `8a24190` against `332776d` on the
240-unit control benchmark:
- **Timings:** p95 13.6 / 16.8 / 14.8 against 19.0 / 32.8 / 13.1 ms; p50 5.1 / 3.8 / 5.4 against
  6.1 / 5.0 / 6.0 ms.
- **Behaviour unchanged:** identical 28,972 attacks in all six runs, all under the 40 ms gate.
- **Earlier failure:** the heavy-suite run's one failure (126.5 ms p95) happened while other test
  suites shared the machine.
- **Caveat:** the after medians are slightly higher, within this machine's noise. A small real cost is
  not ruled out.

## Improvement loop, iterations 5–7 and stopping

- **5, shared path search per group move: reverted.**
  - Measured: 12 units ordered around a wall waited 607 ticks for routes, where one unit alone waits 53.
    Sharing one search cut that to 53.
  - But it deadlocked the 50-vs-50 counterflow crowd, and a narrower version then deadlocked the
    100-unit chokepoint too.
  - The measurement stays as a reported crowd test.
- **6, the deadlock: diagnosed, not fixed.**
  - A probe that gives every unit its route on tick 1 reproduces it with no sharing code: counterflow
    never finishes.
  - Every stalled front unit is blocked by an *ally*. Two moving allies each need the other's space, and
    yielding only moves idle units.
  - The likely fix, letting long-blocked allies briefly overlap as Brood War's harvesters do, changes
    how crowds look, so it is a question for the user in
    [docs/ITERATION_LOG.md](docs/ITERATION_LOG.md).
- **7, control-point edge cases: five new simulation scenarios, no defect found.**
  - Two of them were proven able to fail by deliberately breaking `control.lua`.
  - Simulation suite **64/64**.

The loop stopped here: the remaining high-value work needs user decisions (crowd overlap, control-win
pacing, netcode, expansion income) or hardware this machine lacks (two PCs, generated art). Details are
in [docs/ITERATION_LOG.md](docs/ITERATION_LOG.md).

## Improvement loop, iteration 4: bots take control points

Bots used to retake a point only when the enemy held both, so no bot match ever exercised the
control win. With an army of at least six, an outpost and nothing to defend, the bot now takes the
nearest point it does not own before marching on the enemy base, and moves on once it owns them all.

| Balance match (one seed) | Before | After |
|---|---|---|
| Mirror | 17:33, headquarters | **14:03, player 2 by control** |
| Asymmetric | 13:23, headquarters | **9:17, player 1 by control** |

This is the first time a full match has been decided by control, and the retake rule has now run in
anger. In the asymmetric match the winner had the *smaller* army (peak food 49 against 56), so a hold
works as a way back into a game. Both matches are now below the 15-minute floor. Whether that is right
is a design question recorded in [docs/ITERATION_LOG.md](docs/ITERATION_LOG.md); no rule or number was
changed.

Verified:
- The new bot unit test failed on the old bot and passes now. It covers claiming, moving on, not
  parking on owned points, and retaking an enemy hold.
- quick **75/75**; balance **4/4** with both replays re-verified.

## Construction: stopping, resuming and being told — simulation version 15

A building site is worked by one worker, and work stops if that worker dies, is given another
order, or is replaced. Resuming already worked — right-clicking a site with a worker sends it
back, and progress, health capacity and damage taken were all kept correctly — but three things
around it did not.

| Behaviour, measured on a real match world | Before | After |
|---|---|---|
| A site stalls when its builder dies or is pulled away | held | held |
| Another worker resumes it, keeping progress and damage | held | held |
| The replaced worker is released | **kept its build order for ever** | becomes idle |
| The player is told work stopped | **nothing at all** | alert and selection text |
| The bot returns to a site whose builder died | **never; 1,079 of 1,200 left after 900 ticks** | finished it: 197 left |

- **Taking a site over releases whoever held it.** A worker whose site was taken kept a `build`
  order for ever: standing beside a building it no longer worked on, not counted among idle
  workers, effectively lost to the player.
- **A site records that it has stopped** (`stalled`) when nobody is assigned, and emits
  `build_stalled` once. A builder still walking to its site is on its way, not stopped. The flag
  clears when someone takes the job, and on completion.
- **The player is told**: the alert reads "Construction stopped - send a worker back", and a
  selected site reads "construction stopped" rather than "under construction". This is owner-only
  knowledge: an enemy scouting the site still sees only that it is under construction.
- **The bot sends its nearest free worker back** to a stopped site before starting anything new,
  rather than leaving a half-built building and its spent gold for the rest of the match.

Bot matches are unchanged (mirror 9:38, asymmetric 8:17, both player 1 by control): no site stalls
in either, so the new rule never fires there.

Verified: quick **87/87**, crowd **20/20**, balance **4/4**, determinism **5/5**, network **4/4**,
scenario **2/2**, soak **1/1**, plus the rendered UI and presentation suites. Four new tests — the
takeover release, the single stall report and its clearing on resume, owner-only visibility, and
the bot's return — were each run against the previous commit and failed there.

## Basics swept: production, queued builds, hold, and carriers without an extractor

A probe drove each of these on a real match world rather than reading the code, because most of
them had no test at all.

| Basic | Result |
|---|---|
| A queued second building is placed at once, and still built after the first is cancelled | held |
| A unit on hold attacks what comes into range | held (7 attacks) |
| A unit on hold never leaves its ground | held (moved 0 subunits) |
| A worker is released when the site under it is destroyed | held; now has a test |
| A destroyed extractor stops paying | held |
| **Carriers whose extractor is destroyed** | **stood alive for the rest of the match**; they now deliver |

**Carriers now finish their delivery when their extractor dies.** Eight carriers holding 64 gold
used to stand still for ever: alive, drawn on the minimap, counted in every per-entity pass, and
unable to deliver, because their route came from a building that no longer existed. They now walk
the route they were given and are paid on arrival, chosen by the user over losing the gold:
that gold is already out of the ground, so a raid stops the flow at its source rather than stealing
what has left it. A carrier killed on the road still destroys its own load. Simulation version 17.

Two apparent faults were the probe's own and not the game's: a six-cell wall did not block a
production exit (the spawn search looks further out), and a site set to zero health healed straight
back, which is the documented rule that construction progress adds health every tick.

Verified: quick **89/89**, crowd **20/20**, balance **4/4** (matches unchanged at 9:38 and 8:17),
determinism **5/5**, network **4/4**, scenario **2/2**, soak **1/1**, rendered UI and presentation.
The carrier test fails on the previous commit; the worker-release test passes there, so it is
coverage of behaviour that already held rather than proof of a fix.

## Terrain: Tiled map authoring and a drawn ground

The ground used to be the minimap's one-pixel-per-cell canvas stretched over the world, in three
flat colours, and Twin Marches was Lua code carving squares and rectangles out of a solid grid.
Rock and forest were both just `blocked`, so nothing could tell them apart. Phases 2 and 3 of
[docs/TERRAIN_AND_CAMERA_PLAN.md](docs/TERRAIN_AND_CAMERA_PLAN.md) are now done; the camera phase
is not, so zoom is still there.

**Map format.** `maps/twin_marches.tmx` is the source, edited in Tiled. `scripts/map.ps1` exports
it to `src/maps/twin_marches_tiled.lua` (`-Mode Check` fails if a committed export no longer
matches its `.tmx`, and skips when Tiled is absent). `src/maps/tiled.lua` converts the export into
the table `Sim.create` already read, deriving `blocked` and `unbuildable` from four terrain types
— grass, road, rock, forest — and adding a `terrain` string of one character per cell. The string
copies and hashes as a single value, so worlds and snapshots cost the same as before. Gameplay
objects (starts, gold, camps, unit starts, anchors, control points) come from the object layer in
object-id order, which keeps entity ids stable when the map is edited.

**The layout is the same map, reshaped.** A one-time generator (`tools/tiled/generate`) rebuilt it
from the old code-authored version, kept at `tools/tiled/twin_marches_legacy.lua`. Every base,
mine, road, camp, control point and anchor stayed in its cell, and the map is still symmetric under
a 180-degree rotation. Rock edges became bays and promontories, forest rectangles became lobed
groves, and bays three or more cells deep became woods, so coves read as forest instead of opening
new buildable ground.

| Cells | Before | After |
|---|---|---|
| Grass | 19,448 | 20,622 |
| Road | 2,606 | 2,606 |
| Rock | 13,840 | 8,548 |
| Forest | 970 | 5,088 |

A bay may only open where every open cell near it is a short walk from the bay's own side, so it
can never become a passage between two routes. The generator then measures walking distance between
all ten key places (both bases, both naturals, forwards, contested corners, both control points)
against the old map, and restores terrain along any route that got more than 3% shorter or 6%
longer. **Worst remaining route change: 1.1%**, with no repairs needed and 366 unreachable pocket
cells filled.

**Drawn ground.** `src/ui/terrain.lua` bakes the ground into chunks of 16 cells at 16 pixels per
cell (about 37 MB for the whole map), draws only what is in view, and bakes one chunk of the
surrounding ring per frame. Everything is procedural — no art: mottled grass with tufts, dirt roads
with pebbles, rock with cracks, a lit rim, a dark south-facing cliff and a shadow below it, and
forest crowns with shadows. Type edges wobble by up to 1.5 of the four sub-blocks per cell, so the
middle of a cell always shows its true type. Variation comes from an integer hash of cell
coordinates, never the simulation's PRNG. The minimap is coloured by terrain type too, and maps
without a terrain string (the test fixtures) fall back to the old flags.

Simulation version is unchanged: no rule changed. Map data did change, so `src/build.lua`'s
fingerprint rejects older replays, which is expected.

| Balance match (one seed) | Old map | Reshaped map |
|---|---|---|
| Mirror | 7:16, player 1 by control | **9:38, player 1 by control** |
| Asymmetric | 7:17, player 1 by control | **8:17, player 1 by control** |

Both matches still end by control, and both still end early for the reasons already recorded under
the bot's control-point targeting in [docs/ITERATION_LOG.md](docs/ITERATION_LOG.md).

Verified: quick **83/83** (including three new converter tests: cells, flags, terrain and object
order; refusal of unknown tiles, classes, terrain, layers, external tilesets, empty cells and a
missing start; and Twin Marches' terrain agreeing with its flags and symmetry), crowd **20/20**,
balance **4/4**, determinism **5/5**, network **4/4**, scenario **2/2**, soak **1/1**, plus rendered
UI and presentation suites with three terrain captures (`artifacts/ui-terrain-*.png`) that prove
drawing leaves `Sim.serializeCanonical` unchanged and that closing the app releases the chunks.

Not verified: how any of this looks with real tile art (none exists yet), bake cost on a Raspberry
Pi, and the camera, which this work did not touch.

## Crowd movement: squeeze, push and detour searches — simulation version 14

Crowds in narrow gaps used to lock up. Three causes, three changes, all in `src/sim/movement.lua`:

- **Allies crossing each other.** Two moving allies whose next steps each pass through the other
  waited for ever, because only idle allies step aside. A unit blocked for **10 ticks** may now
  squeeze past a moving ally that is not heading the same way, down to **65%** of their combined
  radii (usual spacing 75%). It never squeezes into the queue in front of it: an early version did,
  and packed whole queues down to the floor until nothing could move.
- **Gentle push.** Allies closer than their usual spacing are eased apart by up to **8 subunits a
  tick** (units walk 26–44), moving units included. Pushes never press anyone closer, never leave a
  keep-right lane, never carry an idle unit more than a cell, and never move held, building,
  mid-swing, rooted or stunned units. Without the push, 26–36% of unit-ticks stayed squeezed.
- **Detour searches starving.** A congested unit restarted its search every 20 ticks with its
  path emptied. Behind a jam, ~85 searches shared a 64-expansion budget, none finished, and the
  units waiting on them stood frozen. A running search is now left to finish, and the unit keeps
  walking its old path meanwhile.

Enemies, terrain and lanes stay solid. The numbers were chosen by sweeping 18 settings over a
28-case crowd lab, then checked on 24 cases they were not chosen on. Every case runs twice: with
the fixture's staggered path searches, and with every route ready on tick 1.

| Crowd lab (deadlocked cases) | Before | After |
|---|---|---|
| Set 1 (28 cases; the tuning set) | **5** | **0** |
| Set 2 (24 unseen cases) | **11** | **0** |

Before, even staggered starts deadlocked 60v60, 80v80, 100v100 and mixed-size counterflows. Allies
now come no closer than 64–65% of their combined radii. Normal crowds spend 0–5% of unit-ticks
squeezed; only the 160–200 unit counterflows through one two-cell gap reach 13–14%.

| Crowd suite, arrival ticks | Before | After |
|---|---|---|
| Chokepoint 5 / 20 / 100 | 340 / 460 / 1,326 | 340 / 459 / 1,193 |
| 20 mixed sizes | 705 | 720 |
| 50 v 50 counterflow | 849 | 856 |
| Open 100 | 445 | 425 |
| 50 v 50 counterflow, every route on tick 1 | never (38 stuck) | 832 |
| 20 mixed, every route on tick 1 | 1,129 | 647 |

**Cost.** The first version added ~50% more spacing and distance checks per tick in the 240-unit
benchmark, because the push pass tested every allied neighbour. Rewritten for the common miss, it
now adds about 2% (spacing checks 3,588 → 3,676 per tick), with identical attacks and movement
before and after the rewrite. Wall-clock A/B, five alternating pairs of the 2,000-tick benchmark, was
bimodal: every run was either near 6 ms p50 or throttled to 21–56 ms. Unthrottled runs: previous commit
6.0 / 6.5 / 6.8 ms, this change 5.7 / 6.2 ms. The medians over all five (6.8 vs 21.2 ms) mostly
record which runs were throttled, so the call counts are the evidence here.

**Bot matches changed, and the cause is the bot.**

| Balance match (one seed) | Before | After |
|---|---|---|
| Mirror | 14:03, player 2 by control | **7:16, player 1 by control** |
| Asymmetric | 9:17, player 1 by control | **7:17, player 1 by control** |

A capture timeline shows why. At 5:17 player 1 took the second point. Player 2's army was standing
in the first, 109/200 of the way to capturing it, and walked off to cross the map to the other one,
because the bot targets the unowned point nearest its *headquarters*. The hold ran out while it was
on the road. Movement only changed which match history hit this. A bot fix (finish a capture under
way, otherwise the point nearest the army) was tried and reverted: both matches then ran to the
25-minute cap unfinished, with 23 holds started and all 23 broken, because both bots always go for
points before bases. That is a bot-strategy and pacing question for the user, recorded in
[docs/ITERATION_LOG.md](docs/ITERATION_LOG.md).

Verified:
- New crowd tests: allies that start together pass in a gap; a jam neither restarts searches nor
  empties waiting units' paths. Both failed on the previous commit and pass now.
- `S.clearance` now holds allies to the pressed floor rather than the usual spacing.
- crowd **20/20**, quick **80/80**, balance **4/4**, determinism **5/5**, network **4/4**, scenario
  **2/2**, soak **1/1**.

Not verified: how 65% looks on screen with real sprites (generated art is absent on this machine).
