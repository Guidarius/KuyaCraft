# LoveRTS — Balance, scale and match pacing

Profile: `marches-v1`, content version 4, simulation version 8. These are LoveRTS starting values inspired by Warcraft-style pacing, not a transcription of Blizzard's unit database. Match duration is a playtest target, not a timer that forces an outcome.

## Intent and rules

- Target 15–25-minute 1v1 matches with a developed army of one hero and roughly 15–25 combat units, plus 12–18 workers. Measured against this on every balance run: see `artifacts/balance-pacing-mirror.txt` and `-asymmetric.txt`, written by `scripts/test.ps1 -Suite balance`. Both currently finish in 9–11 minutes, and the report shows why that number is misleading — the matches are decided around five minutes and spend the rest of their length finishing.
- Start with a completed headquarters, hero, three workers and 650 gold. No initial combat troops. Workers are engineers only; nothing harvests.
- One headquarters advancement unlocks the faction's support and heavy units. Worker production continues during research.
- Fixed 80 food, weighted by unit role. No supply buildings, upkeep, inventory, recall, or armor/damage-type matrix.
- Protect units, retreat on foot, recover at the base, and contest camps and expansion mines.
- Destroy the headquarters to win. An outpost does not replace it for victory, recruitment or revival.

## Coordinates, unit sizes and camera

Simulation remains 20 ticks/second and 256 integer subunits/cell. `src/content_time.lua` converts author-facing seconds and cells into exact tick/subunit values, rejecting unsupported fractions. Authoritative state contains integers; UI conversion to seconds does not affect gameplay.

| Body | Radius in subunits | Diameter in cells |
|---|---:|---:|
| Worker | 72 | 0.5625 |
| Ordinary combat unit | 80 | 0.625 |
| Hero | 96 | 0.75 |
| Heavy/ram/camp leader | 112 | 0.875 |

Collision uses the existing circle-clearance and deterministic crowd system. Allied spacing retains that system's existing reduced separation; hostile bodies use full radii. Weapon ranges below are **edge-to-edge**, including target building footprints. Short melee ranges require subcell contact destinations, not only navigation-cell centers. These contact coordinates are part of the saved path and use ordinary collision-checked movement.

The default camera shows 24 cells vertically in the unobscured battlefield, independently of window height and UI scale. Zoom is 80–135% of that baseline. Horizontal coverage follows aspect ratio. Camera orientation remains fixed. Sprites, footprints, picking, terrain and selection all share the effective world zoom; HUD scaling remains independent.

At 1080p/100% UI, the ordinary sprite body target is about 51 pixels, workers about 42 pixels and heroes about 61 pixels. Metadata body heights calibrate this; weapons, hats and animation silhouettes can extend beyond the body. Selected buildings display their footprint. Buildings and mines are picked by their projected extent, not a large circle around one corner.

## Twin Marches

Default skirmish map: **192×192 cells**, 1v1, with 180-degree paired terrain, resources, camps, roads and starting units. It replaced the first 128×112 layout at simulation version 11 to give Warcraft 3-scale distances. Legacy `river_pass`, `open_fields` and `movement_lab` remain available as smaller scenarios. 256×256 is the largest map the simulation accepts; the collision bins, lane cache, bounded distance helper and path keys all assume it.

| Feature | First side | Opposite side |
|---|---|---|
| HQ footprint origin | (20,20), 5×5 | (167,167), 5×5 |
| Hero rally cell | (28,18) | (163,173) |
| Home mine origin | (21,10), 12,000 gold | (168,179) |
| Natural mine origin / outpost anchor | (58,14) / (50,28) | (131,175) / (141,163) |
| Forward mine origin / anchor | (54,74) / (66,70) | (135,115) / (125,121) |
| Contested corner mine | (174,14) north-east | (15,175) south-west |
| Easy camps | (48,31), (66,80) | rotated counterparts |
| Medium camps | (110,26) north corridor, (25,118) west corridor | rotated counterparts |
| Hard camps | (166,32) guarding a corner, (88,100) in the center | rotated counterparts |

Footprint origins rotate as `(width-x-size, height-y-size)`; unit cells rotate as `(width-1-x, height-1-y)`. Approximate area anchors are not footprint origins. Using this distinction prevents one-cell symmetry errors for odd and even footprints.

The layout is a base clearing, a natural to its east, a forward expansion on a fifteen-cell-wide main diagonal through a large central clearing, and two long outer corridors to the corners. Each corner is nearer one player — the north-east is reached along the north corridor from player one's natural, the south-west from player one's forward expansion — and the rotation makes that fair.

### Roads

