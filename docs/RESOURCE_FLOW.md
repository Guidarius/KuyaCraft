# LoveRTS — Resource flow

Status: **implemented, simulation version 8.** Supersedes the worker-harvesting economy
described in [BALANCE_AND_PACING.md](BALANCE_AND_PACING.md). Numbers here are starting
values chosen to be measurable, not balanced; the pacing report
(`artifacts/balance-pacing-*.txt`) is how they get judged.

Replays and snapshots from version 7 and earlier no longer load. The goldens under
`artifacts/` were regenerated on this change, and this document is the record of why.

## Intent

Gold stops being a task and becomes a flow you protect. The decisions move from "are my
workers saturated" to "is my route safe, and can I cut theirs". Map geometry becomes the
economy.

Lumber is removed entirely. There is one resource.

## The loop

1. Gold mines are inert. Nothing can harvest them.
2. A worker builds an **extractor** on a mine's footprint.
3. The extractor emits a **carrier** holding a fixed amount of gold.
4. The carrier walks a cached route to the nearest friendly drop-off, uncontrollable.
5. On arrival it despawns and its gold is credited. It never returns.
6. The mine's amount falls as carriers are emitted; an exhausted mine stops.

Carriers are killable. Killing one **destroys** the gold rather than transferring it —
stealing compounds a lead, denial only punishes.

## Why distance costs income, and how

An extractor holds at most `carriers` deliveries in flight and waits `emitInterval` ticks
between emissions. Steady-state income per extractor is therefore

    gold per tick = payload × min( 1 / emitInterval , carriers / tripTicks )

A short route is limited by the interval: a near mine pays full rate. A long route is
limited by the in-flight cap, because each carrier occupies a slot for the whole trip, so
income falls as roughly 1/distance beyond the crossover at `carriers × emitInterval`.

Two properties fall out of this that make it worth preferring over a flat penalty:

- **The in-flight cap is a hard bound on entity count.** At most `carriers` per extractor
  exist at once, whatever the route length. That matters: carriers are simulation
  entities, serialized and hashed and scanned as combat candidates.
- **A long route looks like a long supply line.** Nine carriers strung across the map
  reads correctly; a near mine has two or three trotting back and forth.

A slot is released when its carrier is delivered **or killed**. Raiding is therefore pure
denial and does not stall the mine. The denial that matters is not one ambush but holding
a route: while you sit on it, that mine earns nothing.

## The outpost is the answer to distance

Carriers deliver to the nearest friendly drop-off, not specifically the headquarters. An
outpost near a distant mine shortens the route and restores it to full rate.

That turns the distance penalty from something you suffer into something you can act on,
and it puts the investment where the risk is: the outpost is forward, exposed, and worth
killing. Expanding stops being "click the far mine" and becomes "can I hold a building
two thirds of the way across the map".

## Numbers to start from

| Rule | Value | Reasoning |
|---|---:|---|
| `carrierPayload` | 8 gold | Small enough that the stream reads as continuous |
| `emitInterval` | 16 ticks | 0.8 s; near-mine income 600/min, matching today |
| `carriers` | 9 | Crossover at 144 ticks; caps entities at 9 per extractor |
| `carrierSpeed` | 40 subunits/tick | Slightly under a combat unit; catchable |
| `carrierHp` | 40 | Dies to a couple of hits, never fights back |
| carrier food | none | Uncontrollable, should not tax supply |

On the 192×192 Twin Marches, measuring from player one's headquarters at (20,20). Income is
600 × min(1, 144 / trip) at 6.4 ticks per cell:

| Mine | Distance | Trip | Income | Of near |
|---|---:|---:|---:|---:|
| Home (21,10) | ~10 cells | ~64 ticks | 600/min | 100% |
| Natural (58,14) | ~37 cells | ~237 ticks | ~365/min | 61% |
| Forward (54,74) | ~62 cells | ~400 ticks | ~216/min | 36% |
| Contested corner (174,14) | ~153 cells | ~980 ticks | ~88/min | 15% |
| Any of them, with an outpost beside it | ~8 cells | ~51 ticks | 600/min | 100% |

Real routes are longer than straight lines, so treat these as upper bounds. The larger map
makes an outpost matter much more than it did on the 128×112 layout, where the natural
paid 90% without one. Whether that is the right economy for the bigger map is a playtest
question; no economic constant was changed with the map.

**Measured**, by the two scenarios in `tests/balance.lua`, which build a real extractor and
count real deliveries rather than evaluating the formula:

| Case | Measured |
|---|---:|
| Near mine | **600 gold/min** |
| Far mine | **344 gold/min** (57% of near) |
| Far mine with an outpost beside it | **600 gold/min** |

