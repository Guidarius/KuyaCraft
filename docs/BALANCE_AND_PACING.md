# LoveRTS — Balance, scale and match pacing

Profile: `orders-v1`, content version 14, simulation version 26. The Brood War style
pivot's numbers: two resources, two asymmetric factions, supply from buildings, no heroes.
The unit and building statistics themselves are in [FACTIONS.md](FACTIONS.md), which is
the one place they are written down outside `src/content.lua`; this document is about
scale, the map, the economy's shape, the pacing targets and what has been measured against
them. Match duration is a playtest target, not a timer that forces an outcome.

The pre-pivot `marches-v1` profile (heroes, one resource, the extractor economy, camps and
control points) is retired to `tests/fixture_content.lua`; its economy write-up survives
in [RESOURCE_FLOW.md](RESOURCE_FLOW.md) under a superseded banner.

## Intent and rules

- Target 15–25-minute 1v1 matches. The Orders develop 16–24 workers and an army of 20–40
  supply; the Megacorp has no workers and spends the same minutes on rigs, relays and pods.
  Measured on every balance run: see `artifacts/balance-pacing-mirror.txt` (Orders mirror)
  and `-asymmetric.txt` (Orders vs Megacorp), written by `scripts/test.ps1 -Suite balance`.
- **Substrate** (minerals) and **charge** (gas). The Orders start with a Keep, four
  Workers and 400 substrate; the Megacorp with an Orbital Command, a Command Blimp and 400
  substrate. Nothing starts with charge.
- Supply is the sum of completed buildings' `supply`, capped at 200: Keep and Orbital
  Command 10, Supply Depot 8, Substrate Rig 4. Recruitment reserves supply and resources on
  acceptance; loaded and in-flight pod troops count.
- The Orders lose when no Keep stands or is under construction; the Megacorp loses when its
  starting Orbital Command dies. There is no second way to win.
- Cancellation refunds 75%; an unstarted queue item refunds all of it. Sites start at 10%
  health and gain it with progress.
- No heroes, experience, neutral camps, control points, upkeep, inventory or damage-type
  matrix. Armor is flat: `max(1, damage − armor)` per hit.

## Coordinates, unit sizes and camera

Simulation remains 20 ticks/second and 256 integer subunits/cell. `src/content_time.lua`
converts author-facing seconds and cells into exact tick/subunit values, rejecting
unsupported fractions. Authoritative state contains integers; UI conversion to seconds does
not affect gameplay. Reference speeds convert at ×0.4 (world units per second to subunits
per tick), so a Footman walks 40 subunits a tick, 3.125 cells a second.

| Body | Radius in subunits | Diameter in cells |
|---|---:|---:|
| Worker, Associate, Medic, Reliquary, Crossbow | 72–80 | 0.56–0.625 |
| Footman, Gryphon Knight | 80 | 0.625 |
| Enforcer, Command Blimp | 96 | 0.75 |
| Battleship | 112 | 0.875 |

Collision uses the circle-clearance crowd system for ground units; flyers occupy no ground
and block nothing. Weapon ranges are **edge-to-edge**, and a building's reach is measured
from the edge of its footprint nearest the target. Melee ranges are a quarter cell past the
bodies and need subcell contact destinations, which are part of the saved path.

The default camera shows 24 cells vertically, independently of window height and UI
scale. Zoom is 80–135% of that baseline. At 1080p/100% UI the ordinary sprite body is
about 51 pixels and workers about 42. Selected buildings display their footprint;
buildings and nodes are picked by their projected extent.

## Twin Marches

Default skirmish map: **192×192 cells**, 1v1, 180-degree paired terrain, resource fields,
roads and starting units. Authored for player one in `tools/tiled/twin_marches_legacy.lua`;
`tools/tiled/generate/main.lua` writes both `maps/twin_marches.tmx` and the Lua export
`src/maps/twin_marches_tiled.lua`. 256×256 is the largest map the simulation accepts.

