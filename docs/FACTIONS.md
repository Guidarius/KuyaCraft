# Factions — The Orders and The Megacorp

The two factions of the Brood War style pivot, with the numbers the simulation runs. The
design reference (the faction document the pivot was planned from) gives hit points, damage,
costs, supply and times; this file records how they land in LoveRTS units: **ticks** at 20 Hz,
**cells** of 256 subunits, and **speeds** in subunits per tick, which are the reference's
world units per second multiplied by 0.4 so the game keeps its pace. `src/content.lua` is
authoritative; where this file and the content disagree, the content wins and this file is
wrong.

Status tags: **LIVE** is in `src/content.lua` and running; **PLANNED** is the pivot plan's
later phases; **DESIGNED** is in the reference and not scheduled.

## Shared rules — LIVE

| Rule | Value |
|---|---|
| Resources | `substrate` (minerals) and `charge` (gas), in that display order |
| Damage | `max(1, damage - armor)` per hit; armor is flat, from content plus statuses |
| Supply | the sum of completed buildings' `supply`, capped at 200 |
| Cancel refund | 75% of every resource paid; an unstarted queue item refunds all of it |
| Construction | sites start at 10% health and gain it with progress; damage taken is kept |
| Co-construction | percent of a tick's progress per tick by builders at work: 100, 150, 185, 210, 225, 235 |
| Harvesting | one worker loads at a patch at a time; a second hops to a free patch within 6 cells or waits |
| Building weapons | reach is measured from the edge of the footprint nearest the target |
| Sight | line of sight, blocked by terrain, buildings and forests |
| Air | a `flying` unit routes straight to its destination through terrain and units, occupies no ground and blocks nothing; only a `canAttackAir` weapon may target it, using `airDamage` when it has one |
| Splash | a `splash` weapon also hits every enemy on the ground within its radius of the target, each against its own armor; never allies, never the air |

## The Orders — LIVE

Workers harvest both resources and build in person; every Keep is a life; the army trains
from a Barracks. Start: one Keep, four Workers, 400 substrate, 0 charge.

### Buildings

| Kind | Substrate | Charge | Build | HP | Armor | Size | Supply | Sight | Produces | Requires |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|---|
| `keep` Keep | 400 | — | 1400 t (70 s) | 1500 | 2 | 4×4 | +10 | 10 | Worker | — |
| `depot` Supply Depot | 100 | — | 500 t (25 s) | 500 | 1 | 2×2 | +8 | 6 | — | Keep |
| `barracks` Barracks | 150 | — | 900 t (45 s) | 1000 | 1 | 3×3 | — | 8 | Footman, Crossbow, Gryphon Knight | Keep |
| `sanctum` Sanctum | 200 | 100 | 1200 t (60 s) | 900 | 1 | 3×3 | — | 9 | Reliquary | Keep, Barracks |

The Keep is the drop-off, the worker producer and a life. It shoots: 20 damage every 30
ticks (1.5 s), windup 6, reach 7 cells past its wall.

### Units

| Kind | Substrate | Charge | Supply | Train | HP | Armor | Damage | Period | Windup | Range | Speed | Sight |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `worker` Worker | 50 | — | 1 | 360 t | 60 | 0 | 5 | 24 t | 6 t | melee | 40 | 7 |
| `footman` Footman | 50 | — | 2 | 440 t | 140 | 1 | 13 | 22 t | 6 t | melee | 40 | 7 |
| `crossbow` Crossbow | 75 | — | 2 | 560 t | 80 | 0 | 20 | 40 t | 10 t | 9 cells | 34 | 9 |
| `gryphon` Gryphon Knight | 150 | 50 | 3 | 760 t | 180 | 2 | 9 | 12 t | 3 t | melee | 44 | 8 |
| `reliquary` Reliquary | 150 | 100 | 2 | 900 t | 150 | 0 | — | — | — | heals 12/s within 4 cells | 42 | 9 |

