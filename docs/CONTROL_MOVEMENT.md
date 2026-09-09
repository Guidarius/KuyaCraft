# Control and movement implementation



Simulation version 3 implements the accepted core-control plan. The existing 20 Hz step, integer arithmetic, shared command stream and three-tick network lookahead remain in use. This source/content change intentionally invalidates earlier snapshots and replays; it does not silently migrate them or replace a golden result.



## Orders and attacks



- Move cancels windup/recovery and excludes automatic acquisition. Equivalent active Move/Attack commands preserve progress; non-appended commands still clear the queued tail.

- Stop cancels and clears orders immediately, suppresses acquisition for its execution tick, and subsequently allows bounded automatic combat. Hold clears orders and never moves or yields, including while firing. Workers retain their existing explicit-attack-only behavior.

- Attack-move retains its destination during combat. Automatic targets persist while valid; explicit targets take precedence. Automatic pursuit uses a three-cell engagement leash, while enemies already in firing range remain valid. Explicit visible targets can be pursued farther.

- Windup is explicitly four ticks in the current content, preserving the latest UI/combat baseline. A command on the impact tick executes before combat and cancels the uncommitted hit. Commit starts the cooldown; the next windup can begin early enough to preserve the definition's commit-to-commit period. Cancelling never resets an existing cooldown.

- Range is checked again at commit, including visibility and target life. Hits committed on the same tick are accumulated before deaths. The simultaneous-death fixture first establishes visibility, then aligns windups; this fixes an asymmetric setup assumption without forcing differently timed attacks to tie.

- The 32-subunit range margin only permits a two-tick movement grace at the edge; it never extends damage range. Economy, aura, healing and XP ranges retain their separate rules.

- Shift queues remain capped at 32. Movement commands carry an optional positive integer `args.group`, with requested cells and assigned slots retained in the order. Slots are reserved by active and queued own-unit orders, assigned deterministically, and released on replacement, completion or death. UI selection is issued in stable ID order. Commands retain the existing player/sequence execution order.



## Geometry and navigation



- Ordinary units and heroes have an 80-subunit radius; rams and heavy beasts use 112. Allies can compress to 75% of combined radii; enemy bodies retain full separation. Terrain/buildings remain solid. Spawn, revival, construction footprints and recruitment exits use body clearance.

- Weapon definitions now express edge range. Values are unchanged: ordinary unit-to-unit center reach therefore increases by 160 subunits (0.625 cells); an ordinary attacker gains 80 subunits against a building footprint. Large-unit combinations use their actual radii. These intentional range changes require human balance review.

- Incremental A* no longer freezes mobile occupancy into an impassable mask. It retains the 64-expansion tick budget, with a deterministic binary heap for the open set. A separately bounded 16,384-cell direct-route probe budget starts clear-terrain moves on their command tick; general searches remain incremental. Nearby congestion adds bounded reroute costs; search state remains in snapshots.

- Local movement uses integer vectors, fixed candidate order, spatial bins, frozen candidate proposals and longest-wait/stable-ID conflict resolution. Directional sprites do not constrain motion.

- Two-cell passages and their two-cell approaches use a static keep-right rule to separate opposing traffic. Mid-passage reversals can leave their previous lane. This is deliberately a focused navigation rule, not a general traffic scheduler.

- Ten ticks without waypoint progress trigger detour/yield attempts. Global congestion retries are limited to once per twenty ticks; unavailable firing-position retries are staggered deterministically over 20–26 ticks. Stopped allies can yield within one cell of their yield origin; Hold units cannot. After ten blocked ticks, a unit within its radius plus 32 subunits of its final slot may finish there; subsequent yielding stays within one cell of the slot. More distant temporary crowding keeps the order pending. Exhausted terrain searches report failure and advance the queue.

- Searches beginning inside their destination cell still route to its center. This prevents a subcell-position retry from declaring arrival prematurely.



## Verification and operation



