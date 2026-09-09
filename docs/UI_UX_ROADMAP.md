# LoveRTS — UI, Minimap, and Game Feel

Implementation record for the accepted UI/UX roadmap. Updated 2026-09-09. See [STATUS.md](../STATUS.md) for measured results and gates that still require human or cross-machine review.

## Experience and boundaries

The interface answers: what is selected, what it can do, whether an order registered, what needs attention, and what is happening elsewhere. It uses slate panels, brass outlines, geometric command symbols, compact hero portraits, and faction accents. The bottom dock is 180 logical pixels at 100% scale. Settings support 80–125%; layout supports 1280×720, 1080p and ultrawide.

All gameplay still runs through integer-tick Sim.step at 20 Hz. Cursor pulses and sound acknowledge local input without spending resources or moving units early. No hit-stop, routine camera shake, inventory, ultimate slots, or voice assets were added.

The original sprites remain compatible. Procedural portraits/icons and synthesized nonverbal audio are intentionally modest first-pass assets. Their artistic quality requires playtesting.

## Application flow

| Screen | Implemented behavior |
|---|---|
| Main | Skirmish, Multiplayer, Replays, Settings, Quit |
| Skirmish | Two maps with terrain preview, player/bot faction selection, faction description, Start |
| Private lobby | Editable host:port, host/join, compatibility feedback, faction selection, explicit readiness, host Start |
| Match | Resource strip, hero dock, selection tiles, production/cancellation, command card, minimap, alerts |
| Match menu | Resume, Settings, Save Replay, explicit Leave Match |
| Results | Outcome, duration, surviving/dead owned units, remaining resources, replay save, return to setup |
| Replays | File browser, strict compatibility errors, pause, 0.5–4x playback, timeline, ±10-second controls, perspective |

Escape cancels targeting/placement, closes a panel, then opens the match menu. Offline menus pause and clear time accumulation. Multiplayer menus say **Match continues** and keep polling/advancing the session. Upgrades do not pause the match.

Connection compatibility, lobby readiness and gameplay start are separate. Changing a faction invalidates readiness. Both clients receive the finalized faction configuration before host start. Command-line host/join launch the same lobby; automated transport workers retain their explicit test handshake.

No public services, NAT traversal, reconnect or host migration were added.

## Controls and action discovery

| Input | Action |
|---|---|
| Left click / drag | Select / box-select |
| Shift selection | Add or remove units |
| Double click | Visible friendly units of the same type within the battlefield |
| Right click | Move, attack visible enemy, harvest or resume construction |
| A then left click | Attack-move, including minimap |
| S | Stop and clear orders |
| Shift order | Append a task; maximum 32 pending tasks per unit |
| Ctrl+1–9 | Assign groups |
| 1–9 / double tap | Recall / center group |
| F1 / double tap | Hero / center hero |
| Q/W/E/R | Contextual recruitment or stance |
| Space | Center highest-priority recent actionable alert |
| Middle drag / arrows | Camera pan |
| Scroll | Cursor-anchored zoom, subject to map bounds |
| Escape / right click while targeting | Cancel targeting |
| B / T | Worker war hall / watchtower placement |
| F2 | Select all combat units |
| F9 | Select and centre the next idle worker (cycles; rebindable) |
| F5–F8 / Ctrl+F5–F8 | Recall / set camera bookmark |
| Ctrl+F1 | Toggle follow hero |
| Alt held | Show every health bar |
| F4 / F10 | Performance overlay / hotkey help |
| Ctrl+S | Save replay |

Actions have mouse buttons, icons, labels, hotkeys and explanatory tooltips. Disabled controls explain costs, capacity, selection or unfinished construction. Passive actions remain visible. Number keys never recruit.

Selection tiles show type counts; click selects a subgroup and Tab cycles subgroups. Below them, a selection of more than one unit shows a tile per unit with its own health bar: click keeps only that unit, shift-click drops it, and pages appear beyond twelve. Production exposes remaining time, order and individual cancellation with full resource refund. Site cancellation keeps the existing 50% construction refund.

The hero dock shows health, XP, stance, revival and pending upgrades without replacing selection when using hero actions. Upgrade alternatives show exact numerical effects. An option click previews; **Choose Upgrade** sends the irreversible choice command. Closing retains pending milestones.

