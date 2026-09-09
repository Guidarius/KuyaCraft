# LoveRTS asset pipeline — implementation specification

Status: implementation specification. The source baseline below is historical; see ASSET_PIPELINE_VERIFICATION.md and STATUS.md for current implementation evidence and remaining human/cross-PC checks. Inspected against the current project and live Blender scene on 2026-09-09. This document supersedes earlier provisional sprite-size and new-rig recommendations. It complements the gameplay roadmap; it does not replace the simulation architecture.

## 1. Goal and user contribution

Build a repeatable production workflow that turns one supplied sophisticated humanoid rig and its animation library into original low-poly Bastion units, with stump hands, fixed equipment loadouts, eight-direction sprites, team colors, and reliable LÖVE playback.

The user supplies the rig and animation library only. Mesh generation, stump hands, equipment, material design, animation adaptation, cameras, lighting, export scripts, metadata, validation, and runtime integration are implementation responsibilities. Do not request additional meshes, rigs, animations, or reference art as prerequisites.

The first roster is shield infantry, worker, crossbow infantry, and Warden. The visual target is clean shaded sprites viewed from high overhead, with approximately 32 pixels of ordinary body height at default zoom, inside an initially 64×64 delivery canvas. This is our Brood War-inspired scale choice, not a measured claim about Blizzard asset dimensions.

A successful pipeline rebuilds from saved sources without an AI conversation or live Blender session. MCP is the authoring interface; checked-in scripts perform production. The game ships images and metadata, not Blender or skeletons.

## 2. Current evidence and migration baseline

### Supplied source inspected read-only

| Item | Observed value |
|---|---|
| Live file | `C:/Users/guido/Videos/Blender/LoveRTS/RTSAssets.blend` |
| Blender | 5.1.0 |
| Armature | `Armature`, 65 bones |
| Animation library | 120 actions, including idle, locomotion, sword, death, work, hit, and spell clips |
| Scene timing | 24 fps, fps_base 1.0 |
| Bound reference mesh | `Mannequin`, 8,546 vertices, armature modifier targeting `Armature` |
| Other mesh | `Icosphere`, 42 vertices, no armature modifier |
| Relevant action slot | `OBArmature` on sampled candidate actions |
| Save state | Live file has unsaved changes |

This proves availability and names, not animation quality, source licensing, ground contact, root-motion behavior, or correct equipment grips. Those receive explicit implementation checks below. Exclude the mannequin and unrelated objects from final renders by an allowlisted export collection; do not delete them from the supplied file.

### Existing game pipeline

- `tools/blender/export_unit.py` creates an original seven-bone shieldguard from scratch in an isolated factory-startup process. It uses Workbench, four poses per clip, eight directions, and a 1024×2048 atlas of 128×128 cells.
- `scripts/export-assets.ps1` exports that single proof. It does not yet ingest the supplied rig or select roster recipes.
- `src/sprites.lua` hard-codes shield-only playback, 128 frames, four frames per clip, 128-pixel cells, and scale 0.65. Its mask shader is a useful prototype to retain and generalize.
- `src/sprite_proof.lua` displays representative static frames. It is not yet the required motion-review viewer.
- Current camera projection is 26 pixels per X navigation cell and 19 per Y cell. The new camera profile must be integrated with the inverse picking transform, not changed only in Blender.
- Combat applies damage on an attack tick; explicit windup and projectile flight are absent. The application currently displays corpses for 40 simulation ticks. Audio is disabled.
- Generated assets under `assets/generated/` are already ignored, and packaging copies that directory. Preserve this convention.

STATUS.md records prior local tests and a shieldguard visual proof. Those are historical baseline evidence, not fresh tests of this plan. No gameplay or source-rig edits are made by finalizing this document.

## 3. Preserve the source and adapt its rig

### Intake and ownership

