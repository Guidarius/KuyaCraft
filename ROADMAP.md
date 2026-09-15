# LoveRTS — Development Roadmap

## 1. Vision, boundaries, and working defaults

Build a deterministic, Warcraft-inspired RTS in LÖVE, with compact armies and many asymmetric factions. Most factions revolve around a hero and a focused roster of up to four recruitable combat unit types, plus a worker.

This is the accepted development roadmap. See [STATUS.md](STATUS.md) for implementation evidence and unfinished acceptance gates. A feature existing in source does not mean its milestone has passed.

### Confirmed direction

| Area | Decision |
|---|---|
| Primary experience | PvP skirmishes; offline bot matches provide the first playable version |
| Initial multiplayer | 1v1, starting with two local clients and progressing to LAN/direct-IP |
| Scale | Approximately 20–60 units per player; architecture accommodates 2–4 players |
| Match length | Target 15–25 minutes |
| Victory | Destroy the enemy headquarters, or own every control point on the map for two minutes without a break |
| Map activities | Harvesting, expansion, neutral camps, and attacking enemy bases |
| Economy | Gold and lumber initially; resource design remains replaceable |
| Construction | Workers place grid-snapped buildings anywhere legal |
| Heroes | Start with their ability kits; no inventory or ultimate initially |
| Hero progression | Levels grant meaningful, mutually exclusive upgrades |
| Ability emphasis | Passives and toggles, with active abilities used sparingly |
| Content sequence | One faction in mirror matches, then a mechanically different second faction |
| Presentation | Fixed elevated camera and directional sprites rendered from Blender models |
| Determinism guarantee | Supported Windows PCs running the same pinned game, content, and runtime versions |

### Recommended working defaults

- A **20 Hz simulation**, with independently rendered frames and interpolated movement.
- Flat gameplay terrain, a fixed camera orientation, and eight sprite directions.
- Ground units only for the initial playable version.
- Fog of war and explored terrain, with visibility calculated by the simulation.
- One headquarters per player. Its destruction ends that player's participation; simultaneous destruction in 1v1 produces a draw.
- A hero starts with its army and can be revived at the headquarters after a resource cost and tick-based delay. Upgrades persist through death.
- Three hero upgrade milestones, each offering two mutually exclusive choices. No mid-match respec initially.
- Fixed maps and scripted neutral camps before procedural maps or a map editor.
- A fixed population cap initially; supply-building management can be evaluated later.

The first release target is a private playable prototype. Ranked matchmaking, public accounts, campaigns, spectators, reconnects, mod downloads, and a large faction catalog belong after the core game works.

**Small rosters simplify content and controls. They do not remove the difficult engineering work in movement, pathfinding, multiplayer, and verification.** Those systems receive early milestones.

## 2. Install, run, and test LÖVE

### Workspace and installation

The workspace began empty, with Git available and no LÖVE executable found on PATH or in the standard Windows installation folders. The implementation uses a project-local portable runtime, avoiding a global installation.