Roads are a map layer, `map.unbuildable`: walkable, three cells wide, and **nobody may build on them**. They run home mine to headquarters, headquarters to natural to corner, headquarters to forward mine to the other corner, and forward mine to the center, where they meet the other player's. Mines and headquarters are the junctions, so every gold mine is joined to every other and to both headquarters. The purpose is that no wall of buildings, yours or an enemy's, can cut a mine off from the bases.

`Sim.placement` refuses a road cell with *Cannot build on a road*, and the build command revalidates through it, so the rule is authoritative rather than cosmetic. An extractor still goes on its own mine where a road ends. Roads change nothing about movement speed or sight. A regression test floods the road network from one headquarters and requires it to reach every mine and the other headquarters.

Measured infantry routes use the actual pathfinder with speed 35, per-segment integer movement rounding, and no crowd delays. Strategic targets are the 128×112 targets scaled by 1.5 with the map width; the local approaches keep theirs:

| Route | Measurement | Target |
|---|---:|---:|
| Rally to enemy rally | 76.30 s | 60–83 s |
| Center to rally | 38.65 s | 30–42 s |
| Via the south-west corner (22,160) | 109.70 s, +43.8% | reported only: a detour, not a flank |
| Natural approach at (54,26) | 9.95 s | 10–15 s |
| First easy camp at (48,29) | 8.35 s | 8–12 s |

The first layout measured 46.05 s rally to rally, 23.30 s center to rally, 7.25 s to the natural and 6.00 s to the first easy camp. `artifacts/balance-routes.txt` is the regenerated source of measurements.

## Economy and food

**Superseded from simulation version 8.** Workers no longer harvest and lumber no longer
exists. The economy is extractors and carriers, and its design, arithmetic and measured
rates live in [RESOURCE_FLOW.md](RESOURCE_FLOW.md). The summary:

| Rule | Value |
|---|---|
| Starting stockpile | 650 gold |
| Starting workers | 3 |
| Carrier payload | 8 gold |
| Emission interval | 16 ticks (0.8 s) |
| Deliveries in flight per extractor | 9 |
| Carrier speed / HP / food | 40 subunits per tick / 40 / none |
| Carrier corpse before the slot recycles | 40 ticks |
| Starting mine | 12,000 gold |
| Each expansion mine | 9,000 gold |
| Forests | terrain, not a resource; they block movement and sight |

Measured: a near mine pays **600 gold/minute**, a far one **344**, and an outpost beside
the far one restores it to **600**. The two scenarios that measure this are in
`tests/balance.lua` and print `BALANCE gold/min:` on every balance run.

Carriers deliver to the nearest living friendly drop-off — the headquarters or a completed
outpost — chosen by squared distance with the entity id breaking ties. One cached A* route
per extractor is shared by every carrier it emits and is recomputed when the obstruction
set or the destination changes; no carrier ever calls the pathfinder. Carriers are their
own entity category: not selectable, not in the collision bins, no crowd resolution, no
food and no orders. They are ordinary combat targets, and a carrier that dies destroys its
gold rather than handing it over.

| Unit role | Food |
|---|---:|
| Worker | 1 |
| Hero | 5, reserved while dead or reviving |
| Basic melee | 2 |
| Ranged | 3 |
| Support | 2 |
| Heavy | 4 |

Recruitment reserves food and resources on acceptance. Cancelled recruitment releases food; unit death releases food except the hero's reservation. The HUD displays **Food / 80** and actual living **Units** separately.

## Buildings and technology

Costs below fold the old lumber price into gold one for one, so relative prices are
unchanged from the two-resource profile.

| Building/action | Gold | Seconds | Ticks | HP | Footprint |
|---|---:|---:|---:|---:|---|
| Initial HQ | free | complete | — | 2,800 | 5×5 |
| Extractor | 120 | 30 | 600 | 900 | 3×3, on a mine |
| War hall | 220 | 60 | 1,200 | 1,500 | 4×4 |
| Outpost | 530 | 90 | 1,800 | 1,400 | 4×4 |
| Watchtower | 220 | 45 | 900 | 700 | 2×2 |
| HQ advancement | 600 | 100 | 2,000 | unchanged | unchanged |
| Gold mine | — | — | — | resource | 3×3 |

One worker builds a site; no multi-worker acceleration. Construction time begins while the assigned worker is in work range. A site reserves its entire footprint immediately, starts at 10% health capacity, and gains capacity with progress. Damage persists through construction; finishing does not heal away damage already taken.

Construction cancellation refunds 50%. An unstarted production item refunds 100%; an item already training refunds 50%. HQ advancement uses a separate timer, grants one permanent player flag on completion, and refunds 50% on cancellation. Losing a researching HQ ends that player's participation. All war halls check the same completed advancement flag.

| Defender | Damage | Impact period | Windup | Edge range |
|---|---:|---:|---:|---:|
| HQ | 30 | 1.5 s | 0.3 s | 8 cells |
| Watchtower | 26 | 1.6 s | 0.3 s | 7.5 cells |

