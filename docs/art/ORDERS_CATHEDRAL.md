# Orders cathedral assets

Presentation-only production on `codex/orders-cathedral-art`, based on combined build
`e8dfd195c60edf267c9ebb5709918348362db156`. No content/simulation revision change.
Original simulation 30 / content 16 recordings remain compatible. All source gameplay
files remain byte-identical to the combined build; see the final evidence report.

## Visual contract

Orders use pointed hoods/helmets, kite shields, rigid cloth panels, gables, buttresses
and a pointed shrine canopy. Warm ivory, charcoal iron, timber and restrained brass
sit beside neutral team-mask materials. The active Megacorp asset entries are retained
unchanged, including its unit scale, drop pod, aircraft and buildings.

| Asset | Geometry / motion |
|---|---|
| Worker / loaded Worker | Pointed hood, apron, mallet, square tool pack; loaded version has a cargo bundle. Matching canvas, clip timing, stride and anchors. |
| Footman | Wedge helmet, asymmetric kite shield, short sword, split tabard. |
| Crossbow | Compact mantle and horizontal bow, fitted two-hand grip. |
| Gryphon | Dedicated 18-bone four-legged mount, beak, three rigid folded wing slabs per side, saddle socket and preserved 65-bone humanoid rider. Ground gait only. |
| Reliquary | Open pointed canopy, bright relic, rigid base and two keyed cloth panels. Neutral attack clip exists solely for selector compatibility. |
| Keep / 4 cells | Gatehouse, unequal towers and large team roof planes. |
| Depot / 2 cells | Low gabled storehouse with external crates. |
| Barracks / 3 cells | Paired chapter-house gables and troop entrances. |
| Sanctum / 3 cells | Chapel with central pointed spire and relic window. |

The camera is the production 60-degree orthographic view at 64 delivered pixels per
Blender unit. A larger canvas accommodates poses without enlarging the model. Infantry
uses reference height 3.7 against the existing Associate/Medic size class. Gryphon body
length/width supply its extra area; its authoritative radius remains 80 and it never flies.
The ground rig's stance travel is .11 Blender units over .6 of a cycle, giving a reference
stride of `.11/.6*64/26` navigation cells. Rendering advances movement by actual travel.

Building parts stay inside their declared ground square. Completed buildings use one
fixed-facing frame. Construction frames 1–3 represent foundation, walls/partial roof,
and near completion. Completed frame 4 is idle. `Frames.construction` reads existing
remaining/buildTicks; the progress bar remains, and old assets keep their fallback overlay.

## Reproduce

Windows requires Blender 5.1, LOVE 11.5 and Python with Pillow. Put the pinned source at
`art/source/rig-library/RTSAssets.blend`; SHA-256:
`efb90208d845fd180917e2d59a8a30a2e86755cf1c030ae9211191ca20379308`.
The source library is never overwritten; original bones/actions remain in derived files.

```powershell
./scripts/export-assets.ps1 -Mode Preview -Roster orders_units
./scripts/export-assets.ps1 -Mode Preview -Roster orders_buildings
./scripts/export-assets.ps1 -Mode Build -Unit worker,worker_loaded,footman,crossbow,gryphon,reliquary,keep,depot,barracks,sanctum
./scripts/export-assets.ps1 -Mode Validate -Roster orders_units
./scripts/export-assets.ps1 -Mode Validate -Roster orders_buildings
python -m unittest discover -s tests -p 'test_*.py'
blender --background --factory-startup --python-exit-code 1 --python tests/verify_orders_blends.py -- .
./scripts/test-all.ps1
./scripts/test-performance.ps1 -Runs 3 -LiveRuns 3 -RequireAssets -OutputDirectory artifacts/orders/final-performance
./scripts/package.ps1 -WithAssets
```

Use the actual Blender/Python executable paths when they are not on PATH. Preview is
never published. Production exports validate the whole merged catalog and publish its
Lua commit atomically. Worker-pair incompatibilities block publication. Existing immutable
Megacorp builds need not be exported again. Generated scenes, renders, packages and logs
live under ignored artifacts/assets/generated/dist, never in tracked source.

Model/rig adapters: `tools/blender/orders_model.py`, `orders_special_model.py`,
`orders_special_export.py`, `orders_building_model.py`, `orders_building_export.py`.
Editable scenes and all actions: `artifacts/asset-build/<buildId>/<asset>/<asset>.blend`.
Build identities and source/tool checksums are recorded alongside each scene.

## Review and five-minute playtest

Run the package's `ReviewOrders.cmd`, or LOVE with `--orders-review --width 1920 --height 1080`.
1 shows native and normalized scale, matching/opposing colors and moving lineups.
2 shows all building stages beside an Associate. 3 shows every sample and heading;
Tab advances through six units. 4 shows mixed crowds and matching-color architecture.
G cycles color/grayscale/silhouette, L hides labels, Space pauses, Home resets time.
The existing `--asset-viewer` offers each clip at gameplay speed, all headings, stepping,
team colors, anchors and bounds. Construction is included in its clip menu.

Run `PlayOrders.cmd` (or `--orders-lab`) for ordinary game controls with a prepared army,
complete buildings, construction sites and nearby Megacorp targets. This is a fixture,
so it deliberately does not export a normal-match replay. Use skirmish for recordings.

1. Compare Worker, Footman and Crossbow without labels; check faction/team recognition.
2. Move the mixed army past both sides of the buildings; reverse and stop repeatedly.
3. Follow the Gryphon through turns; inspect planted feet, rider seat and melee contact.
4. Harvest with a Worker, then redirect it carrying cargo; look for a pose/anchor pop.
5. Watch construction complete, place another building, and inspect roof occlusion;
   compare the Reliquary above the ground units. Restart the fixture for fresh sites.

Automated geometry/catalog/canonical checks are distinct from human recognition, control
feel and two-PC testing. Existing frame-time failures are reported rather than hidden or
relabeled as an art optimization. Final measured evidence is in ORDERS_ART_HANDOFF.md.

## Concepts

The generated unit and building boards and their exact prompts are delivered in
`artifacts/concept-art`. They guide the primitive language; calibrated Blender exports
are authoritative for scale and animation. Generated captions are illustrative: the
Gryphon remains ground-only, and Sanctum training/healing behavior is unchanged.
Portraits, HUD icons, bespoke VFX and terrain remain outside this release.