The Reliquary flies and has no weapon: it heals the most hurt ally within four cells by 12
every second (the shared healer rule picks the lowest health fraction, not the nearest).
The Crossbow is the Orders' only anti-air weapon, at 10 damage per shot against a flyer
instead of 20; nothing else, the Keep included, can touch one.

The Worker harvests 8 per load: 40 ticks (2 s) at a substrate patch, 60 ticks (3 s) at a
charge geyser. Melee range is a quarter cell past the bodies.

Measured on the balance fixture (`tests/balance.lua`, printed on every run): one worker on a
patch four cells from the keep pays about 136 substrate a minute and 104 charge; a second
worker on the same patch brings it to about 240, not 272, because the patch is exclusive;
a depot takes 499 ticks alone, 332 with two builders and 235 with four; a footman duel
lasts 12.5 s.

### Not yet live for the Orders

- **DESIGNED:** Footman cohesion aura, Crossbow line shot, Gryphon fly/land and Charge,
  Reliquary recall and ranged shield, Keep tiers and Houses, killable building upgrades, a
  Fletchery.

## The Megacorp — LIVE (territory, rigs, orbital logistics, pods, garrisons, weapons)

No workers. Everything arrives from orbit inside relay coverage; the Orbital Command is
unique and its loss is defeat. Start: one Orbital Command, one Command Blimp, 400 substrate.

### Coverage — LIVE

A per-player set of cells within the coverage radius of every completed building and living
unit that carries one, rebuilt each tick (`src/sim/coverage.lua`), binary, checkpointed and
shown to the placing player as a tint. Sources: Orbital Command 18 cells, Orbital Relay 14,
Command Blimp 12 (mobile, the only way to push coverage into enemy ground). Every building
but the Command lands only on covered cells (`Outside relay coverage`, reported before an
unseen footprint), and a Rig outside coverage earns its offline rate.

### Orbital logistics — LIVE

`requisition` pays the price now and puts the building in the player's call-down queue
(five deep); items are produced in orbit for their build time, one at a time, two once two
Requisition Offices stand (`Sim.tier`); a ready item is `land`ed on a site the placement
rules accept, descends for 200 ticks (10 s) and arrives complete; a site found blocked on
arrival sends the item back to the head of the queue, ready; cancelling refunds 75%.

### Buildings

| Kind | Substrate | Charge | In orbit | HP | Armor | Size | Supply | Sight | Notes |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| `orbital_command` Orbital Command | 400 | — | — | 3500 | 5 | 4×4 | +10 | 12 | coverage 18; trains Blimp, Battleship; unique |
| `substrate_rig` Substrate Rig | 60 | — | 300 t | 225 | 0 | 1×1 | +4 | 6 | on a substrate patch; 85/min, 36 offline |
| `charge_rig` Charge Rig | 75 | — | 360 t | 300 | 1 | 2×2 | — | 6 | on a charge geyser; 100/min, 42 offline |
| `mc_barracks` Barracks | 150 | — | 400 t | 1000 | 1 | 3×3 | — | 8 | lets Associates be loaded |
| `med_bay` Med Bay | 100 | 50 | 500 t | 800 | 1 | 2×2 | — | 7 | needs Barracks |
| `armory` Armory | 200 | 100 | 500 t | 900 | 1 | 2×2 | — | 7 | needs Barracks |
| `requisition_office` Requisition Office | 175 | 25 | 700 t | 900 | 1 | 3×3 | — | 8 | `tier`; garrison 4, occupants cannot fight |
| `orbital_relay` Orbital Relay | 125 | — | 500 t | 450 | 0 | 2×2 | — | 10 | coverage 14 |
| `bunker` Bunker | 100 | — | 400 t | 400 | 2 | 2×2 | — | 8 | needs Barracks; garrison 4, occupants fight |

Rig income is exact: the per-minute rate accumulates in 1/1200ths a tick and whole units are
credited, draining the node by the same amount.