HQ recovery heals up to three injured friendly units for 10 HP each per second within six cells of its center, after eight seconds without dealing or receiving damage. Support healing takes precedence on that pulse; the same target cannot also receive HQ recovery. No building healing.

## Recruitable units and heroes

All times include the complete production duration. Period means consecutive committed impacts; windup is part of the attack cycle, never added again to its steady cadence. Movement before impact cancels the hit. Movement after impact cannot erase the committed recovery deadline.

| Unit | Gold | Food | Train s | HP | Damage | Period s | Windup s | Edge range cells | Speed subunits/tick | Cells/s |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Worker | 75 | 1 | 15 | 220 | 5 | 2.0 | .30 | .25 | 30 | 2.344 |
| Shieldguard | 135 | 2 | 20 | 420 | 14 | 1.4 | .30 | .25 | 35 | 2.734 |
| Crossbow | 220 | 3 | 26 | 320 | 22 | 1.6 | .35 | 5 | 35 | 2.734 |
| Standard bearer* | 195 | 2 | 28 | 300 | 8 | 1.8 | .30 | 4 | 35 | 2.734 |
| Ram* | 380 | 4 | 40 | 900 | 60 | 2.5 | .50 | .5 | 26 | 2.031 |
| Stalker | 130 | 2 | 20 | 340 | 13 | 1.25 | .25 | .25 | 40 | 3.125 |
| Thorn thrower | 210 | 3 | 25 | 280 | 19 | 1.45 | .30 | 4.5 | 37 | 2.891 |
| Grove sprite* | 190 | 2 | 28 | 250 | 7 | 1.6 | .25 | 4 | 39 | 3.047 |
| Heavy beast* | 350 | 4 | 36 | 760 | 34 | 1.7 | .40 | .375 | 35 | 2.734 |
| Warden | initial hero | 5 | — | 1,000 | 30 | 1.5 | .30 | .25 | 42 | 3.281 |
| Beastkeeper | initial hero | 5 | — | 900 | 27 | 1.35 | .25 | .25 | 44 | 3.438 |

`*` requires HQ advancement. Ordinary sight is 12 cells, workers/ram 10, heroes/HQ 14, other buildings 12.

Standard bearers heal one injured ally for 12 HP/second within five cells; sprites heal one for 10 HP/second within four. Lowest current/max HP fraction wins, then entity ID. Multiple healers choose different recipients on a pulse. Healing excludes buildings. This avoids the old unlimited stacking group heal.

The isolated shieldguard duel without auras or healing measures **41 seconds**. Focus fire, positioning, heroes and healing change survival substantially; solo TTK is a calibration fixture, not a promised duration for battles.

## Heroes, experience and camps

Warden: six-cell protection aura, reducing each incoming hit by three in defensive stance or one in offensive stance. Offensive stance adds four damage.

Beastkeeper: eight HP/second personal recovery after eight seconds out of combat. Pursuit stance adds four speed subunits/tick and subtracts four damage.

| Earned XP | Warden alternatives | Beastkeeper alternatives |
|---:|---|---|
| 180 | Aura radius 6→8 cells **or** +2 reduction | Personal recovery 8→14 HP/s **or** +4 speed for 2 seconds when entering combat after recovery |
| 500 | +6 damage **or** +240 max/current HP | +6 damage **or** +200 max/current HP |
| 1,000 | Attack period −0.2 s **or** aura radius +2 cells | Attack period −0.2 s **or** nearby allies recover 4 HP/s out of combat |

Choices remain pending, are committed by commands, and are mutually exclusive in milestone order. No respec. Death retains XP and choices.

Revival costs 175 gold and takes 45 seconds, plus 25 gold and five seconds for every **earned** milestone, chosen or pending. Three earned milestones therefore cost 250 gold / 60 seconds. The hero's five food stays reserved.

Hostile combat unit deaths grant 20 XP/food; hostile heroes grant 150. Workers/buildings grant none. The killer's living hero must be within ten cells. Camp rewards use the explicit table below instead. Reward ownership is deterministic; simultaneous damage still resolves before deaths.

| Camp | Members | Member HP / damage / period | Total gold | Total XP |
|---|---|---|---:|---:|
| Easy | 2 scouts | 180 / 7 / 1.8 s | 40 | 60 |
| Medium | 3 guards | 360 / 12 / 1.6 s | 90 | 150 |
| Hard | leader + 2 guards | leader 700 / 24 / 1.8 s | 160 | 220 |

Scouts/guards move at 30 subunits/tick; leaders at 28. All use .25-cell melee range. Guards/scouts have radius 80; leaders 112. Camps acquire within six cells, leash at ten from home, stop attacking when returning, and recover full HP only after three uninterrupted seconds home without receiving damage. No respawn or items; each dead creature pays its own bounty once.

