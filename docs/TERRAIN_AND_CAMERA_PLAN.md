# LoveRTS — Terrain and camera plan

Status: **phases 2 and 3 are done** (map format and terrain on screen); phases 1, 4 and 5
(camera, autotiling, Tiled extras) are not. Decisions taken 2026-09-15: map authoring moves
to Tiled; the game will have many terrain types but starts with a basic set; there is no
camera zoom; the camera is fixed at Brood War level. The defaults marked *accepted* below
were proposed and accepted without a playtest, so each is open to revision once it can be
seen.

What exists now: `maps/twin_marches.tmx` is the map source, exported by `scripts/map.ps1` to
`src/maps/twin_marches_tiled.lua` and converted by `src/maps/tiled.lua`, which derives
`blocked` and `unbuildable` and a per-cell `terrain` string. `src/ui/terrain.lua` draws the
ground from those types in chunks, procedurally, with no art. The camera is unchanged: it still
zooms, and the ground is no longer the stretched minimap canvas.

## Where terrain is today

- A map is Lua code. `src/maps/twin_marches.lua` starts a 192×192 grid solid and carves
  it open, then stamps roads (`unbuildable`), forests (`blocked`), mines, camps and control
  points, mirrored by 180° rotation.
- The simulation reads only `blocked` and `unbuildable` per cell, plus the object lists.
- The battlefield ground is the minimap's one-pixel-per-cell canvas stretched over the
  world (`src/ui/minimap.lua:67`, `src/app.lua:470`), in three flat colours. Fog is the
  same cache's one-pixel-per-cell fog texture drawn over it (`src/app.lua:471`), written
  incrementally since improvement-loop iteration 3.
- Rock and forest are both just `blocked`, so nothing can draw them differently.
- The camera shows 24 cells vertically at any resolution, squashes the vertical axis to
  26 × sin 60°, and zooms 80–135% (`src/ui/camera.lua`).

## Decisions

| Question | Choice | Status |
|---|---|---|
| Authoring tool | Tiled 1.12.2 | decided |
| Camera zoom | none | decided |
| Camera projection | square on-screen grid, no tilt; the 3/4 view lives in the art, as in Brood War | accepted |
| Cell size | 32 native pixels, one Tiled tile per simulation cell | accepted |
| Visible rows | about 15, pending a probe at 12 / 15 / 18 | accepted default |
| Starter terrain types | grass, road, rock, forest | accepted |
| Pathing | derived from terrain type, with an optional override layer | accepted |
| Symmetry | author the whole map; a Tiled command mirrors or checks 180° rotation | accepted |
| Unit body size | 32-pixel woodland body, matching the 32-pixel cell | accepted |

## Camera

Brood War is 640×480 with 32-pixel tiles, leaving roughly 20 × 12.5 tiles above the
console (from a search result; the sources could not be fetched, so unverified). Our
ordinary unit is 160 subunits across, 0.625 cells, which is 20 pixels at a 32-pixel cell;
a Brood War Marine is 17×20 pixels.

- Draw the battlefield to a low-resolution canvas at 32 pixels per cell and upscale it by
  a whole number with `nearest` filtering. The HUD is drawn separately at window
  resolution, unaffected.
- The integer scale is chosen from the window height and the target row count, so the
  exact number of visible rows varies a little by resolution, as it does in StarCraft:
  Remastered.
- Camera positions snap to whole native pixels; interpolated unit positions round to
  native pixels when drawn, so pixel art does not shimmer.
- Remove `Camera.zoom`, `userZoom`, `Camera.normalize`'s scaling, the mouse-wheel handler
  (`src/app.lua:664`) and every `camera.zoom` multiplication in `app.lua`, `feedback.lua`
  and `sprites.lua`. Remove the `26 * sin(60°)` vertical factor (`CELL_Y`).
- Sprites keep their rendered 3/4 viewpoint and ground anchors; only the ground grid
  stops being squashed. Check anchors and picking against the new grid.

This is presentation only: no simulation or content version change.

## Map format

### Layers

| Layer | Kind | Holds | Game effect |
|---|---|---|---|
| `ground` | tile layer, painted with a Tiled corner terrain set | terrain type per cell | `blocked` and `unbuildable` derived from the type |
| `pathing` | tile layer, optional | exceptions only | overrides the derived flags per cell |
| `gameplay` | object layer | starts, gold mines, camps, control points, anchors, unit starts | the object lists `Sim.create` reads today |
| `doodads` | object layer, later | canopies, rocks, props | presentation only |

Starter terrain types and their derived flags:

| Type | blocked | unbuildable | blocks sight |
|---|---|---|---|
| grass | no | no | no |
| road | no | yes | no |
| rock | yes | no | yes |
| forest | yes | no | yes |