`scripts/test.ps1` runs the existing suites plus the new control, crowd, soak and active-performance fixtures. `-Suite crowd`, `-Suite soak`, and `-Suite performance` run focused checks. Generated results stay under ignored `artifacts/`.



Crowd acceptance requires every unit to finish its order within 6,000 ticks and remain within one cell of its assigned slot (the explicit idle-yield allowance). Tests check hard body/terrain clearance, bounded expansions, and absence of silently abandoned orders. They cover 1/10/50/100-unit arrivals, 5/20/100-unit chokepoints, mixed sizes/speeds, 50-versus-50 counterflow, a Hold blocker, death inside a choke, reversal, and the movement-lab obstacles.



Focused regressions cover spammed commands, cancellation before/on/after commit, target priorities, fog and death, bounded chase, 50-unit ranged retreat, queue continuation, snapshots during congestion/windup and different entity insertion histories. The command soak runs 100 units for 10,000 ticks with seeded commands and checks retained memory. The active benchmark retains 240 units with high HP for 10,000 ticks, alternating 300 attack-move ticks and 100 retreat ticks. It reports both p95 and maximum step cost and requires actual attacks and movement. Its report is `artifacts/control-performance.txt`.



The rendered input suite exercises 30/60/144 FPS update schedules, one-tick offline execution, four-tick execution with the existing three-tick lookahead, backlog retention, Hold, and the F3 inspector. Its in-process lockstep stub tests scheduling; separate ENet processes test transport with Move/Hold/Toggle commands.



Final results are recorded in STATUS.md. Human continuous-motion review, subjective stutter-step feel, and repeated matches on two physical Windows PCs remain separate acceptance gates. Projectile travel, patrol/follow, elevation, rollback and broad balance tuning remain deferred.



Optional hotspot sampling uses the [official LuaJIT profiler API](https://luajit.org/ext_profiler.html). Run the pinned executable with `--test performance --filter "240 active" --benchmark-ticks 2000 --profile-sim` for a short diagnostic; acceptance uses the uninstrumented 10,000-tick default.



The host now configures a bounded 4,000-trace / 4 MiB machine-code cache for the pinned LuaJIT runtime using its [documented optimization parameters](https://luajit.org/running.html). This configuration is shared by game, tests and packages; arithmetic optimization flags stay at defaults. An additional fresh-process worker verifies identical canonical checkpoints with the original JIT cache settings.


## Measured acceptance results

The full local run passed **60 tests**. Four fresh processes matched 100,000-tick checkpoints across 30/60/144 FPS scheduling and default/tuned JIT cache settings; a real local ENet pair matched through 600 ticks with Move/Hold/Toggle commands. The rendered regression also passed, including Hold, F3, backlog retention and input scheduling. No golden replay was replaced.

| Fixture | Result |
|---|---|
| 100 units, open arrival | All arrived by tick 932 |
| 100 units, choke | All arrived by tick 1,640 |
| 20 mixed units | All arrived by tick 1,900 |
| 50 versus 50 counterflow | All arrived by tick 4,079 |
| 100 units, seeded command soak | 10,000 ticks; retained heap 5,058 / 5,335 KiB at midpoint/end |
| 240 live units, active 10,000-tick battle | 4.197 ms p50; 6.711 ms p95; 121.046 ms maximum |
| Active-battle work and memory | 29,352 attacks; lead moved 5,796 ticks; retained heap 5,459 / 4,484 / 4,366 KiB |

The active test meets its 10 ms p95 requirement on the recorded hardware. Its 121 ms maximum is still a hitch risk. Timing excludes renderer, bots, transport and replay encoding. A separate 600-tick rendered 1080p battle averaged about 54 FPS, with simulation p95 19.778 ms and frame cadence p95 43.173 ms; stable 60 FPS remains unmet. These fixtures establish bounded, reproducible scenarios, not a proof that every possible crowd configuration resolves. See STATUS.md for workload details and remaining human/cross-PC gates.