Each side has two easy camps, one route medium and one natural medium. Two hard camps occupy central areas. Contested mines have no dedicated guard camp. Hero plus two shieldguards can clear the isolated easy-camp regression without losses. Hard-camp approach quality and army requirements remain playtest questions.

## Desired timeline and bot behavior

| Event | Target elapsed match time |
|---|---|
| First completed war hall | 1:00–1:15 |
| First combat unit | 1:20–1:35 |
| Hero + 2–3 units begin camps | 1:45–2:45 |
| Meaningful player conflict | 3:00–5:00 |
| Start HQ advancement | 4:00–6:00 |
| Establish natural expansion | 6:00–9:00 |
| Developed army | 10:00–15:00 |
| Match conclusion | 15:00–25:00 |

XP milestone targets are 3–5, 7–11 and 12–18 minutes. They are not automatically granted by time.

Bots read filtered views and public coordinates. They build production, keep four to six workers, put an extractor on every gold mine they can see within reach of a drop-off, save for advancement and an outpost, and recruit a mixture of unlocked roles. A production-count pattern prevents a time-based rotation from repeatedly skipping expensive ranged troops. They clear visible camps, scout public positions, pressure opponents and retreat damaged units for base recovery. Bots are a reproducible smoke/playability workload, not a substitute for human balance testing.

## Verification and iteration

Run from the repository in PowerShell:

```powershell
.\scripts\run.ps1 -Map twin_marches
.\scripts\test.ps1
.\scripts\test.ps1 -Suite balance
.\scripts\test-ui.ps1
```

`tests/fixture_content.lua` and `tests/fixture_bot.lua` preserve the previous short prototype workload for established movement/mechanics regressions. Playable content is always `src/content.lua`. These frozen fixtures do not certify the new pacing profile; the dedicated balance tests do that. No golden replay was silently regenerated.

New regressions exercise exact conversions, opening food, mine saturation, snapshot continuation while hauling/researching/building, construction health, tech gating, cancellation, dead-hero reservation, earned revival cost, nonstacking support healing, drop-off loss, forest succession, camp rewards/reset, melee contact, and sight equivalence. The larger-map scenario suite writes route reports, two bot-match replays/state dumps, and active simulation timing.

`src/build.lua` fingerprints the new content conversion helper, map modules and all simulation modules. Old content/simulation/source combinations are rejected by replay and multiplayer compatibility checks.

Tune in this order: income and worker travel; production and tech affordability; map routes; unit survival and focus fire; then faction modifiers. Change one family at a time, preserve the old report, and compare command/replay behavior. Do not disguise failed acceptance gates by lowering their thresholds or changing fixture stats.

Human acceptance still requires three mirror and three asymmetric matches, measuring camp safety, harassment timing, retreat success, building space, expansion value, unit readability and final match length. Physical Windows DPI checks and matches between two PCs remain separate gates. See `STATUS.md` for tests actually run and measured results; it supersedes aspirational targets here.


Reference host for this pass: local Windows development PC, AMD Ryzen 5 5600G, pinned LÖVE 11.5. Headless timing and a rendered 1080p workload are measured separately. Filtered-view copying now uses a validated ordered deep copy rather than a serialization round trip; canonical byte serialization is unchanged. Sight uses integer row-interval coverage, verified against the original circular-cell formula.

## Hero abilities — provisional, unmeasured

From simulation version 10 each hero has two active abilities. They exist to prove the
four targeting kinds run end to end through shipping content, and their numbers are a
starting point for playtesting rather than a balanced kit. Nothing in this document's
measured timings accounts for them: the mirror and asymmetric bot matches do not cast,
because the bot has no ability behaviour yet.

| Hero | Ability | Kind | Mana | Cooldown | Effect |
|---|---|---|---:|---:|---|
| Warden | Bulwark | instant, 6-cell radius | 60 | 24 s | Allies take 4 less damage per hit for 8 s |
| Warden | Challenge | unit, 5 cells | 45 | 12 s | 60 damage, 35% slow for 4 s |
| Beastkeeper | Thornfall | area, 8 cells, 2.5 radius | 70 | 20 s | 30 damage, burns 15 a second for 5 s |
| Beastkeeper | Snare | skill shot, 7 cells | 50 | 16 s | Thrown at 3 cells/s; first enemy takes 35 and is rooted 3 s |

Both heroes have 200 mana and regenerate 1 a second. Tune these only alongside a playtest
that actually uses them; the isolated duel and gold-rate fixtures cannot see them at all.

Auto-attacks remain instantaneous. The projectile mechanism that would make a crossbow
bolt travel exists and is used by abilities, but enabling it for ranged attacks changes
when every ranged trade in the game lands, which is a balance change and not a refactor.