### Units

| Kind | Substrate | Charge | Supply | Train | HP | Armor | Damage | Period | Windup | Range | Speed | Sight |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `command_blimp` Command Blimp | 100 | — | 0 | 600 t | 200 | 0 | — | — | — | coverage 12 | 38 | 11 |
| `battleship` Battleship | 300 | 200 | 6 | 1400 t | 500 | 3 | 50 (8 vs air) | 60 t | 15 t | 12 cells, splash 1.5; Barrage | 22 | 13 |
| `associate` Associate | 50 | — | 1 | 320 t | 55 | 0 | 6, stacks | 18 t | 4 t | 5 cells, can hit air | 44 | 8 |
| `medic` Medic | 50 | 25 | 1 | 400 t | 70 | 1 | — | — | — | heals 6/s within 3 cells | 44 | 8 |
| `enforcer` Enforcer | 125 | 50 | 3 | 600 t | 250 | 2 | 25 | 28 t | 7 t | melee | 32 | 7 |

The Blimp and the Battleship fly and train at the Command. The other three arrive by drop
pod: the Associate needs a Barracks, the Medic a Med Bay, the Enforcer an Armory.

### Drop pods — LIVE

`pod_load` pays a unit's cost and supply and puts it in the open pod (four seats); the pod
exists only in the queue until `pod_launch` sends it at a covered cell, after which the
Command waits 300 ticks (15 s) before launching again; ten seconds later the troops step
out onto a ring of free cells around the point in the order they were loaded. Pods in
flight at once: one, plus one per Requisition Office, at most three. Cancelling the open pod
refunds everything in it. A partly loaded pod may be launched.

### Garrisons — LIVE

A unit ordered into a building with `garrison` slots walks there and steps inside if there
is room (an Enforcer takes two of the four). Inside it is unseen by the enemy, cannot be
targeted, takes half of any splash, and fights from a Bunker but not from an Office.
`unload` puts everyone out beside the building; a building's death does the same.

### Weapons — LIVE

**Target stacks.** Every Associate hit adds a stack to its target (both sides see the pips).
At the target's threshold, `5 + 150% of armour + 2 per 100 max hp` stacks (Associate 6,
Footman 8, Enforcer 13, Bunker 16, Keep 38), the stacks burst for 45 damage that ignores
armour, on the tick of the hit that crossed the line, and start again from any hits left on
that tick. Stacks fade once 15 ticks pass without a hit, by 30 plus 6 per armour point a tick
(200 per stack), so the Associate's own 18-tick period loses a little between hits and focus
fire is what bursts a target.

**Barrage.** The Battleship's ability (W): a 4.5-cell circle in the sky within 12 cells,
14 damage to every enemy flyer in it every half second for 3 seconds, cooldown 18 s charged
at the cast point. The ship holds and its gun is silent while it channels; any new order
breaks the channel. The bot casts it at the nearest enemy flyer in reach.

The reference's designed-but-not-live Megacorp features (Battleship repair at the Command,
Enforcer area damage, office staffing research, franchises and livery) stay out of scope
until the user asks; nothing else of the Megacorp is planned.

## The map

Twin Marches gives every base a curved line of one-cell substrate patches four to seven
cells from its keep and a two-cell charge geyser at the end: seven patches (1500 each) and
a 5000 geyser at each main, six (1000) and 3500 at each natural, four (800) and 3000 at the
forward and contested corner sites. No neutral camps, no control points. The layout lives in
`tools/tiled/twin_marches_legacy.lua`; the generator writes both the `.tmx` and the Lua
export.

## Retired

The Bastion and the Wild Pact, their heroes, experience, neutral camps and control points
are no longer shipped. The simulation keeps every one of those systems, content-gated, and
they stay covered by the mechanics fixture (`tests/fixture_content.lua`) and the rendered
suite, which plays that fixture.