Use the official Windows 64-bit LÖVE **11.5** distribution. Pin the actual runtime archive used for development and releases. [Official downloads](https://www.love2d.org/?page=download)

From PowerShell in the repository:

```powershell
.\scripts\setup.ps1
.\scripts\run.ps1 -Smoke
.\scripts\run.ps1
.\scripts\test.ps1
```

The setup wrapper verifies the archive checksum recorded in toolchain.json. The runtime resides under the ignored .tools directory. A standard installation can instead be checked with:

```powershell
& "C:\Program Files\LOVE\love.exe" --version
```

Use a Lua-capable editor configured for LuaJIT/Lua 5.1. A separate Lua installation is unnecessary for the initial game and test workflow.

### First smoke test

A minimal LÖVE game consists of main.lua in its root:

```lua
function love.load()
    print("LoveRTS smoke test started")
end

function love.draw()
    love.graphics.print("LoveRTS is running", 40, 40)
end

function love.keypressed(key)
    if key == "escape" then
        love.event.quit()
    end
end
```

Launch the directory using the console executable:

```powershell
& "C:\Program Files\LOVE\lovec.exe" "D:\LoveRTS"
```

Success means a window displays the message, the terminal displays startup output, Escape closes the application, and editing the text then restarting displays the change.

LÖVE runs a directory containing main.lua or a .love archive with main.lua at its root. During development, run the directory directly; ordinary Lua changes require no separate native compilation. [Getting started](https://love2d.org/wiki/Getting_Started)

Use conf.lua for title, window dimensions, save identity, and module configuration. It runs before module initialization. Disable the physics module because authoritative movement uses project-owned rules. [Configuration](https://www.love2d.org/wiki/conf.lua)

### Testing interfaces

The project wrappers provide:

```powershell
.\scripts\run.ps1
.\scripts\test.ps1
.\scripts\test.ps1 -Suite determinism
.\scripts\replay.ps1 -ReplayPath ".\artifacts\sample.replay"
.\scripts\test.ps1 -Suite network
```

These are project scripts, not built-in LÖVE commands. Each must locate the pinned runtime, report missing dependencies clearly, preserve exit codes, and store generated output under the ignored artifacts directory.

| Layer | Purpose | Execution |
|---|---|---|
| Simulation | Validate rules, movement, combat, resources, upgrades | Same LÖVE runtime, graphics/window/audio disabled |
| Replay and networking | Verify identical state from identical commands | Separate processes, recorded fixtures, controlled packet schedules |
| Presentation | Check selection, camera, animation, UI, readability | Windowed scenarios and screenshots |

Use a small assertion runner under the same runtime as the game. Simulation modules remain independent of LÖVE APIs even though LÖVE hosts the runner.

Automated runs print a summary and exit. Failed assertions and uncaught errors return nonzero status rather than waiting at an interactive error screen. [Exit-status documentation](https://love2d.org/wiki/love.event.quit)

| Symptom | Check |
|---|---|
| Command not found | Full executable path or PATH |
| No game screen | Supplied folder directly contains main.lua |
| Missing output | lovec.exe or console configuration |
| Lua syntax/library mismatch | Pinned runtime; avoid assuming Lua 5.4 |
| Tests remain open | Runner exits on success and failure |
| Unexpected save/log location | Print and document LÖVE save and project artifact paths |

A working window and a validated simulation are separate acceptance gates.

## 3. Simulation and multiplayer architecture

### Boundaries and interfaces

Use ordinary Lua modules, explicit systems, and entity records indexed by stable IDs. Do not build a general-purpose ECS framework first.

| Subsystem | Responsibility |
|---|---|
| Simulation | All authoritative state and rules |
| Content | Factions, units, buildings, abilities, upgrades, maps |
| Command layer | Common entry for human, bot, replay, network orders |
| Presentation | Drawing, animation, sound, camera, selection, UI |
| Networking | Connections, command delivery, frame completion, diagnostics |
| Tooling | Tests, replay inspection, profiling, asset export, packaging |

```lua
world = Sim.create(matchConfig, content, map)
events = Sim.step(world, commandsForTick)
snapshot = Sim.snapshot(world)
world = Sim.restore(snapshot)
bytes = Sim.serializeCanonical(world)
```

Sim.step advances one tick, with no frame delta argument. Commands carry execution tick, player ID, sequence, kind, and arguments. Targets use entity IDs and positions use simulation coordinates.

Initial commands cover move, attack, attack-move, stop, harvest, build, recruit, toggle, upgrade, and revive. The renderer reads state and events; it cannot change gameplay.

### Determinism contract

Identical configuration, content, map, seed, and ordered commands must yield identical authoritative state at every tick.

- Fixed-point positions: **256 subunits per navigation cell**.
- Time is ticks; authoritative quantities are integers.
- Centralized arithmetic, explicit rounding, bounded exact intermediate values.
- No platform-dependent transcendental calculations in movement or targeting.
- Project-owned, versioned PRNG with golden vectors: Park–Miller, multiplier 16807, modulus 2147483647.
- Separate cosmetic randomness.
- Stable ordering for entities, commands, candidates, and events.
- No dependence on unordered table traversal, memory addresses, wall clock, filesystem order, or thread completion.
- Tick or operation-count budgets for gameplay work.
- Physics, animation callbacks, and asynchronous loading remain outside gameplay.

Lua table traversal order is unspecified; sparse table length is not an entity count. Use dense arrays, explicit counts, or sorted keys. [Lua manual](https://www.lua.org/manual/5.1/manual.html)

A fixed timestep and shared seed alone are insufficient.

### Tick order

1. Validate and apply commands.
2. Resolve combat intent, order priority, and movement interruption.
3. Timers, harvesting, construction, production.
4. Scheduled pathfinding and local movement.
5. Visibility, order completion, passive modifiers and committed combat effects.
6. Effects, deaths, experience, progression, and death-related visibility refresh.
7. Victory, presentation events, tick completion.

Use effect queues rather than recursive callbacks. Generate due attacks before finalizing deaths, supporting simultaneous combat outcomes.

Limit work per rendered frame while retaining backlog. Never discard authoritative ticks. Multiplayer waits for missing required commands.

### Movement and construction

- Square navigation grid; eight-way A* with integer costs and no diagonal corner cutting.
- Fixed neighbor order and explicit tie-breaking.
- Incremental searches with fixed expansion budgets.
- Stable request queue; snapshot all future-affecting search state.
- Buildings block from the start of construction.
- Validate terrain, visibility, occupancy, affordability, and bounds.
- Deterministic group destinations and local movement conflict resolution.
- Body radii (80 ordinary / 112 heavy subunits), bounded allied compression, and explicit Hold behavior.
- Heap-based incremental A* plus a separately bounded direct-route probe for immediate clear-terrain movement.

See [the implemented control and movement rules](docs/CONTROL_MOVEMENT.md) for attack cancellation, crowd recovery, cache settings, and verification evidence.

Units occupy subcell positions. Test chokepoints early, including crowds and new buildings. Failed destinations require bounded retries and a clear blocked/idle result.

Defer flow fields, multithreading, elaborate formations, and physics-based navigation until measurements justify them.

### Economy and content

Use a resource ledger keyed by resource ID. Gold/lumber are definitions, not assumptions scattered across systems.

Include nodes, worker assignments, carrying, delivery, depletion, construction, recruitment queues, and explicit cancellation refunds.

Factions reference shared definitions by stable IDs. Resolve variants before a match and never mutate shared content at runtime.

Begin with damage, healing, stat modifiers, auras, toggles, and timed effects. Exceptional mechanics use focused modules; avoid a universal ability language before two factions demonstrate the requirements.

### Heroes and visibility

Heroes begin with complete base kits. Upgrade milestones each offer two alternatives, permit one permanent choice, remain pending until chosen, are validated in simulation, and are recorded as commands.

Experience comes from nearby hostile combat deaths, including neutrals, excluding friendly kills and building destruction. Range, thresholds, revival cost, and delay live in data.

Visibility controls targeting and bot perception. Provide filtered player views. Hidden enemy activity must not leak through the renderer.

### Replays and desync diagnostics

Record initial configuration and finalized commands, including bot commands.

Headers identify game/simulation/runtime versions, map/content hashes, seed, players, and replay format. Start with strict same-version compatibility and clear mismatch rejection.

Canonical state includes PRNG, ID allocation, pending effects, queues, paths, and scheduler progress. Exclude presentation state.

Compare SHA-256 hashes in tests and periodic multiplayer checks. Preserve divergent states, first divergent tick, nearby commands, and subsystem differences.

Snapshot restoration must produce an identical continuation. Initially this supports tests and diagnostics; player-facing saves are later.

### Multiplayer

Use host-coordinated deterministic lockstep over bundled ENet. ENet supplies reliable ordered packets, not the command protocol. [ENet documentation](https://love2d.org/wiki/lua-enet)

- Every client runs the same simulation.
- Commands target future ticks, with configurable three-tick input delay initially.
- Host finalizes ordered batches.
- Players complete each contribution explicitly, including empty batches.
- Advance only with complete frames.
- Order by tick, player, sequence.
- Verify versions, content, map, and configuration at startup.
- Handle malformed, unauthorized, duplicate, and stale commands consistently.
- Missing peers cause visible waiting; disconnect ends the initial match.
- Defer rollback, host migration, reconnect, and mid-match join.

Prove two local processes, then two Windows PCs and direct-IP play. Direct connection does not supply NAT traversal. Public lobbies/relays are later. Full-state lockstep exposes world state to modified clients; competitive public infrastructure needs separate design work.

## 4. Content, Blender assets, and AI development

### Provisional factions

These are replaceable test fixtures, not final themes or balance.

| | The Bastion | The Wild Pact |
|---|---|---|
| Identity | Cohesion, protection, sustained engagements | Mobility, recovery, raiding |
| Hero | Warden | Beastkeeper |
| Base kit | Defensive aura; offensive/defensive stances | Recovery passive; pursuit/regroup stances |
| Roster | Shield infantry, crossbow, support, siege | Fast melee, skirmisher, support creature, heavy beast |
| Worker | Shared economy initially | Shared economy initially |
| Distinction | Stay together around the hero | Disengage and choose a new engagement |
| Tension | Vulnerable to splitting and raids | Weaker sustained frontal combat |

Warden example: wider protection radius versus stronger protection in a smaller radius.
Beastkeeper example: faster out-of-combat recovery versus brief movement benefit on entering combat.

Start the first faction with two combat types, a hero, and a worker. Expand toward four when each type adds a strategic role. Keep early economic mechanics shared while combat and heroes prove asymmetry.

### Blender-to-sprite production

Blender is an offline authoring tool. The game consumes sprites and metadata.

1. Simple model with a strong silhouette.
2. Reusable rig.
3. Idle, movement, attack, death.
4. Eight directions through a fixed orthographic camera.
5. Transparent output with stable ground origin.
6. Atlas packing.
7. Animation and anchor metadata.
8. In-game battlefield inspection.

The finalized [asset pipeline specification](docs/ASSET_PIPELINE_PLAN.md) extends the existing shieldguard proof using the supplied 65-bone rig and animation library. Preserve the source skeleton and generate stump-handed unit meshes around it. Lock camera, lighting, scale, color management, and render settings in a reusable scene. The revised target is approximately 32-pixel-tall ordinary bodies inside 64×64 delivery cells, rendered at twice delivery resolution; larger cells retain the same world scale. These are planned production settings, not a claim that the existing 128×128 proof has migrated.

Export frame rectangles, source size, trim offsets, ground anchor, timing, loop behavior, and team-mask references. Keep masks aligned. Start with simple runtime ground shadows.

Use checked-in Python scripts and a command wrapper for repeatable background exports. Load the scene before applying overrides and rendering. [Blender CLI](https://docs.blender.org/manual/en/5.1/advanced/command_line/arguments.html)

### Runtime presentation

Provide atlas animation, eight directions, anchors, stable depth sorting, mask-based team colors, interpolation, selection rings, health bars, shadows, fog, and shared camera/world conversion.

Simulation timing determines damage; animation displays the phase. Missing frames never change outcomes.

Keep buildings compact; no bridges or overhangs initially. Split render layers for tall assets rather than changing collision rules.

### MCP decision

A LÖVE MCP is optional. No suitable runtime server was verified during planning. Terminal commands, structured output, replay fixtures, dumps, and screenshots provide the initial automation interface. Add an MCP wrapper only if it improves iteration.

Blender MCP tools are available in this session, but their connection was not verified during planning. Use them for interactive authoring if connected; retain production logic in source-controlled scripts. Do not build a custom Blender add-on or sprite editor before integrating a complete unit.

### AI-assisted rules

Each task needs a concrete behavior, acceptance criteria, affected boundary, reproducible scenario, required tests/artifacts, and scope limits.

Repository instructions require deterministic ordering and replay checks for simulation changes. AI can implement, test, inspect logs, generate placeholders, and script Blender. Humans judge readability, feel, strategy, and interesting choices.

Never update a golden replay solely to silence a failure. Explain the intended rule change, inspect divergence, then regenerate.

## 5. Milestones, acceptance gates, and delivery

Use evidence-based gates rather than calendar promises. Measure actual velocity after the first two milestones.

| Milestone | Deliverable | Acceptance gate |
|---|---|---|
| 0. Toolchain | Pinned runtime, Git, launch script, window, runner | Clean setup launches; passing/failing tests return correct codes |
| 1. Kernel | Tick loop, integer helpers, PRNG, IDs, commands, snapshots, serialization | Separate processes agree over 100,000 ticks; restored continuation agrees |
| 2. Movement/network proof | Selection, A*, obstacles, two-client exchange | Congestion behavior; matching state under different render schedules and delayed packets |
| 3. Mirror match | Workers, resources, building, recruitment, combat, hero kit, bot, victory | Complete match reproducible from replay |
| 4. Match loop | Fog, camps, XP, upgrades, revival, attack-move, groups, minimap | Progression/map activity without hidden-state targeting or divergence |
| 5. Art pipeline | Animated unit, exporter, colors, anchors, playback | Scripted regeneration and readable directions; gameplay unchanged |
| 6. Second faction | Contrasting hero/roster, definitions, validation | Shared systems support different play patterns |
| 7. Private alpha | LAN/direct-IP, compatibility, failure UI, diagnostics, Windows package | Two PCs complete repeated matches with matching hashes |
| 8. Expansion | Four-player scenarios, performance, bots, second map, authoring checklist | New content without unrelated core edits; target-scale performance |

The single-unit art experiment can follow movement. Full roster art waits for a reliable mirror match and settled camera/scale.

### Required verification

**Determinism:** fresh processes; 30/60/144 FPS schedules; headless and effects-disabled replay; different supported Windows PCs; different insertion histories; PRNG vectors; arithmetic boundaries; serialization; snapshots during combat/construction/searches; changed-command divergence.

**Movement/economy:** opposing crowds in narrow gaps; shared destinations; buildings on routes; unreachable/occupied destinations; competing workers; depletion/cancellation/blocked exits; bounded retries and memory.

**Combat/heroes:** simultaneous kills/HQ destruction; target death during windup; vision/aura boundaries; multiple unspent levels; duplicate/conflicting choices; revival retention; camp aggression/leash/reset; toggles across death and cooldowns.

**Networking:** empty frames; delay/jitter/loss/duplication/reordering; slow clients; missing input; compatibility mismatch; unauthorized/malformed commands; disconnect at startup and during play; post-match replay agreement.

**Presentation:** selection/placement at multiple zooms; direction changes; anchored feet; team colors; building overlap; fog-respecting UI/effects; diagnostic placeholders for missing assets.

### Performance

Record a reference Windows PC. Initial budgets:

- 60 FPS presentation at 1080p.
- 20 Hz simulation without growing backlog.
- Stress scenario: 240 player-owned mobile units plus buildings/neutrals.
- Simulation tick below 10 ms at the 95th percentile on the reference machine.
- Bounded pathfinding and stable memory over long replays.

Measure simulation, path expansions, rendering, allocations, and network waits separately.

### Packaging and maintenance

Package the pinned runtime and dependencies. Test outside the development directory. Put main.lua at the archive root.

Expose build version and artifact locations. Preserve bug fixtures.

Before broad faction expansion require a reliable match, repeatable sprites, stable deterministic regressions, two distinct factions, and a content checklist for rules, bots, art, and performance.

**First task:** pin LÖVE, launch the smoke test, and prove passing/failing automated exits.
**Next task:** deterministic kernel before substantial gameplay or asset production.


## Playable balance profile

The Warcraft-inspired scale, economy, tech, unit statistics and pacing specification is [docs/BALANCE_AND_PACING.md](docs/BALANCE_AND_PACING.md). It supersedes the initial prototype balance numbers; see STATUS.md for measured gates and remaining playtest work.
