# Combined controls and Megacorp build

Branch: `codex/overnight-controls-performance`. Integration starts at the art/drop-pod
commit `fd851d4` and merges controls `541498d`. Simulation 29 / content 16 rejects older
recordings explicitly. Economy, roster, combat numbers, 20 Hz simulation and network
lookahead are unchanged. Generated assets and evidence remain outside tracked source.

## Integration

Shared searches match owner, group, radius, direction and navigation version. Vehicle
followers retain clearance offsets and validate their suffix from the actual end of the
shared route. Required clearance cannot fail because optional smoothing exhausted its
budget. New regressions reproduced both defects before the fixes and pass afterwards.

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
16.667 ms. Profiled runs are diagnostic only. The final evidence and package identity
will be recorded below after verification.
