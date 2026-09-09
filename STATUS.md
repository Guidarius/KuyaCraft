# Implementation status



This repository contains the accepted roadmap and a playable **prototype**, not a completed release. Milestones have explicit validation limits below.



## Delivered



- Project-local, checksum-pinned LÖVE 11.5 Windows x64 runtime and repeatable setup.

- Git initialization, Lua editor configuration, development rules, launch/test/replay scripts.

- Pure Lua authoritative simulation: 20 Hz ticks, integer positions and quantities, Park–Miller PRNG, stable IDs and ordering, bounded incremental A*, radius-aware local movement, snapshots, canonical encoding.

- Workers, gold/lumber nodes, carrying/delivery, construction, recruitment, refunds, population limits.

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



- Bot games finish in roughly 2–3 simulated minutes, much shorter than the 15–25 minute target. Costs, damage, map size, hero progression, and economy need playtesting.

- Unit collision uses soft allied compression, hard enemy/terrain clearance, persistent destination slots and bounded local steering/rerouting. The finite crowd fixtures pass; universal liveness and polished continuous-motion behavior are not proven. Terrain-unreachable slots can still fail explicitly.

- Combat now has integer windup, impact and recovery, cancellation semantics and phase-driven animation. Projectile travel remains outside the simulation.

- Passive mechanics are focused Lua implementations, not a generalized ability framework.

- Fog uses radial visibility on flat terrain, without obstacle line-of-sight. Filtered observation memory supplies last-seen enemy-building/resource/camp minimap markers.

- Native multiplayer is 1v1. The simulation accepts four players; interactive 4-player matches are not yet exposed.

- Desync reports identify the first **observed checkpoint**, preserve each peer's local state and replay, and allow subsystem-path comparison. Automatic exchange of both states and exact first-divergent-tick bisection are not implemented.

- Network tests cover in-process reordered/duplicate/delayed batches and real local reliable ENet. They do not constitute a long unreliable-network soak or public-service hardening.

- The v2 catalog maps shieldguards, unloaded/loaded workers, crossbows, and Warden to Blender sprites. Other faction units and buildings retain procedural presentation. Nonverbal synthesized sound, positional effects and volume settings are enabled. All five assets are published and validated.

- Generated atlases and editable recipe output are ignored by Git. Obtain the pinned local source library and run export-assets.ps1 after cloning to regenerate them; see tools/blender/README.md.

- Source updates can invalidate replays because compatibility includes the exact authoritative source fingerprint.

- No public lobbies, NAT traversal, accounts, reconnect, host migration, ranked play, or persistent player saves.



## Next engineering work



1. Run the same package on a second Windows PC; compare full-match hashes and record hardware/network conditions.

2. Playtest the mirror matchup and tune toward the intended match duration.

3. Playtest the movement-lab map, opposing chokepoints and final-slot tolerance; tune movement quality from observed cases.

4. Review attack animation contact, audio mix and command latency with human players.

5. Extend content validation and ability-combination tests as faction rules grow.

6. Reduce active-battle maximum-step spikes and rendered frame hitches; extend session/network soaks before increasing content scope.



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
