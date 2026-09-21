# Overnight performance evidence

No new performance optimization was retained. The vision-union candidates varied across fresh processes; the explicit entity-view copy reduced typical view cost but worsened its tail costs without a repeatable frame improvement. Both targets were restored to the integrated implementation. No budgets, VSync setting, simulation frequency, lookahead, effects or collision bodies were reduced.

## Measurement conditions

Windows 11 Home; Ryzen 5 5600G; RTX 3060 (OpenGL driver 591.86 / Windows 32.0.15.9186); 25,601,957,888 bytes system RAM. LOVE 11.5, 1920x1080, VSync 1, 240 initial units, seed and scripted commands fixed by the benchmark. Three fresh 2,000-tick headless processes and three fresh 600-tick live processes per faction, sequentially. Live runs use actual sprites, selection, fog, sidebar, effects, audio and replay recording. They exclude networking and replace the bot with fixed commands.

Active catalog SHA-256: `3808FE0062712E80EE33E112829A9CA0ACED0B3E9EF9D0B60D468122D9324B6F`. Asset-file manifest SHA-256: `21669EDA5A583BF204A944C1A4A339EE516F96B5A995EDB41DCE291FAE5F6936`. Both sets use identical assets and canonical benchmark checkpoints.

Baseline: clean commit `9415109`, simulation 30 / content 16. Rejected projection candidate: clean commit `7909306`. Earlier runs with screenshot capture inside the timing interval are excluded here; benchmark screenshots now happen after reporting. The final retained source is the baseline implementation plus packaging/documentation changes.

## Baseline versus rejected view-copy candidate

Each cell below is the median of the three per-run percentiles; max is the largest observed sample across all three runs. These are not pooled percentiles. Times are milliseconds; heap values are KiB.

| Build | Faction | Metric | p50 | p95 | p99 | Observed max |
|---|---|---|---:|---:|---:|---:|
| Baseline | orders | step_ms | 4.446 | 7.949 | 13.222 | 63.906 |
| Baseline | orders | whole_tick_ms | 5.978 | 11.169 | 17.309 | 71.542 |
| Baseline | orders | frame_ms | 16.686 | 17.764 | 20.972 | 178.083 |
| Baseline | orders | draw_ms | 14.312 | 15.463 | 15.975 | 115.404 |
| Baseline | orders | view_ms | 1.228 | 2.345 | 7.410 | 28.843 |
| Baseline | orders | events_ms | 0.008 | 0.045 | 0.161 | 1.025 |
| Baseline | orders | feedback_ms | 0.102 | 0.234 | 0.552 | 1.717 |
| Baseline | orders | replay_ms | 0.004 | 0.009 | 0.055 | 11.730 |
| Baseline | orders | draw_calls | 150.000 | 166.000 | 168.000 | 168.000 |
| Baseline | orders | sampled_heap_kib | 40724.062 | 57358.378 | 61044.921 | 66012.568 |
| Baseline | megacorp | step_ms | 4.303 | 7.813 | 11.324 | 67.493 |
| Baseline | megacorp | whole_tick_ms | 5.780 | 11.003 | 17.830 | 72.735 |
| Baseline | megacorp | frame_ms | 16.620 | 18.006 | 21.543 | 177.037 |
| Baseline | megacorp | draw_ms | 14.167 | 15.425 | 15.908 | 101.930 |
| Baseline | megacorp | view_ms | 1.261 | 2.305 | 8.129 | 10.747 |
| Baseline | megacorp | events_ms | 0.013 | 0.046 | 0.264 | 0.868 |
| Baseline | megacorp | feedback_ms | 0.137 | 0.350 | 0.821 | 1.892 |
| Baseline | megacorp | replay_ms | 0.004 | 0.007 | 0.055 | 17.301 |
| Baseline | megacorp | draw_calls | 374.000 | 378.000 | 378.000 | 378.000 |
| Baseline | megacorp | sampled_heap_kib | 41880.342 | 59266.795 | 63455.283 | 69288.998 |
| Rejected copy | orders | step_ms | 5.076 | 8.383 | 12.877 | 90.275 |
| Rejected copy | orders | whole_tick_ms | 5.934 | 11.709 | 19.434 | 95.834 |
| Rejected copy | orders | frame_ms | 16.651 | 17.786 | 22.021 | 267.927 |
| Rejected copy | orders | draw_ms | 14.322 | 15.488 | 15.873 | 118.291 |
| Rejected copy | orders | view_ms | 0.582 | 1.508 | 10.186 | 28.796 |
| Rejected copy | orders | events_ms | 0.008 | 0.034 | 0.167 | 0.342 |
| Rejected copy | orders | feedback_ms | 0.097 | 0.202 | 0.416 | 2.139 |
| Rejected copy | orders | replay_ms | 0.004 | 0.009 | 0.088 | 16.190 |
| Rejected copy | orders | draw_calls | 150.000 | 166.000 | 168.000 | 168.000 |
| Rejected copy | orders | sampled_heap_kib | 40578.273 | 57635.996 | 61362.930 | 70489.595 |
| Rejected copy | megacorp | step_ms | 4.574 | 8.021 | 13.227 | 95.991 |
| Rejected copy | megacorp | whole_tick_ms | 5.437 | 11.353 | 19.320 | 99.995 |
| Rejected copy | megacorp | frame_ms | 16.619 | 17.947 | 22.049 | 186.266 |
| Rejected copy | megacorp | draw_ms | 14.226 | 15.451 | 15.876 | 106.133 |
| Rejected copy | megacorp | view_ms | 0.577 | 1.424 | 9.108 | 15.560 |
| Rejected copy | megacorp | events_ms | 0.012 | 0.038 | 0.206 | 0.571 |
| Rejected copy | megacorp | feedback_ms | 0.120 | 0.257 | 0.633 | 1.790 |
| Rejected copy | megacorp | replay_ms | 0.004 | 0.009 | 0.042 | 17.797 |
| Rejected copy | megacorp | draw_calls | 374.000 | 378.000 | 378.000 | 378.000 |
| Rejected copy | megacorp | sampled_heap_kib | 41722.353 | 59145.415 | 63379.384 | 73184.458 |

