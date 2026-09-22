# Footman overhead equipment review

Scope: improve the Orders Footman's shield visibility and sword presentation under
the existing 60-degree orthographic camera. Preserve body scale, source rig, gameplay,
other units and the faction's kite-shield identity.

The baseline carries a thin sword through the source sword animation and places the
shield along the left flank. Review all eight headings and idle, move, attack and death
before accepting changes. Keep before/after comparisons at the same scale and anchor.

## Findings and changes

The baseline shield face was vertical and close to the torso. From the 60-degree
camera it often became a thin edge, with its team field merging into the tabard.
The sword blade was only .09 source units wide and .025 thick (about 1.56 and .43
delivered pixels before projection). Its source carry orientation amplified that
loss of readability.

The derived Footman now tilts his shield upward 45 degrees relative to his torso
and carries it farther outboard. The kite outline, rim and team field remain intact.
The sword keeps its .52 blade length, but has a .15-wide, .044-thick tapered blade.
Its right arm has an explicit forward ready pose and a six-sample windup, strike,
follow-through and recovery. Contact remains sample 3 of the existing 700 ms clip.
These corrections are baked onto derived actions; original source actions and the
65-bone rig remain available in the saved scene.

Review covered all eight headings and all 208 idle/move/attack/death poses, with
matched before/after backgrounds, fixed anchors, native pixels and 3x inspection.
Front and side shield faces are more distinct, and the broader blade survives the
overhead view. Rear-facing shield occlusion remains visible, especially N/NE;
the shield is not forced through the body. The inherited torso turn makes its
projected shape vary during attack. Death retains the source fall and existing
ground correction. The blade remains attached through the fall.

The wider review also shows limits outside this equipment pass: the helmet dominates
the upper silhouette, heraldry is too small to read as a symbol at native size, and
shield/tabard team colors can merge. Idle, movement and death use different source
body poses; this pass does not provide cross-clip skeletal blending. Human review of
the transition feel and readability in a crowded live match is still needed.

## Reproduction and evidence

From the task checkout, run:

```powershell
./scripts/export-assets.ps1 -Mode Build -Unit footman -Roster orders_units
./scripts/export-assets.ps1 -Mode Validate -Unit footman -Roster orders_units
python scripts/review-footman.py --root . --baseline assets/generated/builds/39ccd959f9eccb416f8bd4cc/footman/metadata.json
```

The review helper requires Pillow and the baseline generated build to remain locally
available. It writes all eight contact sheets to `artifacts/footman-review`.
The runtime review uses `--orders-review --review-page 3 --review-unit 3` for all
samples, or `--orders-lab --orders-test` for the gameplay fixture.

Validated build: `2f7c44f21da2da741599435c`; canvas 96x96; anchor (48,56).
No per-frame rescaling, timing, gameplay, body geometry or camera changes.
Generated output is local to the task checkout and excluded from commits.

Checks performed:

- Full export: 208 poses, paired color/team-mask renders, successful publication.
- Asset Validate: passed; 33 Python asset tests: passed.
- Saved Blender reopened: 208 evaluated poses exactly matched export bounds;
  minimum Z -0.001519, within the existing -0.002 tolerance; 34 editable meshes.
- `scripts/test-presentation.ps1`: passed with normal user save-directory access.
  The initial sandboxed attempt failed the replay fallback save test.
- Orders gameplay fixture: presentation and roof-pixel checks passed, with canonical
  simulation unchanged by rendering.
- Shipping shader contact sheet and gameplay screenshots inspected; no human
  playtest or second-PC check was performed.

The source equipment remains hand-bound procedural geometry. This pass establishes
a better sword/kite pose for later reusable Blender equipment and complete variant
exports; it does not add runtime equipment layers or claim a finished item library.