1. Preserve the live unsaved state by saving a copy to an owned staging location during implementation; do not overwrite the user's source or load a factory scene into their interactive session. Use Blender's save-copy behavior, keeping the current main-file association.
2. Record the saved-copy hash, Blender version, effective fps, source origin, external dependencies, armature, bones, actions, slots, NLA tracks, constraints, drivers, and packed textures. Audit scripted drivers and external dependencies before batch execution.
3. Store an immutable source copy under `art/source/rig-library/` and keep recipes under `art/recipes/`. Keep the original library separate from generated working scenes. Large source binaries use the project's source-asset storage policy; until one exists, retain the local source and a tracked acquisition/hash manifest. Do not distribute third-party source files without confirming their permissions.
4. Pin the saved source hash for a batch. Never quietly rebuild against later unsaved live edits. A deliberate source refresh creates a new recorded revision and invalidates dependent exports.
5. All subsequent builds use separate background Blender processes. Only the asset worker controls the interactive Blender session.

### Keep the full skeleton

Keep all 65 source bones and all original actions. Finger bones are harmless in an offline renderer and may be referenced by curves, constraints, or action slots. Do not prune, rename, regenerate, or apply transforms to the source armature to simplify the visible model.

Bind generated stump meshes rigidly to `hand_l` and `hand_r`. They have no finger geometry or finger weights. Preserve wrist orientation; do not bind the whole hand to the forearm and lose useful wrist animation. Use a rounded low-poly capsule or mitten-like stump with a clearly defined palm/grip center.

Use the original rest skeleton as the first rig family. Normalize scale and forward direction through a parent export root, applied to the entire assembly, rather than changing source bone lengths. Use stocky surface proportions around those joints; substantially different anatomical proportions belong to a later explicit retargeting profile.

### Semantic map

| Role | Source bone |
|---|---|
| Motion root / hips | `root` / `pelvis` |
| Torso | `spine_01`, `spine_02`, `spine_03` |
| Head | `Head` |
| Left arm / hand | `upperarm_l`, `lowerarm_l`, `hand_l` |
| Right arm / hand | `upperarm_r`, `lowerarm_r`, `hand_r` |
| Left leg / foot | `thigh_l`, `calf_l`, `foot_l`, `ball_l` |
| Right leg / foot | `thigh_r`, `calf_r`, `foot_r`, `ball_r` |

Validate all mapped bones before generation. Bone-local, armature, and world transforms must be converted explicitly. Keep attachment transforms relative to the actual wrist/palm, rather than assuming the bone tail is the grip point.

## 4. Generate the unit family

Create original, recipe-driven low-poly meshes using simple rings, boxes, capsules, and wedges around the rig. Begin with roughly 1,000–3,000 triangles per dressed unit as a working budget, not a reason to sacrifice silhouettes. Use rigid head/armor/equipment binding and short blended transitions at elbows, shoulders, knees, and hips. Verify deformation in extreme poses before adding detail.

| Unit | Visible recipe | Motion adaptation |
|---|---|---|
| Shield infantry | Helmet, tunic, boots, shield, sword, large team cloth region | Sword attack; corrected shield carry |
| Worker | Same body family, simple clothes, tool, recipe-attached back cargo bundle | Walk, work, loaded/unloaded variants |
| Crossbow infantry | Narrower armor, horizontal crossbow silhouette | Authored two-hand aim/fire/recovery based on source motion |
| Warden | Same skeleton, larger crest/shoulders, distinct armor and weapon | Sword motion with stronger silhouette and stance pose |

Fixed loadouts are rendered as complete units. Do not introduce layered runtime equipment compositing. Team colors use a mask rather than rendering one atlas per player.

Worker cargo uses two complete baked visual assets: `worker` and `worker_loaded`. The loaded recipe inherits the body, tool, rig, and all five clips, adds a back-mounted bundle, and applies a modest carry-posture correction. It shares the unloaded canvas, anchors, clip durations, sample counts, and phase. Select the loaded asset when the filtered entity's existing `cargo` quantity is greater than zero, retaining animation phase on deposit/pickup transitions. Do not create a new gameplay carry flag. The loaded asset includes attack, death, and work as well as idle/move so cargo does not disappear when changing clips. Use a generic bundle for both resource types initially; separate gold/lumber art variants are deferred. Both recipe variants are required for the roster gate and are assembled before rendering, never composited in-game.