All six baseline and all six candidate rendered runs fail the unchanged 16.667 ms frame-p95 gate. Their simulation-p95 gates pass. The 10 ms simulation gate covers Sim.step; whole-tick costs include view, feedback and recording and can exceed it. Headless p95 baseline: 7.678 / 5.314 / 5.608 ms; rejected copy: 6.034 / 6.383 / 6.140 ms. The candidate does not run view copying in the headless benchmark, so those differences are measurement variation, not an optimization benefit.

View-copy p95 fell from 2.003–2.363 to 1.072–1.947 ms for Orders, and 2.206–2.379 to 1.334–1.702 ms for Megacorp. However, median view p99 rose from 7.410 to 10.186 ms and 8.129 to 9.108 ms respectively. Median whole-tick p99 also rose, and frame-p95 distributions overlap. Given the priority on spikes and responsiveness, the candidate was rejected.

## Remaining bottlenecks and measurement limits

- Sampling attributed roughly 47.5% of a live run to the terrain canvas draw call and its C/driver work. A diagnostic VSync-off run reduced draw-submission p95 from about 15.4 to 4.8 ms. This indicates synchronization/driver waiting is substantial; it is not a GPU-time measurement, not an accepted gate run, and VSync remains enabled.
- Headless phase profiling found movement and combat orders among the largest costs; visibility also contributed. The two visibility-union approaches preserved checkpoints but did not improve performance consistently. They were reverted. Further movement changes would exceed the authorized safe optimization scope.
- Both factions loaded 49 images and 25 canvases, reporting 260,707,712 texture bytes. Draw calls and temporary heap measurements are in the table and raw logs. Lua heap samples measure allocation footprint, not cumulative bytes allocated or a retained-memory leak.
- Cold startup, JIT compilation and replay checkpoints remain in the timing interval. Tail values are reported rather than removed as outliers. Screenshot capture is outside the interval.
- The production soak reports post-GC retained memory separately from temporary reclamation. It retains intentional entity history and replay frames; surviving module/JIT caches mean that releasing the world is not a proof of zero leaks.

## Reproduction and raw evidence

