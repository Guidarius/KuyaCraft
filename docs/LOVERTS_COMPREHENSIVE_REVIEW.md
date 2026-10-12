# LoveRTS: Engineering Case Study and Game Inventory

A consolidated review dossier for expert game developers and AI reviewers.

**Combined:** 2026-10-11. **Engineering audit:** 2026-09-25. **Inventory audit:**
2026-09-21. **Game baseline:** `4da4c0e`, simulation 30, content 16, LÖVE 11.5.

This file includes both complete documents, with their original evidence, limitations,
and proposed experiments. It can be shared or uploaded on its own. References between
the two documents now stay inside this file; supporting repository references use
immutable GitHub source links. Access to private repository links still requires
repository permission, but the substantive documentation is included here.

**This is a historical snapshot, not an October code audit.** The remote master had
advanced to `7fc1697` when this file was assembled. Statements about shipping content,
unmerged branches, open PRs, local tooling and test status retain their original audit
context. No game tests or performance measurements were rerun for this consolidation.
The earlier 28-test unit result and all other measurements retain their stated dates.

The two parts are complementary: Part I explains implementation and improvement
experiments; Part II supplies detailed content, controls and asset inventories.
Some context is repeated intentionally to preserve each document's reasoning.

## Navigation

- [Part I: Engineering case study](#engineering)
- [Engineering contents](#engineering-contents)
- [Part II: Game inventory and production setup](#inventory)
- [Inventory contents](#inventory-contents)

## Suggested review brief

Evaluate the implementation against the audited baseline. Separate observed defects
from hypotheses and distinguish shipping systems from mechanics fixtures or separate
art studies. Prioritize improvements by player impact, measured cost and regression
risk. For each recommendation, name the relevant source, explain the mechanism,
propose a focused change and describe the test or experiment that would validate it.
Do not treat historical performance results as fresh measurements or the retained hero
systems as active shipping content.

---

<a id="engineering"></a>

## Part I: Engineering case study


Expert developer and AI analysis guide, source audit dated 2026-09-25.

This case study analyzes merged game revision `4da4c0e` (simulation 30, content 16,
LÖVE 11.5). Its companion [current setup inventory](#inventory) records
the playable content and authoring environment. This documentation branch includes
that earlier overview; it does not integrate the separate Footman or mouse studies.

<a id="engineering-abstract"></a>

### Abstract

LoveRTS is a useful example of building an RTS in a small general-purpose 2D engine
without delegating gameplay to physics, a scene graph or an external networking
framework. LÖVE supplies application callbacks, graphics, audio, files, hashing and
an ENet binding. Project-owned Lua code supplies rules, fixed-step simulation,
navigation, visibility, command validation, replay and lockstep orchestration.

Its strongest reusable ideas are the shared command interface, explicit integer
geometry, deterministic scheduling of expensive work, source-identified replay
compatibility, filtered presentation views, and reproducible Blender sprite builds.
Its most instructive limits are crowded movement, the cost of the full rendered
frame beyond `Sim.step`, growth of historical state, and the distinction between
passing technical checks and delivering satisfying RTS control and readable art.

This is a working prototype case study, not a claim that LÖVE has been proven for
every RTS scale or deployment target. The game ships two asymmetric factions with
worker/orbital economies. Hero mechanics survive in fixtures but are not active in
normal shipping skirmishes. Performance acceptance remains open.

The document combines implementation description with analysis. Sections labelled
**Review hypothesis** or **Proposed experiment** are recommendations, not delivered
features or reproduced defects. Source inspection is not a formal proof. Historical
test results are attributed to their reports; this audit's fresh checks are listed
separately near the end.

<a id="engineering-reading-paths"></a>

### Reading paths

- **First-time developer:** sections 1–5, then the subsystem relevant to the task.
- **Simulation/network reviewer:** sections 5–11 and 17–19.
- **Rendering/tools engineer:** sections 12–16 and the companion inventory.
- **AI improvement agent:** sections 1, 17–21 before proposing or editing anything.
- **Producer/designer:** companion [CURRENT_GAME_SETUP.md](#inventory),
  then the evidence and experiment sections here.

<a id="engineering-contents"></a>

#### Contents

1. [Scope and provenance](#engineering-1-scope-and-provenance)
2. [The implemented game as a workload](#engineering-2-the-implemented-game-as-a-workload)
3. [Repository and dependency map](#engineering-3-repository-and-dependency-map)
4. [Why this is a LÖVE implementation](#engineering-4-why-this-is-a-löve-implementation)
5. [Time, commands and the live frame](#engineering-5-time-commands-and-the-live-frame)
6. [State model and numeric determinism](#engineering-6-state-model-and-numeric-determinism)
7. [Tick ordering and gameplay resolution](#engineering-7-tick-ordering-and-gameplay-resolution)
8. [Navigation and crowd movement](#engineering-8-navigation-and-crowd-movement)
9. [Visibility, views and information boundaries](#engineering-9-visibility-views-and-information-boundaries)
10. [Replay and compatibility](#engineering-10-replay-and-compatibility)
11. [Private multiplayer](#engineering-11-private-multiplayer)
12. [Rendering, camera and animation](#engineering-12-rendering-camera-and-animation)
13. [Content and map authoring](#engineering-13-content-and-map-authoring)
14. [Blender and asset publication](#engineering-14-blender-and-asset-publication)
15. [Controls, audio and usability](#engineering-15-controls-audio-and-usability)
16. [Packaging and reproducibility](#engineering-16-packaging-and-reproducibility)
17. [Test strategy and evidence](#engineering-17-test-strategy-and-evidence)
18. [Failure studies and engineering lessons](#engineering-18-failure-studies-and-engineering-lessons)
19. [Prioritized improvement experiments](#engineering-19-prioritized-improvement-experiments)
20. [Developer and AI handoff protocol](#engineering-20-developer-and-ai-handoff-protocol)
21. [Source index and glossary](#engineering-21-source-index-and-glossary)

<a id="engineering-1-scope-and-provenance"></a>

### 1. Scope and provenance

Remote references were refreshed on 2026-09-25. `origin/master` still resolved to
`4da4c0e` (Integrate responsive controls and both faction sprite sets). This case-study
branch starts from `65cf498`, which adds only the previous setup document to that game
baseline. Do not assume that this document describes future HEADs without re-auditing.

| Identity | Audited value or meaning |
|---|---|
| Game source | `4da4c0e` |
| Simulation schema/rules revision | 30, `Sim.VERSION` |
| Shipping content revision | 16, `src/content.lua` |
| Engine/runtime | Portable Windows x64 LÖVE 11.5, archive hash in `toolchain.json` |
| Script language | The pinned LÖVE LuaJIT environment; Lua 5.1-compatible project code |
| Art environment | Blender 5.1.0 and Python/Pillow workflow |
| Active art at previous production handoff | 27 catalog entries; generated locally, not versioned PNGs |
| Separate Footman work | `desk/footman-overhead`, `1cc4808`, not part of audited master |
| Separate overview | `desk/current-system-overview`, included in this documentation branch |
| Mouse study | Separate PR #2; not shipping content or production catalog integration |

The source files linked below describe implementation. [STATUS.md](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/STATUS.md),
[CONTROL_RESPONSE.md](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/docs/CONTROL_RESPONSE.md), [OVERNIGHT_HANDOFF.md](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/docs/OVERNIGHT_HANDOFF.md)
and [ORDERS_ART_HANDOFF.md](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/docs/art/ORDERS_ART_HANDOFF.md) describe earlier measurements.
Those reports do not become fresh measurements simply because this document quotes
them. Raw screenshots, logs, blends, runtimes and catalogs may be absent in a clone.

There are three different identities worth preserving in every experiment:

1. **Rules identity:** source/content/map/runtime compatibility used by replay/network.
2. **Presentation identity:** asset catalog/build IDs, renderer settings and display.
3. **Measurement identity:** machine, process, scenario, warmup, instrumentation and
   output reports. Equivalent rules do not imply equivalent frame time or pixels.

<a id="engineering-2-the-implemented-game-as-a-workload"></a>

### 2. The implemented game as a workload

The game has conventional RTS interactions: selection, queued orders, construction,
harvesting, training, attack commitment, fog, expansion and headquarters defeat.
The Orders use workers and multiple Keeps; Megacorp uses coverage, automated rigs,
orbital buildings, pods and garrisons. Ground and flying units coexist. Associates
apply accumulating target stacks; Battleships have a channelled anti-air ability.

This matters architecturally because it produces several kinds of persistent work:

| Workload | Consequence for implementation |
|---|---|
| Crowds receive one click together | Destination assignment and many concurrent routes |
| Workers repeatedly travel and load | Node contention, pathing, carrying and drop-off state |
| Buildings alter terrain occupancy | Route/cache invalidation during a match |
| Flyers and heavy vehicles | More than one clearance/targeting policy |
| Garrison and pod delivery | Hidden occupants, deferred spawn placement and capacity |
| Coverage-based production | Per-player spatial state and future arrivals |
| Windup, channel and periodic effects | Tick ordering changes combat outcomes |
| Fog and private orders | UI, audio and bots need filtered information |
| Recorded long matches | Historical entities, command storage and checkpoint cost |

There are four symmetric shipping maps, ranging from 160×224 to 224×224 cells, plus
smaller test scenarios. Shipping resources are substrate/charge; supply comes from
buildings up to 200. The original Warcraft-inspired hero design survives in fixtures
with XP, revival, upgrades and camps/control points. It must not be used to infer
that the current shipping maps contain those objectives.

The companion inventory gives all rosters, current statistics and controls. This
case study emphasizes how those mechanics exercise the engine rather than repeating
every unit value.

<a id="engineering-3-repository-and-dependency-map"></a>

### 3. Repository and dependency map

```text
main.lua / conf.lua                    LÖVE lifecycle and execution mode
    ├─ src/ui/shell.lua                 menus, lobby, replay library
    ├─ src/app.lua                      live match, wall time and presentation
    │    ├─ src/ui/*                    input, camera, HUD, observation, audio
    │    ├─ src/sprites.lua             catalog, textures, masks and draw calls
    │    ├─ src/asset_frames.lua        read-only animation choice
    │    ├─ src/bot.lua → src/bot/*     commands from filtered views
    │    ├─ src/net/*                   ENet transport and complete command frames
    │    ├─ src/replay.lua              recording, compatibility and checkpoints
    │    └─ src/sim/init.lua            authoritative step / views / snapshots
    │         ├─ fixed.lua, codec.lua   bounded arithmetic and canonical state
    │         ├─ path.lua, movement.lua, geometry.lua
    │         └─ vision, harvest, abilities, projectiles, stats, coverage, control
    └─ tests/*                         headless or rendered execution modes

src/content.lua + src/maps/*            definitions and map data
art/recipes + tools/blender/*           reproducible source art operations
tools/assets/* → assets/generated       packing, metadata and local publication
scripts/*                              setup, test, export, map and package wrappers
```

The simulation is a module-oriented Lua application, not an ECS framework with
archetype storage. Entity records live in an ID-indexed table with an explicit ordered
ID array. `src/sim/init.lua` still orchestrates substantial gameplay logic. `src/app.lua`
similarly joins input scheduling, stepping, observation, feedback, replay and drawing.
Extracted modules reduce complexity but do not make either orchestration file small.

**Review hypothesis:** both large orchestrators are maintainability pressure points.
Extraction should be driven by a stable state contract and a reproducing test, not a
generic rewrite. A rewrite that changes ordering can alter gameplay without changing
any balance number.

<a id="engineering-4-why-this-is-a-löve-implementation"></a>

### 4. Why this is a LÖVE implementation

LÖVE is the host, not the owner of game truth. [conf.lua](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/conf.lua) disables physics,
joystick, video and touch. Test/network-worker modes also disable window, graphics,
audio and sound. This lets the same runtime host deterministic headless tests without
requiring a separate Lua interpreter or a window.

[main.lua](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/main.lua) selects the shell, match fixtures, viewers, benchmarks or
headless runner. Headless modes override `love.run` to return an exit status; ordinary
modes implement `love.load/update/draw` and input callbacks. Automated windowed modes
capture screenshots and use an error handler that exits nonzero.

| LÖVE responsibility | Project-owned responsibility |
|---|---|
| Window and callbacks | Match/menu state and command scheduling |
| Canvas, Image, Quad, Shader | World projection, depth policy, atlas contract |
| Audio sources and sound data | Cue selection, cooldowns, buses and visibility policy |
| Timer | Feeding the outer accumulator and measuring performance |
| Filesystem and data hashing | Save policy, source fingerprint and replay validation |
| ENet binding | Lobby protocol, complete tick aggregation and desync checks |
| LuaJIT execution | Numeric discipline and deterministic algorithm order |

No LÖVE call belongs in `src/sim`. Hashing uses LÖVE outside that folder; serialization
inside it emits bytes without needing engine APIs. A future port can retain simulation
rules while replacing application, graphics and transport adapters, but that port
would still need new compatibility and numerical verification.

`src/runtime.lua` adjusts LuaJIT cache capacity to `maxtrace=16000` and
`maxmcode=16384`. These are limits, not preallocated memory. The control report records
trace-cache churn as a measured reason for this setting; it does not establish that
the same tuning benefits every LuaJIT game. Default versus tuned JIT determinism is
included in the fresh-process test workflow.

<a id="engineering-5-time-commands-and-the-live-frame"></a>

### 5. Time, commands and the live frame

<a id="engineering-51-three-clocks"></a>

#### 5.1 Three clocks

There are three distinct concepts:

- **Simulation tick:** one authoritative 50 ms step; all rules use integer ticks.
- **Host frame time:** floating-point elapsed seconds used by camera/audio/UI and
  the accumulator. It is not read inside simulation rules.
- **Presentation phase:** interpolation and sprite time derived from known state,
  movement and host presentation state. It cannot decide hits or visibility.

In `App:update`, elapsed time is clamped to 0.25 seconds before accumulation. Offline
backlog above 0.5 seconds is capped and counted; at most eight simulation steps are
processed per update. Network mode does not apply the offline backlog discard cap.
The input delta clamp still applies in network mode. Thus “network preserves ticks”
means it never skips authoritative tick numbers, not that arbitrary wall-clock
stalls are fully recovered in real time.

Discarding offline backlog discards accumulated wall time, not recorded command
frames from an already advanced simulation. This is why replay consistency can
survive a host stall while real-time match pacing slows. Never describe this as a
render-only detail when assessing responsiveness or speed under load.

Offline pause clears accumulation. Offline speed scales the time fed to the fixed
step, while network play remains at 1×. Replay seeking processes bounded batches of
up to 40 ticks per update; it is not a full rollback netcode system.

<a id="engineering-52-command-envelope"></a>

#### 5.2 Command envelope

The stable integration point is a primitive Lua record:

```lua
-- Example for an existing owned unit; x/y here are integer world subunits.
local cmd = {
    tick = world.tick + 1,
    player = 1,
    sequence = world.players[1].sequence + 1,
    kind = 'move',
    args = {entity = unitId, x = 10 * 256 + 128, y = 12 * 256 + 128}
}
Sim.step(world, {cmd})
```

This is a minimal simulation-side example, not a UI shortcut. Normal UI uses
`App:command`; it stages commands and assigns actual execution ticks later. Coordinate
conventions are command-specific: move destinations are subunits, while building
placement uses grid cells. Read the corresponding command branch before generating
commands programmatically.

The simulation rejects unknown command kinds, wrong ticks, invalid player/sequence,
defeated senders and malformed arguments. Entity operations validate ownership.
Append flags and group IDs are checked; appended orders have a 32-entry limit.
Once a valid envelope is accepted for processing, its sequence is consumed even if
later entity/argument validation rejects the operation. Reusing that sequence is
not a retry protocol.

The step sorts commands by player, sequence and canonical byte ordering for ties.
Arrival order must not become execution order. The command vocabulary includes move,
attack, attack-move, stop, hold, build, recruit, cancel, rally, patrol, follow, cast,
ping, harvest, requisition, land, pod load/launch, garrison/unload and fixture hero
operations. A recognized kind need not be available to every faction.

<a id="engineering-53-one-order-traced-end-to-end"></a>

#### 5.3 One order traced end to end

1. Input resolves selection/card context and converts the cursor to world space.
2. The application allocates a sequence and stores pending feedback metadata, then
   queues the command. Local acknowledgment can happen immediately.
3. Offline play assigns the next tick; network play submits into a future complete
   frame. Bot commands join this same flow.
4. `Sim.step` checks the envelope, ownership and destination. Formation/destination
   assignment is deterministic and may produce a route request.
5. Route and movement phases change authoritative position when work can proceed.
6. The new filtered view updates selection, animation, observation and feedback.
7. Accepted/rejected events resolve pending UI state. Replay records the executed
   command frame, not the user's raw mouse event.

Immediate sound, command acceptance and first actual displacement are three different
latency measurements. The control regression measures displacement separately.

<a id="engineering-54-whole-tick-cost"></a>

#### 5.4 Whole-tick cost

The live loop measures step, view, event filtering, feedback and replay portions.
It also performs selection pruning, hover refresh, alert/audio observation and
interpolation bookkeeping. Optimizing `Sim.step` alone can leave the rendered game
over budget because these surrounding costs remain.

The offline bot is queried on a 20-tick cadence in the normal application loop, using
a filtered view for player 2. Benchmark fixtures can replace its commands while
retaining the surrounding live update path; that does not measure bot decision cost.

<a id="engineering-6-state-model-and-numeric-determinism"></a>

### 6. State model and numeric determinism

<a id="engineering-61-world-schema"></a>

#### 6.1 World schema

This is a field-family guide, not a complete formal schema:

| World region | Examples | Why it matters |
|---|---|---|
| Identity/configuration | version, tick, config, content, map | Establishes rules and coordinates |
| Entity store | entities, order, nextId | Stable IDs and deterministic traversal |
| Players | resources, sequence, defeat, HQ, technology | Economy and command ownership |
| Navigation | searches, pathCursor, navVersion, entity paths/goals | Future movement depends on pending work |
| Spatial game state | visible, known resources, coverage | Target validity and production legality |
| Deferred economy | queues, call-downs, landings, pods | Future purchases/spawns |
| Combat | attacks, casts, cooldowns, statuses, projectiles | Future effects and commitment |
| Objectives/result | control, result | End conditions |
| Transient/derived | events, metrics, geometry scratch, blocked cache | Different retention/checkpoint rules |

Search heaps and scheduling cursors are not disposable performance caches. Changing
them can change which unit gets a route first, affecting future combat and economy.
They belong in restore/checkpoint reasoning.

`Sim.create` currently copies configuration, content and map with `Codec.copy`.
A nearby comment claims content is held by reference; the executable expression
still copies it. This is a concrete example of why commentary is weaker evidence
than the implementation. Shared input definitions must remain unmodified either way.

<a id="engineering-62-integer-arithmetic-over-lua-numbers"></a>

#### 6.2 Integer arithmetic over Lua numbers

`fixed.lua` sets 256 subunits per cell and a maximum exact integer of
9,007,199,254,740,991. It validates bounded integers, checks `mulDiv` products, uses
integer square root and deterministic rounding, and supplies vector/geometry helpers.
The representation is not a native fixed-point integer datatype: it relies on
exactly representable integers within Lua's numeric range.

For example, negative `mulDiv` uses floor semantics; symmetric-looking arithmetic
rewrites can change results. Squared-distance hot paths rely on known bounds, with
comments constraining map extents. Extending maps or statistic magnitudes requires
checking intermediate products, not just final coordinates.

No shipping gameplay randomness currently runs. A project PRNG and its golden
sequence remain available. Determinism does not require eliminating randomness;
it requires controlling its algorithm, seed, call order and retained state if it is
reintroduced. The current absence is a game rule, not the sole reason replay works.

<a id="engineering-63-canonical-primitive-codec"></a>

#### 6.3 Canonical primitive codec

`codec.lua` encodes nil, booleans, bounded integers, strings and acyclic tables using
length-prefixed tokens. Keys sort numerically or bytewise rather than by insertion
order or locale-sensitive string ordering. Unsupported values and cycles fail.
Decoding does not execute Lua source.

The decoder bounds payload size to 32 MiB, depth to 64, visited nodes to one million
and a table's count to 500,000. It rejects duplicate keys, nil table values, trailing
bytes and noncanonical numeric strings. Network transport imposes a smaller message
limit. These checks reduce malformed-input risk; they are not a complete untrusted
network security assessment.

Numeric output tokens are memoized only over a bounded positive range. Zero is
excluded because `-0` and `0` share a Lua key but can format differently. This is an
example of preserving bytes while optimizing serialization.

<a id="engineering-64-ordering-is-a-semantic-contract"></a>

#### 6.4 Ordering is a semantic contract

Do not replace stable arrays with `pairs` in gameplay decisions. Conversely, a use of
`pairs` is not automatically a determinism defect: the crowd push pass accumulates
integer contributions commutatively and applies results in world order. Its safety
depends on bounded exact sums and equivalent pair membership. A refactor that adds
clamping during accumulation could destroy that property.

Derived geometry buckets are created for a step and removed before returning.
Destination claims used while applying commands are also transient. Future-affecting
data must not accidentally move into module-level scratch. Such scratch also means
the current simulation should not be assumed reentrant or safe for concurrent calls
inside one Lua state without a separate audit.

<a id="engineering-7-tick-ordering-and-gameplay-resolution"></a>

### 7. Tick ordering and gameplay resolution

The authoritative entry point is `Sim.step(world, commands)`. Its major ordering is:

1. Increment tick, reset events/counters and expire statuses.
2. If the match is already resolved, return without more gameplay.
3. Establish temporary geometry/command state; sort commands; plan destinations;
   apply commands and emit acceptance/rejection.
4. Process combat orders and economy, movement, visibility and order completion.
5. Advance ability projectiles and casts/channels into pending effects.
6. Resolve combat/effects, updating visibility when needed.
7. Evaluate headquarters defeat and control objectives; clear geometry scratch.

This ordering is not interchangeable. Expiring statuses before commands avoids one
extra active tick. A stun committed before attack selection can prevent a swing.
Headquarters defeat takes priority over a simultaneous control hold result. Collecting
effects and applying them through the defined resolution phase reduces scan-order
bias, but does not mean every subsystem is mathematically simultaneous.

Attack state exposes start, impact and finish for presentation. Casts have their own
point/finish, target revalidation, resource spending and cooldown commitment. New
orders can interrupt recovery or a channel without refunding already committed
effects. A renderer cannot infer damage from the visible blade position.

Economy similarly has future commitments: reserved supply, production queues,
construction progress, finite node amounts, rig accumulation, orbital readiness and
pending arrivals. A snapshot test that checks only positions and hit points misses
these important state transitions.

**Extension rule:** new mechanics should name the phase where they become effective,
the state retained across ticks, and interactions with death, cancellation, ownership,
visibility and restore before adding presentation effects.

<a id="engineering-8-navigation-and-crowd-movement"></a>

### 8. Navigation and crowd movement

<a id="engineering-81-terrain-route-planning"></a>

#### 8.1 Terrain route planning

`path.lua` uses grid A* with a binary heap. Cardinal moves cost 10, diagonals 14;
ties order by `f`, then `h`, then cell key. Deterministic direction iteration and tie
breaking prevent equal-cost alternatives from depending on table order.

Requests first validate destination clearance and attempt a direct route. Remaining
searches retain their open heap, costs, parents, closed set, destination and navigation
version. `P.step` rebuilds an active schedule in world order and advances it using a
persistent cursor. Shipping `pathBudget` is 256 expansions per tick. Direct checks
and optional smoothing have separate budgets (16,384 and 8,192 respectively).

The budget makes CPU work more predictable but introduces simulated latency. It
must be measured as time-to-first-displacement and eventual arrival, not merely path
success. Raising it can improve responsiveness while violating the frame budget.

<a id="engineering-82-shared-pending-searches"></a>

#### 8.2 Shared pending searches

Nearby group members may share terrain search work only when owner, group, radius,
lane direction and navigation version agree. Start/destination proximity is bounded.
A follower does not blindly reuse its leader's final movement: it gets validated
connectors, a copied waypoint chain, its own destination and local avoidance.

Leader cancellation/death or terrain version changes trigger deterministic promotion
or revalidation. Detours caused by local congestion remain independent. Heavy-unit
waypoints retain radius-specific offsets (`px/py`); reducing them to cell centers
can make an apparently valid shared path cut through terrain.

<a id="engineering-83-local-movement"></a>

#### 8.3 Local movement

Air movement is a separate early pass: flyers travel toward waypoints without ground
crowd occupancy. Ground movement uses spatial bins, frozen proposals, deterministic
candidate choices and live reservations. Proposals prioritize waiting time then ID.
Updating accepted positions in the live index prevents later units from moving
through earlier accepted positions.

Idle allies can yield; Hold has a stronger non-yielding contract. Blocked units back
off at a staggered cadence, and congestion can request a detour while preserving a
usable old path. Restarting searches repeatedly would starve units sharing a finite
search budget, so pending detours are allowed to finish.

**Clearance nuance:** terrain uses the full body radius, but allied unit separation
is deliberately softer: normally 75% of combined radii, with a 65% pressed threshold
for applicable squeezing. Enemies retain full separation. “No collision compromise”
must not be read as “all friendly circles are always disjoint.” Spawn/unload geometry
has its own stricter free-space checks.

Navigation versions invalidate routes when buildings, terrain occupancy or resource
depletion change the navigable world. Any new obstacle system must participate in
that invalidation contract.

<a id="engineering-84-limits-and-research-directions"></a>

#### 8.4 Limits and research directions

Opposing dense heavy traffic can jam. Full-radius opposing Enforcers cannot pass
side by side in two cells: required width is 640 subunits versus 512 available.
Even a geometrically sufficient corridor does not prove local steering converges.

This implementation is not hierarchical navigation, a flow-field solver or a formal
multi-agent pathfinding solution. Those are possible alternatives, not drop-in fixes.
Compare them with replayable workloads, different radii, terrain invalidation,
ownership, and deterministic CPU budgets before replacing existing behavior.

<a id="engineering-9-visibility-views-and-information-boundaries"></a>

### 9. Visibility, views and information boundaries

`vision.lua` performs integer/rational shadowcasting and caches per-entity fields in
a weak-key world cache. The cache checks navigation version, origin and sight; it
reuses field membership, not a license to skip visibility unions unconditionally.
`coverage.lua` provides the separate orbital placement/income territory mechanic.
Sight and coverage answer different questions.

`Sim.view` builds whitelisted entity records, hides enemy queues/orders and private
timers, and exposes limited attack/cast phases for readable presentation. Friendly
orders are copied; enemy orders become a neutral stopped representation. Garrisoned
enemies are omitted. `Sim.eventsFor` filters events before audio and effects consume
them, because an unseen sound or projectile can leak information too.

The view is **read-only by convention, not recursively immutable**. Some map and
player fields reference underlying tables, while mutable entity order/queue records
are copied. A proposed allocation optimization must document aliases. A renderer
that writes a referenced visibility table can corrupt game state despite receiving
an object called a view.

`ui/observation.lua` remembers last-seen buildings/resources and produces ghost
markers. Seeing an empty formerly occupied footprint invalidates that memory.
Presentation remembers what was observed; it must not update hidden objects using
full-world truth. Snapshot/seek operations must also reset or rebuild this memory.

Bots receive filtered views and content through faction strategy modules. That is
the intended information contract, not a claim of a hardened secrecy boundary:
both lockstep peers locally simulate the complete world. A modified client can read
hidden state. Fog-correct UI and resistance to map hacks are different problems.

<a id="engineering-10-replay-and-compatibility"></a>

### 10. Replay and compatibility

<a id="engineering-101-three-state-representations"></a>

#### 10.1 Three state representations

| API | Contents/purpose | Important limit |
|---|---|---|
| `Sim.snapshot` / `restore` | Deep copy of world; events cleared on snapshot | Schema/version compatibility is required |
| `serializeCanonical` | Whole world except transient events | Includes more than periodic checks need |
| `serializeAuthoritative` | Selected future-affecting roots for checkpoint hashing | New player/root fields require explicit review |

Authoritative checkpoints include entity records, ID order, search state, cursor,
navigation version, control and selected player fields including visibility, coverage
and orbital commitments. They omit fixed content/map copies covered by identities,
recomputable blocked data, explored rendering history and per-tick metrics.

New entity fields are picked up because full entities are encoded. New player/root
fields are not automatically picked up by an explicit projection. This asymmetry is
a particularly important review trap. Every added field needs a classification:
immutable, future-affecting, recomputable or presentation-only, with a restore test
or recomputation argument.

<a id="engineering-102-recording-format"></a>

#### 10.2 Recording format

`replay.lua` stores a header, contiguous command frames and tick-indexed hashes.
Header fields include format/game/simulation/runtime identifiers, source build hash,
content hash, map/hash, configuration and checkpoint interval. Default interval is
100 ticks; ordinary application recording uses 500 ticks. Network checksum exchange
is independent at 100 ticks.

A longer interval reduces recording cost but increases how long divergence may go
undetected. Hashes locate a detected mismatch, not necessarily its originating tick.
The exact command stream is the replay; sparse hashes are verification points.

Reads reject incompatible identities and noncontiguous frames. The build fingerprint
hashes an explicit set of authoritative source files plus recursively discovered
`src/sim` and `src/maps` Lua files. It does not hash every source file. In particular,
presentation, bot strategy and `src/app.lua` are outside that list. Bot decisions are
recorded as commands, but network scheduling changes in the application still deserve
compatibility review even if they do not change this fingerprint.

Because source bytes are hashed, even a non-semantic edit to fingerprinted files can
invalidate recordings. This is conservative compatibility, not migration support.
Presentation-only source and sprite changes are intentionally able to preserve it.

<a id="engineering-103-diagnostic-workflow"></a>

#### 10.3 Diagnostic workflow

Preserve the failing command stream, both peers' identities and the earliest retained
divergent checkpoint. Compare state paths with `scripts/compare-states.ps1`. Reproduce
from an earlier snapshot and narrow the interval. Do not simply update a golden hash
or assume a matching final winner means the match remained deterministic.

<a id="engineering-11-private-multiplayer"></a>

### 11. Private multiplayer

ENet sends reliable encoded messages. The host aggregates complete frames; the client
submits commands and receives the assembled stream. Lobby messages exchange compatible
configuration, faction choices, readiness and explicit host start.

At match start, the application submits empty frames for ticks 1–3. While preparing
tick `t`, it submits queued input for `t+3`. At 20 Hz this is a nominal 150 ms scheduling
lead, not a guarantee of exactly 150 ms input-to-motion latency. Sampling boundaries,
transport wait, validation and route work add latency.

`lockstep.lua` accepts up to 128 commands per submission, validates ownership of the
envelope and bounds submissions from the next tick through 120 ticks ahead. Identical
duplicate batches are idempotent; conflicting batches fail. `take` waits for every
player, then sorts the combined commands. Missing input causes a stall, not a guessed
empty command frame.

Transport rejects messages over 1 MiB before codec decoding. Checksum messages detect
divergence, retain a small diagnostic history and fail the match on mismatch. There
is a 30-second connection timeout in the implemented connection states. These are
private prototype protections, not production service infrastructure.

**Review hypotheses, not proven exploits:** client-side received frames and hash
messages deserve stricter tick-window/state-machine validation before exposing this
to untrusted peers; a malicious peer might exercise retention and validation paths
differently from the honest-host tests. Reliable transport also does not supply
authentication, authorization beyond local protocol rules, or anti-cheat.

No rollback/prediction, host migration, reconnection, NAT traversal, public lobby,
accounts or spectators are delivered. Same-host ENet agreement cannot establish
real two-PC latency/jitter behavior. A WAN release would need a separate security,
deployment and latency design rather than only opening the port.

<a id="engineering-12-rendering-camera-and-animation"></a>

### 12. Rendering, camera and animation

<a id="engineering-121-coordinate-chain"></a>

#### 12.1 Coordinate chain

The simulation uses integer subunits. The camera maps one cell to 26 horizontal units
and `26*sin(60°)` vertical units before zoom. Viewport normalization targets 24 rows;
UI size and orbital sidebar affect the viewport. The camera can pan and zoom but
does not rotate with the unit.

Blender separately renders an orthographic camera 60° above the ground at a calibrated
world-to-pixel scale. These are related presentation contracts, not one real-time 3D
camera. Picking, selection rings, sprite anchors and building footprints must agree
through the full conversion chain.

`App:interpolated` uses prior positions and `accumulator/0.05`, clamped to one. Prior
records are stamped so a newly visible unit is not interpolated from its old last-seen
position. Presentation can be smooth while the authoritative world remains at 20 Hz.

<a id="engineering-122-frame-selection"></a>

#### 12.2 Frame selection

`asset_frames.lua` selects idle/move/attack/death and worker cargo variants. Eight
direction headings have a 15° hysteresis margin beyond the ordinary sector boundary,
reducing flicker in crowds. Movement advances by actual travel relative to exported
stride when available. Attack frames map start/impact/finish onto the exported
contact frame. Death uses death tick; building construction maps progress into stages.

Those calculations may use floating-point trigonometry because they are cosmetic.
Copying them into authoritative movement would violate the numeric contract.

The team shader samples a color atlas and matching mask, derives luminance and mixes
team color into the masked region. Pixel-style assets have a separate palette lookup
path. Ordinary production art uses linear filtering; legacy/pixel-style paths choose
nearest filtering. “All sprites are pixel art” would be an inaccurate description.

<a id="engineering-123-draw-cost-and-correctness"></a>

#### 12.3 Draw cost and correctness

`sprites.lua` loads pages, constructs Quads, binds mask/team uniforms and draws around
ground anchors. Draw state is preserved around each call. This is simple and robust,
but repeated pages/uniform changes/state saves are plausible batching costs.

Batching must preserve painter/depth order, occlusion, masks and separate team colors.
Sorting an entire crowd by texture can create wrong overlaps. A useful candidate is
batching compatible consecutive draws, measured against the unchanged image/ordering
contract. A custom packed texture/shader scheme is a larger experiment, not a proven
necessary rewrite.

Terrain is a separate procedural chunk renderer: 16-cell chunks at 16 internal pixels
per cell, baked lazily with presentation hash noise and nearest filtering. Fog overlays
and remembered markers have distinct state. A previous scissor/viewport leak clipped
terrain baking and obscured roofs; actual gameplay pixel checks were needed to catch it.

<a id="engineering-13-content-and-map-authoring"></a>

### 13. Content and map authoring

`content.lua` defines rules, units, buildings, statuses, abilities and factions.
`content_time.lua` converts exact seconds/cells into ticks/subunits and rejects
unrepresentable quantities. `content_validate.lua` and tests check references and
definition consistency. This is data-driven content within a focused implementation,
not an arbitrary user scripting sandbox.

Factions specify headquarters, worker policy, starting assets, defeat policy, bot and
building availability. A new faction is more than another dictionary: it also needs
production rules the engine understands, interface affordances, a bot strategy,
sprite mappings and regression coverage. The Orders/Megacorp pivot demonstrates
both useful reuse and places where specialized Lua mechanics remain appropriate.

Maps use tracked TMX sources and Lua exports converted into terrain strings, blocked
and unbuildable cells, starts, resources and anchors. Layout generators create
180°-symmetric shipping maps and validate route/layout properties. Tiled export/check
and generated output are different paths; do not claim the editor validated a map
when only the generator ran.

Rendering terrain can change without changing pathing, but moving resources, flags or
starts is authoritative. Cosmetic jagged borders deliberately do not move the center
cell's gameplay identity. Finished Blender tiles, autotile adjacency, cliffs and
elevation mechanics are future art/engine work.

<a id="engineering-14-blender-and-asset-publication"></a>

### 14. Blender and asset publication

<a id="engineering-141-reproducible-source-instead-of-opaque-exports"></a>

#### 14.1 Reproducible source instead of opaque exports

Tracked JSON recipes and Python adapters derive geometry and animation from a pinned
local `RTSAssets.blend`. Blender runs in an isolated background process. Original
bones/actions are preserved; sampled correction poses are baked into derived actions.
The original source file is never the export destination.

Each complete asset is sampled over its clips/headings, bounded under the fixed camera,
and rendered into paired color/team-mask images at supersampled resolution. Reduction,
packing, padding and metadata generation follow. Stable ground anchors prevent each
pose being recentered by its visible alpha bounds. Long weapons/falls enlarge the
canvas instead of shrinking the model frame by frame.

The exporter produces metadata for duration, loop state, direction, contact sample,
pages, rectangles, anchors and movement stride. A successful PNG render alone is not
a valid sprite: the runtime contract and complete frame coverage are part of the asset.

<a id="engineering-142-publication-as-a-transaction"></a>

#### 14.2 Publication as a transaction

Build identity depends on inputs/tools. Generated asset directories are retained by
build ID. Preview is unpublished. Build merges requested entries with existing
catalog entries, validates the result, then atomically replaces the Lua catalog
commit point. Failed generation must preserve the previous usable publication.

This guards against partial roster publication and mismatched worker cargo variants.
It does not guarantee byte-identical renders on every GPU/Blender release. Build
identity and environment reports support diagnosis; pixel reproducibility needs
its own evidence.

<a id="engineering-143-variant-design-and-art-evidence"></a>

#### 14.3 Variant design and art evidence

The Orders production set contains humanoids, a separately rigged mount/rider,
floating shrine and building construction stages. The Megacorp has infantry,
aircraft, buildings and a pod. Catalog count includes variants and retained legacy
assets, so it is larger than the gameplay roster.

Reusable weapons/shields are agreed as Blender authoring inputs, exported as complete
variants. Runtime equipment swapping and layered combat sprites are not implemented
by that decision. The separate Footman study fixes shield presentation and sword
pose, but remains unmerged. It is evidence of the importance of overhead silhouette,
not proof of a general modular equipment library.

For every variant, review grip, floor clearance, silhouette, native pixels, all
headings, motion/contact, masking and runtime zoom. Structural bounds checks can pass
while a shield remains unreadable. Still-image review cannot establish transition
feel or temporal artifacts. Reopened Blender verification confirms saved poses match
reports, not that the animation is artistically accepted.

<a id="engineering-15-controls-audio-and-usability"></a>

### 15. Controls, audio and usability

Contextual cards, subgroup selection, queued orders, control groups, smart casting,
minimap input, camera bookmarks and placement previews form an actual input system,
not a list of hotkeys tied directly to entity mutation. Command feedback tracks local
pending state and resolves it against simulation events.

The distinction between selecting a subgroup for its command card and discarding the
rest of the selection is important. So is treating A-click on a unit differently
from A-click on ground. Input tests cover these semantics because a simulation test
fed the correct command cannot detect a UI that produced the wrong one.

Audio currently synthesizes short nonverbal cues; named manifest entries can load
recordings later. Priority, bus gain and cooldown control spam. Cosmetic effects
observe filtered events and have bounded lifetimes. They must not reveal hidden
combat or change game authority. Acknowledgment timing is part of perceived control,
but it cannot compensate indefinitely for a stalled unit.

Human review still matters for readable health trails, targeting previews, opposing
team recognition, camera easing, congestion and crowded battles. A screenshot assert
can verify a roof pixel or placement ring, not whether a new player understands the
economy. Treat usability and visual acceptance as explicit test sessions.

<a id="engineering-16-packaging-and-reproducibility"></a>

### 16. Packaging and reproducibility

<a id="engineering-161-clean-checkout-requirements"></a>

#### 16.1 Clean-checkout requirements

The repository tracks source, recipes, maps and tests. It does not contain portable
runtimes, the source blend, generated atlases, screenshots or finished packages.
Personal skills are outside the repository too. A clone and a developer's populated
workspace are different environments.

```powershell
# From the checkout; downloads the pinned portable runtime and checks its archive.
./scripts/setup.ps1
./scripts/run.ps1 -Smoke
./scripts/run.ps1

# Headless and live verification have different coverage.
./scripts/test.ps1 -Suite unit
./scripts/test-all.ps1

# Generate required art only after provisioning the pinned source and Blender/Pillow.
./scripts/export-assets.ps1 -Mode Build -Roster orders_units
./scripts/export-assets.ps1 -Mode Build -Roster orders_buildings
./scripts/export-assets.ps1 -Mode Validate -Roster orders_units
./scripts/export-assets.ps1 -Mode Validate -Roster orders_buildings

# Require an already available valid art set for the art-inclusive package path.
./scripts/package.ps1 -WithAssets
```

Other production rosters are `megacorp_aircraft`, `megacorp_infantry`,
`megacorp_buildings`, `megacorp_props`; legacy/pilot rosters are separate. A source-only
package can use procedural art fallbacks. That makes it runnable but unsuitable for
claiming production rendering performance.

The source blend's pinned digest and art recipes are documented in the companion.
Do not change the expected digest to make a different file pass. Use a deliberate
source revision with provenance. Python/Pillow and Blender path availability are
independent of whether the game itself runs.

<a id="engineering-162-shareable-windows-build"></a>

#### 16.2 Shareable Windows build

Packaging produces a folder containing the fused game executable and LÖVE DLLs,
plus test/review helpers where configured. Keep the files together. Users do not
need Blender to play exported sprites. Package tests should exercise that exact
package and asset manifest; a passing source checkout does not prove an archive
contains the intended assets.

Replays first target project artifacts and can fall back to the user's LÖVE save
directory. In restricted test environments this fallback may be unwritable too.
Record the actual path and access conditions rather than treating an environment
failure as a combat regression.

<a id="engineering-163-source-synchronization"></a>

#### 16.3 Source synchronization

Task branches/worktrees isolate changes; source is pushed via GitHub. Generated data
is recreated or delivered separately with identity manifests. Golden changes and
simulation/content version updates are reviewed explicitly. The current document
includes the previous overview commit but does not merge art branches into master.

<a id="engineering-17-test-strategy-and-evidence"></a>

### 17. Test strategy and evidence

<a id="engineering-171-coverage-matrix"></a>

#### 17.1 Coverage matrix

| Layer | Representative checks | What a pass does not prove |
|---|---|---|
| Primitive/unit | Integer bounds, codec, definitions, frame selector | Live UI correctness |
| Simulation scenario | Commands, harvesting, attacks, queues, pod/garrison | Human control feel |
| Navigation | Wall detour, body radius, counterflow, terrain change | All congestion converges |
| Snapshot/replay | Continued exact state and checkpoints | Cross-version migration |
| Fresh-process determinism | 30/60/144 FPS schedules, default/tuned JIT | Other hardware/OS without runs |
| Local ENet | Complete command agreement in separate processes | Real network latency/jitter or security |
| Rendered UI | Selection, input, hover, viewport, abilities | Balanced gameplay |
| Sprite/pixel | Atlas contract, team masks, roof visibility, pose bounds | Art direction and transition quality |
| Production soak | Replacements, deaths, restores and replay | Arbitrarily long memory stability |
| Fresh/live performance | p95 step/frame against declared gates | Optimization causality from one run |

`scripts/test-all.ps1` combines headless tests, fresh determinism processes, local
network proof, rendered UI at three sizes and asset presentation. `test.ps1` alone
does not run rendered code. Conversely, an art viewer showing a sprite does not
exercise gameplay construction, fog or collision.

Tests intentionally use both shipping content and compact mechanics fixtures.
When evaluating a result, identify which it uses. Hero tests passing under a fixture
do not mean the Orders start with a hero; a tiny fixture path budget does not establish
shipping responsiveness.

<a id="engineering-172-historical-evidence-ledger"></a>

#### 17.2 Historical evidence ledger

The later Orders art handoff records the following for its stated measured revisions:

- 194 headless checks, four fresh 100,000-tick determinism runs, local networking
  and rendered UI/presentation checks.
- 33 Python asset tests and 27 validated active catalog entries.
- Ten saved Blender scenes and 1,304 reopened poses with zero saved/export discrepancy.
- A 12,000-tick production/combat soak, restores at 4,000/8,000, 24 replay checkpoints
  and 1,632 attacks, including replacement production.
- No authoritative gameplay change for that art pass; prior integrated replay matches.

The control integration report records 1/12/24/48-worker wall-detour groups beginning
actual movement by tick 14 in its specified fixture. Infantry counterflow arrived at
tick 615. Heavy recovery arrived by 1954 only after redirection at 1501. The latter
is a recovery result, not proof of unassisted heavy counterflow.

<a id="engineering-173-performance-numbers-and-their-meaning"></a>

#### 17.3 Performance numbers and their meaning

The Orders art report measured three sequential runs per faction at 1080p, 240 units,
VSync 1, Ryzen 5 5600G / RTX 3060. Median of per-run p95 values:

| Metric | Orders | Megacorp | Acceptance |
|---|---:|---:|---|
| Live `Sim.step` | 7.972 ms | 9.761 ms | Below 10 ms |
| Whole live tick | 10.792 ms | 12.745 ms | Diagnostic breakdown |
| Rendered frame | 17.915 ms | 18.043 ms | At most 16.667 ms |

All six final frame gates failed. The report records substantial baseline variation
and does not claim art improved simulation speed. Earlier overnight results were
worse in some metrics; combining the best values across runs is not valid evidence.

Decoded atlas allocation was 239,857,792 bytes, with total runtime texture memory
246,444,160 bytes in that report. Compressed PNG size is not decoded GPU allocation.
Draw-call p95 rose to 450/538 in its Orders/Megacorp scenarios; mixed armies mean an
Orders art change can affect both scenarios.

The live benchmark includes update, views, effects, audio, recording and drawing,
but uses scripted commands and excludes network costs. CPU draw submission is not
GPU timing. Sampled heap is not retained heap after GC. The soak reports retained
and reclaimed memory separately, with suite/module/JIT-cache caveats.

<a id="engineering-174-reproduce-a-candidate-honestly"></a>

#### 17.4 Reproduce a candidate honestly

```powershell
./scripts/test-performance.ps1 -Runs 3 -LiveRuns 3 -RequireAssets `
  -OutputDirectory artifacts/case-study/baseline
```

Run baseline and candidate sequentially without Blender or competing tests. Preserve
source/catalog hashes, CPU/GPU, settings, resolution, VSync, sample counts, cold/warm
state and process identity. Compare distributions and canonical checkpoints. Use
profiling to choose a target, then uninstrumented runs for acceptance. Explicitly
report clamped time/discarded backlog and failures instead of changing budgets.

<a id="engineering-175-checks-performed-for-this-documentation-audit"></a>

#### 17.5 Checks performed for this documentation audit

On 2026-09-25, the pinned local LÖVE 11.5 runtime executed the **unit suite against
the isolated case-study checkout: 28 passed, 0 failed**. That checkout has no copied
production catalog; runtime contract tests are not a fresh production asset validation.
Source inspection checked symbols, key constants, wrappers and branch provenance.
Documentation validation checks local links, headings and whitespace.

No full determinism, LAN, rendered, Blender export, performance or package suite was
rerun for this documentation task. Historical evidence remains historical. Human
playtesting and a second machine remain unperformed here.

<a id="engineering-18-failure-studies-and-engineering-lessons"></a>

### 18. Failure studies and engineering lessons

<a id="engineering-a-correct-paths-unacceptable-start-delay"></a>

#### A. Correct paths, unacceptable start delay

**Recorded problem:** independently routing a large selection around a wall made
first displacement unacceptably late. **Change:** shared pending terrain searches,
an active deterministic schedule and cheaper destination reservation work.
**Lesson:** path existence and total throughput do not describe RTS responsiveness.
Track percentiles of click-to-displacement, including the last units in the group.
**Limit:** the synthetic regression is not an all-map latency bound.

<a id="engineering-b-a-visual-scale-change-invalidated-a-movement-claim"></a>

#### B. A visual scale change invalidated a movement claim

**Recorded problem:** the larger Enforcer no longer fit assumptions used by an older
two-cell counterflow test. Shared waypoints/connectors also needed actual radius-aware
positions. **Change:** preserve vehicle offsets, verify connector origins and separate
infantry arrival from heavy recovery tests. **Lesson:** content radius is part of the
navigation contract. Never make a failed geometry test pass by quietly shrinking the
body or calling an assisted recovery an autonomous solution.

<a id="engineering-c-optional-quality-work-blocked-required-correctness"></a>

#### C. Optional quality work blocked required correctness

**Recorded problem:** an exhausted smoothing budget could reject necessary vehicle
clearance work. **Change:** mandatory clearance remains valid under its appropriate
bounded work; optional smoothing may stop without invalidating a valid remainder.
**Lesson:** budget quality improvements separately from safety checks. “Budgeted” is
not sufficient if running out changes validity incorrectly.

<a id="engineering-d-explicit-garrison-orders-fought-automatic-combat-behavior"></a>

#### D. Explicit garrison orders fought automatic combat behavior

**Recorded problem:** an Enforcer alternated between entering a bunker and pursuing
an enemy. **Change:** garrison suppresses fresh automatic acquisition en route, like
other explicit noncombat orders. **Lesson:** acquisition policy is an order-state
machine issue, not merely a better pathfinding problem. Test mixed pod/choke/garrison
sequences, not just isolated garrison entry.

<a id="engineering-e-headless-green-did-not-cover-frame-loop-regressions"></a>

#### E. Headless green did not cover frame-loop regressions

**Recorded problem:** backlog behavior changed while headless tests stayed green.
**Change:** the combined wrapper runs rendered/input suites too. **Lesson:** tests
must execute the code path being claimed. Correct `Sim.step` does not validate
`App:update`, which chooses when and with which commands it is called.

<a id="engineering-f-valid-art-disappeared-through-render-state-leakage"></a>

#### F. Valid art disappeared through render-state leakage

**Recorded problem:** a terrain-bake viewport/scissor error obscured building roofs.
**Change:** refresh the scissor and add an actual roof-pixel gameplay check.
**Lesson:** successful asset export and atlas loading do not prove correct compositing
inside a warmed, cached gameplay scene.

<a id="engineering-g-plausible-optimizations-failed-measurement"></a>

#### G. Plausible optimizations failed measurement

**Recorded result:** visibility/coverage optimization candidates were reverted after
inconsistent or adverse timings. **Lesson:** removing theoretically redundant work
can increase allocation or worsen JIT/cache behavior. Preserve failed experiments
as reports, not production complexity. A hypothesis is useful even when rejected.

<a id="engineering-h-a-technically-valid-footman-was-visually-unclear"></a>

#### H. A technically valid Footman was visually unclear

**Observed in separate art work:** shield face projection and thin sword orientation
made equipment hard to read from above. All the relevant structural checks could
pass. **Lesson:** inspect at native pixels, across headings and motion, with the same
camera/scale. Art fixes should address pose and silhouette before arbitrary enlargement.
**Limit:** the revised equipment remains on an unmerged branch and needs human motion
acceptance; do not attribute it to audited master.

<a id="engineering-19-prioritized-improvement-experiments"></a>

### 19. Prioritized improvement experiments

This is a proposed investigation order, not a promised roadmap. Select one experiment
at a time and preserve its baseline. No improvement below is claimed implemented here.

| Priority | Question | Candidate intervention | Acceptance evidence |
|---|---|---|---|
| P0 | Can the shipping frame meet its target? | Profile whole-frame phases; reduce measured view/draw costs | Repeated asset-backed frame/step distributions, identical authoritative checkpoints |
| P0 | Are controls good under representative congestion? | Target explicit order/acquisition and heavy-flow cases | Replays, start/arrival latency, body clearance, human micro session |
| P1 | Does long-session cost track live or historical entities? | Measure retained entity iteration and checkpoint growth | Increasing casualty/replacement soak, GC-separated heap and timing |
| P1 | Can view allocation be reduced safely? | Reuse only well-defined records or split static/dynamic projections | Alias/privacy tests, draw-read-only proof, restore and live timing |
| P1 | Can sprite submissions be batched safely? | Compatible consecutive batches or measured shader/atlas redesign | Occlusion/team-mask comparisons plus draw/frame metrics |
| P1 | What fails on two real machines? | Instrumented LAN tests with controlled delay/jitter | Matching command/checkpoint traces, stall/ack timing and logs |
| P1 | What must change for current-faction heroes? | One hero vertical slice through content, bots, UI and art | Complete progression/revival/cast scenarios and human balance study |
| P2 | Can terrain art replace procedural ground coherently? | One connected terrain family with map semantics preserved | Adjacency/seam/runtime checks and collision overlays |
| P2 | Can equipment variants scale beyond hand editing? | Grip/socket convention and manifest-driven complete exports | All-heading all-clip validation, saved-scene reopening, visual review |
| P2 | Can maintainability improve without rule drift? | Extract one tested orchestration responsibility | Identical commands/checkpoints and smaller coupling surface |

<a id="engineering-191-performance-experiment-template"></a>

#### 19.1 Performance experiment template

State the hypothesis in measurable terms, for example: “Repeated view construction
accounts for enough live tick time that eliminating specific copies lowers p95 without
sharing mutable authoritative tables.” Capture allocation counts and time at that
boundary first. Prove equal view membership/privacy and identical simulation hashes,
then compare fresh processes at the same asset identity. Reject the change if it
improves a microbenchmark but worsens live frames or complexity without a real gain.

Do not optimize by disabling fog, recording, effects, large bodies or production art
unless those are diagnostic runs explicitly excluded from acceptance.

<a id="engineering-192-historical-state-experiment"></a>

#### 19.2 Historical state experiment

Count alive/dead entities, ordered-ID length, searches, recording frames, checkpoint
bytes and retained heap at fixed intervals through repeated production/death cycles.
Measure whole-world iteration separately from recording retention. Only then choose
compaction, a live-ID index or serialization changes. Preserve stable IDs, corpse
presentation, last-seen knowledge and replay equivalence. New indexes are derived
state only if reconstruction and scheduling effects are actually proven.

<a id="engineering-193-multiplayer-hardening-experiment"></a>

#### 19.3 Multiplayer hardening experiment

Use two PCs and record identities before measuring latency. Test missing/late/duplicate
batches, connection loss, malformed payloads, oversized/far-future frame claims and
readiness transitions. Bound retention independently of honest-peer behavior.
Separate protocol robustness from anti-cheat: complete-world lockstep remains an
information disclosure model even if every packet validator is correct.

<a id="engineering-194-hero-integration-experiment"></a>

#### 19.4 Hero integration experiment

Pick one shipping faction and one hero role. Decide how its cost, starting timing,
revival, XP acquisition and upgrades interact with current supply/economy and HQ
defeat. Implement one complete match loop, including bot use and replay. Do not
reactivate the old fixture wholesale: its compact test values and old rosters are
not a balance specification for the new game.

<a id="engineering-195-art-pipeline-experiment"></a>

#### 19.5 Art pipeline experiment

One sword/shield variant should establish the item pivot, hand attachment, compatible
pose family, color/mask contract and all-pose bounds. Export full units and compare
at matched scale. Only after that should an item library generalize across bodies.
For terrain, begin with adjacent repeatable tiles and a small runtime map; atlas
gutters cannot repair incompatible edge geometry or shading.

<a id="engineering-20-developer-and-ai-handoff-protocol"></a>

### 20. Developer and AI handoff protocol

Before editing, resolve the baseline and inspect outstanding branches. The companion
overview, the latest applicable handoff and live source have different roles. Do not
turn a historical roadmap paragraph into an implicit implementation requirement.

For a proposed change, produce this compact review record:

```text
Baseline: source revision, runtime, content/simulation versions, asset identity
Observed problem: exact input/scenario and evidence location
Hypothesis: why the code produces that behavior
Contract: state ownership, timing, ordering, visibility and compatibility constraints
Change: smallest implementation or content revision that addresses the cause
Regression: scenario that fails before and passes after
Equivalence: hashes/restores/commands expected to remain identical, or intentional changes
Measurement: settings, machine, process count and acceptance thresholds
Visual/human checks: what was actually watched or played, and what remains unreviewed
Delivery: branch, commit, generated manifest, commands and outstanding limitations
```

Suggested task prompt for another AI or reviewer:

> Audit the linked baseline before changing it. Select one failure or measured
> bottleneck from the case study. Reproduce it with shipping content and a declared
> asset/runtime identity. Preserve deterministic command ordering, future-affecting
> state, visibility privacy and existing gameplay unless a rule change is explicitly
> intended. Explain the mechanism, implement the smallest justified change, and run
> the tests that execute the changed path. Report historical evidence separately
> from fresh results. Do not claim performance, artistic acceptance or multiplayer
> readiness from a test that cannot establish it.

<a id="engineering-questions-an-expert-review-should-answer"></a>

#### Questions an expert review should answer

1. Does any new scratch/cache outlive a step and influence future results?
2. Does any optimized view expose mutable tables or private opponent information?
3. Does a data change invalidate route radii, asset scale or map-clearance assumptions?
4. Does a command change preserve cancellation, queues and attack commitment?
5. Does a compatibility-affecting change fall outside the current source fingerprint?
6. Are tests exercising shipping content, mechanics fixtures, or both?
7. Is a timing claim about step, whole tick, frame cadence, CPU submission or GPU work?
8. Does a claimed visual fix survive all headings and actual motion at delivery scale?
9. Can a new checkout reproduce the result without hidden generated files?
10. Does the proposed abstraction solve an observed repeated need, or only make the
    current code look more general?

The full test suite is valuable, but it is not permission to silently replace golden
outcomes. If rules intentionally change, record the expected consequences, review
compatibility versions and produce new evidence rather than calling divergence a fix.

<a id="engineering-21-source-index-and-glossary"></a>

### 21. Source index and glossary

<a id="engineering-implementation-entry-points"></a>

#### Implementation entry points

| Question | File and symbols to start with |
|---|---|
| Lifecycle/modes | [main.lua](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/main.lua), [conf.lua](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/conf.lua) |
| Time and command delivery | [app.lua](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/src/app.lua): `command`, `update`, `interpolated`, `seek` |
| Core rules | [sim/init.lua](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/src/sim/init.lua): `create`, `step`, command `apply`, combat/economy |
| State boundary | Same file: `snapshot`, `restore`, both serializers, `view`, `eventsFor` |
| Arithmetic | [fixed.lua](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/src/sim/fixed.lua): `mulDiv`, `isqrt`, `vector` |
| Stable encoding | [codec.lua](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/src/sim/codec.lua): `keys`, `encode`, `decode`, `copy` |
| Search scheduling | [path.lua](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/src/sim/path.lua): `request`, follower connectors, `step` |
| Crowd steering | [movement.lua](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/src/sim/movement.lua): `step`, proposals, yield/push policies |
| Clearance | [geometry.lua](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/src/sim/geometry.lua): `terrain`, `separation`, `free` |
| Sight/territory | [vision.lua](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/src/sim/vision.lua), [coverage.lua](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/src/sim/coverage.lua) |
| Ability rules | [abilities.lua](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/src/sim/abilities.lua), [projectiles.lua](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/src/sim/projectiles.lua), [stats.lua](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/src/sim/stats.lua) |
| Bot dispatch | [bot.lua](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/src/bot.lua), `src/bot/orders.lua`, `src/bot/megacorp.lua` |
| Lockstep | [lockstep.lua](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/src/net/lockstep.lua): `submit`, `take` |
| Transport | [session.lua](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/src/net/session.lua): `receive`, lobby/start, checksum |
| Replay identities | [replay.lua](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/src/replay.lua), [build.lua](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/src/build.lua) |
| Content validation | [content.lua](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/src/content.lua), [content_validate.lua](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/src/content_validate.lua) |
| Fixture distinction | [fixture_content.lua](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/tests/fixture_content.lua) |
| Map conversion | [tiled.lua](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/src/maps/tiled.lua), [map wrapper](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/scripts/map.ps1) |
| World projection | [camera.lua](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/src/ui/camera.lua), application screen/position helpers |
| Fog memory | [observation.lua](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/src/ui/observation.lua) |
| Sprite contract | [asset_frames.lua](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/src/asset_frames.lua), [sprites.lua](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/src/sprites.lua), [asset_catalog.lua](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/src/asset_catalog.lua) |
| Terrain rendering | [terrain.lua](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/src/ui/terrain.lua) |
| Art production | [pipeline.py](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/tools/blender/pipeline.py), [build.py](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/tools/assets/build.py), [pack.py](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/tools/assets/pack.py) |
| Full verification | [test-all.ps1](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/scripts/test-all.ps1), [runner.lua](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/tests/runner.lua) |
| Performance capture | [test-performance.ps1](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/scripts/test-performance.ps1), [ui_benchmark.lua](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/tests/ui_benchmark.lua) |
| Shipping distribution | [package.ps1](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/scripts/package.ps1) |

<a id="engineering-glossary"></a>

#### Glossary

| Term | Meaning in this project |
|---|---|
| Tick | One 1/20-second authoritative update |
| Cell | Navigation/map unit; 256 subunits |
| Subunit | Integer spatial coordinate unit |
| Command | Validated player intent assigned to a tick and sequence |
| Event | Transient result emitted by simulation for consumers |
| View | Player-filtered projection, read-only by convention |
| Snapshot | Copy used to restore a simulation continuation |
| Checkpoint | Hashable future-state representation at a chosen tick |
| Build fingerprint | Hash over the selected rules/network/map source set |
| Asset build ID | Generated art input/tool identity, distinct from game fingerprint |
| Ground anchor | Sprite origin corresponding to world placement |
| Contact frame | Animation sample aligned to attack impact timing |
| Navigation version | Invalidation identity for changed traversability |
| Shared search | Reused terrain search work, not shared steering or final destination |
| Shipping content | Current Orders/Megacorp definitions |
| Mechanics fixture | Older compact content used to prove retained systems |
| Acceptance gate | A stated measurable requirement, not merely code presence |

This document intentionally preserves unresolved results. Its value as an example
is the connection between rules, code, evidence and failed assumptions, rather than
a claim that every subsystem is finished.

---

<a id="inventory"></a>

## Part II: Game inventory and production setup


Repository and production overview, audited 2026-09-21 (America/Chicago).

For expert implementation analysis, failure studies and improvement experiments, read
the companion [engineering case study](#engineering), audited
2026-09-25 against the same merged game revision. This inventory retains its original
date; local tooling and unmerged work should be rechecked before use.

This document describes the game we have, the hero systems retained underneath it,
and the art and engineering tools around it. It is a snapshot, not a new design brief.
The merged baseline is `4da4c0e` on `master`, simulation version **30**, content version
**16**, using LÖVE **11.5**. Separate work is identified explicitly.

<a id="inventory-contents"></a>

#### Contents

1. [Project identity](#inventory-1-what-the-project-currently-is)
2. [Match structure](#inventory-2-player-experience-and-match-structure)
3. [The Orders](#inventory-3-the-orders)
4. [The Megacorp](#inventory-4-the-megacorp)
5. [Hero foundations](#inventory-5-hero-rts-foundations-retained-in-the-engine)
6. [Controls and interface](#inventory-6-controls-interface-and-feedback)
7. [Simulation and movement](#inventory-7-simulation-movement-and-combat-architecture)
8. [Fog, bots, replay and multiplayer](#inventory-8-fog-bots-replay-and-multiplayer)
9. [Maps and terrain](#inventory-9-maps-and-terrain)
10. [Camera and scale](#inventory-10-camera-and-visual-scale)
11. [Blender production](#inventory-11-blender-to-sprite-production)
12. [Art inventory and equipment](#inventory-12-art-inventory-and-current-footman-work)
13. [Skills and tooling](#inventory-13-reusable-skills-and-local-tooling)
14. [Commands and packaging](#inventory-14-development-commands-and-packaging)
15. [Verification and limits](#inventory-15-verification-status-and-known-limits)
16. [Repository workflow](#inventory-16-repository-ownership-and-how-to-extend-it)
17. [Reading guide](#inventory-17-reading-guide-and-documentation-discrepancies)

<a id="inventory-1-what-the-project-currently-is"></a>

### 1. What the project currently is

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

Primary truth comes from [content](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/src/content.lua), [simulation](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/src/sim/init.lua),
[map registry](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/src/maps.lua), and the actual export/render code. Historical documents
record useful decisions, but do not override those implementations.

<a id="inventory-2-player-experience-and-match-structure"></a>

### 2. Player experience and match structure

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

<a id="inventory-3-the-orders"></a>

### 3. The Orders

The Orders are the conventional worker-and-base faction, visually built around
pointed helmets and hoods, kite shields, cloth panels, ivory masonry, timber, brass
and cathedral roof shapes.

<a id="inventory-roster"></a>

#### Roster

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

<a id="inventory-buildings"></a>

#### Buildings

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

<a id="inventory-4-the-megacorp"></a>

### 4. The Megacorp

The Megacorp has no workers. It uses mobile and stationary relay coverage, resource
rigs, queued orbital buildings and drop pods. Rounded pressure suits, heavy vehicle
forms, pressure-hull aircraft and industrial structures distinguish its art.

<a id="inventory-roster-1"></a>

#### Roster

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

<a id="inventory-economy-buildings-and-delivery"></a>

#### Economy, buildings and delivery

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
research, franchises and livery. Full statistics are in [FACTIONS.md](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/docs/FACTIONS.md).

<a id="inventory-5-hero-rts-foundations-retained-in-the-engine"></a>

### 5. Hero RTS foundations retained in the engine

[The mechanics fixture](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/tests/fixture_content.lua) retains The Bastion and The Wild
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

<a id="inventory-6-controls-interface-and-feedback"></a>

### 6. Controls, interface and feedback

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

<a id="inventory-7-simulation-movement-and-combat-architecture"></a>

### 7. Simulation, movement and combat architecture

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

Useful modules: [movement](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/src/sim/movement.lua), [pathfinding](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/src/sim/path.lua),
[geometry](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/src/sim/geometry.lua), [harvesting](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/src/sim/harvest.lua),
[abilities](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/src/sim/abilities.lua), [vision](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/src/sim/vision.lua),
[coverage](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/src/sim/coverage.lua), [stats](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/src/sim/stats.lua).

<a id="inventory-8-fog-bots-replay-and-multiplayer"></a>

### 8. Fog, bots, replay and multiplayer

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

<a id="inventory-9-maps-and-terrain"></a>

### 9. Maps and terrain

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

See [MAPS.md](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/docs/MAPS.md) for layout tooling. The older
[terrain/camera plan](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/docs/TERRAIN_AND_CAMERA_PLAN.md) contains unimplemented camera and
autotile proposals; its proposed 32-pixel square grid and no-zoom camera are not live.

<a id="inventory-10-camera-and-visual-scale"></a>

### 10. Camera and visual scale

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

<a id="inventory-11-blender-to-sprite-production"></a>

### 11. Blender-to-sprite production

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

See [the pipeline guide](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/tools/blender/README.md) and
[Orders production guide](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/docs/art/ORDERS_CATHEDRAL.md).

<a id="inventory-12-art-inventory-and-current-footman-work"></a>

### 12. Art inventory and current Footman work

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

<a id="inventory-footman-improvement-separate-from-master"></a>

#### Footman improvement, separate from master

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

<a id="inventory-modular-equipment-direction"></a>

#### Modular equipment direction

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

<a id="inventory-13-reusable-skills-and-local-tooling"></a>

### 13. Reusable skills and local tooling

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
is portable and pinned by [toolchain.json](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/toolchain.json), including archive
checksum. Lua code targets that runtime's LuaJIT/Lua 5.1 environment. No global Lua
installation is required. Tiled is the chosen map editor; actual editor installation
and headless export availability need checking on each machine.

<a id="inventory-14-development-commands-and-packaging"></a>

### 14. Development commands and packaging

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

<a id="inventory-15-verification-status-and-known-limits"></a>

### 15. Verification status and known limits

The following are **recorded evidence from the audited implementation**, not tests
rerun for this documentation-only task.

The Orders art handoff records 194 headless checks, four fresh 100,000-tick determinism
runs, same-host networking, rendered UI/presentation suites, 33 Python asset tests and
27 validated catalog entries. Ten saved Blender scenes were reopened across 1,304
poses with zero saved/export pose discrepancy. The 12,000-tick production/combat soak
included restores at 4,000/8,000, 24 replay checkpoints and replacement production.
See [the handoff](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/docs/art/ORDERS_ART_HANDOFF.md) for exact measured revisions.

Earlier control-integration reports have different test/asset counts and timing
results. They describe earlier evidence sets, not contradictions to silently combine.
The merged baseline contains those changes; their reports may still use pre-merge
branch wording.

<a id="inventory-performance-remains-an-open-acceptance-gate"></a>

#### Performance remains an open acceptance gate

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

<a id="inventory-still-unverified-or-unfinished"></a>

#### Still unverified or unfinished

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

<a id="inventory-16-repository-ownership-and-how-to-extend-it"></a>

### 16. Repository ownership and how to extend it

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

<a id="inventory-17-reading-guide-and-documentation-discrepancies"></a>

### 17. Reading guide and documentation discrepancies

| Question | Best source |
|---|---|
| What actually ships? | [content](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/src/content.lua), [maps](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/src/maps.lua) |
| Faction rules and detailed numbers | [FACTIONS](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/docs/FACTIONS.md), checked against content |
| Hero/ability foundations | [fixture content](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/tests/fixture_content.lua), [ABILITIES](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/docs/ABILITIES.md) |
| Map authoring | [MAPS](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/docs/MAPS.md), `tools/tiled`, `src/maps/tiled.lua` |
| Controls and feel | [CONTROL_RESPONSE](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/docs/CONTROL_RESPONSE.md), [GAME_FEEL](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/docs/GAME_FEEL.md), live actions/settings |
| Current art production | [ORDERS_CATHEDRAL](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/docs/art/ORDERS_CATHEDRAL.md), [Blender guide](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/tools/blender/README.md) |
| Latest art evidence | [ORDERS_ART_HANDOFF](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/docs/art/ORDERS_ART_HANDOFF.md) |
| Congestion and practice scenarios | [OVERNIGHT_HANDOFF](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/docs/OVERNIGHT_HANDOFF.md) |
| Performance history | [OVERNIGHT_PERFORMANCE](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/docs/OVERNIGHT_PERFORMANCE.md), later art handoff |
| Historical decisions and progression | [ROADMAP](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/ROADMAP.md), [STATUS](https://github.com/Guidarius/KuyaCraft/blob/1b8ad583aa8afc76e9ee5a80c816927cf2c11665/STATUS.md) |

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