| Feature | First side | Opposite side |
|---|---|---|
| HQ footprint origin | (20,20), Keep 4×4 / Command 4×4 | (167,167) |
| Main field | seven 1×1 substrate patches of 1500 in an arc north of the keep: (18,16) (19,14) (21,13) (23,13) (25,13) (27,14) (28,16); 2×2 charge geyser of 5000 at (30,18) | rotated |
| Natural field / anchor | six patches of 1000 at (57,24) (59,25) (60,27) (60,29) (60,31) (59,33); geyser 3500 at (56,34); bot anchor (50,28) | rotated / (141,163) |
| Forward field / anchor | four patches of 800 at (61,68) (60,70) (60,72) (61,74); geyser 3000 at (57,71); anchor (66,70) | rotated / (125,121) |
| Contested corner field / anchor | four patches of 800 at (172,18) (174,17) (176,18) (177,20); geyser 3000 at (178,23); anchor (168,24) north-east | (23,167) south-west |

Footprint origins rotate as `(width−x−size, height−y−size)`; unit and patch cells rotate
as `(width−1−x, height−1−y)`. In all, 42 substrate patches and 8 charge geysers. There are
no neutral camps and no control points; the generator's helpers for both remain for a map
that wants them.

The layout is a base clearing, a natural to its east, a forward expansion on the main
diagonal, a large central clearing, and two long outer corridors to the corners. The two
triangles between the diagonal and the outer corridors are open fields broken up by forest
clumps; about 60% of the map is walkable. Each corner is nearer one player, and the
rotation makes that fair.

### Roads

Roads are a map layer, `map.unbuildable`: walkable, three cells wide, and **nobody may
build on them**. They run from the main field to the headquarters, headquarters to natural
to corner, headquarters to forward field to the other corner, and forward field to the
centre, where they meet the other player's. Fields and headquarters are unpaved
junctions, so a Keep, a Rig or a Depot goes where it belongs and no wall of buildings can
cut a field off from the bases. `Sim.placement` refuses a road cell with *Cannot build on a
road*, and the build and land commands revalidate through it.

Measured infantry routes use the actual pathfinder at Footman speed 40, per-segment
integer movement rounding, and no crowd delays (`artifacts/balance-routes.txt`, printed by
the balance suite; the labels still name the pre-pivot approach points):

| Route | Measurement | Target |
|---|---:|---:|
| Rally (28,18) to enemy rally (163,173) | 67.00 s | 60–83 s |
| Center to rally | 33.80 s | 30–42 s |
| Via the south-west corner (22,160) | 96.35 s, +43.8% | reported only: a detour, not a flank |
| Natural approach (54,26) | 9.10 s | 10–15 s |
| Old easy-camp point (48,29) | 7.50 s | 8–12 s |

The two short approaches fall under their targets because the Footman is faster than the
Shieldguard the targets were set for; the targets have not been moved.

## Economy and supply

**The Orders harvest.** One worker loads at a patch at a time; a second one hops to a free
patch of the same resource within 6 cells or waits. A load is 8, taking 40 ticks at a
substrate patch and 60 at a charge geyser, walked home to the nearest completed Keep.
Measured on the balance fixture (`tests/balance.lua`, printed on every run):

| Measurement | Value |
|---|---:|
| One worker on a patch four cells from the keep | about 136 substrate a minute |
| The same worker on a geyser | about 104 charge a minute |
| Two workers on that one patch | about 240 a minute, not 272: the patch is exclusive |
| A depot alone / two builders / four | 499 / 332 / 235 ticks |

Co-construction pays 100, 150, 185, 210, 225, 235 percent of a builder's rate for one to
six builders at the site. The 42 patches and 8 geysers hold 45,800 substrate and 29,000
charge in all; the mirror match leaves 28 patches untouched, so the map is not what ends a
match.

**The Megacorp mines.** A Substrate Rig lands on a patch and pays 85 a minute while its
cell is inside relay coverage, 36 outside; a Charge Rig on a geyser pays 100 and 42. The
rate accumulates in 1/1200ths a tick and whole units are credited, draining the node by
the same amount. Buildings arrive from orbit through the call-down queue and troops by drop
pod; both are in FACTIONS.md.

