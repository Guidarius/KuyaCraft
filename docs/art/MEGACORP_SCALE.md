# Megacorp unit, building and drop-pod scale

Use compressed RTS proportions: people remain readable, vehicles earn space through
width, and buildings communicate role and capacity without literal architectural
dimensions. Associate and Medic share the Marine-like size class; Enforcer is the
Goliath-like heavy. It should look broad and squat rather than twice as tall.

The reference is the relationship, not a recreation of StarCraft artwork. In
[BWAPI's unit type source](https://github.com/bwapi/bwapi/blob/main/bwapi/BWAPILIB/Source/UnitType.cpp),
Marine and Medic collision bounds are 17 by 20 pixels; Goliath is 32 by 32. Command
Center placement is 4 by 3 build tiles. Collision bounds, placement tiles, visible
sprite extents and the damage-system size class are distinct concepts. Our square
headquarters stays 4 by 4 navigation cells; those cells are not StarCraft build tiles.

## Current authored scale

All sprites use the same 60-degree orthographic camera and 64 delivery pixels per
Blender unit. At zoom 1 the game's ground projection is 26 by 22.52 pixels per
navigation cell. These are alpha bounds above 32/255 in the first idle sample,
across all eight headings, including equipment; animation can extend farther.

| Asset | Visible width | Visible height | Gameplay footprint |
| --- | ---: | ---: | --- |
| Associate | 16–20 px | 22–26 px | radius 80 subunits |
| Medic | 18–22 px | 22–31 px | radius 80 subunits |
| Enforcer | 29–41 px | 32–44 px | radius 160 subunits |
| Drop pod, closed | 60 px | 59 px | cosmetic, no collision |
| Bunker | 48 px | 46 px | 2x2 cells |
| Barracks | 76 px | 77 px | 3x3 cells |
| Orbital Command | 98 px | 97 px | 4x4 cells |

The previous Enforcer was up to 102 pixels wide, slightly wider than headquarters.
This pass halves Associate/Medic model scale and takes Enforcer to 40% of its
preceding scale. The buildings retain their current sizes. Standing model heights
are approximately 0.479, 0.454 and 0.612 Blender units; equipment and projected
depth explain the different screen-height ratios. Collision rules, costs, speed,
range, arrival ticks and pod capacity are unchanged.

At zoom 1, infantry collision diameters project to 16.25 horizontal pixels and the
Enforcer to 32.5. Selection rings deliberately provide some margin: 22.5-pixel-wide
infantry ellipses and a 40-pixel-wide Enforcer ellipse. Atlas cells are 96 pixels
square, including padding for all animation poses. The three paired atlases now
occupy about 50.35 MiB before GPU overhead, down from about 166.13 MiB. This is a
texture-memory reduction, not a measured frame-rate improvement.

## Drop pod assembly and runtime

`tools/blender/drop_pod_model.py` builds an original faceted pressure capsule with
a graphite heat shield, rounded cap, three rigid landing fins, broad team panels,
small porthole and two separate doors. `DoorHingeLeft` and `DoorHingeRight` are
object pivots with editable keys: closed at frame 1, open 105 degrees at frame 6.
No humanoid rig or skin weighting is needed. Capacity uses RTS abstraction; the
interior is not a literal seating model for four Enforcers.

The fixed-view prop profile packs one idle and six deploy frames, with canonical
headings aliasing those seven images. Paired atlas allocation is 0.534 MiB. It has
no simulation entity, health, selection or obstruction. Only the existing owner's
filtered in-flight queue and landing events create the cosmetic. The closed shell
appears in the final 45% of descent; landing opens it over 450 ms, holds briefly,
then fades. The effect expires after 2.5 seconds, with at most 12 landed shells.
Troops arrive on their existing simulation tick, independent of the door animation.
Missing art retains the original descent marker.

```powershell
./scripts/export-assets.ps1 -Unit drop_pod,associate,medic,enforcer
./scripts/export-assets.ps1 -Mode Validate -Unit drop_pod,associate,medic,enforcer
blender --background --factory-startup --python-exit-code 1 --python tests/verify_drop_pod_blend.py -- .
blender --background --factory-startup --python-exit-code 1 --python tests/verify_megacorp_blends.py -- . --catalog
./scripts/test-all.ps1
```

Generated Blender files are under `artifacts/asset-build/<buildId>/<unit>/`;
`assets/generated/catalog.json` identifies the active build IDs. The procedural
pod needs no external source blend; infantry still requires the pinned rig library.
All exports stay ignored. Recipes, modeling scripts and checks are tracked.

Rendered tests capture a common-scale lineup at 1x and 2x, both team colors, every
door sample and actual game descent/landing. They check the ground anchor, expiry,
owner privacy, fallback and unchanged canonical state. Saved-scene checks reopen
Blender files and inspect the keyed geometry. Native-size recognition, crowd
readability and mouse feel still need human playtesting; another GPU/PC remains
outside these local checks.
