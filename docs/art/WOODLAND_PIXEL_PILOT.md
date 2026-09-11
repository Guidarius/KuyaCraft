# Woodland pixel-art pilot

The isolated Mouse Builder pilot uses the existing Blender exporter, PNG/mask packer,
metadata v2 and LÖVE sprite reader. It does not change simulation, production catalog,
game camera, fractional zoom, factions, or shipping packages.

## Build and compare

From the project root:

    .\scripts\export-assets.ps1 -Roster woodland
    .\scripts\export-assets.ps1 -Roster woodland -Mode Validate
    .\scripts\run.ps1 -WoodlandViewer

Requires Blender 5.1 and Python 3.10+ with Pillow. The wrapper locates the bundled Python,
or accepts -Python / ASSET_PYTHON. Keep the pinned RTSAssets.blend in
art/source/rig-library. Aseprite and Krita are optional; neither runs during a build.

The viewer displays all eight directions at 32/48/64 nominal body pixels with nearest
sampling, integer magnification, pixel-aligned positions, three terrain swatches and a
native-scale crowd containing pilot variants and available shaded production units.
C changes clip; Space pauses; Left/Right step; Z changes integer magnifier; T changes
team; B changes background; G toggles ground anchors; Home restarts; +/- change speed.
At smaller windows the magnifier reduces to fit. Use 1600x1000 for the intended layout.

For reproducible captures, LÖVE options include --pilot-clip idle|move|work,
--pilot-team 1|2|3, --pilot-background 1|2|3 and --pilot-time <milliseconds>.
The normal game renderer is deliberately unchanged.

## Source and finishing contract

The original reference inspires newly authored low-poly geometry: oversized ears,
muzzle, sturdy legs, stump paws, mallet, tail and left team shoulder. The supplied rig
is duplicated, including armature data, before shortening legs and adapting the torso.
Source actions are sampled onto the derived proportions; feet and weapon grip receive
procedural corrections. The mallet cycle is authored over the source idle motion.
The original rig and its 120 actions remain in the generated authoring scene alongside
the 65-bone derived rig and three baked actions. Source blend bytes remain unchanged.

Body size is normalized using sole-to-head-crown geometry in the reference pose,
excluding ears and equipment. Nominal body pixels describe this shared orthographic
world-height scale, not a per-frame screen bounding box; perspective pitch, pose and
outline affect visible screen height. Every frame uses the same scale and anchor.

| Nominal body pixels | Fixed canvas | Ground anchor |
| --- | --- | --- |
| 32 | 96 x 96 | 48, 56 |
| 48 | 144 x 144 | 72, 84 |
| 64 | 192 x 192 | 96, 112 |

Idle has 8 samples; move and work have 12 each. Every clip is a one-second loop.
Eight independently rendered directions give 256 poses and 768 finished frame entries
across three sizes. No mirrored directions or separate-limb slicing are used.
Raw renders are twice canonical resolution; each variant reduces from that common
source. A fixed 32-color palette reserves five blue shades for team indices. Reduction
uses no dithering; alpha is binary; a one-pixel 8-neighbor dark outline follows reduction.
Team masks encode five discrete indices, and the shader substitutes blue/red/green
ramps without tinting skin, neutral materials or outlines.

Recipe: art/recipes/woodland/mouse_builder.json.
Geometry/rig recipes: tools/blender/woodland_model.py and woodland_export.py.
Render revisions hash the source, Blender version and authoring recipes/scripts.
Build identities additionally hash finishing code and cleanup sources.
Raw cache receipts detect modified render PNGs. Use -Force to regenerate corrupt raw
renders. Immutable packed-output mismatches fail for review instead of overwriting.
All variants validate before the isolated Lua catalog publication point.

Generated files live under assets/generated/woodland and artifacts/woodland (ignored).
The latest report points to the build and render revision; the render folder contains
mouse_builder.blend, source inventory, raw frames and Blender logs.

## Optional Aseprite cleanup

Aseprite was found at C:/Program Files/Aseprite/Aseprite.exe. Its documented
[batch CLI](https://www.aseprite.org/docs/cli/) and
[sprite scripting API](https://www.aseprite.org/api/sprite) power the optional round trip.
Use your Python-with-Pillow executable in place of python if it is not on PATH:

    python tools/assets/woodland_edit.py prepare --height 48 --workspace artifacts/woodland/my-edit
    python tools/assets/woodland_edit.py check --workspace artifacts/woodland/my-edit
    python tools/assets/woodland_edit.py import --workspace artifacts/woodland/my-edit
    .\scripts\export-assets.ps1 -Roster woodland

Prepare creates mouse.aseprite with 256 frames, 24 clip/direction tags, durations,
a palette, a visible color layer and hidden mask layer. Open that file in Aseprite and
save your edits before check/import. Prepare refuses to overwrite an existing workspace.
The CLI uses an isolated preferences folder, preserving personal editor settings.
Sandboxed Aseprite exited before executing locally; verification succeeded outside the
sandbox. Automated builds do not need editor permissions.

Check validates every frame but writes no cleanup source. Import copies only changed
PNG pairs plus the editable .aseprite into art/cleanup/woodland/edits/<content hash>,
then publishes a source-revision-bound manifest. See art/cleanup/woodland/README.md for
mask values, palette restrictions and the manifest schema. All edited frames validate
before source publication. Unchanged round trips produce no cleanup manifest.
A stale source or editor baseline stops with an explicit review error. Existing edits
remain on disk; no automatic revision relabeling occurs.

[Krita](https://krita.org/en/) remains an optional companion for paintovers, texture ideas
and portraits. No Krita-specific converter or installation is needed for this pilot.

## Review and next decision

    python tools/assets/woodland_review.py

This creates dense full-loop sheets for all clips, directions and sizes under
artifacts/woodland/review. Each row repeats its first frame at the end to expose the
loop transition. The viewer plays the same metadata. Review at native size first.

Look for ear/mallet readability, planted feet during work, coherent walk contacts,
team-only recoloring, temporal shading changes, outline crawling, canvas clipping,
and readability in a mixed crowd on light and dark terrain.
Initial contact-sheet inspection shows recognizable ears and the work swing; far-side
equipment is naturally occluded in some headings. The 32-pixel muzzle/tool details
compress considerably. Quantized facets and thin tail contours still warrant human
motion review. Dense ordered sheets were inspected; this is not a claim of human
real-time animation approval or a final resolution decision.

Choose the native body size after playing the comparison. Then apply the same contracts
to Hedgehog Guard, Squirrel Crossbow and Badger Warden. Full-game pixel alignment and
gamefeel/UI work remain separate renderer/product tasks.

## Validation record

- Python asset/pixel tests cover palette, binary alpha, exact outline width, discrete
  team shades, cleanup containment, stale revisions and edited-file round trips.
- All three generated variants pass atlas/mask/palette validation.
- Aseprite 1.3.17: the 48-pixel file exports/import-checks all 256 frames unchanged.
- LÖVE work/move viewer smoke runs and light/red-team screenshots succeeded.
- Production catalog and supplied blend SHA-256 are checked against pre-build values.
- Full gameplay suite: 98 passed, 1 failed on the existing 10 ms active-unit performance
  gate (13.168 ms while asset work was concurrent). No gameplay or golden results changed.
  See STATUS.md for the isolated recheck and final check results.
- Final native-size choice, perceived flicker/crawling and human motion approval remain
  review decisions; no other-PC or human playtesting is claimed.
