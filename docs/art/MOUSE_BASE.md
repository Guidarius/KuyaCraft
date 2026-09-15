# Modular mouse base

Equipment-free low-poly mouse for the existing 60-degree orthographic RTS camera.
Broad head, round ears, short muzzle, pear torso, short legs, mitten paws and tapered
tail. Omit fur tufts, digits, clothing and equipment geometry.

Derive a proportion-fitted skeleton from the pinned 65-bone library, preserving bone
names and original actions. Add ear/tail bones and attachment markers. Inspect neutral
and difficult poses before baking idle, walk, run, punch, hit reaction and celebration.

Deliver an editable derived blend, reproducible generator, motion showcase, game-camera
pixel previews and structural checks. Keep source blend and existing catalogs unchanged.
Generated outputs remain ignored. Final sprite size and gameplay are outside this task.

## Implementation

The first base is 1,036 triangles across 17 mesh parts, using four simple material
regions: fur, cream muzzle/belly, pink ears/paws/tail and dark eyes. Body and limbs
have explicit normalized skin weights; hands and facial parts follow rigid bones.
The source rest pose remains a T-pose for predictable binding. The mesh is an original
simplification of the approved concept, not an image-to-mesh conversion.

The derived rig preserves all 65 source bone names and adds two ear bones and four
tail bones (71 total). Original source data and 120 actions remain preserved. Six
editable MouseBase_* actions reuse source upper-body motion with shorter-limb fitting,
grounded foot targets and restrained ear/tail secondary motion. They are sequenced on
separate NLA tracks with named timeline markers at 24 FPS.

| Clip | Source | Frames |
| --- | --- | --- |
| idle | Idle_Loop | 60 |
| walk | Walk_Loop | 32 |
| run | Jog_Fwd_Loop | 23 |
| punch | Punch_Jab | 22 |
| hit | Hit_Chest | 9 |
| celebrate | Celebration | 97 |

These are equipment-free motion studies, not final guard combat timing. Non-looping
clips pause briefly before repeating in the web/video review. The Blender timeline
sequences them directly, without authored transition blending.

Eight non-rendered bone-parented attachment markers cover helmet, torso, both shoulders,
both bracers, shield and weapon. Rigid equipment can parent to the matching marker.
Clothing must share the armature and receive skin weights; a torso marker does not
automatically fit or deform a tunic. No equipment meshes are present. Source finger
bones remain available, but this simplified base has mitten paws without individual
digit geometry. The visible body and limbs are separate skin parts, not a production
continuous-surface topology or an automatic universal clothing-fit system.

## Reproduce

Work from this task branch/worktree. Supply the existing pinned source file explicitly,
and put Blender and Python-with-Pillow on PATH or pass their executable locations:

    .\scripts\build-mouse-base.ps1 -SourceBlend <path-to-RTSAssets.blend> -Blender <blender-executable> -Python <python-executable>

Use -Preview for a sparse pose probe, or -Output artifacts/mouse-base-v2 for a separate
review revision. The generator only runs in background Blender and does not clear a
live user scene. It writes its own output folder; use a new output name to retain an
earlier iteration. The pinned source hash is checked before and after generation.

The full build produces mouse_base.blend, manifest.json, validation.json, front/side/
back/top references, shaded/game-camera sequences, palette-finished atlas previews,
dense loop sheets, video PNGs and a standalone index.html. Open the blend and press
Space over the timeline to inspect all six NLA clips. Open index.html in a browser to
compare shaded motion and pixel output; it is also usable through a local HTTP server.

Optional 12-second MP4 encoding, from the output folder with FFmpeg on PATH:

    ffmpeg -framerate 12 -i video/%03d.png -c:v libx264 -pix_fmt yuv420p -crf 19 -movflags +faststart mouse-base-motion.mp4

The review uses the existing pixel finisher and Woodland palette. Nominal 32/48/64
body heights use a common sole-to-crown scale excluding ears, with the actual 60-degree
game camera. The fixed canonical canvas is 224 square at the 64-pixel body scale,
anchor (112,128). All poses use that same framing. The hit reaction required a larger
canvas than the first trial; the body scale was preserved. The browser never stretches
the pixel canvas to fit CSS; effective integer magnification is capped to its panel.
All existing production and Woodland catalogs remain unchanged; these are review
atlases, not a newly published game catalog or final resolution choice.

## Verification on this Windows PC, 2026-09-14

- Full bake/render: 243 poses at each of two cameras; 729 pixel-finished frame variants.
- Saved blend reopened: source actions retained, 71 derived bones, eight sockets,
  normalized vertex weights, finite evaluated geometry and nonstatic NLA clips.
- Minimum foot height remains within 0.003 normalized units of the floor in every
  sampled frame. This checks grounding, not absence of foot sliding or all self-contact.
- Game-camera frame bounds pass across all six clips after the canvas correction.
- Python asset tests: 28 passed.
- Existing Woodland catalog validation and scripts/test-presentation.ps1 passed.
  The first presentation run failed because the sandbox blocked LÖVE's save-directory
  fallback; rerunning with normal save-directory access passed.
- Interactive preview loaded all six clips. Pause, resume and pose scrub were exercised;
  rendered model/pixel views and dense ordered pose sequences were inspected.
- Original source blend and production catalog SHA-256 stayed unchanged.

Human real-time motion approval, other-PC checks and production integration remain
separate. No new gameplay/performance claim is made; the previous full-suite performance
failure is not resolved by this art task. The tiny face is deliberately subordinate
to ears, head mass, stance and paw motion at gameplay scale.