Controls for attack, stop, hero, alert and construction can be rebound in settings; numbers and Q/W/E/R stay reserved for consistent group/context behavior. Settings are versioned, validated and saved to the LÖVE save directory printed at startup.

Input routing owns pointer capture. HUD/menu clicks cannot become battlefield orders; minimap dragging cannot become box selection. Lobby text focus suppresses game hotkeys. Optional edge scrolling defaults off and is suppressed over HUD/modal UI and during drags.

## Camera and minimap

The camera clamps to map margins and centers maps smaller than the unobscured battlefield. Coordinate helpers are shared for world projection, picking, orders, minimap conversion and the viewport outline.

The minimap is north-up with square cells and aspect-preserving letterboxing. Layers are terrain/obstacles, unexplored and explored fog, remembered resources/camps/buildings, visible units, hero diamonds, selection accents, attention/order markers and camera outline. Ordinary units are dots; buildings are squares; resource symbols differ by type.

| Minimap action | Result |
|---|---|
| Left click/drag | Reposition camera; capture persists to release and clamps at edges |
| Right click | Contextual position order; visible enemy marker can receive targeted attack |
| A + left click | Attack-move |
| Shift + order | Append |
| Alt + left click | Temporary local attention marker |
| Alert click | Center on the known location |
| Letterbox click | No action |

Two small reused canvases cache terrain and fog; battlefield terrain shares this cache. Canvases use one pixel per cell and nearest filtering; UI transforms remain logical-coordinate based. Fog canvas contents change only when observation masks change. Rendering into the cache explicitly clears the inherited battlefield scissor.

### Fog and observations

The old explored-resource live-state exposure was removed. Sim.view supplies currently observed entities; enemy private orders, queues and progression are not exposed as observation data. A separate presentation memory records filtered observations only.

Hidden enemy units disappear. Buildings, resources and camp locations can persist as dim last-seen markers. Hidden depletion, death, damage or recruitment cannot update those memories. Re-observation refreshes/removes them. Remembered markers are coordinate destinations, never live targets.

Replay seeking rebuilds memory from tick zero using filtered views. A bounded saved-path index in artifacts (with L�VE save-directory fallback) lets packaged games find external artifact replays without mounting arbitrary folders. UI seeks execute at most 40 ticks per update and suppress historical audio, particles and alerts.

## Deterministic order and combat changes

Simulation version is now **2**. Old replays intentionally fail strict version/source checks. No existing golden result was silently rewritten.

- Move, attack-move, attack, harvest and construction share an explicit deterministic task queue.
- Normal orders replace; Shift appends; Stop clears. Completed, depleted, invalidated or exhausted tasks advance.
- Queued construction spends resources and blocks its footprint at command acceptance. Work starts only when the builder reaches that task.
- Placement preview and authority share Sim.placement; authority also checks complete occupancy.
- Distinct destination candidates use stable ordering and claims. Incremental A* retains its fixed expansion budget.
- Occupancy blocking triggers a bounded reroute after ten blocked ticks, with at most three attempts before a visible blocked result.
- Narrow congestion remains a playtest/tuning risk; nearby destination candidates can still prove unreachable in A*. The result is bounded and explicit.

Attacks use start, impact and finish ticks plus a locked target and facing vector. Default windup is four ticks; recovery uses the unit's attack period. Impact revalidates the target's life, hostility and range. Pre-impact movement cancels the hit; post-impact movement retains cooldown. Due impacts are queued before deaths.

Animation samples windup/contact/recovery from those ticks. Ranged impacts remain instantaneous gameplay with cosmetic tracers; no projectile simulation was introduced.

All queue, phase and retry state participates in snapshots/canonical serialization. Tests restore during queued movement/construction and windup, then compare continued state.

## Feedback and sound

Local destination pulses appear without waiting for lockstep. Pending commands are tracked by player sequence. Authoritative accepted/rejected events clear them; mixed results are summarized instead of issuing one notification per unit.

Stable events include tick/index, filtered audiences and event-time positions. Hidden source coordinates are removed. Audio, effects and alerts receive the filtered event stream.

Feedback includes selection/order rings, queued destination lines, impact sparks/tracers, direct health bars with short damage trails, scaffold/progress indicators, completion/healing/upgrade pulses, corpses, revival and outcome cues. Cosmetic fades use frame time; gameplay phases use simulation ticks.

