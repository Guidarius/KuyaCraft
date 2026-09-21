# Megacorp pressure-hull aircraft

The Command Blimp is a squat observation capsule with a large smoked bubble visor,
shallow gondola, relay puck and two small rear engines. The Battleship has a wide
three-lobed silhouette, closed forward nacelle caps, rear exhausts, a small bridge
porthole and one blunt cannon. Continuous upper shells carry player color; glass,
graphite lower hulls and restrained aluminum rims stay neutral.

`tools/blender/aircraft_model.py` is the original editable source recipe. It builds
named rigid modules in Blender units, with the nose along -Y. An aircraft motion
root carries the assembly; the Battleship adds a cannon recoil object. Object actions
are saved for idle, movement, attack and death. The Blimp's required attack clip is
an inert pose: it remains unarmed. No source humanoid rig or external model is needed.

## Build and review

```powershell
./scripts/export-assets.ps1 -Mode Preview -Roster megacorp_aircraft
./scripts/export-assets.ps1 -Mode Build -Roster megacorp_aircraft
./scripts/export-assets.ps1 -Mode Validate -Roster megacorp_aircraft
./scripts/run.ps1 -AssetViewer
./scripts/test-presentation.ps1
```

Use `-Unit command_blimp` or `-Unit battleship` for individual builds. The shared
production profile remains 60-degree orthographic, 64 delivery pixels per Blender
unit, eight headings, twice-resolution raw frames, neutral shaded team material and
an occlusion-aware coverage pass. Existing packing, validation, immutable output and
transactional catalog publication are reused. Publishing adds these entries to the
existing catalog. A clean checkout still needs its ordinary roster built separately.

`bodyHeightPixels=32` denotes the shared standing-body scale reference, not the
aircraft's literal hull height: the runtime uses this field to normalize unit size.
This preserves the aircraft dimensions relative to ground units. The game supplies
the flight offset and ground shadow; the model contains only local hull height and
small cosmetic motion. Canvas growth never rescales a unit.

Generated editable scenes are under `artifacts/asset-build/<id>/<unit>/<unit>.blend`.
Paired atlases and metadata are under `assets/generated/builds/<id>/<unit>/`.
Both are ignored. The active `assets/generated/catalog.json` identifies current IDs.
Saved action keys are sparse samples; recipe durations govern runtime playback.

Run `tests/verify_aircraft_blends.py` in background Blender with the repository root
after `--` to reopen both scenes and compare every evaluated pose/direction with
the export bounds. The rendered presentation suite additionally captures every clip
sample in all eight directions for blue and red teams, and a mixed army on shipping
terrain through the real App draw path. These checks run when both aircraft are built;
without them the presentation suite explicitly reports that the aircraft checks skipped.

## Cost and acceptance

The ships are pre-rendered: Blender triangle counts do not become gameplay draw calls.
Each aircraft uses one ordinary color/mask sprite draw. Initial sampling is four idle,
four movement and six death frames per heading; the Battleship has six attack samples,
and the Blimp one inert sample. Cannon recoil starts at contact sample 3, with recovery
afterwards. Damage, attack windup, targeting, collision and flight remain authoritative
simulation behavior. The death clip banks and settles locally; it is not a physical
crash simulation.

Review native and fractional zoom, both team colors, all headings and all clips.
Automated bounds and mask checks establish export integrity, not player approval or
cross-machine render equivalence. Fresh verification results belong in STATUS.md.
