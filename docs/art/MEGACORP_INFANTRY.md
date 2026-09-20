# Megacorp pressure-suit infantry

Associate, Medic and Enforcer share rounded graphite pressure suits, short legs,
chunky boots and broad player-color shells. Their primary shapes differ:

- Associate: large bubble visor, compact two-handed carbine and low battery pack.
- Medic: small oval visor, horizontal capsule pack, pale chest panel and treatment wand.
- Enforcer: wide helmetless barrel, small porthole and one oversized impact gauntlet.

The geometric shells and neutral glass remain readable with either team color.
These squat rounded silhouettes contrast with the Orders' taller shields and armor.
The medical mark is secondary; recognition should survive its disappearance at zoom.

Associate and Medic occupy the same infantry size class. The Enforcer is a small
walking vehicle: its full assembly is twice the original infantry-sized Enforcer,
roughly twice their standing height, while retaining the broad barrel and gauntlet.
This is visual model scale; simulation collision and balance are unchanged.

## Editable source and export

`tools/blender/megacorp_model.py` builds named low-poly modules and rigid bone weights
on the pinned RTSAssets library. No fingers or facial rig are needed. The original
65 bones, rest transforms and source actions remain available in the saved scenes.
Derived actions use a fixed 0.62 leg-length ratio, wider shoulders and fitted grips;
the original skeleton is not destructively resized. Equipment follows named hands
or torso bones. The two-hand carbine has a measured support-grip gate.

```powershell
./scripts/export-assets.ps1 -Mode Preview -Roster megacorp_infantry
./scripts/export-assets.ps1 -Mode Build -Roster megacorp_infantry
./scripts/export-assets.ps1 -Mode Validate -Roster megacorp_infantry
./scripts/run.ps1 -AssetViewer
./scripts/test-presentation.ps1
```

The pinned local `art/source/rig-library/RTSAssets.blend` is required. Use `-Unit`
with an individual unit ID for a smaller rebuild. Generated scenes live at
`artifacts/asset-build/<id>/<unit>/<unit>.blend`; paired sprite atlases and metadata
live under `assets/generated/builds/<id>/<unit>/`. The active catalog identifies IDs.
These generated files are ignored; tracked recipes and scripts reproduce them.

The existing 60-degree orthographic profile, eight headings, twice-resolution
render/downsample, shared ground anchor and occlusion-aware team mask are reused.
`referenceHeight` supplies a fixed authored normalization for the shorter suits;
camera scale never changes between poses. Canvas expansion only prevents clipping.
Runtime sizing retains the shared 32-pixel body reference used by other units.
The Enforcer's `referenceHeight=0.725` doubles its assembly relative to the first
pass (`1.45`). Its recipe permits cells up to 256 pixels through `maxCellSize`;
other recipes retain the 128-pixel limit. Larger cells preserve pixel density and
all directional death poses rather than shrinking the unit to fit. The packer
continues to split paired pages at the existing 2048-pixel limit.

All three export idle, walk, attack and death. Associate fires a compact recoil
gesture; Enforcer punches with its oversized gauntlet. The unarmed Medic's required
attack clip is inert. Its extra looping `work` clip demonstrates treatment reach in
the viewer; gameplay currently has no healer-source presentation event to trigger
that clip accurately. This task does not change healing, damage, targeting or movement.
Sparse baked keys are sprite samples; recipe durations control runtime playback.

## Review and limits

Run `tests/verify_megacorp_blends.py` in background Blender, passing the repository
root after `--`, to reopen the latest batch. It checks source/action retention, floor
clearance, carbine grip, selected weapon/body surface intersections and all stored
directional bounds. It also renders enlarged gameplay and three-quarter views.
Add `--catalog` after the root to reopen all three active infantry assets, including
unchanged builds. This also verifies their standing-height ratios and uses identical
camera framing for the visual size comparison.
These targeted intersection checks are not a general collision proof.

With all three assets published, the presentation suite captures every clip sample
and heading with blue/red teams, fractional zoom on light/dark backgrounds, and a
mixed lineup beside same-team Orders sprites using the real game draw path. It
checks that presentation leaves canonical simulation state unchanged. Without the
assets it explicitly reports a skip.

Native-size silhouettes, team-color readability, walking cadence and transitions
still deserve human playtesting. Automated integrity and sampled-pose review do not
establish player approval or render equivalence on another GPU. Record actual local
verification and atlas costs in STATUS.md.