Original generated sounds live in the checked-in audio recipe/manifest: gain, priority, cooldown, bus and pitch variations. There are master/UI/effects/ambience controls. Reused source slots are capped at 32; decorative effect entries at 256. Alerts and commands outrank decorative cues. Positions are relative to the camera; missing audio hardware is tolerated.

Alerts prioritize hero/HQ attacks, hero loss, upgrades, construction completion, blocked orders and production exits. Nearby repeated notices merge; per-key cooldowns and a four-item display cap constrain spam. Alerts never move the camera automatically.

## Module map

| Module | Responsibility |
|---|---|
| src/ui/shell.lua | Main/setup/lobby/replay/results flow |
| src/ui/screens.lua | Match panels and settings |
| src/ui/input.lua | Intent routing, focus, capture, hotkeys |
| src/ui/camera.lua | Viewport, clamp, centering, zoom |
| src/ui/widgets.lua / icons.lua | Small button/tooltip layer and symbols |
| src/ui/selection.lua | Selection membership and subgroups |
| src/ui/actions.lua | Labels, costs, availability, upgrade descriptions |
| src/ui/hud.lua | Hero, selection, production, commands, replay controls |
| src/ui/minimap.lua | Shared terrain cache, tactical markers/transforms |
| src/ui/observation.lua | Last-observed memory |
| src/ui/alerts.lua / audio.lua | Prioritized notification and sound |
| src/ui/settings.lua | Local settings validation/persistence |
| src/feedback.lua / asset_frames.lua | Cosmetic effects and animation timing |
| src/app.lua | Match orchestration and battlefield entities |
| src/sim/init.lua | Authoritative commands, queues, placement, combat, events |

## Delivery gates and verification

| Phase | Evidence | Remaining gate |
|---|---|---|
| Interaction foundation | Rendered capture/pause/transform tests at 80/100/125% | Physical Windows DPI changes and usability review |
| HUD/minimap | Clicked hero/actions/recruit/upgrade; rectangular/square transforms, fog-memory regression | Human mouse-only base-building and navigation |
| Orders/movement | Queue continuation, reservation/refund, stop, rerouting and prior congestion fixtures | Crowd feel in opposing narrow chokepoints |
| Combat/sound | Windup cancellation/cadence/simultaneous outcomes; actual audio/effects battle benchmark | Listen and assess continuous combat readability |
| Full flow | Menu/setup/lobby/settings/replay captures; real ENet lobby handshake; packaged launch | Full human session between physical PCs |
| Polish | Regression suite, fresh-process hashes, rendered scenarios, capped effects/audio | Stable-60 certification, extended soak and human sign-off |

Run:

~~~powershell
.\scripts\run.ps1
.\scripts\test.ps1
.\scripts\test-presentation.ps1
.\scripts\test-ui.ps1
.\scripts\test-ui.ps1 -Benchmark
.\scripts\package.ps1
~~~

tests/ui_contracts.lua covers queue advancement/Stop, queued building reservations, cancelled windup, recovery, snapshot continuation, hidden-resource equality, observation memory, minimap mapping and explicit real-ENet lobby readiness/start.

tests/presentation.lua exercises rendered input at three scales, modal capture, minimap dragging, projection round trips, offline pause, multiplayer polling, clickable recruitment/upgrade/stance, reserved number keys, draw immutability, compatible replay seeking and text focus. It produces separate screen captures under artifacts.

The active benchmark starts 240 units across two players at 1080p and runs 600 ticks with movement/combat, sprites, fog, minimap, effects and audio. It excludes bots, network and replay recording. Deaths are not replenished. Source slots, particles, CPU timings, frame cadence and heap samples are reported in artifacts/ui-benchmark.txt.

### Human acceptance scenarios

1. Build a base and recruit an army using only mouse commands and tooltips.
2. Fight while managing production and navigating through the minimap.
3. Respond to an offscreen base attack, pending hero upgrade and blocked order.
4. Repeat on a second Windows PC, including physical DPI changes and direct-IP matches.
5. Run longer sessions to assess memory growth, repeated alerts, sound fatigue and late-game crowd movement.

Success requires understandable outcomes and next actions, readable battles, and reproducible simulation. Passing automation alone does not establish these human gates.