The far mine beats its straight-line estimate because the estimate assumed a longer route
than the map actually has. The shape is what the design asked for: distance costs income,
and an outpost buys it back in full.

## Removing lumber

Costs fold one-to-one into gold, preserving relative prices: starting resources become
650 gold, war hall 220, watchtower 220, outpost 530, headquarters advancement 600. The
**lumber depot is deleted** — it existed only as a lumber drop-off.

Starting workers drop from five to three. With no harvesting a worker is purely an
engineer: it builds, and it rebuilds what raids destroy.

Forests stay on the map as **terrain**, not as entities. They keep blocking movement and,
since the sight work, they block line of sight too — so they remain tactical cover for
raids without being a resource. Converting them to plain blocked cells removes roughly
180 node entities per match on Twin Marches, which every per-entity loop in the step pays
for today.

This deletes a large amount of simulation state: `cargo`, `cargoType`, `dropoff`,
`harvestRemaining`, `economySearch`, `economyRetry`, `dropoffVersion`, mine `slots`,
`nextExtractTick`, and the whole of `src/sim/harvesting.lua` including its bounded
nearest-reachable searches and forest succession.

## What this costs to build

- `Sim.placement` needs an explicit exception so an extractor can be placed **on** a mine.
  Today any overlap with a non-unit entity is rejected outright.
- Carriers want their own entity category rather than being units: not selectable, not in
  the collision bins, no crowd resolution, no food, no orders. They pass through units and
  through each other, colliding only with terrain, with a small lateral offset derived
  from the carrier's id so the stream spreads instead of forming single file.
- One cached path per extractor, shared by all its carriers, recomputed on `navVersion`
  change. No carrier ever calls the pathfinder itself.
- The bot's economy is rewritten: its entire gold logic is "assign five workers per mine".
- Content, tests and documentation that describe harvesting are removed, including the
  gold-throughput, slot-cap, hidden-mine-depletion and forest-succession scenarios.
- Simulation version bump and new regression scenarios.

## Risks worth naming

**The game becomes almost entirely about map control.** With no harvesting and one
resource, base management nearly disappears: you build extractors, you defend routes, you
fight. That is a distinctive and coherent direction, but it is a change of identity, not a
tuning pass. If matches start to feel thin, the missing texture is build-order variety,
and the place to add it back is the tech tree rather than a second resource.

**It may fix the pacing problem or sharpen it.** The pacing report shows matches are
decided at five minutes and take eleven to finish, because a losing player has no way
back. Raidable income is a genuine comeback mechanism: a losing army can trade itself for
the winner's economy instead of dying to it head on. Whether that is enough is a question
for the report and a playtest, not for this document.

## Build order

1. ~~Extractor building, carriers, cached route, delivery, mine depletion.~~ Done.
2. ~~Killability, and carriers as ordinary combat targets.~~ Done.
3. ~~Remove lumber: fold costs, delete the depot, convert forests to terrain, strip the
   harvesting system.~~ Done. `src/sim/harvesting.lua` is deleted.
4. ~~Rewrite the bot's economy around holding extractors.~~ Done.
5. ~~Re-measure pacing and report.~~ Done; see below.

## What the change did to the shape of a match

The current report, `artifacts/balance-pacing-mirror.txt`:

    first extra worker                 0:15
    war hall                           1:01
    first combat unit                  1:22
    first extractor                    0:30
    headquarters advance               5:40
    outpost                            5:44
    first contact between players      4:20
    peak army, player 1                4:56
    peak army, player 2                8:23
    match end                          9:33
    peak food                          P1 46, P2 80 of 80
    extractors at the end              P1 1, P2 2
    carriers on the road               P1 5, P2 4

Two things can be compared honestly against the harvesting economy, because they are the
only two figures from the old report that were written down before it was overwritten:
first contact was **4:32** and the match ran about **eleven minutes**. Contact is
essentially unchanged at 4:20; the match is shorter, at 9:33.

Everything else here is a new baseline rather than a comparison. Reading it on its own
terms: income arrives at 0:30, far earlier than a worker line could saturate a mine, and
expansion follows at 5:44 — an outpost is now worth building for what it does to income,
not only for the ground it takes.

The match still ends well short of the 15 minute floor, and the comeback mechanism the
design hoped for did not appear on its own. The bot does not raid carrier routes, so a
losing bot still has no way back. Whether raidable income helps is a question about
players, and it needs either a bot that hunts carriers or a playtest. It is not answered
here, and this document should not be read as claiming it was.

The extractor and carrier counts are the useful new line. At the end of the mirror match
the winner held two extractors to the loser's one: that count is now a more direct read on
who is winning than the army count is.
