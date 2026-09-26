# Megacorp landed building modules

Nine original low-poly buildings implement the approved rounded retrofuturist
concept sheet. Broad team-color roofs sit over ivory edges and graphite bases.
The silhouettes remain faction-specific when two opposing teams use the same
Megacorp roster: saucer, twin vault, four-pod courtyard, banded medical capsule,
armored drum, dish, three-foot pump, twin capacitors and low pillbox.

| Asset | Existing footprint | Primary form | Idle frames | Triangles |
| --- | ---: | --- | ---: | ---: |
| Orbital Command | 4x4 | Saucer and visor belt | 1 | 1,176 |
| Barracks | 3x3 | Two parallel pressure vaults | 1 | 1,888 |
| Requisition Office | 3x3 | Four cargo pods around a recessed hatch | 1 | 2,160 |
| Med Bay | 2x2 | Banded vault with side capsules | 1 | 1,392 |
| Armory | 2x2 | Heavy vault with transverse drum | 1 | 1,476 |
| Orbital Relay | 2x2 | Concave dish on a short mast | 8 | 868 |
| Substrate Rig | 1x1 | Three-foot pump with moving piston | 4 | 1,176 |
| Charge Rig | 2x2 | Two rounded capacitor tanks | 1 | 1,172 |
| Bunker | 2x2 | Low eight-sided armored pillbox | 1 | 968 |

The bunker uses eight sides for regular firing ports and simple assembly. The
concept's small 1x1 substrate rig is deliberately small at gameplay zoom; its
three-foot outline and colored piston cap are its main read. All models use named
rigid meshes; the relay and pump use keyed object pivots. No armature, deforming
skin, external mesh library or texture dependency is required. Door frames, shell
panels and landing feet remain separate editable components.

## Rebuild and review

```powershell
./scripts/export-assets.ps1 -Mode Preview -Unit orbital_command
./scripts/export-assets.ps1 -Mode Build -Roster megacorp_buildings
./scripts/export-assets.ps1 -Mode Validate -Roster megacorp_buildings
# Run through the installed Blender CLI, passing this repository after --:
blender --background --factory-startup --python-exit-code 1 --python tests/verify_building_blends.py -- .
python tools/assets/building_review.py
./scripts/test-presentation.ps1
./scripts/run.ps1 -AssetViewer
```

Use a Python with Pillow. `tools/blender/building_model.py` and the nine individual
`art/recipes/*.json` files are the authoritative editable recipes.
`building_export.py` uses the existing production lighting, 60-degree camera,
64 delivery pixels per Blender unit, 2x rendering, paired team-mask passes and
transactional catalog publication. Generated scenes live at
`artifacts/asset-build/<buildId>/<asset>/<asset>.blend`; atlas paths are recorded
in `assets/generated/catalog.json`. All generated files remain ignored.

The saved-scene verifier reopens every active blend, checks every sampled bound,
finite geometry, floor clearance, footprint containment, team materials and moving
pivots, then renders game-camera and three-quarter assembly views. The composer
writes sheets and links to the current editable scenes under
`artifacts/building-review/`. Assembly thumbnails fit each building individually;
the game's footprint guides show their actual relative scale.

## Runtime contract

Buildings have one fixed facing. `building_overhead_v1` requires an idle clip,
`fixedFacing='S'` and an integer `footprintCells` from 1 through 4. The eight
canonical direction lists alias the same packed frame IDs, allowing the existing
viewer, mask shader, loader and packaging path to work without eight copies of
each image. The roster packs 19 unique color/mask frame pairs into about **0.85
MiB** of uncompressed RGBA atlas data, before GPU overhead.

An assembly spans at most `footprintCells * 26 / 64` Blender units in X and Y;
the exporter fails on floor or footprint crossings, rather than resizing the art
to fit. The renderer places the export origin at the center of the existing
occupied-cell rectangle, respecting the game's 26-by-22.52-pixel ground projection.
Selection/hover rectangles and picking retain that existing footprint. Missing
or incompatible building art uses the original drawn fallback. Tooltips and the
selection panel provide building names; sprite buildings omit placeholder labels.

This changes presentation only: costs, health, placement, coverage, production,
collision, damage and orbital timing are unchanged. The established construction
overlay remains available. Completed modules appear through the existing orbital
landing behavior; this pass does not add descent/death sprite animations or new
simulation events. Idle joint motion is cosmetic and does not indicate income.

The rendered fixture verifies all nine ground anchors and click targets, every
idle sample, both team colors, neutral trim, fractional zoom, missing-art fallback,
and unchanged canonical simulation state. Native camera captures are the size
reference; enlarged assembly renders are for inspecting shapes and editability.
Human visual/play approval and another machine's rendering remain separate checks.