Sight is unchanged: every blocked cell already blocks line of sight.

### Pipeline

1. **Source.** `maps/<id>.tmx` with its tilesets is tracked. Tiled reads `.aseprite` files
   directly as tileset images, so tile art can stay in Aseprite source form.
2. **Export.** Tiled's built-in Lua format, run headless:
   `tiled.exe --export-map lua maps/<id>.tmx src/maps/<id>_tiled.lua`. Verified to run
   without a window on this machine.
3. **Convert.** A Lua module in `src/maps/` turns the export into the table the simulation
   already reads, plus a `terrain` grid of type indices for presentation. It must:
   - clear Tiled's flip flags from tile ids (`0x80000000`, `0x40000000`, `0x20000000`,
     `0x10000000`) and subtract each tileset's `firstgid`; 0 means empty;
   - read rows top-left with y down, matching the simulation's cell keys;
   - iterate in fixed order and fail loudly on an unknown tile or object class.
4. **Tileset properties.** Tiled's Lua export includes only a `filename` for external
   tilesets, not their tile properties. Either embed tilesets on export or keep a
   tile-to-type table beside the converter.

Because `src/build.lua` fingerprints `src/maps`, saved replays stop loading after the
switch. That is expected.

### Checks

- The existing Twin Marches tests in `tests/balance.lua` (footprint safety and symmetry,
  road connectivity, control points) run against the converted map.
- Converter tests: flip bits, orientation, unknown tile and unknown object rejection.
- A drift test re-exports each `.tmx` and compares the result with the committed export.
  It runs from `scripts/test.ps1` and is skipped with a message when Tiled is absent.
- A Tiled JavaScript action (`tools/tiled/extensions/`) mirrors the north-west half onto
  the south-east, or reports the first asymmetric cell or object.

## Rendering

- **Chunks.** Bake the ground into static `SpriteBatch`es of 32×32 cells, rebuilt only when
  the map changes, and draw only the chunks in view.
- **Dual-grid autotiling.** A second grid offset by half a cell takes each tile's four
  corners from the terrain grid. Five tiles per terrain pair cover every case with
  rotation; sixteen when lighting must not rotate.
- **Layering.** Terrain types draw in priority order, as Warcraft III blends ground
  textures.
- **Variants.** Picked by an integer hash of the cell, never the simulation PRNG, as
  `lords-of-the-dead` does in `docs/wiki/systems/arena-terrain.md`.
- **Visual height.** Rock draws a south-facing cliff face and baked shadow into the cell
  below; forests draw y-sorted canopy sprites taller than a cell. Gameplay stays flat.
- **Minimap.** Stays one pixel per cell, coloured by terrain type, and stops doubling as
  the world ground.
- **Fog.** Unchanged: one texture drawn over the world.
- **Before tiles exist.** Each terrain type renders as a flat colour through the same
  chunked path. No placeholder art is added; tile art is the user's.

## Phases

1. **Camera.** Square grid, native canvas and integer upscale, zoom removed, and a probe
   comparing 12, 15 and 18 visible rows. Verify with `scripts/test-ui.ps1`,
   `scripts/test-presentation.ps1` and inspected captures.
2. **Map format.** Converter and tests; generate a starting `twin_marches.tmx` from today's
   Lua map so the layout is edited, not repainted; prove `Sim.serializeCanonical` of a new
   world is identical before and after, so there is no simulation version bump and bot
   matches are unchanged; pin Tiled in `toolchain.json` and `scripts/setup.ps1`.
3. **Terrain types on screen.** Chunked flat-colour renderer and terrain-coloured minimap,
   with a rendered test that asserts drawing leaves the world unchanged.
4. **Autotiling.** Enable the dual-grid renderer when the first tileset exists.
5. **Tiled extras.** Symmetry action, and custom object classes in a `.tiled-project` so
   gameplay objects carry typed properties.
6. **Later.** Canopies and cliff visuals, more terrain types, a second map.

## Tooling

Tiled 1.12.2 is unpacked, not installed, at `.tools/tiled-1.12.2/PFiles/Tiled/` from the
official `Tiled-1.12.2_Windows-10+_x86_64.msi` (23,425,024 bytes, SHA-256
`11a0e6c97cc105e07a57ea9995f2704617986722de4ab699d286dab0d2becc3f`, signed by SignPath
Foundation), using `msiexec /a <msi> /qn TARGETDIR=<dir>`. `tiled.exe --help` prints
nothing because it is a GUI application, and `tmxrasterizer.exe --help` hangs, so scripts
must run Tiled tools with a timeout.

## Not verified

- Brood War's visible tile count.
- Whether 15 rows reads well with the HUD: that is what the phase 1 probe is for.
- Tiled's command-line flag for embedding tilesets on export.
- Any of this on a Raspberry Pi.
