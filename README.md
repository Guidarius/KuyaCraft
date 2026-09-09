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

## Testing

```powershell
.\scripts\run.ps1 -Smoke
.\scripts\run.ps1 -AutoQuit 60
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

The intentional-failure command must return exit code 1. Normal success is 0.
The all/determinism suites compare fresh processes over 100,000 ticks using 30/60/144 FPS schedules.

## Controls and UI

The game opens a main menu. Choose Skirmish to select your map and factions. All gameplay actions have mouse controls and explanatory tooltips.

- Left click/drag selects; Shift adds/removes; double click selects a visible unit type.
- Right click moves, attacks, harvests or resumes construction. A then **left click** issues attack-move. Shift appends; S stops and clears orders; H holds position without chasing or yielding.
- Ctrl+1–9 assigns groups; 1–9 recalls; double tap centers. Number keys never recruit.
- F1 selects the hero; double tap centers. Q/W/E/R use contextual commands.
- With only workers selected, B opens Build; Q/T/E/R choose war hall, watchtower, outpost and lumber depot. Cards show costs; shortages are red. Escape cancels placement, then returns to commands. Shift repeats queued placement. Select one HQ and use T to advance technology, unlocking support and heavy troops.
- With only the hero selected, U opens the ability card: three paired tiers show XP requirements, learned choices and exclusions. Preview an available upgrade, then click Choose Upgrade. The hero dock also selects the hero and opens the card. Mixed groups get shared movement/combat commands; worker-only groups get Build/Harvest.
- Minimap left drag pans, right click orders, A-left attack-moves; Alt-left adds a local marker. Space centers an important alert.
- Middle drag/arrows pan; wheel zooms. Edge scroll is optional in Settings.
- Escape cancels targeting, closes a panel, then opens the match menu. Use Leave Match to exit. Offline menus pause; multiplayer continues.
- F3 toggles the selected own-unit order inspector, including paths, attack timing, blocking and command acknowledgement latency.
- F5 / Save Replay writes under artifacts. Replays menu provides pause/speed/timeline/perspective.

UI scale (80–125%), volume buses, edge scroll and common hotkey bindings are in Settings. Commands use distinct audio cues and brief visual markers; invalid actions flash the card and deficient resource totals. See [command cards and feedback](docs/COMMAND_CARDS.md). The implementation and acceptance checklist are in [docs/UI_UX_ROADMAP.md](docs/UI_UX_ROADMAP.md).

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