Create named hand sockets with saved position/rotation offsets. For two-handed weapons, treat the weapon and its two grip markers as the reference, correct both hands in derived actions, and bake the result. Never hope two independent hand paths remain on the handle. Check the palm surface against the grip and the whole weapon sweep against head, shoulders, shield, and ground.

No cloth simulation is required. If a Warden cloth accent is included, use a small keyed secondary-motion chain on a derived rig only; defer it if it threatens the first roster. The source rig and library remain unchanged.

## 5. Curate and normalize animations

### Initial clip mapping

| Runtime clip | Source starting point | Required handling |
|---|---|---|
| `idle` | `Idle_Loop`; `Sword_Idle` for armed variants | One full cycle; equipment carry correction |
| `move` | `Walk_Loop`; `Jog_Fwd_Loop` retained as an alternate | Remove planar travel and preserve foot phase |
| `attack` | `Sword_Attack_Standing` | Identify contact; correct stump grip and shield clearance |
| `death` | `Death01` | Preserve fall, settle on ground, hold final pose |
| `work` | `Fixing_Kneeling` as reference | Author a standing tool cycle for harvest; do not blindly reuse kneeling repair |
| `hit` | `Hit_Chest` | Optional review clip; runtime tint is sufficient initially |
| Crossbow attack | Derived authored action | Source contains no named crossbow clip; do not relabel pistol fire as finished crossbow motion |

Reserve spell, celebration, dodge, and alternate movement clips for future content. Inventory all 120 actions, but export only recipe-selected clips.

Candidate names are fixed starting points, not proof that every candidate is suitable. Review them on the generated body. If a required candidate fails, author a derived correction under the same runtime clip ID and document it; no new user-supplied animation is required.

### Sampling and baking

- Select both the action and its Blender 5.1 action slot. Disable unrelated NLA contributions in the isolated export scene. Preserve all source actions with persistent references in the source copy.
- Respect fractional action endpoints: observed ranges include 36.799999… and 57.600002…. Sample normalized time with frame plus subframe; do not truncate to integer endpoints. Effective fps is `fps / fps_base`.
- Loop sampling excludes the repeated endpoint. Nonloops include both ends. Store source duration separately from intended presentation duration.
- Start with idle 4 samples/one-second presentation loop, move 8 samples/reference cycle duration, attack 6 samples, death 8 samples/approximately one-second presentation, and worker work 8 samples. Increase samples only where visible motion requires it.
- Remove planar root translation and accumulated heading for locomotion using an export wrapper or baked derived action. Preserve vertical body motion, gait, and local foot relationships. Do not cancel death's intended body fall or flatten pelvis motion indiscriminately.
- Measure reference stride distance before removing root travel; use it to tune presentation playback against visible movement. If source motion is already in place, record a measured stance-foot stride instead.
- Bake constraints and procedural corrections into derived working actions before rendering. No dependence on interactive timeline playback or unbaked physics caches.

### Honest combat timing

Current damage is instantaneous on `attackTick`. The initial runtime shows the contact sample on that tick followed by recovery; the asset viewer still previews the complete windup/contact/recovery clip. Do not invent anticipation before an unknowable future attack or postpone damage to match art.

Export `contactFrame` as presentation metadata. It never causes damage. Full windup/cancellation and traveling projectiles require a separate simulation change, with new regression and replay checks, before the game uses those full phases. Until then, ranged feedback uses an immediate tracer/impact. Death playback clamps to the final pose and fits within the existing corpse visibility window; extending corpse policy is separate presentation work.

## 6. Camera, lighting, masks, and packing

### Locked profile: `bastion_overhead_v1`

- Blender 5.1.0, Eevee, Standard color transform, fixed exposure/gamma, fixed sample count recorded in the profile.
- Orthographic camera at 60 degrees above the ground; no perspective, depth of field, motion blur, or camera auto-fit.
- Fixed broad key and fill lights. Lights stay in world space while the entire character assembly rotates around its projected ground origin.
- Canonical generated forward is negative Y, Blender Z is up. Explicitly label image headings `N, NE, E, SE, S, SW, W, NW`; do not infer runtime direction from action names or assume the old atlas numbering agrees.
- Normalize the ordinary reference body's standing height to one Blender unit through the export parent. Use 64 delivery pixels per Blender unit, giving about 32 pixels projected vertical height at this camera elevation. Warden size may be 1.15 times the ordinary body through its recipe.
- Default delivery cell 64×64, rendered 128×128, with projected ground anchor at (32, 40) in delivery pixels. Larger 96/128 cells retain pixels-per-world-unit and expand around that anchor; never shrink one clip to fit.
- Scan bounds across every sampled pose/direction before rendering. Use one canvas per unit covering every clip. Reject clipping, or select the next approved canvas size automatically and record it.
- Transparent background; simple runtime ground shadow. Self shading is baked, ground shadows are not.