Run `scripts/test-performance.ps1 -Runs 3 -LiveRuns 3 -RequireAssets -OutputDirectory artifacts/overnight/final` with the pinned runtime and active catalog. Each run writes distributions, canonical checkpoints, renderer details, clamp totals and discarded-backlog counts. `performance-environment.json` ties it to the exact revision and settings; `asset-files.json` lists all active asset hashes. Hardware was captured separately in `hardware.json` because the sandbox denied the benchmark script CIM queries.

Generated logs, screenshots and packages are intentionally ignored by Git. The delivered evidence archive includes the clean baseline, rejected projection, final runs, soak comparison and verification logs.

## Final retained build: acceptance results

Clean benchmark commit: `df6de37053e6789bc5649ebddeb0e23bb05ee445`. Git-normalized simulation and presentation sources match the clean integration baseline `9415109`. Later commits only record the handoff. This final pass nevertheless measured slower; the cause of this timing variation has not been isolated. No performance improvement is claimed. Defaults are copied fresh for every benchmark: 24 selected units, gameSpeed index 2, edge scrolling and day/night disabled by the existing benchmark, VSync 1.

**Acceptance failed:** all six live frame-p95 gates and five of six live Sim.step-p95 gates failed. All three headless simulation runs passed. The all-green functional suite is separate from these failed performance gates.

| Faction | Run | Sim p95 ms | Whole tick p95 ms | Frame p95 ms | Frame max ms | Clamped seconds |
|---|---:|---:|---:|---:|---:|---:|
| orders | 1 | 10.360 | 14.102 | 18.023 | 200.178 | 0.000 |
| orders | 2 | 10.518 | 15.302 | 19.039 | 255.459 | 0.005 |
| orders | 3 | 10.671 | 14.304 | 18.155 | 272.961 | 0.023 |
| megacorp | 1 | 10.438 | 14.245 | 19.017 | 214.389 | 0.000 |
| megacorp | 2 | 14.258 | 18.883 | 21.268 | 377.568 | 0.128 |
| megacorp | 3 | 6.708 | 10.549 | 18.046 | 201.022 | 0.000 |

Final headless Sim.step p95: 6.750 / 9.496 / 5.910 ms. All final canonical checkpoint lists and active asset-file hashes match the baseline. No discarded backlog ticks were reported; accumulated clamped time was 0.028 s for Orders and 0.128 s for Megacorp. Texture memory remains 260,707,712 bytes.

Final distribution summary uses the same median-of-three percentile / observed-maximum convention as above.

| Faction | Metric | p50 | p95 | p99 | Observed max |
|---|---|---:|---:|---:|---:|
| orders | step_ms | 5.958 | 10.518 | 15.553 | 84.189 |
| orders | whole_tick_ms | 7.818 | 14.304 | 21.978 | 92.159 |
| orders | frame_ms | 16.633 | 18.155 | 24.023 | 272.961 |
| orders | draw_ms | 13.944 | 15.469 | 15.992 | 183.859 |
| orders | view_ms | 1.925 | 3.094 | 8.754 | 14.635 |
| orders | events_ms | 0.010 | 0.069 | 0.249 | 2.552 |
| orders | feedback_ms | 0.129 | 0.347 | 0.615 | 4.820 |
| orders | replay_ms | 0.006 | 0.013 | 0.086 | 13.506 |
| orders | draw_calls | 150.000 | 166.000 | 168.000 | 168.000 |
| orders | sampled_heap_kib | 36782.304 | 52295.261 | 55474.983 | 62727.514 |
| megacorp | step_ms | 5.999 | 10.438 | 14.143 | 66.493 |
| megacorp | whole_tick_ms | 7.697 | 14.245 | 22.789 | 78.792 |
| megacorp | frame_ms | 16.634 | 19.017 | 25.595 | 377.568 |
| megacorp | draw_ms | 13.670 | 15.566 | 16.052 | 126.918 |
| megacorp | view_ms | 1.430 | 3.061 | 8.610 | 12.234 |
| megacorp | events_ms | 0.013 | 0.062 | 0.256 | 0.448 |
| megacorp | feedback_ms | 0.134 | 0.379 | 0.701 | 4.078 |
| megacorp | replay_ms | 0.004 | 0.009 | 0.047 | 18.785 |
| megacorp | draw_calls | 374.000 | 378.000 | 378.000 | 378.000 |
| megacorp | sampled_heap_kib | 35604.576 | 58445.154 | 61981.408 | 68793.900 |
