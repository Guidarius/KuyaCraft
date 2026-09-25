# LoveRTS: current Warcraft-inspired RTS setup

Repository and production overview, audited 2026-09-21 (America/Chicago).

For expert implementation analysis, failure studies and improvement experiments, read
the companion [engineering case study](RTS_ENGINEERING_CASE_STUDY.md), audited
2026-09-25 against the same merged game revision. This inventory retains its original
date; local tooling and unmerged work should be rechecked before use.

This document describes the game we have, the hero systems retained underneath it,
and the art and engineering tools around it. It is a snapshot, not a new design brief.
The merged baseline is `4da4c0e` on `master`, simulation version **30**, content version
**16**, using LÖVE **11.5**. Separate work is identified explicitly.

### Contents

1. [Project identity](#1-what-the-project-currently-is)
2. [Match structure](#2-player-experience-and-match-structure)
3. [The Orders](#3-the-orders)
4. [The Megacorp](#4-the-megacorp)
5. [Hero foundations](#5-hero-rts-foundations-retained-in-the-engine)
6. [Controls and interface](#6-controls-interface-and-feedback)
7. [Simulation and movement](#7-simulation-movement-and-combat-architecture)
8. [Fog, bots, replay and multiplayer](#8-fog-bots-replay-and-multiplayer)
9. [Maps and terrain](#9-maps-and-terrain)
10. [Camera and scale](#10-camera-and-visual-scale)
11. [Blender production](#11-blender-to-sprite-production)
12. [Art inventory and equipment](#12-art-inventory-and-current-footman-work)
13. [Skills and tooling](#13-reusable-skills-and-local-tooling)
14. [Commands and packaging](#14-development-commands-and-packaging)
15. [Verification and limits](#15-verification-status-and-known-limits)
16. [Repository workflow](#16-repository-ownership-and-how-to-extend-it)
17. [Reading guide](#17-reading-guide-and-documentation-discrepancies)

## 1. What the project currently is

LoveRTS is a Windows-first, deterministic, Lua/LÖVE RTS prototype. Warcraft-style
selection, command cards, responsive orders, compact readable armies and stylized
overhead units are central to its presentation. The current playable economy and
factions also draw strongly on Brood War: two exhaustible resources, supply buildings,
expansions and sharply asymmetric production.

**The current shipping skirmish is not yet a hero-led game.** It offers The Orders
and The Megacorp. Heroes, XP, revival, paired permanent upgrades, neutral camps and
control-point victory still exist as content-gated mechanics and test fixtures, but
they are not active in these two shipping factions or the four main maps.

Calling the project a Hero RTS therefore describes its broader direction and retained
foundation. It must not imply that players currently recruit or level a hero in a
normal Orders-versus-Megacorp match.

| Area | Current state |
|---|---|
| Playable mode | Offline bot skirmish; private two-player host/join multiplayer |
| Shipping factions | The Orders and The Megacorp |
| Main maps | Twin Marches, The Narrows, Open Reach, Crossroads |
| Rules | Fixed 20 Hz simulation, integer positions and deterministic commands |
| Economy | Substrate and charge; supply from buildings, capped at 200 |
| Victory | Orders lose when no Keep remains, including sites; Megacorp lose their unique Orbital Command |
| Hero mechanics | Retained in mechanics fixtures; absent from shipping faction definitions |
| Camera | Fixed orientation, elevated projection, player zoom still enabled |
| Unit art | Blender-rendered directional sprites with paired team-color masks |
| Terrain art | Procedural chunked ground driven by map terrain types |
| Equipment modularity | Agreed Blender-authoring workflow; prototypes and a separate Footman improvement branch |
| Distribution | Standalone Windows folder, with runtime and optional generated assets |
| Readiness | Playable prototype; performance, human feel/balance and real two-PC verification remain open |

Primary truth comes from [content](../src/content.lua), [simulation](../src/sim/init.lua),
[map registry](../src/maps.lua), and the actual export/render code. Historical documents
record useful decisions, but do not override those implementations.

## 2. Player experience and match structure

The application opens a main menu with skirmish, multiplayer, settings and replay
flows. Skirmish selects map and factions, then runs the player against a faction-aware
bot. Both players expand resource access, establish production, field armies and
attack the opponent's headquarters infrastructure.

The Orders begin with a Keep, four Workers and 400 substrate. Their early loop is
harvesting, supply, Barracks production, expansion and eventually Sanctum support.
The Megacorp begin with an Orbital Command, a Command Blimp and 400 substrate. Their
loop is coverage, income rigs, orbital requisitions and troop delivery by drop pod.

The original roadmap targeted roughly 20–60 units per player and 15–25-minute matches.
Those are design targets, not validated guarantees for the current content. The live
200 supply cap is not a 200-unit count, and 240-unit stress benchmarks are not a
promise of smooth performance at that scale. Historical bot timings are useful for
regression comparison, not evidence of human match balance.

Normal attacks have explicit windup/commitment and cooldown. Armor reduces each hit,
with a minimum of one damage. Standard ranged auto-attacks resolve through combat
timing; their drawn bolts are not authoritative travelling projectiles. Separate
ability-projectile mechanics exist and are exercised in fixtures.

## 3. The Orders

The Orders are the conventional worker-and-base faction, visually built around
pointed helmets and hoods, kite shields, cloth panels, ivory masonry, timber, brass
and cathedral roof shapes.

### Roster

Costs below are substrate/charge. Times are gameplay seconds at 20 Hz. These values
are an audited snapshot of `src/content.lua`, not a second balance authority.

| Unit | Role | Cost | Supply | Train | HP | Armor |
|---|---|---:|---:|---:|---:|---:|
| Worker | Harvesting, construction, weak melee | 50/0 | 1 | 18 s | 60 | 0 |
| Footman | Basic sword-and-shield melee | 50/0 | 2 | 22 s | 140 | 1 |
| Crossbow | Ground ranged damage and anti-air | 75/0 | 2 | 28 s | 80 | 0 |
| Gryphon Knight | Fast ground-mounted melee | 150/50 | 3 | 38 s | 180 | 2 |
| Reliquary | Flying healing support | 150/100 | 2 | 45 s | 150 | 0 |

The Footman deals 13 damage per 1.1-second attack period with a 0.3-second windup.
The Crossbow deals 20 ground damage, or 10 against air, at nine-cell range. It is the
Orders' only current anti-air attacker. The Gryphon Knight is **ground-only**, despite
its name and folded wing geometry. The Reliquary has no weapon and heals a wounded
ally for 12 each second within four cells, prioritizing lowest health fraction.

### Buildings

| Building | Cost | Build | Footprint | Function |
|---|---:|---:|---|---|
| Keep | 400/0 | 70 s | 4×4 | Resource drop-off, Workers, +10 supply, defense, faction survival |
| Supply Depot | 100/0 | 25 s | 2×2 | +8 supply |
| Barracks | 150/0 | 45 s | 3×3 | Footman, Crossbow, Gryphon Knight |
| Sanctum | 200/100 | 60 s | 3×3 | Reliquary; requires Keep and Barracks |

Workers carry eight resource units per load. Loading takes two seconds at substrate
and three seconds at charge, followed by travel to a drop-off. A resource node admits
one loading worker at a time; additional workers can seek a nearby free patch.

Construction is grid-snapped and checked against terrain, occupancy, prerequisites
and resources. Multiple workers accelerate a site with diminishing returns. Sites
start at 10% health and gain health as construction advances while retaining damage.
Stopping and resuming construction are supported. The general cancellation refund
is 75%, with full refunds for applicable unstarted production items.

Every Keep is a life: the faction can survive loss of its starting Keep if another
Keep or qualifying Keep site remains. This differs from the original single-HQ plan.

Designed but absent: Footman cohesion aura, Crossbow line shot, Gryphon fly/land and
Charge, Reliquary recall/ranged shield, Keep tiers/Houses, Fletchery and killable
building upgrades. These are reference ideas, not promised next tasks.

## 4. The Megacorp

The Megacorp has no workers. It uses mobile and stationary relay coverage, resource
rigs, queued orbital buildings and drop pods. Rounded pressure suits, heavy vehicle
forms, pressure-hull aircraft and industrial structures distinguish its art.

### Roster

| Unit | Role | Cost | Supply | HP | Delivery |
|---|---|---:|---:|---:|---|
| Command Blimp | Flying mobile coverage, no weapon | 100/0 | 0 | 200 | Orbital Command |
| Battleship | Heavy flying siege, anti-air Barrage | 300/200 | 6 | 500 | Orbital Command |
| Associate | Ranged infantry, anti-air, target stacks | 50/0 | 1 | 55 | Drop pod; Barracks required |
| Medic | Ground healer, no weapon | 50/25 | 1 | 70 | Drop pod; Med Bay required |
| Enforcer | Large-body melee anchor | 125/50 | 3 | 250 | Drop pod; Armory required |

The Enforcer's authoritative radius is 160 subunits, twice the usual 80-unit infantry
radius. Its vehicle-like presentation has real movement implications; it cannot be
treated as a normal infantry body in choke tests. It takes two garrison slots.

The Medic heals six per second within three cells. The Battleship deals 50 ground
damage with ground splash, or eight against air. Barrage is the shipping content's
one active ability: an air-only area channel lasting three seconds, dealing 14 damage
every half second, with an 18-second cooldown. New orders interrupt the channel.

Associate hits accumulate stacks on the target. The threshold depends on armor and
maximum health; reaching it causes a 45-damage armor-piercing burst. Stacks decay when
pressure stops. This makes sustained focus fire a distinct faction mechanic.

### Economy, buildings and delivery

Coverage sources are Orbital Command (18 cells), Orbital Relay (14) and Command Blimp
(12). Covered placement is required for orbital expansion and pod delivery. Coverage
is deterministic game state, not merely a visual placement tint.

| Building | Primary purpose |
|---|---|
| Orbital Command | Unique headquarters; trains aircraft; +10 supply; coverage |
| Substrate Rig | Sits on substrate; 85/min covered, 36/min offline; +4 supply |
| Charge Rig | Sits on charge; 100/min covered, 42/min offline |
| Barracks | Enables Associates |
| Med Bay | Enables Medics |
| Armory | Enables Enforcers |
| Requisition Office | Logistics tier and four-slot non-firing garrison |
| Orbital Relay | Extends stationary coverage |
| Bunker | Four-slot garrison whose occupants can fight |

Rig income uses integer accumulation and drains the underlying finite resource node.
Buildings are purchased into a five-item call-down queue, produced in orbit, then
landed on valid covered ground. Descent takes ten seconds. Blocked arrivals return
the ready building to the queue rather than silently destroying it.

Pods hold up to four units, can launch partly loaded, and have a 15-second launch
cooldown. Flight takes ten seconds. Requisition Offices increase simultaneous pod
capacity up to three. Landing places troops into available surrounding spaces in
load order. Open pods and individual seats can be cancelled/refunded.

Units can garrison and unload. Bunker occupants fight; Office occupants do not.
Garrisoned units take half of applicable splash and are unloaded when the building
dies. Explicit garrison orders now suppress automatic target acquisition en route.

The Orbital Command is unique: its loss defeats the Megacorp. Designed but absent
features include Command-based Battleship repair, Enforcer area damage, staffing
research, franchises and livery. Full statistics are in [FACTIONS.md](FACTIONS.md).

## 5. Hero RTS foundations retained in the engine

[The mechanics fixture](../tests/fixture_content.lua) retains The Bastion and The Wild
Pact with Warden and Beastkeeper heroes, older rosters and short test-oriented values.
It exists to prove rules and interfaces, not as a balanced alternate shipping roster.

| Hero-oriented system | Current availability |
|---|---|
| Hero entities and faction hero references | Fixture content |
| XP, level thresholds and nearby credit | Simulation and fixture scenarios |
| Paired permanent upgrade choices | Three fixture milestones, faction-specific branches |
| Hero death and headquarters revival | Retained, with fixture cost and tick delay |
| Stances/passive effects | Retained and tested |
| Mana, casts, cooldowns and statuses | Ability system and fixture spells |
| Neutral camp enemies | Retained map/fixture support |
| Control-point capture/hold victory | Retained system; absent from four shipping maps |
| Inventory, loot, modular armor gameplay | Not implemented as a shipping hero system |

Ability definitions support no-target, unit, point, area and directional targeting;
damage, healing, statuses and ability projectiles; cast points, backswing and channels.
Statuses can modify statistics, refresh/stack, apply periodic effects and prohibit
movement, attacks or casting. Mana/cooldowns commit at the cast point, with target
revalidation. This is a focused Lua vocabulary rather than a universal visual editor.

Some older ability documentation names an earlier set of hero spells. For exact
current fixture definitions, read the fixture itself. Ability levels, autocast UI and
charge-based abilities are not a finished system.

The current fixture gives the Warden **Ward** (protective status) and **Smite**
(damage/slow); Beastkeeper has **Scorch** (area damage/burn), **Lash** (instant
directional damage/stun), and **Dart** (travelling damage/stun projectile). Its XP
thresholds are 60/160/320; revival uses 200 ticks and a cost of 120. These deliberately
compact test values should not be copied into a shipping hero balance plan by default.

Returning heroes to shipping play would require explicit faction roles, content,
progression/economy choices, command-card integration, bots, art and balance checks.
Retaining the mechanics reduces that work; it does not make a hero release complete.

## 6. Controls, interface and feedback

The interface is already substantially beyond a debug prototype. It has faction
themes, contextual command cards, explanatory tooltips, selection tiles, placement
feedback, a minimap, settings, alerts and replay controls. Megacorp orbital logistics
has a dedicated sidebar that narrows the battlefield instead of obscuring it.

| Input | Behavior |
|---|---|
| Left click/drag | Select; Shift modifies selection; own units take box priority |
| Double click / Ctrl-click | Select visible units of the same type |
| Tab | Change active command subgroup while keeping the complete selection |
| Right click | Contextual move, attack, harvest, build/resume, follow or rally |
| A + left click | Attack-move; clicking an enemy gives focused attack |
| Shift + order | Append queued order |
| S / H | Stop / Hold |
| P + left click | Patrol where context permits; orbital contexts have their own cards |
| Ctrl+1–9 / 1–9 | Assign / recall control groups; double recall centers |
| Q/W/E/R | Contextual command-card abilities/actions |
| B | Worker building card or orbital requisition context |
| F1 / F2 / F9 | Headquarters or fixture hero / all combat units / next idle worker |
| F3 / F4 / F10 | Order inspector / performance overlay / live hotkey reference |
| F5–F8 | Camera bookmarks; Ctrl assigns |
| Minimap left drag / right click | Pan / order; Alt-click pings |
| Wheel / middle drag / arrows | Zoom / pan; optional edge scrolling |
| Ctrl+S | Save replay |
| Escape | Cancel targeting, close panels, then open match menu |

Bindings and contextual actions are authoritative in the live action list; the table
is a default guide. Number keys recall groups rather than recruiting units.

Ability aiming draws range/area/line indicators. Out-of-range casts can walk into
range. Smart cast is optional; Shift queues casts. Selection and damaged-unit health
bars, individual selection tiles, health trails, attack windup feedback, order markers,
floating text, pings and alerts make state changes visible.

Immediate local acknowledgement is separate from command execution. It confirms the
click without predicting damage or mutating authoritative state. Audio currently uses
synthesized nonverbal placeholder cues with named events, buses, priorities and
cooldowns. File-backed recordings can replace them; a finished voice/music library
is not established by those hooks.

Settings include UI scale, audio buses, health-bar policy, edge scroll, smart cast,
screen shake, cosmetic day/night tint, hotkeys and offline speed. Offline match menus
pause; multiplayer continues. Offline speed changes wall-clock feeding of the fixed
simulation, not the rules. Network matches stay at normal speed.

## 7. Simulation, movement and combat architecture

The authoritative simulation lives in `src/sim` and does not call LÖVE, filesystem,
network, OS or wall-clock APIs. Human input, bots, replays and multiplayer submit the
same command structures. **Only `Sim.step(world, commands)` advances game rules.**

```text
Human input ─┐
Bot logic ───┼─> commands ─> offline queue / lockstep ─> Sim.step
Replay ──────┤                                           │
Remote peer ─┘                         snapshots / state / events
                                                        │
                              visible views ─> UI, sprites, sound
```

Positions use 256 integer subunits per navigation cell. The simulation runs at 20 Hz.
Stable entity IDs, ordered processing, bounded work and deterministic serialization
are fundamental. Shipping rules currently use no random rolls; the project PRNG and
its tests remain available for a deliberate future versioned mechanic. Cosmetic
variation is kept outside game authority.

Each step advances the tick, expires statuses, deterministically orders and applies
commands, processes combat orders/economy/movement/visibility/order completion, then
projectiles, abilities and combat, followed by defeat/control victory. Transient
events describe results for presentation. Rendering does not decide whether an
attack landed, a cooldown elapsed or an enemy became visible.

Movement supports precise same-cell destinations, radius-aware clearance, direct
routes, bounded path searches, smoothing, shared group routes, avoidance and queued
continuation. Ground bodies cannot pass through terrain or shrink to fit a gap.
Flying units use their air layer and do not occupy ground space. Targeting explicitly
distinguishes weapons that can attack air.

Current shipping flags are `preciseMovement=true`, `sharedPaths=true`,
`formationPacing=false`, `lineOfSight=true`. **Mixed armies do not currently travel
at the slowest member's speed**, despite an older README description. Faster units
may pull ahead. The fixture still exercises formation pacing separately.

Known limit: dense opposing large units can jam, including tested three-cell heavy
counterflow. Orders remain valid and recovery after redirection is tested; autonomous
resolution of every congestion case is not established. Two radius-160 Enforcers
need 640 subunits side-by-side, wider than a two-cell (512-subunit) opening.

Useful modules: [movement](../src/sim/movement.lua), [pathfinding](../src/sim/path.lua),
[geometry](../src/sim/geometry.lua), [harvesting](../src/sim/harvest.lua),
[abilities](../src/sim/abilities.lua), [vision](../src/sim/vision.lua),
[coverage](../src/sim/coverage.lua), [stats](../src/sim/stats.lua).

## 8. Fog, bots, replay and multiplayer

Simulation visibility includes line-of-sight occlusion from blocked terrain and
buildings. Explored terrain and currently visible terrain have distinct presentation.
Views whitelist fields and distinguish owner-only information; UI must not obtain
hidden information by reading the unrestricted world. Fog and terrain caches are
presentation optimizations, not alternate visibility rules.

Bots are faction-aware command producers. Orders logic handles worker economy,
building and recruitment; Megacorp logic handles coverage, rigs, requisitions, pods
and its army. They exercise expansion and production/combat loops. They are useful
opponents and regression workloads, not evidence of competitive AI or human balance.
The current bots are oriented around one enemy, not a completed multi-team strategy.

Replays record configuration and commands with compatibility identities and state
checkpoints. Snapshot restore and continued replay are tested. Full canonical
serialization supports exact comparisons and desync dumps; a separate authoritative
checkpoint representation excludes documented derived/presentation data while
covering future-affecting state. These two representations should not be conflated.

The replay UI supports playback, pause/speed, timeline and perspective. Save attempts
use project artifacts, with a LÖVE user-save-directory fallback for read-only installs.
Older simulation/content recordings require their compatible original build.

Networking uses ENet and deterministic lockstep. Each tick waits for complete player
command submissions, including empty batches; it does not invent absent inputs.
Host/join compatibility checks, explicit Ready/Start, checkpoints and disconnect/error
handling are present. Simulation supports broader player configurations, but the
current ENet session is a two-player connection.

Same-host separate-process networking has evidence. Real two-PC LAN/direct-IP play,
latency/jitter behavior and other-machine determinism remain separate acceptance
work. There is no public matchmaking, account backend, NAT traversal, reconnect,
host migration, spectator service or shipped anti-cheat service.

## 9. Maps and terrain

| Shipping map | Size | Layout emphasis |
|---|---|---|
| Twin Marches | 192×192 | Diagonal starts, central clearing, outer corridors |
| The Narrows | 160×224 | Central bridge plus long flanking lanes |
| Open Reach | 224×224 | Open ground, broad flanks and expansion space |
| Crossroads | 192×192 | Short central route and longer outer lanes |

These maps are 180-degree symmetric and distribute equivalent main, natural, third
and contested fields. Main fields have seven 1,500-unit substrate patches and one
5,000-unit charge geyser. Naturals have six 1,000 patches and 3,500 charge; later
fields have four 800 patches and 3,000 charge. There are no neutral camps or control
points in these four maps. Smaller procedural scenarios remain in the registry for
testing, including Open Fields, River Pass and Movement Lab.

The authoring chain is layout Lua under `tools/tiled`, generated tracked TMX maps,
tracked Lua exports, then `src/maps/tiled.lua` conversion. Tiled is the chosen editor;
runtime players do not need it. Generation supports mirrored carving, roads, forests,
resource fields and connectivity/layout checks. Regenerating a map can overwrite
manual TMX edits and is deliberately explicit.

The current renderer uses procedural grass, road, rock and forest colors/details.
It lazily bakes 16-cell chunks at 16 internal pixels per cell, with nearest filtering
and presentation-only coordinate-hash variation. It is not yet drawing a finished
Blender-derived terrain tileset. Roads are walkable but unbuildable; rock/forest
block movement and sight. Visual boundary variation does not redefine collision.

General terrain skill guidance now covers seamless surfaces, adjacency, inner/outer
corners, cliffs, slopes and sidescrolling platforms. That is a reusable authoring
method, **not an installed terrain exporter or completed autotile set**. Elevation
gameplay, connected cliff art, authored doodad collections and side-view terrain
controllers are not current LoveRTS features.

See [MAPS.md](MAPS.md) for layout tooling. The older
[terrain/camera plan](TERRAIN_AND_CAMERA_PLAN.md) contains unimplemented camera and
autotile proposals; its proposed 32-pixel square grid and no-zoom camera are not live.

## 10. Camera and visual scale

The game uses a fixed camera orientation and elevated sprite art, with zoom and pan.
The runtime projects a cell as 26 units horizontally and `26 × sin(60°)` vertically,
then applies normalized viewport zoom. Default framing targets 24 visible rows;
UI/sidebar dimensions affect the available battlefield.

Blender production uses an orthographic camera **60 degrees above the ground**, at
64 delivered pixels per normalized Blender world unit. This is not a rotatable
real-time 3D battlefield. Eight facing sprites represent unit direction under that
fixed view. Assets are rendered at twice delivery resolution and reduced for export.

Sprite canvas size is not body size. A larger cell accommodates weapons, mount tails
or falling poses without enlarging the character. The Footman's current cell is
96×96 with ground anchor (48,56). Recipe normalization, projected silhouette and
runtime scale jointly determine apparent size; a `bodyHeightPixels` metadata value
alone is not proof of the visible model's exact standing pixel height.

Readability is judged in native pixels, at gameplay zoom, across all headings, on
light/dark terrain, in silhouette and grayscale, and in motion. Enlarged model views
are useful for geometry inspection but cannot establish small-sprite readability.

## 11. Blender-to-sprite production

The production workflow is reproducible background Blender driven by tracked Python
adapters and JSON recipes. Live Blender/MCP can support inspection and prototyping;
shipping exports do not require a live MCP connection.

```text
Pinned source rig + recipe + model adapter
                 ↓
Build derived geometry / fit grips / sample source actions
                 ↓
Bake derived actions, calibrate camera, check every pose's bounds
                 ↓
Render color and occlusion-aware team mask for each direction/sample
                 ↓
Reduce, pack atlas, write metadata, validate merged catalog
                 ↓
Publish catalog → runtime frame selection, team shader and anchored drawing
```

The local source library is `art/source/rig-library/RTSAssets.blend`, with SHA-256
`efb90208d845fd180917e2d59a8a30a2e86755cf1c030ae9211191ca20379308`.
It is ignored by Git and must be provisioned separately. The original 65-bone humanoid
rig and actions are preserved; derived scenes/actions are saved under artifacts.
Recipes declare model family, source actions, samples, durations, contact frame,
looping, scale/reference height and root-motion policy.

Color and mask atlases have shared frame placement. Metadata records directions,
clip frame sequences, durations, anchors, pages and relevant stride/construction
information. Team masks are rendered with occlusion, so hidden equipment does not
show through the body. The runtime recolors those regions and chooses animation
from simulation state; movement uses travel/stride and attack timing uses commitment.

Build identities include source/tool/recipe dependencies. Build output is immutable
by identity, and catalog publication validates the merged entries before an atomic
Lua catalog switch. Preview does not publish. Worker/loaded-worker compatibility is
checked to avoid cargo transitions changing scale, anchors or stride.

Key paths:

| Path | Purpose |
|---|---|
| `art/recipes` | Asset definitions |
| `tools/blender/pipeline.py` | Humanoid sampling, scene, bounds and export |
| `tools/blender/orders_model.py` | Orders humanoid geometry and pose corrections |
| `tools/blender/orders_special_*` | Gryphon mount/rider and Reliquary |
| `tools/blender/orders_building_*` | Cathedral architecture and construction stages |
| `tools/blender/megacorp_model.py` | Megacorp infantry |
| `tools/blender/aircraft_*`, `building_*`, `drop_pod_*` | Megacorp specialist exports |
| `tools/assets` | Build coordination, reduction, packing and validation |
| `src/sprites.lua`, `src/asset_frames.lua` | Shipping shader, drawing and frame contract |
| `assets/generated/catalog.lua` | Local active production catalog |
| `artifacts/asset-build/<buildId>` | Derived scenes, renders, reports and logs |

See [the pipeline guide](../tools/blender/README.md) and
[Orders production guide](art/ORDERS_CATHEDRAL.md).

## 12. Art inventory and current Footman work

The audited main checkout has **27 local catalog entries**. Catalog presence is not
equivalent to a recruitable unit count, and generated catalogs are not tracked source.

| Group | Entries |
|---|---|
| Orders units/variants (6) | Worker, loaded Worker, Footman, Crossbow, Gryphon, Reliquary |
| Orders buildings (4) | Keep, Depot, Barracks, Sanctum |
| Megacorp units (5) | Command Blimp, Battleship, Associate, Medic, Enforcer |
| Megacorp buildings (9) | Command, two rigs, Barracks, Med Bay, Armory, Office, Relay, Bunker |
| Megacorp prop (1) | Drop pod |
| Retained legacy (2) | Shieldguard, Warden |

Orders buildings have foundation, partial and near-complete construction frames plus
completed idle. The Gryphon has a dedicated 18-bone ground mount, saddle socket and
the preserved humanoid rider. Reliquary attack frames are compatibility placeholders,
not evidence of an offensive mechanic. The pod has authored deployment presentation.
Missing generated assets can fall back to procedural placeholders.

### Footman improvement, separate from master

The pushed `desk/footman-overhead` branch, commit `1cc4808`, reviews all 208 poses and
changes the derived equipment pose: upward shield tilt/outboard carry, a wider/thicker
tapered sword and a deliberate ready/windup/contact/recovery sequence. The camera,
body scale, gameplay and attack timing are preserved. Its generated build is
`2f7c44f21da2da741599435c`; the main checkout still references baseline Footman build
`39ccd959f9eccb416f8bd4cc`.

The review found improved front/side equipment readability, with rear shield
occlusion, tiny heraldry and cross-clip pose differences still needing judgment.
It passed 33 Python tests, asset validation, 208 reopened pose comparisons and
presentation checks. It has been pushed but **not merged or installed into the main
checkout's catalog**. Its report and reproducible comparison helper live on that
[branch](https://github.com/Guidarius/KuyaCraft/tree/desk/footman-overhead).

### Modular equipment direction

The agreed scope is **reusable Blender weapons, shields and similar equipment,
assembled before export into complete unit variants**. Armor, torsos and helmets
are outside the current requested modularity scope. Runtime sprite layering and
equipment changes during a match are not the chosen first implementation.

An item should have a stable grip/socket convention, compatible pose family, material
and team-mask behavior, and enough silhouette at the delivery scale. A variant must
be checked across all directions, attacks, movement and death, with consistent scale
and anchors. Swapping geometry alone does not prove the animation fits it.

The current production models still build equipment procedurally; there is not yet
a completed shared item catalog and general variant-batch system. The local overhead
study and Footman work provide concrete evidence to build on. A separate open
[mouse equipment study, PR #2](https://github.com/Guidarius/KuyaCraft/pull/2), explores
removable equipment and fitted animation, but does not change production catalogs
or establish a shipping Woodland faction.

## 13. Reusable skills and local tooling

The current authoring environment has these personal Blender skills installed:

| Skill | Intended use |
|---|---|
| `blender-game-assets` | General props, environments and project asset workflows |
| `blender-sprite-sheets` | Directional units, side-view games, fighters, sampling, anchors and atlas/runtime review |
| `blender-terrain-tiles` | Seamless terrain, connectivity, cliffs/slopes/platforms and tilemap alignment |
| `blender-godot-characters` | Character rigging/performance and Godot-oriented integration where applicable |

The sprite skill includes overhead RTS and modular-equipment guidance. Sprite and
terrain skills deliberately generalize beyond LoveRTS: eight headings, this camera
and this tick rate are project settings, not universal requirements for side-scrollers
or fighters. Personal skills are installed outside the repository and are not
automatically distributed by cloning or packaging the game. This document inventories
them; it does not make them runtime dependencies.

The working art toolchain is Blender 5.1.0 plus Python 3.10+ with Pillow. LÖVE 11.5
is portable and pinned by [toolchain.json](../toolchain.json), including archive
checksum. Lua code targets that runtime's LuaJIT/Lua 5.1 environment. No global Lua
installation is required. Tiled is the chosen map editor; actual editor installation
and headless export availability need checking on each machine.

## 14. Development commands and packaging

Run these from a checkout in PowerShell. Each checkout needs its own ignored runtime
and generated outputs. Source-only play can use placeholders without Blender.

```powershell
# Bootstrap and play
./scripts/setup.ps1
./scripts/run.ps1
./scripts/run.ps1 -Map crossroads -Faction megacorp

# Local host / second local client (separate terminals)
./scripts/run.ps1 -HostAddress '*:22122'
./scripts/run.ps1 -JoinAddress '127.0.0.1:22122'

# Tests
./scripts/test.ps1
./scripts/test-all.ps1
./scripts/test-presentation.ps1

# Orders art; requires the pinned local source and art dependencies
./scripts/export-assets.ps1 -Mode Build -Roster orders_units
./scripts/export-assets.ps1 -Mode Build -Roster orders_buildings
./scripts/export-assets.ps1 -Mode Validate -Roster orders_units
./scripts/export-assets.ps1 -Mode Validate -Roster orders_buildings
./scripts/run.ps1 -AssetViewer

# Maps: export tracked TMX maps, or deliberately regenerate one layout
./scripts/map.ps1 -Mode Export
./scripts/map.ps1 -Mode Generate -Map crossroads -Force

# Distribution
./scripts/package.ps1
./scripts/package.ps1 -WithAssets
```

For Megacorp export, the wrapper also supports `megacorp_aircraft`,
`megacorp_infantry`, `megacorp_buildings` and `megacorp_props`. Python asset tests use
`python -m unittest discover -s tests -p 'test_*.py'` with the Pillow-capable interpreter.

The standalone Windows package contains LoveRTS.exe plus required DLLs and related
files. Keep that folder together. It does not require Blender, Python or the source
rig to play. Packaging includes self-checking tests unless explicitly skipped.
`-WithAssets` requires the validated asset-package path; it should not be assumed to
generate every missing roster from scratch. Build required catalogs first.

Review/practice modes include `--orders-review`, `--orders-lab`, `--micro-lab` and the
asset viewer. The Orders review shows scale, construction, every heading/sample,
crowds, grayscale and silhouettes. Practice fixtures differ from ordinary matches
and are not substitutes for normal-match replay testing.

## 15. Verification status and known limits

The following are **recorded evidence from the audited implementation**, not tests
rerun for this documentation-only task.

The Orders art handoff records 194 headless checks, four fresh 100,000-tick determinism
runs, same-host networking, rendered UI/presentation suites, 33 Python asset tests and
27 validated catalog entries. Ten saved Blender scenes were reopened across 1,304
poses with zero saved/export pose discrepancy. The 12,000-tick production/combat soak
included restores at 4,000/8,000, 24 replay checkpoints and replacement production.
See [the handoff](art/ORDERS_ART_HANDOFF.md) for exact measured revisions.

Earlier control-integration reports have different test/asset counts and timing
results. They describe earlier evidence sets, not contradictions to silently combine.
The merged baseline contains those changes; their reports may still use pre-merge
branch wording.

### Performance remains an open acceptance gate

The more recent Orders art handoff measured three runs per faction at 1920×1080 with
240 units on Ryzen 5 5600G / RTX 3060 hardware. Median run p95 values were:

| Metric | Orders | Megacorp | Gate |
|---|---:|---:|---|
| Simulation step | 7.972 ms | 9.761 ms | Below 10 ms |
| Rendered frame | 17.915 ms | 18.043 ms | At most 16.667 ms |

All six final frame gates failed. This is not a passed 60 FPS target. The handoff
records 239,857,792 bytes of decoded atlas allocation and higher draw submissions
after more roles became sprite-backed. Hardware/run variation prevents claiming
that the art change optimized simulation performance.

### Still unverified or unfinished

- Human micro, retreat, attack commitment and congested movement feel.
- Human faction balance, match length and counterplay.
- Real two-PC latency/jitter, other-machine performance and broader determinism.
- Dense autonomous heavy-unit counterflow without redirection.
- Final small-sprite recognition, crowd readability, roof occlusion and animation transitions.
- Finished terrain tiles, connected cliffs and coherent authored environment art.
- Shipping hero integration and progression design for current factions.
- A production shared equipment library and automated complete-variant workflow.
- Final recorded sound effects, acknowledgement voices and music.
- Public-service multiplayer features and commercial-release hardening.

## 16. Repository ownership and how to extend it

The project uses GitHub as its source synchronization channel. Agents work on separate
task branches/worktrees, stage only their own files, review diffs, commit and push.
They do not merge into master without authorization. Other machines need the pushed
source plus their own runtime/source-rig provisioning and generated asset rebuilds.

Tracked source includes Lua systems/tests, map layouts/TMX/exports, Blender adapters,
recipes, scripts and documentation. `.tools`, `assets/generated`, `artifacts`, `dist`,
source/generated `.blend` files, screenshots and logs are not committed. Personal
credentials and machine-specific executable paths do not belong in source.

Gameplay changes require simulation/regression checks. Input/drawing/frame-loop
changes require rendered checks as well: `test.ps1` alone executes no rendered code.
Asset changes require catalog validation, Python tests and presentation review.
Golden replay changes must be intentional and explained, never silently accepted.
Documentation-only work checks sources, links and commands rather than claiming a
fresh game validation run.

Local working rules also live in the provided `AGENTS.md` and `docs/GIT_WORKFLOW.md`.
At audit time the latter and other local instruction edits were uncommitted user
work; this overview does not commit or replace them. Draft PR creation has encountered
GitHub integration permission failures; a pushed branch must not be reported as a PR.

## 17. Reading guide and documentation discrepancies

| Question | Best source |
|---|---|
| What actually ships? | [content](../src/content.lua), [maps](../src/maps.lua) |
| Faction rules and detailed numbers | [FACTIONS](FACTIONS.md), checked against content |
| Hero/ability foundations | [fixture content](../tests/fixture_content.lua), [ABILITIES](ABILITIES.md) |
| Map authoring | [MAPS](MAPS.md), `tools/tiled`, `src/maps/tiled.lua` |
| Controls and feel | [CONTROL_RESPONSE](CONTROL_RESPONSE.md), [GAME_FEEL](GAME_FEEL.md), live actions/settings |
| Current art production | [ORDERS_CATHEDRAL](art/ORDERS_CATHEDRAL.md), [Blender guide](../tools/blender/README.md) |
| Latest art evidence | [ORDERS_ART_HANDOFF](art/ORDERS_ART_HANDOFF.md) |
| Congestion and practice scenarios | [OVERNIGHT_HANDOFF](OVERNIGHT_HANDOFF.md) |
| Performance history | [OVERNIGHT_PERFORMANCE](OVERNIGHT_PERFORMANCE.md), later art handoff |
| Historical decisions and progression | [ROADMAP](../ROADMAP.md), [STATUS](../STATUS.md) |

Known differences that matter when reading older documents:

1. The original roadmap's gold/lumber, one-HQ, fixed-population, hero-start and
   control-point framing is historical; shipping content now has substrate/charge,
   building supply and faction-specific defeat, without heroes or map control points.
2. The terrain plan's square-grid/no-zoom proposal is not the current camera.
3. The README's slowest-member formation pacing statement is outdated for shipping
   content, where pacing is false. Its Wild Pact launch example is not a supported
   current shipping-faction description.
4. Older Bastion asset lists do not represent the current Orders/Megacorp catalog.
5. Fixture comments or older spell examples do not establish active hero gameplay.
6. A generated local preview, a pushed branch, merged source and a distributed package
   are distinct states. Footman improvements currently occupy the first two.

Future revisions of this overview should update the baseline revision, recheck live
content/camera/catalog boundaries, and retain dates and provenance for test claims.