Integrate the profile with the existing camera: retain 26 horizontal pixels per navigation cell and use `26 * sin(60 degrees)` vertically in presentation for the new profile. Update inverse picking and placement in the same change. This alters no simulation coordinates. Verify cardinal and diagonal travel with an asymmetric direction fixture; diagonals are headings on the ground plane, not necessarily 45-degree screen-space lines.

### Color and team passes

Use neutral shaded material on team regions. Generate an aligned unlit coverage mask using white team regions and black occluding non-team surfaces, preserving the same geometry, visibility, camera, and sample positions. Mask values are coverage, not display-color data.

Downsample color with alpha-aware filtering; unpremultiply if needed for the runtime's chosen straight-alpha representation. Downsample masks as coverage. Check outlines and partial coverage against both bright and dark backgrounds. The shader replaces neutral team-region color while retaining luminance; masked and unmasked edges must not acquire dark fringes.

### Atlas layout

Use stable unit/clip/direction/frame ordering, two delivery-pixel gutters with edge-color extrusion, no frame rotation, and no trimming initially. Cap pages at 2048×2048. Keep color/mask page layouts identical. Use linear filtering for the clean rendered style and no mipmaps in v1; gutters protect fractional zoom sampling.

Four base units using 4+8+6+8 samples plus eight worker-work samples require 896 directional poses. The additional loaded-worker variant repeats its five clips, adding (4+8+6+8+8)×8 = 272 poses, for a required roster budget of 1,168 poses. Each pose has color and mask output. Time a representative subset including mask work, downsampling, and packing; do not estimate throughput from a single easy render.

## 7. Build interfaces and reproducibility

Extend the existing wrapper rather than creating a competing export path. The following production commands are implemented; see the verification record for executed checks:

```powershell
.\scripts\export-assets.ps1 -Mode Inspect -SourceBlend <saved-source-copy>
.\scripts\export-assets.ps1 -Mode Preview -Unit shieldguard
.\scripts\export-assets.ps1 -Mode Build -Unit shieldguard
.\scripts\export-assets.ps1 -Mode Build -Roster bastion
.\scripts\export-assets.ps1 -Mode Validate -Roster bastion
.\scripts\run.ps1 -AssetViewer
```

Retain the existing `-Blender` executable override. Add `-Force` to bypass caches, not validation. Empty/unknown units, actions, bones, slots, or source hashes fail clearly. A plain export command builds the default Bastion roster after migration; provide an explicit legacy-proof mode while v1 remains supported.

Tracked recipes define source ID/hash, export collection, rig profile, body/equipment/material choices, selected actions and slots, source frame intervals, runtime clips, contact marker, and render profile. Validate input before starting a long batch. Store machine-specific executable/source paths in local configuration rather than hard-coding another user's profile.

Hash source dependencies, recipes, derived-animation corrections, scripts, Blender version, render profile, and packing settings. Rebuild only invalidated units. Record failures per unit and return nonzero if any requested unit fails; successful subset output does not count as a successful roster build.

Build into `artifacts/asset-build/<build-id>/`, then validate and copy to a new immutable directory beneath `assets/generated/builds/`. Publish the small active catalog manifest last through same-volume atomic replacement, retaining its previous version. Packaging reads the active catalog and includes only referenced complete builds. Never expose an atlas with metadata from a different build.

Outputs include color/mask PNGs, Lua runtime metadata, equivalent JSON inspection metadata, contact sheets, motion previews, dependency inventory, timings, and validation report. Derived editable `.blend` files live in artifacts; source recipes and any authored corrections must remain reproducible. Source assets stay outside the shipped game.

