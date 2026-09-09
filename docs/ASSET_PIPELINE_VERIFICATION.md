# Asset pipeline verification

This records implementation evidence, not artist approval or cross-PC certification. Final catalog, cache, rendered integration and standalone package verification pass. STATUS.md is the milestone summary.

## Scope delivered

The pipeline consumes the supplied saved humanoid library and generates original stump-handed shieldguard, worker, worker_loaded, crossbow, and Warden meshes. Each has idle, move, attack, and death; both workers additionally have work. This is 1,168 poses across eight directions, with matching color and team masks. Audio, HUD redesign, balance, projectile travel, and authoritative windup remain separate work.

## Evidence map

| Requirement | Evidence |
|---|---|
| Source preserved and pinned | `art/source/rig-library/source.json`, SHA-256 `efb90208d845fd180917e2d59a8a30a2e86755cf1c030ae9211191ca20379308`; background intake test passes and every render checks the pin |
| Skeleton and actions retained | Source inventory: 65 bones, 120 actions, 24 fps, OBArmature slots; each derived blend preserves original actions and adds baked pose actions |
| Stump meshes, original geometry | `unit_model.py`; per-unit render report lists stump objects, empty finger-weight groups, triangle counts, and 65 retained bones |
| Sampling and motion | Blender-hosted fractional/loop/nonloop sampling tests; locomotion planar-root selfcheck; death clamping, contact-first recovery, and distance-driven gait tested in Lua |
| Equipment and bounds | `artifacts/model-check/final-bounds.json`: all 1,168 sampled poses within 128-pixel canvas and two-pixel margin; crossbow support error below 4.18e-7 source units including death |
| Color, masks, atlas schema | Raw-frame clipping checks; aligned dimensions; two-pixel edge/corner extrusion; transparent RGB filtering; frame/page/anchor/clip validation and Lua/JSON agreement |
| Worker cargo | Complete five-clip assets; publication checks matching stride, durations, samples and anchors; actual rendered harness checks both variants |
| Incremental and transactional build | 22 Python tests cover cache isolation, bad frames/files/paths, corrupt active replacement, interrupted first/repeated publication, rollback and package filtering |
| Runtime independence | Pure frame-selector tests plus actual v2/v1/fallback draw comparison: 300 ticks, 386 attacks, 290 moving ticks, matching canonical state each tick and before/after draws |
| Camera and viewer | 720p input proof includes projection round trips at 0.75/1/1.25/2 zoom; viewer exposes all eight directions and tested controls; battle screenshots at 0.75/1/1.25 zoom |
| Existing gameplay regressions | `artifacts/asset-full-tests.log`: 27 tests; fresh-process 100,000-tick checkpoint agreement at 30/60/144 scheduling; two-process ENet agreement through 600 ticks |
| Full production render | `artifacts/asset-first-roster-report.json`: all five passed, 515.81 seconds on this machine; subsequent build verifies final tooling revision |

## Repeat the checks

```powershell
.\scripts\export-assets.ps1 -Mode Build -Roster bastion
.\scripts\export-assets.ps1 -Mode Validate -Roster bastion
.\scripts\test.ps1
.\scripts\test-presentation.ps1 -AssetPipeline
.\scripts\package.ps1
```

See `tools/blender/README.md` for Python/Blender test commands and saved-source setup. The comparison harness intentionally draws the legacy and diagnostic fallback paths too; their missing-asset diagnostic messages are expected. Its CPU draw timer measures submission, not GPU time. Comparison cadence includes three worlds, serialization and offscreen drawing, so it does not certify 60 FPS.

## Visual review and limitations

The 720p viewer and 1080p battle screenshots were inspected for direction labels, team contrast, frame containment, ground placement, and crowd readability. Representative worker work, crossbow contact/death, and shieldguard death renders were inspected. This does not certify every continuous transition or replace human motion/style review.

All sampled death geometry stays above ground. The inherited source gait retains less than 0.23 delivery pixel of boot penetration. Artist refinement may still improve gait, wrist silhouettes and weapon clearance between sampled poses. Sparse derived Blender pose keys use one-frame spacing; delivered playback duration is explicitly in each recipe and is reviewed in LÖVE.

Human playtesting, artistic sign-off, cross-PC rendering tolerance checks and LAN play on another physical PC are unperformed. Source licensing/distribution was not expanded: the supplied source remains local and is excluded from the game package.

## Final build and timing record

`artifacts/asset-final-audit.json` confirms the source hash, 65-bone units, both named palm stumps, zero finger groups, seven atlas pages and 1,168 frames. Final build IDs are recorded there and in the active catalog. The final tooling revision rebuilt four units with byte-identical color/mask output; Warden was a validated cache hit. All five were cache hits in the next run (1.05 seconds inside the builder).

The separate v2-only benchmark ran after background production ended: 600 ticks / 30.033 seconds / 1,787 frames / 910 attack events, zero discarded dt. P95 simulation CPU was 2.226 ms; draw submission CPU 15.338 ms; actual update cadence 17.620 ms, maximum 185.372 ms. Peak sampled texture memory was 167,270,400 bytes. This supports roughly 59.5 average FPS for the fixture, with frame-time spikes; it does not certify stable 60 FPS or a full bot/replay/audio workload. The complete hardware/scope/memory report is `artifacts/asset-benchmark-report.txt`.
## Standalone package

`dist/LoveRTS-20260908-233352` launched from its own directory with its bundled LÖVE runtime. All 27 bundled headless tests passed; the eight-direction viewer and rendered game input proof both exited successfully and produced inspected screenshots. Blender was not invoked at runtime.

Archive SHA-256: `67f620803c1f6d2f5ff9ef55b1be614fc23747cf9045f03a96b4e1e9bd9789c3`. `artifacts/asset-package-audit.json` confirms exactly 31 active-catalog asset files with matching bytes, main.lua at the archive root, and no source blends, tools, raw renders or stale generated builds. Package test logs/screenshots are in its artifacts directory. This is local standalone evidence; a second physical PC remains untested.