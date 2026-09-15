# Modular mouse guard equipment

This isolated fitting study adds a short sword, shield, open-ear helmet and
sleeveless armor vest to the saved [mouse base](MOUSE_BASE.md). Broad shapes and
large team regions suit the 60-degree RTS camera and existing pixel finish.
It does not publish a production unit or alter simulation timing.

## Assembly

| Kit | Blender collection | Binding |
| --- | --- | --- |
| Sword: grip, crossguard, broad blade | Equipment_sword | attach_weapon / right hand |
| Shield: wood rim, blue face, boss, handle | Equipment_shield | attach_shield / left hand |
| Helmet: central cap and brow, open ear roots | Equipment_helmet | attach_helmet / Head |
| Armor: fitted sleeveless shell | Equipment_armor | Shared MouseBaseRig, transferred Body weights |

Toggle these collections in the Outliner to remove individual equipment categories.
Rigid meshes use socket-local coordinates, corrected for bone-tail offsets and rig
scale. The sword grip and shield handle centers coincide with the mitten palms.
The vest copies the base's torso-ring weights with outward clearance and a small
Solidify modifier. It does not require cloth simulation. The underlying Body is
preserved, so removing armor restores the complete bare base.

The kit adds 268 authored triangles: 1,304 total before the vest's thickness modifier.
The saved-scene validation also reports the evaluated count. This is a fitted kit for
this mouse revision; changing body proportions requires another fitting pass.

## Motion

Six MouseGuard_* actions are baked separately from the preserved MouseBase_* actions:
idle, walk, run, punch, hit and celebrate. They retain the base torso/leg motion while
fitting the arms for equipment carry. The punch becomes a short sword-thrust fitting
study; it is not a final authored guard attack or a new gameplay damage event.

The first vertical sword carry crossed an ear. Tilting the carry outward removed
those sampled surface crossings before the complete animation render. The new NLA
timeline sequences all six equipped clips at 24 FPS without transition blending.
Original library and bare-mouse actions remain available in the Action Editor.

## Reproduce and inspect

First generate the complete mouse base, then run with executable paths or tools on PATH:

    .\scripts\build-mouse-guard.ps1 -Base artifacts/mouse-base -Blender <blender-executable> -Python <python-with-Pillow>

Use -Preview for a four-pose-per-clip fitting probe. Use a new -Output folder to
preserve an earlier review revision. The script opens a copy of the supplied base
in background Blender and saves mouse_guard.blend in the output folder. It checks
the input blend hash and never saves over the base file or the pinned source rig.

The full wrapper renders 243 poses from two cameras plus occlusion-aware team masks,
reopens the saved scene for verification, and builds the shared review viewer.
Open index.html to play all clips and compare 32/48/64 body heights at integer zoom.
Review renders use blue equipment; pixel inputs use neutral team shading and masks
to select discrete blue shades from the existing palette. Front/side/back/top and
eight independent idle-heading renders provide additional silhouette diagnostics.
These are not complete eight-direction animation atlases.

Optional video encoding, from the output folder:

    ffmpeg -framerate 12 -i video/%03d.png -c:v libx264 -pix_fmt yuv420p -crf 19 -movflags +faststart mouse-guard-motion.mp4

## Verification scope

The saved-scene checker evaluates every NLA frame for finite geometry, grip drift,
equipment-floor clearance, retained source/bare actions, vest weight normalization
and blade surface crossings against the body, head, ears, helmet and shield rim.
Triangle-surface overlap does not prove complete collision freedom or garment fit;
the ordered motion sheets and actual camera views are a separate visual review.
Human real-time motion approval and other-PC validation remain separate.

Verified on this Windows PC, 2026-09-14: the complete PowerShell build wrapper passed,
including saved-scene checks over all 243 frames. Evaluated triangle count: 1,448.
Maximum measured palm/grip discrepancy was below 0.000001 normalized units; no blade
surface crossings were detected against the listed targets. All game-frame bounds
passed. The 22 asset-tool tests and six Woodland tests passed, along with existing
Woodland catalog validation and rendered presentation checks. Dense sequences of all
six motions and the interactive shaded/pixel preview were inspected. Original base,
pinned source rig and production catalog remained unchanged.
