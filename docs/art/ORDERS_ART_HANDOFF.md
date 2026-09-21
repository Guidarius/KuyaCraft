# Orders cathedral art handoff — 2026-09-21

Six unit variants and four buildings are published in the active catalog, including
the ground-mounted Gryphon, floating Reliquary and three construction stages per building.
All 15 existing Megacorp entries and legacy Shieldguard/Warden entries are retained.
No gameplay, footprint, radius, command, simulation or network contract changed.

## Play and review

Unzip the Windows package and keep its DLLs beside LoveRTS.exe. Launch PlayOrders.cmd
for a playable army/construction scene, ReviewOrders.cmd for comparisons, or LoveRTS.exe
for normal skirmish and replay playback. The five-minute checklist and viewer keys are in
[ORDERS_CATHEDRAL.md](ORDERS_CATHEDRAL.md).

The companion Orders-Art-Review bundle contains index.html, concepts, native APNG motion
previews, scale/silhouette/grayscale boards, every unit pose, ten editable Blender scenes,
recipes, the clip-selection helper, asset inventory and raw evidence. Concepts guide design;
calibrated exports determine scale. Generated concept labels do not add gameplay abilities.
Source adapters and recipes are committed to codex/orders-cathedral-art.

Generated outputs are ignored by Git. artifacts/latest-package.txt identifies the playable
folder; artifacts/orders/delivery.json identifies archives, hashes and package smoke results.
Asset identities are in the bundle's asset-inventory.json and package BUILD-INFO.json.

## Measured performance

Baseline e8dfd195c60edf267c9ebb5709918348362db156; measured art code 052d73e.
Three fresh simulation processes and three sequential rendered runs per faction, actual
assets, 240 units, 1920×1080, VSync 1, Blender stopped. Hardware: Ryzen 5 5600G, RTX 3060
(591.86), Windows 11 Home, 25,601,957,888 bytes RAM. Later commits contain delivery tooling
and documentation only. Values are median run p95; parentheses show min–max run p95.

| Metric | Before ms | After ms |
|---|---:|---:|
| Headless simulation | 7.744 (5.673–8.720) | 5.644 (5.300–6.049) |
| Orders simulation | 9.449 (8.364–11.198) | 7.972 (7.158–9.546) |
| Orders whole tick | 13.148 (11.362–15.795) | 10.792 (9.720–13.493) |
| Orders frame | 18.028 (18.009–18.101) | 17.915 (17.747–18.018) |
| Megacorp simulation | 9.710 (9.704–13.881) | 9.761 (9.682–9.823) |
| Megacorp whole tick | 14.731 (14.426–18.166) | 12.745 (12.497–13.607) |
| Megacorp frame | 18.150 (18.095–19.107) | 18.043 (18.025–18.049) |

**Performance acceptance still fails:** all six final rendered frame p95 values exceed
16.667 ms. All final simulation p95 values are below 10 ms, but baseline variation is
substantial and no art-driven performance improvement is claimed. No budgets were relaxed.
All corresponding canonical checkpoints match.

Draw-call p95 increased from 166 to 450 in the Orders scenario and from 378 to 538 in the
Megacorp scenario. Both scenarios contain opposing units; newly sprite-backed Orders roles
add paired color/mask submissions. Draw ordering and occlusion-aware masks are preserved.
These submission counts remain a rendering cost.

Decoded atlas allocation fell from 254,121,344 to 239,857,792 bytes: **−13.6028 MiB**, within
the +64 MiB budget. Runtime texture memory, including other graphics, fell from 260,707,712
to 246,444,160 bytes. No final run clamped frame time or discarded backlog ticks.
Full p50/p95/p99/max, heap samples, draw calls, texture bytes, exact catalogs and individual
gate results are in evidence/performance-summary.json and the raw run directories.
Sampled heap is temporary allocation evidence, not a retained-memory measurement.

## Verification evidence

- scripts/test-all.ps1 passed: 194 headless tests, four 100,000-tick determinism runs,
  same-host networking and rendered UI/presentation suites.
- The production/combat/replacement soak passed 12,000 ticks, restores at 4,000/8,000,
  1,632 attacks and 24 replay checkpoints.
- All 33 Python asset tests passed; all 27 active catalog assets validated. Final building
  re-export passed the catalog checks again.
- Reopened all ten Blender scenes and checked 1,304 saved poses. Saved pose error was zero;
  source bones/actions and pinned source hash are preserved. Floor tolerance: 0.002 Blender units.
- Rendered checks cover construction boundaries, cargo continuity, mount/shrine playback
  and canonical state unchanged by rendering. Full heading/sample boards were reviewed.
- A reproduced terrain-bake viewport clipping error was corrected by refreshing the viewport
  scissor; the actual gameplay roof-pixel regression passes.
- The prior combined build's 12,000-tick recording passes all 24 checkpoints. All 27
  authoritative source files remain byte-identical; simulation 30/content 16 are unchanged.
- Package smoke results are recorded separately in the delivery manifest and package artifacts.

The full test log, Python log, scene verification, source-byte comparison and prior-replay
check are included in the companion bundle. Human recognition, gameplay feel, crowded roof
readability, balance and real two-PC latency/jitter remain follow-up work.

The branch is pushed without merging master. Draft PR creation was blocked by GitHub's
403 “Resource not accessible by integration”; the branch remains available for review.
