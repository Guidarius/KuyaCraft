# Combined controls and Megacorp build

Branch: `codex/overnight-controls-performance`. Integration starts at the art/drop-pod
commit `fd851d4` and merges controls `541498d`. Simulation 30 / content 16 rejects older
recordings explicitly. Economy, roster, combat numbers, 20 Hz simulation and network
lookahead are unchanged. Generated assets and evidence remain outside tracked source.

## Integration

Shared searches match owner, group, radius, direction and navigation version. Vehicle
followers retain clearance offsets and validate their suffix from the actual end of the
shared route. Required clearance cannot fail because optional smoothing exhausted its
budget. New regressions reproduced both defects before the fixes and pass afterwards.

A reproduced garrison defect is fixed: an explicit garrison order suppresses new
enemy acquisition on the way into the building. It no longer alternates a route to
the bunker with a route toward a nearby enemy. Existing attack commitment is unchanged.
The mixed-pod regression now crosses a two-cell gap, returns to a bunker, garrisons
all three infantry types, unloads them with clearance and verifies restoration.

The radius-160 Enforcer keeps its current scale, selection ring and collision body.
Two-cell passage traversal, terrain updates and unloading retain hard clearance.
Infantry counterflow (50 per side) arrives at tick 615. The heavy recovery fixture
redirects one side at tick 1501; all arrivals are registered by tick 1954. It checks
clearance and retained orders throughout. Arrival is recorded when each unit reaches
its destination, before a later auto-acquisition can take it away again.

**Remaining movement limitation:** opposing dense heavy armies can jam without player
intervention, even at the tested three-cell gap. Two opposing Enforcers need 640
subunits to pass side by side; a two-cell opening is only 512. No collision radius or
clearance rule was relaxed. The old test used radius-96 Enforcers and was not a valid
acceptance claim for the new models. Infantry keeps the original two-cell arrival gate;
vehicle congestion is tested for safe retention and recovery, not claimed solved.

## Repeatable morning playtest (five minutes)

Launch `LoveRTS.exe --micro-lab --width 1920 --height 1080`, or from source:
`.tools/love-11.5-win64/lovec.exe . --micro-lab --width 1920 --height 1080`.
This practice fixture starts with Associates, Medics, two Enforcers, a bunker, production
buildings and 5,000 of each resource. The opponent holds position. Unit statistics are
normal. Restart the command to reset. Practice recordings are not exported; use a
normal skirmish for replay testing.

1. **0:00-1:00 — precision.** Select one Associate. Right-click several nearby points
   inside the same terrain cell, reverse direction rapidly, then use Stop and Hold.
   Check the selection circle, immediate order acknowledgement and exact final point.
2. **1:00-2:00 — retreat.** Move east toward the four enemy Footmen. Issue retreat
   before a shot begins, during its windup and after it commits. Damage should follow
   the existing commitment rules; repeated cancels must not create free attacks.
3. **2:00-3:00 — mixed movement.** Select Associates, Medics and Enforcers. Send them
   through the two-cell opening in the wall, then return via the wider opening south.
   Check that infantry can pull ahead, heavy bodies clear walls and pending orders
   survive queues. Shift-click a return destination and compare Move/Stop/Hold.
4. **3:00-4:00 — building traffic.** Move around the bunker north of the army. Garrison
   an Associate and Enforcer, then unload. Check spacing, picking and selection rings.
5. **4:00-5:00 — pods.** Use the orbital sidebar to load an Associate, Medic and Enforcer.
   Launch onto covered ground west of the wall. Check descent, doors, team color,
   ground anchor and troop placement, then move the newly landed group through a gap.

Human feel, faction balance and real two-PC latency/jitter remain separate acceptance
work. Automated command/input timing cannot establish those judgments.

## Reproducing performance

Use the pinned LOVE 11.5 runtime and a validated active asset catalog. Run benchmarks
sequentially with no Blender export or competing test process:

```powershell
$env:APPDATA=Join-Path $PWD 'artifacts/test-userdata'
./scripts/test-performance.ps1 -Runs 3 -LiveRuns 3 -RequireAssets -OutputDirectory artifacts/overnight/baseline
```