GPU renders are not promised bit-identical across drivers or hardware. Stable manifests/order and same-pinned-environment rebuild checks are required; visual comparison on other machines is tolerance-based. Simulation determinism is a separate guarantee.

## 8. Runtime schema and migration

Introduce a version-2 asset catalog while retaining a read-only v1 adapter for the existing shieldguard proof until v2 passes. Keep artwork metadata outside authoritative content hashes; confirm the actual replay fingerprint boundaries before changing code organization.

Minimum v2 contract:

| Field | Meaning |
|---|---|
| `version`, `unitId`, `buildId`, `profileId` | Identity and format compatibility |
| `pages` | Ordered color/mask file pairs and page dimensions |
| `directions` | Ordered eight-heading labels |
| `frames` | Page index, x/y/width/height, anchorX/anchorY for each frame |
| `clips` | Named clips with ordered frame IDs per direction, integer presentation duration in milliseconds, loop flag, optional contactFrame |
| `referenceStride` | Optional presentation stride length and units |
| `bodyHeightPixels` | Reference size for inspection; not a per-frame scale correction |

Use one-based page/frame IDs in Lua and JSON, zero-based top-left pixel rectangles, and anchors in untrimmed cell coordinates excluding gutter. JSON and Lua must describe the same catalog. No implicit index formula such as `clip*32+direction*4+frame` remains in v2.

Replace the shield-only loader with a catalog keyed through a presentation mapping from gameplay kind to asset ID. Build quads from metadata; preload pages and shaders outside draw/update hot paths. Unknown or corrupt v2 assets produce a conspicuous diagnostic placeholder and log entry while leaving simulation unaffected. A release with required invalid assets fails packaging validation even though developer fallback exists.

Use a frame selector that can be tested without graphics. Resolve moving direction from world-ground motion, attack facing only from permitted target data, and retain last known heading while idle. Keep direction/phase caches in presentation and clear them on restart/restore/seek. Do not use screen-space angle for an anisotropically projected ground plane.

Maintain visibility filtering and stable ground-depth order. Batching may combine only draws compatible with that order and mask bindings. Selection rings and picking use ground positions, not animated torso bounds. Unit animation cannot change movement, damage, vision, cooldowns, commands, or snapshots.

## 9. Asset viewer and feedback integration

Extend the sprite proof into a LÖVE viewer with unit/clip/direction selectors, play/pause, frame stepping, speed control, 1× and enlarged views, team-color switching, terrain backgrounds, ground/anchor guides, rectangle overlays, and source/build information. Show all eight directions simultaneously and a small mixed-roster crowd. Save contact sheets and a recorded preview to artifacts.

Check these states at default gameplay zoom: idle identity, gait, turn changes, weapon contact, death settling, worker work, carrying, and two teams on light/dark ground. A clean still does not prove continuous motion.

For the overnight game integration, preserve the agreed tactile, restrained presentation: immediate selection/order markers, authoritative rejection messages, small hit flashes, clear death and production cues, and distinct silhouettes. Use tick/event identity to consume effects once and filter them before sound or particles reveal hidden activity.

Audio enablement, HUD redesign, bot tuning, and the 8–12 minute prototype preset are companion workstreams, not exporter requirements. Their implementation owner must preserve the core's existing command path. No routine camera shake or global hit-stop is needed to prove the assets. Current instant-hit timing limits remain visible in the handoff.

## 10. Implementation order and overnight ownership

| Phase | Deliverable | Gate |
|---|---|---|
| 0: intake | Saved source copy, inventory, dependency/hash manifest | All required bones/actions/slots resolve; original scene preserved |
| 1: rig adaptation | Generated stump-handed shieldguard bound to source rig | Rest, gait, attack, death poses deform acceptably |
| 2: exporter | Eight-heading sample, color/mask, v2 metadata | Correct direction, 32-pixel scale, anchor, bounds, alpha |
| 3: runtime | v2 loader, viewer, in-game shieldguard | Continuous playback and old v1 proof both work |
| 4: roster | Worker unloaded/loaded, crossbow, Warden recipes and derived clips | All requested outputs pass; identities distinct at 1×; cargo transitions preserve phase |
| 5: handoff | Incremental rebuild, clean package, evidence | Rebuild without MCP; package loads active catalog |

