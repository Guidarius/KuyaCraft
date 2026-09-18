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

## The Megacorp — PLANNED

Phases 5 to 7 of the pivot plan: the unique Orbital Command, relay coverage from the
Command, Orbital Relays and Command Blimps, automatic Rigs on patches with an offline rate,
the orbital call-down queue for buildings, drop pods for Associates, Medics and Enforcers,
garrisons, tier by Requisition Office count, Associate target stacks and the Battleship's
anti-air barrage. Numbers will be recorded here as each lands.

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
