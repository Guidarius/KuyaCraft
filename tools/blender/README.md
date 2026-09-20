# Blender-to-LÖVE asset pipeline

The production pipeline adapts the saved 65-bone humanoid library into original low-poly Bastion units. It builds shieldguard, worker, worker_loaded, crossbow, and Warden assets. Visible hands are stumps; the original skeleton and animation library remain intact.

The procedural Megacorp aircraft adapter builds `command_blimp` and `battleship`
without an external source blend. Use `-Roster megacorp_aircraft` with Preview,
Build or Validate; the same camera, masks, packing and catalog contracts apply.
See [aircraft modeling and review](../../docs/art/MEGACORP_AIRCRAFT.md).

The rounded Megacorp infantry adapter builds `associate`, `medic` and `enforcer`
on the pinned source rig. Use `-Roster megacorp_infantry`; see
[infantry modeling and review](../../docs/art/MEGACORP_INFANTRY.md) for the preserved
rig, fitted poses, team masks and saved-scene verification.

## Prerequisites and saved source

Use Blender 5.1.0, Python 3.10+ with Pillow, and the project-pinned LÖVE 11.5 runtime. The PowerShell wrapper finds the bundled Python or accepts `-Python`; `-Blender` overrides the Blender executable. No MCP connection or open Blender window is needed for production.

The local source is `art/source/rig-library/RTSAssets.blend`. Its acquisition and SHA-256 are recorded in `art/source/rig-library/source.json`; each recipe pins that hash. The binary is ignored and is not shipped. On another checkout, obtain the authorized source copy and verify its hash before building. Missing or changed sources fail explicitly.

Do not overwrite the original library or edit generated working scenes as your only source of changes. Store deliberate model/pose changes in `unit_model.py` and recipes. A source refresh means saving a new owned copy, inspecting it, recording its new hash/provenance, reviewing action/bone compatibility, then updating recipe pins deliberately.

## Commands

Run from the project root:

```powershell
.\scripts\export-assets.ps1 -Mode Inspect
.\scripts\export-assets.ps1 -Mode Preview -Unit shieldguard
.\scripts\export-assets.ps1 -Mode Build -Roster bastion
.\scripts\export-assets.ps1 -Mode Validate -Roster bastion
.\scripts\run.ps1 -AssetViewer
.\scripts\package.ps1
```

A plain export command builds the Bastion roster. `-Unit crossbow` builds only that asset; repeat builds validate and reuse unchanged outputs. `-Force` rerenders but keeps validation and immutable-output checks. `-Mode Legacy` regenerates the earlier seven-bone shieldguard proof; it does not replace an active v2 catalog. Preview renders one sample per clip/direction and does not publish production assets.

## Files and failure recovery

- `art/recipes/*.json`: tracked unit recipes, source pins, action choices, sample counts, durations, contact markers.
- `tools/blender/unit_model.py`: original geometry, equipment sockets, and derived pose corrections.
- `tools/blender/pipeline.py`: isolated source intake, evaluated animation baking, bounds scan, camera and color/mask rendering.
- `tools/assets/pack.py`: alpha-aware downsampling, paired pages, two-pixel extruded gutters, metadata and validation.
- `tools/assets/build.py`: dependency hashes, cache validation, publication and packaging.
- `artifacts/asset-build/<id>/<unit>/`: inventory, dependencies, render log/report, raw frames, editable derived blend, packed contact sheet and motion preview.
- `artifacts/asset-build/latest-report.json`: latest batch outcome and timings.
- `assets/generated/builds/<id>/<unit>/`: immutable validated runtime output.
- `assets/generated/catalog.lua` and `.json`: active roster, published after all requested units pass. Previous catalog files are retained.

Generated output is ignored by Git. A failed unit prevents the requested batch from publishing; the prior active roster stays usable. Inspect that unit's `blender.log` and any `bounds-failure.json/.blend`, correct the recipe or adapter, and rerun. Packaging validates the full five-asset roster and copies only catalog-referenced images and metadata, excluding Blender sources and stale builds.

## Render and playback contract

The camera is orthographic, 60 degrees above the ground, with fixed world-space lights. Ordinary standing bodies project to about 32 pixels; Warden is 1.15 times larger. A bounds scan chooses 64, 96, or 128-pixel delivery cells across all sampled poses without changing body scale. Frames render at twice delivery resolution. Every frame retains its ground anchor.

Headings are N, NE, E, SE, S, SW, W, NW. Color and occlusion-aware team coverage have identical page layouts. Page dimensions are at most 2048 pixels, frames are untrimmed/unrotated, and Lua/JSON metadata use one-based frame/page IDs with zero-based pixel rectangles. Playback uses metadata, not a fixed atlas formula.

Movement phase follows distance traveled. Cargo selects the complete worker_loaded asset while preserving phase. Damage remains authoritative and instantaneous on attackTick: gameplay starts at the exported contact sample and shows recovery, while the viewer plays the full attack. Animation never causes damage or changes snapshots. Attack facing uses only filtered visible target positions.

## Viewer controls

Tab/U: unit; C: clip; D: highlighted direction; Space: play/pause; Left/Right: frame step; Home: rewind; +/-: speed; Z: zoom; T: team; B: ground; G: anchors; R: frame rectangles. All eight directions appear together, with a mixed-roster 1x strip below. Review idle, gait, attack, death and worker work at 1x and fractional gameplay zoom, against both light and dark ground.

A still or passing bounds check does not certify animation quality. Human style/readability approval and cross-PC visual comparison remain separate from automated verification. See STATUS.md for the evidence actually collected, and docs/ASSET_PIPELINE_PLAN.md for the full design and acceptance requirements.

## Reproducible checks

Run `scripts/test.ps1` for the full simulation/runtime regression and process comparisons. Run `scripts/test-presentation.ps1 -AssetPipeline` after a complete v2 build for picking at 720p, the viewer, and a 1080p 60-versus-60 rendered comparison across v2, legacy, and diagnostic fallback. This comparison harness also needs the original legacy proof files (`-Mode Legacy` generates them); packaged games intentionally omit those stale legacy assets. The report distinguishes CPU draw submission from GPU frame time and records comparison overhead.

Python tooling tests: `python -m unittest discover -s tests -p test_asset_tools.py -v` using a Python with Pillow. Blender intake/sampling checks: run Blender with `--background --factory-startup --python-exit-code 1 --python tools/blender/verify_pipeline.py`. Generated reports belong under artifacts. The recipe hash covers all exporter/model/packer Python, so shared script changes invalidate the roster, while a unit-only recipe edit invalidates that unit.
Derived working `.blend` files retain the original actions and sparse `RTS_<unit>_<clip>` pose actions. Derived sample keys are one Blender frame apart for inspection; the recipe's `durationMs` controls delivered playback speed. Use the LÖVE viewer for authoritative presentation timing, or adjust Blender playback while inspecting those sparse samples.

For a separate 30-second v2-only battle benchmark, run `scripts/test-presentation.ps1 -Benchmark` with background rendering stopped. This uses actual game HUD, fog and feedback at 1080p and 1x, and excludes legacy/comparison worlds and screenshots from the timed run. Inspect `artifacts/asset-benchmark-report.txt`; update cadence includes vsync and is not a direct GPU timer.
