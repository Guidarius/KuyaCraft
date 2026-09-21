# Responsive control

The original controls checkpoint used simulation 28 / content 15. The combined Megacorp build uses simulation 30 / content 16; see OVERNIGHT_HANDOFF.md for integration evidence and current limitations.

The target is Brood War style pace and individual unit control. Coarse navigation is a performance compromise, not a desired interaction. This change retains 20 Hz simulation, integer subpositions, the cell navigation grid, existing attack commitment and network lookahead. Earlier replays and snapshots require their original build; no golden result was overwritten.

## Behavior

- Shipping selections retain each unit's own speed. Optional formation pacing remains available to content, keyed by player plus group so an opponent cannot slow your army.
- Move, attack-move and patrol preserve the clicked subcell offset in the assigned destination slot. Unsafe endpoints fall back to that slot's center. A second click within the same cell can change the destination. Queues, patrol reversals and snapshots retain the endpoint.
- Nearby units in the same player/group can share a pending terrain search when radius, lane direction and navigation version match. Each follower gets its own validated connectors, copied path, destination and local steering. Congestion reroutes remain independent. Leader cancellation, death and terrain changes promote/revalidate searches deterministically.
- A stable active-search schedule avoids repeatedly scanning every entity per expansion. The A* budget remains 256 expansions/tick in shipping content. Shared-route connectors consume the existing direct-route budget. Every optional smoothing sample, including failed probes, consumes the smoothing budget; exhaustion retains the unsmoothed remainder. Required vehicle clearance checks have their own reported counter and remain bounded by direct-route/expansion work; optional smoothing exhaustion cannot reject a required route.
- Destination reservations use per-player reference counts during command application, updated as orders replace or append. A non-destination command invalidates the cache because it may change other entities' reservations. Scratch state is removed before snapshots.

The 64-cell wall-detour regression enforces first actual displacement within 40 ticks for 1/12/24/48 workers. All four measured 14 ticks (0.70 simulated seconds), versus the audited 48-worker p95 of 30.55 seconds. This is a synthetic navigation test, not a claim about all map situations. The original small-radius mixed 50-versus-50 two-cell choke completed at tick 874. With the integrated radius-160 Enforcer, two opposing vehicles cannot pass side by side in a two-cell opening. Infantry counterflow completes at tick 615; the heavy counterflow recovery fixture redirects one army at tick 1501 and all units register arrival by tick 1954. Dense unassisted heavy counterflow remains a known limitation, including the tested three-cell opening.

## Performance and tooling

The host JIT limits rise from 4,000 traces / 4 MiB machine code to 16,000 / 16 MiB. These are capacity limits; arithmetic optimizations and gameplay are unchanged. A diagnostic shipping battle went from 12 cache flushes / 44,967 successful traces to zero flushes / 11,950 successful traces. The diagnostic hooks affect timing, so the uninstrumented runs are the acceptance evidence.

`tests/ui_benchmark.lua` now drives `App:update` and `App:draw`. It includes selection, hover, view/observation, feedback, juice, audio and replay recording. It uses scripted commands in place of the bot and excludes network costs. The Orders view and Megacorp orbital sidebar are both exercised, with 240 mixed units and default presentation settings. The benchmark asserts that effects observation and recording actually ran. CPU draw submission is not GPU time.

Run:

```powershell
.\scripts\test-all.ps1
.\scripts\test-performance.ps1
```

The second script runs three fresh shipping simulation processes and two live 1080p benchmarks. Default gates are simulation p95 < 10 ms and frame cadence p95 <= 16.667 ms. Logs are under ignored `artifacts/performance-*.log`. Hardware-specific budgets can be supplied explicitly; they must not be used to conceal a failing reference result. Trace diagnostics are available with `--test balance --filter 'active performance' --profile-sim traces`.

Fresh-process determinism workers now also compare 1,800 ticks of shipping route sharing, cancellation, death, terrain invalidation and restoration, alongside the existing 100,000-tick checks.

## Limits

The frame-time target is separate from simulation responsiveness. See the dated STATUS entry for actual results and failures. There is no claim of verified human micro feel, real two-PC latency or faction balance. Combat/economy numbers are unchanged. Coverage/vision union caching, historical-entity iteration, further movement scratch reduction and firing-position retry tuning remain candidates for a subsequent measured optimization pass.
