# LoveRTS engineering case study

Expert developer and AI analysis guide, source audit dated 2026-09-25.

This case study analyzes merged game revision `4da4c0e` (simulation 30, content 16,
LÖVE 11.5). Its companion [current setup inventory](CURRENT_GAME_SETUP.md) records
the playable content and authoring environment. This documentation branch includes
that earlier overview; it does not integrate the separate Footman or mouse studies.

## Abstract

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

## Reading paths

- **First-time developer:** sections 1–5, then the subsystem relevant to the task.
- **Simulation/network reviewer:** sections 5–11 and 17–19.
- **Rendering/tools engineer:** sections 12–16 and the companion inventory.
- **AI improvement agent:** sections 1, 17–21 before proposing or editing anything.
- **Producer/designer:** companion [CURRENT_GAME_SETUP.md](CURRENT_GAME_SETUP.md),
  then the evidence and experiment sections here.

### Contents

1. [Scope and provenance](#1-scope-and-provenance)
2. [The implemented game as a workload](#2-the-implemented-game-as-a-workload)
3. [Repository and dependency map](#3-repository-and-dependency-map)
4. [Why this is a LÖVE implementation](#4-why-this-is-a-löve-implementation)
5. [Time, commands and the live frame](#5-time-commands-and-the-live-frame)
6. [State model and numeric determinism](#6-state-model-and-numeric-determinism)
7. [Tick ordering and gameplay resolution](#7-tick-ordering-and-gameplay-resolution)
8. [Navigation and crowd movement](#8-navigation-and-crowd-movement)
9. [Visibility, views and information boundaries](#9-visibility-views-and-information-boundaries)
10. [Replay and compatibility](#10-replay-and-compatibility)
11. [Private multiplayer](#11-private-multiplayer)
12. [Rendering, camera and animation](#12-rendering-camera-and-animation)
13. [Content and map authoring](#13-content-and-map-authoring)
14. [Blender and asset publication](#14-blender-and-asset-publication)
15. [Controls, audio and usability](#15-controls-audio-and-usability)
16. [Packaging and reproducibility](#16-packaging-and-reproducibility)
17. [Test strategy and evidence](#17-test-strategy-and-evidence)
18. [Failure studies and engineering lessons](#18-failure-studies-and-engineering-lessons)
19. [Prioritized improvement experiments](#19-prioritized-improvement-experiments)
20. [Developer and AI handoff protocol](#20-developer-and-ai-handoff-protocol)
21. [Source index and glossary](#21-source-index-and-glossary)

## 1. Scope and provenance

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

The source files linked below describe implementation. [STATUS.md](../STATUS.md),
[CONTROL_RESPONSE.md](CONTROL_RESPONSE.md), [OVERNIGHT_HANDOFF.md](OVERNIGHT_HANDOFF.md)
and [ORDERS_ART_HANDOFF.md](art/ORDERS_ART_HANDOFF.md) describe earlier measurements.
Those reports do not become fresh measurements simply because this document quotes
them. Raw screenshots, logs, blends, runtimes and catalogs may be absent in a clone.

There are three different identities worth preserving in every experiment:

1. **Rules identity:** source/content/map/runtime compatibility used by replay/network.
2. **Presentation identity:** asset catalog/build IDs, renderer settings and display.
3. **Measurement identity:** machine, process, scenario, warmup, instrumentation and
   output reports. Equivalent rules do not imply equivalent frame time or pixels.

## 2. The implemented game as a workload

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

## 3. Repository and dependency map

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

## 4. Why this is a LÖVE implementation

LÖVE is the host, not the owner of game truth. [conf.lua](../conf.lua) disables physics,
joystick, video and touch. Test/network-worker modes also disable window, graphics,
audio and sound. This lets the same runtime host deterministic headless tests without
requiring a separate Lua interpreter or a window.

[main.lua](../main.lua) selects the shell, match fixtures, viewers, benchmarks or
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

## 5. Time, commands and the live frame

### 5.1 Three clocks

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

### 5.2 Command envelope

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

### 5.3 One order traced end to end

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

### 5.4 Whole-tick cost

The live loop measures step, view, event filtering, feedback and replay portions.
It also performs selection pruning, hover refresh, alert/audio observation and
interpolation bookkeeping. Optimizing `Sim.step` alone can leave the rendered game
over budget because these surrounding costs remain.

The offline bot is queried on a 20-tick cadence in the normal application loop, using
a filtered view for player 2. Benchmark fixtures can replace its commands while
retaining the surrounding live update path; that does not measure bot decision cost.

## 6. State model and numeric determinism

### 6.1 World schema

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

### 6.2 Integer arithmetic over Lua numbers

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

### 6.3 Canonical primitive codec

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

### 6.4 Ordering is a semantic contract

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

## 7. Tick ordering and gameplay resolution

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

## 8. Navigation and crowd movement

### 8.1 Terrain route planning

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

### 8.2 Shared pending searches

Nearby group members may share terrain search work only when owner, group, radius,
lane direction and navigation version agree. Start/destination proximity is bounded.
A follower does not blindly reuse its leader's final movement: it gets validated
connectors, a copied waypoint chain, its own destination and local avoidance.

Leader cancellation/death or terrain version changes trigger deterministic promotion
or revalidation. Detours caused by local congestion remain independent. Heavy-unit
waypoints retain radius-specific offsets (`px/py`); reducing them to cell centers
can make an apparently valid shared path cut through terrain.

### 8.3 Local movement

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

### 8.4 Limits and research directions

Opposing dense heavy traffic can jam. Full-radius opposing Enforcers cannot pass
side by side in two cells: required width is 640 subunits versus 512 available.
Even a geometrically sufficient corridor does not prove local steering converges.

This implementation is not hierarchical navigation, a flow-field solver or a formal
multi-agent pathfinding solution. Those are possible alternatives, not drop-in fixes.
Compare them with replayable workloads, different radii, terrain invalidation,
ownership, and deterministic CPU budgets before replacing existing behavior.

## 9. Visibility, views and information boundaries

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

## 10. Replay and compatibility

### 10.1 Three state representations

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

### 10.2 Recording format

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

### 10.3 Diagnostic workflow

Preserve the failing command stream, both peers' identities and the earliest retained
divergent checkpoint. Compare state paths with `scripts/compare-states.ps1`. Reproduce
from an earlier snapshot and narrow the interval. Do not simply update a golden hash
or assume a matching final winner means the match remained deterministic.

## 11. Private multiplayer

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

## 12. Rendering, camera and animation

### 12.1 Coordinate chain

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

### 12.2 Frame selection

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

### 12.3 Draw cost and correctness

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

## 13. Content and map authoring

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

## 14. Blender and asset publication

### 14.1 Reproducible source instead of opaque exports

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

### 14.2 Publication as a transaction

Build identity depends on inputs/tools. Generated asset directories are retained by
build ID. Preview is unpublished. Build merges requested entries with existing
catalog entries, validates the result, then atomically replaces the Lua catalog
commit point. Failed generation must preserve the previous usable publication.

This guards against partial roster publication and mismatched worker cargo variants.
It does not guarantee byte-identical renders on every GPU/Blender release. Build
identity and environment reports support diagnosis; pixel reproducibility needs
its own evidence.

### 14.3 Variant design and art evidence

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

## 15. Controls, audio and usability

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

## 16. Packaging and reproducibility

### 16.1 Clean-checkout requirements

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

### 16.2 Shareable Windows build

Packaging produces a folder containing the fused game executable and LÖVE DLLs,
plus test/review helpers where configured. Keep the files together. Users do not
need Blender to play exported sprites. Package tests should exercise that exact
package and asset manifest; a passing source checkout does not prove an archive
contains the intended assets.

Replays first target project artifacts and can fall back to the user's LÖVE save
directory. In restricted test environments this fallback may be unwritable too.
Record the actual path and access conditions rather than treating an environment
failure as a combat regression.

### 16.3 Source synchronization

Task branches/worktrees isolate changes; source is pushed via GitHub. Generated data
is recreated or delivered separately with identity manifests. Golden changes and
simulation/content version updates are reviewed explicitly. The current document
includes the previous overview commit but does not merge art branches into master.

## 17. Test strategy and evidence

### 17.1 Coverage matrix

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

### 17.2 Historical evidence ledger

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

### 17.3 Performance numbers and their meaning

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

### 17.4 Reproduce a candidate honestly

```powershell
./scripts/test-performance.ps1 -Runs 3 -LiveRuns 3 -RequireAssets `
  -OutputDirectory artifacts/case-study/baseline
```

Run baseline and candidate sequentially without Blender or competing tests. Preserve
source/catalog hashes, CPU/GPU, settings, resolution, VSync, sample counts, cold/warm
state and process identity. Compare distributions and canonical checkpoints. Use
profiling to choose a target, then uninstrumented runs for acceptance. Explicitly
report clamped time/discarded backlog and failures instead of changing budgets.

### 17.5 Checks performed for this documentation audit

On 2026-09-25, the pinned local LÖVE 11.5 runtime executed the **unit suite against
the isolated case-study checkout: 28 passed, 0 failed**. That checkout has no copied
production catalog; runtime contract tests are not a fresh production asset validation.
Source inspection checked symbols, key constants, wrappers and branch provenance.
Documentation validation checks local links, headings and whitespace.

No full determinism, LAN, rendered, Blender export, performance or package suite was
rerun for this documentation task. Historical evidence remains historical. Human
playtesting and a second machine remain unperformed here.

## 18. Failure studies and engineering lessons

### A. Correct paths, unacceptable start delay

**Recorded problem:** independently routing a large selection around a wall made
first displacement unacceptably late. **Change:** shared pending terrain searches,
an active deterministic schedule and cheaper destination reservation work.
**Lesson:** path existence and total throughput do not describe RTS responsiveness.
Track percentiles of click-to-displacement, including the last units in the group.
**Limit:** the synthetic regression is not an all-map latency bound.

### B. A visual scale change invalidated a movement claim

**Recorded problem:** the larger Enforcer no longer fit assumptions used by an older
two-cell counterflow test. Shared waypoints/connectors also needed actual radius-aware
positions. **Change:** preserve vehicle offsets, verify connector origins and separate
infantry arrival from heavy recovery tests. **Lesson:** content radius is part of the
navigation contract. Never make a failed geometry test pass by quietly shrinking the
body or calling an assisted recovery an autonomous solution.

### C. Optional quality work blocked required correctness

**Recorded problem:** an exhausted smoothing budget could reject necessary vehicle
clearance work. **Change:** mandatory clearance remains valid under its appropriate
bounded work; optional smoothing may stop without invalidating a valid remainder.
**Lesson:** budget quality improvements separately from safety checks. “Budgeted” is
not sufficient if running out changes validity incorrectly.

### D. Explicit garrison orders fought automatic combat behavior

**Recorded problem:** an Enforcer alternated between entering a bunker and pursuing
an enemy. **Change:** garrison suppresses fresh automatic acquisition en route, like
other explicit noncombat orders. **Lesson:** acquisition policy is an order-state
machine issue, not merely a better pathfinding problem. Test mixed pod/choke/garrison
sequences, not just isolated garrison entry.

### E. Headless green did not cover frame-loop regressions

**Recorded problem:** backlog behavior changed while headless tests stayed green.
**Change:** the combined wrapper runs rendered/input suites too. **Lesson:** tests
must execute the code path being claimed. Correct `Sim.step` does not validate
`App:update`, which chooses when and with which commands it is called.

### F. Valid art disappeared through render-state leakage

**Recorded problem:** a terrain-bake viewport/scissor error obscured building roofs.
**Change:** refresh the scissor and add an actual roof-pixel gameplay check.
**Lesson:** successful asset export and atlas loading do not prove correct compositing
inside a warmed, cached gameplay scene.

### G. Plausible optimizations failed measurement

**Recorded result:** visibility/coverage optimization candidates were reverted after
inconsistent or adverse timings. **Lesson:** removing theoretically redundant work
can increase allocation or worsen JIT/cache behavior. Preserve failed experiments
as reports, not production complexity. A hypothesis is useful even when rejected.

### H. A technically valid Footman was visually unclear

**Observed in separate art work:** shield face projection and thin sword orientation
made equipment hard to read from above. All the relevant structural checks could
pass. **Lesson:** inspect at native pixels, across headings and motion, with the same
camera/scale. Art fixes should address pose and silhouette before arbitrary enlargement.
**Limit:** the revised equipment remains on an unmerged branch and needs human motion
acceptance; do not attribute it to audited master.

## 19. Prioritized improvement experiments

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

### 19.1 Performance experiment template

State the hypothesis in measurable terms, for example: “Repeated view construction
accounts for enough live tick time that eliminating specific copies lowers p95 without
sharing mutable authoritative tables.” Capture allocation counts and time at that
boundary first. Prove equal view membership/privacy and identical simulation hashes,
then compare fresh processes at the same asset identity. Reject the change if it
improves a microbenchmark but worsens live frames or complexity without a real gain.

Do not optimize by disabling fog, recording, effects, large bodies or production art
unless those are diagnostic runs explicitly excluded from acceptance.

### 19.2 Historical state experiment

Count alive/dead entities, ordered-ID length, searches, recording frames, checkpoint
bytes and retained heap at fixed intervals through repeated production/death cycles.
Measure whole-world iteration separately from recording retention. Only then choose
compaction, a live-ID index or serialization changes. Preserve stable IDs, corpse
presentation, last-seen knowledge and replay equivalence. New indexes are derived
state only if reconstruction and scheduling effects are actually proven.

### 19.3 Multiplayer hardening experiment

Use two PCs and record identities before measuring latency. Test missing/late/duplicate
batches, connection loss, malformed payloads, oversized/far-future frame claims and
readiness transitions. Bound retention independently of honest-peer behavior.
Separate protocol robustness from anti-cheat: complete-world lockstep remains an
information disclosure model even if every packet validator is correct.

### 19.4 Hero integration experiment

Pick one shipping faction and one hero role. Decide how its cost, starting timing,
revival, XP acquisition and upgrades interact with current supply/economy and HQ
defeat. Implement one complete match loop, including bot use and replay. Do not
reactivate the old fixture wholesale: its compact test values and old rosters are
not a balance specification for the new game.

### 19.5 Art pipeline experiment

One sword/shield variant should establish the item pivot, hand attachment, compatible
pose family, color/mask contract and all-pose bounds. Export full units and compare
at matched scale. Only after that should an item library generalize across bodies.
For terrain, begin with adjacent repeatable tiles and a small runtime map; atlas
gutters cannot repair incompatible edge geometry or shading.

## 20. Developer and AI handoff protocol

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

### Questions an expert review should answer

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

## 21. Source index and glossary

### Implementation entry points

| Question | File and symbols to start with |
|---|---|
| Lifecycle/modes | [main.lua](../main.lua), [conf.lua](../conf.lua) |
| Time and command delivery | [app.lua](../src/app.lua): `command`, `update`, `interpolated`, `seek` |
| Core rules | [sim/init.lua](../src/sim/init.lua): `create`, `step`, command `apply`, combat/economy |
| State boundary | Same file: `snapshot`, `restore`, both serializers, `view`, `eventsFor` |
| Arithmetic | [fixed.lua](../src/sim/fixed.lua): `mulDiv`, `isqrt`, `vector` |
| Stable encoding | [codec.lua](../src/sim/codec.lua): `keys`, `encode`, `decode`, `copy` |
| Search scheduling | [path.lua](../src/sim/path.lua): `request`, follower connectors, `step` |
| Crowd steering | [movement.lua](../src/sim/movement.lua): `step`, proposals, yield/push policies |
| Clearance | [geometry.lua](../src/sim/geometry.lua): `terrain`, `separation`, `free` |
| Sight/territory | [vision.lua](../src/sim/vision.lua), [coverage.lua](../src/sim/coverage.lua) |
| Ability rules | [abilities.lua](../src/sim/abilities.lua), [projectiles.lua](../src/sim/projectiles.lua), [stats.lua](../src/sim/stats.lua) |
| Bot dispatch | [bot.lua](../src/bot.lua), `src/bot/orders.lua`, `src/bot/megacorp.lua` |
| Lockstep | [lockstep.lua](../src/net/lockstep.lua): `submit`, `take` |
| Transport | [session.lua](../src/net/session.lua): `receive`, lobby/start, checksum |
| Replay identities | [replay.lua](../src/replay.lua), [build.lua](../src/build.lua) |
| Content validation | [content.lua](../src/content.lua), [content_validate.lua](../src/content_validate.lua) |
| Fixture distinction | [fixture_content.lua](../tests/fixture_content.lua) |
| Map conversion | [tiled.lua](../src/maps/tiled.lua), [map wrapper](../scripts/map.ps1) |
| World projection | [camera.lua](../src/ui/camera.lua), application screen/position helpers |
| Fog memory | [observation.lua](../src/ui/observation.lua) |
| Sprite contract | [asset_frames.lua](../src/asset_frames.lua), [sprites.lua](../src/sprites.lua), [asset_catalog.lua](../src/asset_catalog.lua) |
| Terrain rendering | [terrain.lua](../src/ui/terrain.lua) |
| Art production | [pipeline.py](../tools/blender/pipeline.py), [build.py](../tools/assets/build.py), [pack.py](../tools/assets/pack.py) |
| Full verification | [test-all.ps1](../scripts/test-all.ps1), [runner.lua](../tests/runner.lua) |
| Performance capture | [test-performance.ps1](../scripts/test-performance.ps1), [ui_benchmark.lua](../tests/ui_benchmark.lua) |
| Shipping distribution | [package.ps1](../scripts/package.ps1) |

### Glossary

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