Each fresh simulation runs 2,000 ticks with 240 units. Each faction's live benchmark
runs 600 ticks at 1080p through App:update/draw with selection, fog, effects, audio,
orbital UI where applicable and replay recording. The Megacorp mix includes the current
Enforcer body. Reports contain p50/p95/p99/max, whole-tick and phase costs, draw calls,
sampled heap, texture memory, clamped time, canonical checkpoints and catalog identity.
The environment manifest records revision, dirty files, CPU/GPU, memory and runtime.
Heap samples are not retained-memory evidence. The separate production soak explicitly
collects garbage and reports retained versus reclaimed memory.

Default gates remain simulation p95 below 10 ms and rendered frame p95 at most
16.667 ms. Profiled runs are diagnostic only. Detailed results are in
[OVERNIGHT_PERFORMANCE.md](OVERNIGHT_PERFORMANCE.md).


## Final verification and limits

- `scripts/test-all.ps1`: PASS. 190 headless checks; four fresh 100,000-tick
  determinism processes (30/60/144 FPS schedules and default/tuned JIT); shipping
  shared-route checkpoints; real local ENet host/client agreement; rendered suites
  at 1280x720, 1920x1080 and 2560x1080; actual asset presentation tests.
- Active catalog validation: PASS, all 20 active assets. Python asset tests:
  32 passed. No Blender rebuild was necessary; existing validated assets were preserved.
- Seed-725 production/combat soak: 12,000 ticks, exact restores at 4,000 and 8,000,
  24 fresh-replay checkpoints, 1,632 attacks. Orders produced 49 units with 42 deaths
  and 28 later production events; Megacorp produced 54 with 14 deaths and 12 later
  production events. Both built new buildings. All 12,000 command frames and 24
  authoritative hashes match the clean baseline soak.
- Retained heap was measured after GC separately from reclaimed temporary memory.
  In the final full-suite process, retained heap was 25,744.8 KiB before this soak,
  24,003.0 KiB with world and recording at tick 12,000, and 20,581.5 KiB after
  releasing them. Prior suite/module/JIT caches make these values unsuitable for
  claiming zero leaks or comparing fresh-process allocation rates.
- Worker wall detour: all 1/12/24/48-unit groups began actual movement by tick 14.
  Commitment, cooldown preservation, fog/target loss, same-cell destinations,
  queued continuation and mixed pod/choke/garrison/unload regressions passed.

Final performance remains a failed acceptance gate. Below are medians of three
per-run p95 values, in milliseconds; the final source retains the baseline
implementation, so timing differences are not an optimization benefit.

| Metric | Integration baseline | Final retained build | Gate |
|---|---:|---:|---:|
| Orders live Sim.step | 7.95 | 10.52 | <10 |
| Orders frame | 17.76 | 18.15 | <=16.667 |
| Megacorp live Sim.step | 7.81 | 10.44 | <10 |
| Megacorp frame | 18.01 | 19.02 | <=16.667 |

All six final live frame gates and five live simulation gates failed. All three
headless gates passed. Both attempted optimization targets were reverted after
inconsistent or adverse results. No game speed, network lookahead, attack stats,
vision rules, effects or collision bodies were weakened to improve scores.

Dense heavy counterflow, human mouse-and-keyboard feel, balance and real two-PC
latency/jitter remain outstanding. The functional checks above do not certify them.

## Windows package

Extract the complete delivered ZIP and double-click `LoveRTS.exe` for the normal
menu, or `PlayMicro.cmd` for the five-minute practice scene above. Keep the DLLs
beside the executable. `BUILD-INFO.json` records the exact clean source commit,
LOVE version, executable/archive hashes and active catalog identity. The package
contains only validated active asset builds. The accompanying evidence archive
contains raw performance and verification logs.

Work is pushed to `codex/overnight-controls-performance`; master was not merged.
Draft PR creation was attempted but GitHub returned HTTP 403, “Resource not
accessible by integration.” The branch remains available for review.


Packaged build `LoveRTS-20260921-003836` was produced from clean commit `46e914b`.
Its fused executable passed the rendered suite (both shipping faction views, replay
seek and Megacorp pod presentation), plus separate practice and production-replay
launches. The latter two screenshots were visually reviewed. The packaged unit suite
passed 25 checks. Every packaged source Lua file and all 106 active asset files
were compared byte-for-byte/hash-for-hash with the tested working tree. The package
includes the compatible `artifacts/overnight-soak.replay` and `VERIFICATION.json`.
The replay launch smoke is separate from the full 12,000-tick source replay proof.
