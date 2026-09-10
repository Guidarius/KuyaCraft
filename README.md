# LoveRTS

A Windows-first LÖVE 11.5 RTS prototype with a deterministic Lua simulation.

Read [ROADMAP.md](ROADMAP.md) for design and [STATUS.md](STATUS.md) for verified progress and limitations. The playable balance profile, unit statistics, economy and timing targets are in [BALANCE_AND_PACING.md](docs/BALANCE_AND_PACING.md). Twin Marches is the default 1v1 map.

## Quick start

In PowerShell, from this folder:

```powershell
.\scripts\setup.ps1
.\scripts\run.ps1
```

Setup downloads the official portable runtime into .tools and verifies the checksum in toolchain.json. No global Lua installation or MCP is required.

Once setup has run, **Play.bat** in this folder launches the game with a double-click.

## Standalone build

```powershell
.\scripts\package.ps1
```

This writes `dist\LoveRTS-<timestamp>\` containing **LoveRTS.exe**, a normal
double-clickable Windows program: the pinned LÖVE runtime with the game archive appended
to it. The folder stands alone — copy it to another PC, shortcut the executable, or zip
and share it — but keep its files together, because the executable loads the DLLs beside
it. `RunTests.ps1` in that folder runs the regression suites against that exact build,
and packaging verifies itself by running the unit suite before it reports success.

Generated sprite atlases are optional: without them the game draws procedural
placeholders rather than failing, so a machine with no Blender or Python toolchain can
still produce a playable package. Pass `-WithAssets` to require the real atlases and fail
if they cannot be built.

## Testing

```powershell
.\scripts\run.ps1 -Smoke
.\scripts\run.ps1 -AutoQuit 60
.\scripts\test-all.ps1
.\scripts\test.ps1
.\scripts\test.ps1 -Suite simulation
.\scripts\test.ps1 -Suite balance
.\scripts\test.ps1 -Suite crowd
.\scripts\test.ps1 -Suite soak
.\scripts\test.ps1 -Suite performance
.\scripts\test.ps1 -Suite network
.\scripts\test-presentation.ps1
.\scripts\export-assets.ps1
.\scripts\package.ps1
.\scripts\test.ps1 -SelfTestFailure -Suite unit
.\scripts\replay.ps1 -ReplayPath .\artifacts\sample.replay
```

`test-all.ps1` runs the headless suites, the multi-process determinism and network proofs, and the rendered suites. Use it after any change to the frame loop, the draw path or input: `test.ps1` alone executes **no rendered code**, because `tests/control_input` and `tests/presentation` only run under `--ui-test`.

The intentional-failure command must return exit code 1. Normal success is 0.
The all/determinism suites compare fresh processes over 100,000 ticks using 30/60/144 FPS schedules.

## Controls and UI

The game opens a main menu. Choose Skirmish to select your map and factions. All gameplay actions have mouse controls and explanatory tooltips.

- Left click/drag selects; Shift adds/removes; double click selects a visible unit type.
- Right click moves, attacks or resumes construction. A then **left click** issues attack-move. Shift appends; S stops and clears orders; H holds position without chasing or yielding.
- Replays are written next to the game under `artifacts`. If that folder cannot be written to — a packaged build placed somewhere read-only — the game saves to `%APPDATA%\LOVE\LoveRTS` instead and reports the path it used.
- Right click on one of your own units to follow it; the follower keeps station and never starts a fight of its own, and the order ends when its target dies.
- P then **left click** sets a patrol beat between where the unit stands and the point clicked. It engages on the way and turns around at each end, including when an end is unreachable.
- Right click with only production buildings selected sets their rally point; new units walk there, or fall in behind it if the rally point is one of your own units. The flag and its line are drawn while the building is selected.
- Units moved together as one group travel at the slowest member's pace so a mixed army arrives together. This is `rules.formationPacing` in content and can be turned off.
- Ctrl+1–9 assigns groups; 1–9 recalls; double tap centers. Number keys never recruit.
- F1 selects the hero; double tap centers. Q/W/E/R use contextual commands.
- G/B/T/O arm extractor, war hall, watchtower and outpost placement. An extractor goes **on** a gold mine and is the only way to earn gold: it sends carriers walking home to your nearest drop-off on their own. Select the HQ and use T to advance technology, unlocking support and heavy troops. Preview explains invalid footprints. Shift repeats queued placement.
- Hero dock buttons toggle stance, revive and open upgrades. Preview an upgrade, then click Choose Upgrade.
- Minimap left drag pans, right click orders, A-left attack-moves; Alt-left adds a local marker. Space centers an important alert.
- Middle drag/arrows pan; wheel zooms. Edge scroll is optional in Settings.
- Escape cancels targeting, closes a panel, then opens the match menu. Use Leave Match to exit. Offline menus pause; multiplayer continues.
- F2 selects every combat unit you own. F9 selects and centres on the next idle worker, cycling through them; the top bar always shows how many there are.
- Selecting more than one unit adds a tile per unit with its own health. Click a tile to keep only that unit, shift-click to drop it, and page when the selection exceeds twelve.
- Hold Alt to show every health bar. By default bars appear on selected and damaged units only; Settings offers always/selected/damaged.
- F5–F8 recall camera bookmarks and Ctrl+F5–F8 set them. Jumps to a group, the hero or an alert ease over about 150 ms rather than cutting. Ctrl+F1 toggles following the hero.
- F3 toggles the selected own-unit order inspector, including paths, attack timing, blocking and command acknowledgement latency.
- F4 shows an FPS/simulation/draw-call overlay. F10 lists every hotkey, generated from the live action list and your bindings.
- Ctrl+S / Save Replay writes under artifacts. Replays menu provides pause/speed/timeline/perspective.
- Offline matches can run slower/normal/faster from Settings. Speed changes only how fast wall-clock time is fed to the fixed 20 Hz simulation, so replays and checkpoints are identical at every speed; network matches always run at 1x.

Settings holds UI scale (80–125%), the volume buses, edge scroll, health-bar policy, screen shake, a cosmetic day/night tint, offline game speed, and every hotkey binding. The implementation and acceptance checklist are in [docs/UI_UX_ROADMAP.md](docs/UI_UX_ROADMAP.md).

The simulation contains no randomness at all: no damage variance, no scatter, no rolls. Every outcome follows from orders and content, which is what lets a replay reproduce a match exactly. `src/sim/rng.lua` and its golden-sequence test are kept so randomness can be reintroduced as a deliberate change.

## Gold

There is one resource and nothing harvests it. You build an **extractor** on a gold mine and it sends a stream of carriers walking to your nearest drop-off — the headquarters, or an outpost — where each one delivers its gold and is gone. Carriers take no orders and cannot be selected. They are ordinary targets, and killing one destroys the gold rather than stealing it.

A mine pays less the further it is from a drop-off, because an extractor holds only so many deliveries in flight at once. An outpost beside a distant mine shortens the route and restores it to full rate, which is what makes expanding a decision about ground you can hold rather than a button you press. The design, the arithmetic and the measured rates are in [docs/RESOURCE_FLOW.md](docs/RESOURCE_FLOW.md).

The movement lab is selectable in Skirmish or with `scripts/run.ps1 -Map movement_lab`. It contains flat chokepoints, a U-shaped obstacle, a concave wall, a corridor, and forest clutter. Its purpose is navigation testing, not a balanced economic match. See [the control and movement verification record](docs/CONTROL_MOVEMENT.md).

## Private multiplayer

The Multiplayer menu provides host/join fields, faction selection and explicit Ready/Start controls. A compatible connection waits for both players and host start. Command-line shortcuts open that lobby too.

Host:

```powershell
.\scripts\run.ps1 -HostAddress "*:22122"
```

Join on the same computer:

```powershell
.\scripts\run.ps1 -JoinAddress "127.0.0.1:22122"
```

On another PC, replace 127.0.0.1 with the host's reachable address. Both copies must use identical authoritative source/content/runtime. Start Wild Pact with -Faction wild, or the second map with -Map open_fields. The prototype supplies no NAT traversal, public lobby, reconnect, or host migration.

## Files

- src/sim: engine-independent authoritative state and rules.
- src/content.lua and src/maps.lua: data definitions.
- src/net: lockstep aggregation and ENet session.
- src/app.lua: match orchestration; src/ui: screens, input, HUD, minimap, sound and settings. All gameplay changes use commands.
- tests: regression fixtures and process checks.
- scripts: setup, launch, testing, replay, export, packaging.
- artifacts: generated logs/replays/screenshots/test results, ignored by Git.
- LÖVE save directory: printed at startup; separate from project artifacts.

See [docs/TOOLCHAIN.md](docs/TOOLCHAIN.md) for runtime provenance and troubleshooting.

Compare desync checkpoint files with scripts/compare-states.ps1 -Left <host.state> -Right <client.state>. The output lists changed subsystem paths; it does not infer an earlier divergent tick.
## Unit assets

The production workflow creates five source-rig-derived Bastion assets: shieldguard, worker, loaded worker, crossbow, and Warden. See [the asset pipeline guide](tools/blender/README.md) for prerequisites, source setup, rendering, validation, viewer controls, and recovery. The saved source library is local and excluded from the package; runtime players need only the generated images and metadata.

```powershell
.\scripts\export-assets.ps1 -Mode Build -Roster bastion
.\scripts\export-assets.ps1 -Mode Validate -Roster bastion
.\scripts\run.ps1 -AssetViewer
```