| Unit | Supply |
|---|---:|
| Worker, Associate, Medic | 1 |
| Footman, Crossbow, Reliquary | 2 |
| Gryphon Knight, Enforcer | 3 |
| Battleship | 6 |
| Command Blimp | 0 |

## Desired timeline and bot behavior

Targets, and what the two bot matches on one seed measured at content 14. The measurement
is the shape of a match, not balance between the factions.

| Event | Target | Orders mirror | Orders vs Megacorp |
|---|---|---:|---:|
| First Barracks | 0:45–1:15 | 0:47 | 0:47 (Megacorp barracks lands 1:30) |
| First combat unit | 1:10–1:35 | 1:10 | 1:10 |
| First contact | 3:00–5:00 | 3:46 | 3:38 |
| First Gryphon Knight | 4:00–6:00 | 4:34 | 4:34 |
| Second Keep | 6:00–9:00 | 6:59 | 12:08 |
| Peak army | 10:00–15:00 | 10:54 / 7:25 | 19:20 / 12:54 |
| Match end | 15:00–25:00 | 12:23, player 1 by headquarters | 22:45, Orders by headquarters |
| Peak food | — | 92 / 52 of caps 100 / 24 | 74 / 34 of caps 84 / 24 |

The mirror finishes 2.6 minutes short of the floor; the asymmetric match is inside the
window but the Megacorp bot has not yet won one. Neither number has been tuned: balance
is the user's, and these are the figures to tune from.

The Orders bot sends idle workers to the patch with the fewest assigned, grows to 16 then
24 workers, raises a Depot before the cap, a Barracks at 150 substrate, a second Barracks
later, a Keep at the natural, a Sanctum after two halls, alternates Footmen and Crossbows,
adds Gryphon Knights once charge flows and two Reliquaries, and attacks at 12 army supply.
The Megacorp bot requisitions Rigs on covered patches, a Barracks, a Charge Rig, an Office,
a Relay toward the natural, a Med Bay, an Armory and a Bunker; lands what is ready; fills
and launches pods at the natural; walks the Blimp forward; casts the barrage at flyers in
reach; and sorties with two Battleships or 12 troop supply. Bots read filtered views and
public coordinates and are a reproducible smoke workload, not a substitute for human
balance testing.

## Verification and iteration

Run from the repository in PowerShell, always with `-PerfBudget 40` on the desk machine:

```powershell
.\scripts\run.ps1 -Map twin_marches
.\scripts\test.ps1 -Suite quick -PerfBudget 40
.\scripts\test.ps1 -Suite balance -PerfBudget 40
.\scripts\test-ui.ps1
```

`tests/fixture_content.lua` and `tests/fixture_bot.lua` keep the pre-pivot workload for
the movement and mechanics regressions and for the rendered suite, which plays that
fixture. Playable content is always `src/content.lua`; the dedicated balance tests
certify it, the fixtures do not. No golden replay was silently regenerated.

The balance suite's rails (`tests/balance_scenarios.lua`): Barracks between 20 and 180 s,
first contact between 60 and 900 s, peak supply at least 20, for both the mirror and the
asymmetric match. The scenario files that pin the mechanics are `tests/harvest_scenarios`,
`orders` via `tests/balance.lua`, `air_scenarios`, `megacorp_scenarios`, `pod_scenarios` and
`weapon_scenarios`.

Tune in this order: income and worker travel; production and requirement affordability;
map routes; unit survival and focus fire; then the Megacorp's coverage and pod timings.
Change one family at a time, preserve the old report, and compare command/replay
behaviour. Do not disguise failed acceptance gates by lowering their thresholds or changing
fixture stats.

Human acceptance still requires three mirror and three asymmetric matches, measuring
harassment timing, retreat success, building space, expansion value, pod landings under
fire, unit readability and final match length. Physical Windows DPI checks and matches
between two PCs remain separate gates. See `STATUS.md` for tests actually run and measured
results; it supersedes aspirational targets here.