One integration lead owns existing main/app wiring, camera conversion, replay-sensitive boundaries, and packaging. An asset worker exclusively owns Blender/recipes; a runtime worker owns the v2 loader/viewer; a UI/feedback worker owns bounded companion modules. Freeze interfaces and shared-file ownership before parallel work, checking the core task's current changes first.

For an eight-hour run: first 30 minutes intake and baseline; by hour two a correctly labeled eight-direction sample in LÖVE; by hour four one complete derived unit and measured throughput; by hour six integrate roster work and freeze additions; final two hours verify, fix, and package. These are decision checkpoints, not completion promises.

If throughput is insufficient, keep one complete source-rig-derived unit and explicit distinct placeholders for the rest in the overnight game build. The full asset-pipeline goal remains incomplete until the roster gate passes; a fallback must not be relabeled as finished production. Cut decorations, extra actions, cloth, portraits, and a Blender panel before correctness. The command interface and LÖVE viewer are sufficient for v1; an add-on panel can later wrap them.

## 11. Acceptance and evidence

### Automated or reproducible

- Intake verifies source hash, bone names, action slots, external dependencies, and saved-file reproducibility. Preserve unsaved user work and compare the untouched original source where applicable.
- Mesh check finds zero visible finger geometry and confirms both stumps follow hand bones; finger bones remain intact in the source family.
- Sample time tests cover fractional endpoints, loop endpoint omission, nonloop endpoint inclusion, root-motion removal, and death clamping.
- Fixture export proves eight labels, asymmetric handedness, common anchors, no clipping, valid alpha, aligned mask/occlusion, page bounds, and gutters.
- Lua/JSON catalogs agree; frame selector covers varying clip lengths and pages. Unknown versions, missing frames, mismatched masks, and corrupt files fail clearly.
- Worker zero/nonzero cargo selects unloaded/loaded complete assets without changing clips, phase, anchor, or gameplay quantity; both variants cover every required worker clip and package validation requires both.
- Export interrupted before catalog publication preserves the previous usable roster. Changing one recipe invalidates only its dependencies. A saved-source rebuild works with Blender MCP disconnected.
- Camera/picking round-trips and directional movement pass at normal and fractional zoom. Existing v1 proof remains supported during migration.
- Run `scripts/test.ps1` after integration; compare the same command replay with v1/v2/fallback assets and effects disabled. No gameplay golden is silently changed.
- Validate package contents against the active catalog and launch it outside the development directory without Blender installed or invoked at runtime.
- Measure actual 60-versus-60 presentation with UI/fog/effects and preserve the roadmap's 240-unit stress scenario. Record p95 frame/tick times, GPU/CPU/runtime, memory, export time, and artifact paths; do not equate idle simulation performance with busy-battle performance.

### Visual and human checks, reported separately

- Continuous gait and loop closure at 1×; no anchor hopping, wrist separation, weapon/head crossings, or floating corpse.
- Shield, crossbow, worker, Warden and team ownership recognizable without labels.
- Team edges clean against dark/light terrain; no clipped swing or halo at fractional zoom.
- Contact/recovery agrees with current instant-hit behavior. Full source animation looks correct in the viewer; deferred gameplay windup is not claimed implemented.
- Review a playable fight for clutter, responsiveness, and sound fatigue when the companion feedback work is available.
- Cross-PC and human playtest evidence is explicitly marked unperformed until actually collected.

### Completion audit for this planning task

The plan is complete when it identifies the actual provided library and existing exporter/runtime, requires only the promised rig from the user, specifies original mesh/stump generation without destructive skeleton edits, defines action/slot and root-motion handling, provides render/catalog/build contracts, maps runtime migration and gamefeel constraints, and lists ordered implementation and verification gates. Completing this document does not claim those future gates passed.

Implementation handoff must report delivered units/clips, exact build/test commands, known limitations, source/build IDs, rendered previews, and what still requires human review. Keep milestone status evidence-based in STATUS.md.
