# Maps

Four 1v1 maps ship, each a different answer to "where does the fight happen". All are
symmetric under a 180-degree rotation, and all give each player the same four fields, so
what differs between them is ground, not income: a main of seven substrate patches (1500
each) and a 5000 charge geyser, a natural of six (1000) and 3500, and a third and a
contested field of four (800) and 3000. No neutral camps, no control points.

| Map | Size | Walkable | Base to base | Shape | What it asks |
|---|---|---:|---:|---|---|
| `twin_marches` Twin Marches | 192×192 | about 60% | 67 s | Corner bases on a diagonal, naturals to the side, a central clearing, long outer corridors to the corners | The reference map: every kind of ground in moderation |
| `the_narrows` The Narrows | 160×224 | 30% | 81 s | North against south across a wide band of rock: a seven-cell wooded bridge down the middle and one five-cell lane down each flank | Hold the bridge, or walk round. The enemy's flank lane comes out at the southern edge of your natural, so the safe-looking natural has a long back door |
| `open_reach` Open Reach | 224×224 | 84% | 80 s | Corner against corner on open grass; two stubs of rock shade each main, a block fills the very centre, woods and outcrops break sight lines | No chokepoint anywhere. Wide economies, flanks, and room for the Megacorp to spread relays |
| `crossroads` Crossroads | 192×192 | 33% | 47 s | West against east. The short road runs through a walled clearing at the centre with a narrow gate each side and two small fields inside; two wide outer lanes go the long way | Whoever holds the middle holds the direct road and both centre fields. Your natural guards the lane that leaves your base; the enemy's lane arrives at your back door |

Base to base is a Footman's march with no crowd delays; the natural is 9 to 14 s from the
main on every map. Crossroads is the rush map of the set, its direct road a third shorter
than any other; in six-minute bot matches first contact came at 4:01 there against 4:42 and
4:49 on Open Reach and The Narrows.

The balance suite prints one line per map (`artifacts/balance-map-<id>.txt`): the march
between the bases and to the natural at Footman speed, and the state of a six-minute Orders
against Megacorp bot match on it. Those lines are for comparing layouts; the only things
asserted are that both bots get production up and an economy running.

## How a map is made

1. **Write a layout** in `tools/tiled/layouts/<id>.lua` with the helpers in
   `tools/tiled/layout.lua`. The map starts as solid rock and is carved open for player one;
   every helper applies the rotation for player two. `carve`, `disc`, `rect` and `corridor`
   open ground, `rock` closes it, `road` lays a three-cell unbuildable road, `forest` plants
   woods (they block movement and sight), `base(x,y,fx,fy)` places the headquarters with its
   main field and starting units, and `expansion(kind,x,y,pattern,fx,fy,...)` places an
   anchor with a field. `fx`/`fy` of -1 flip a field about its keep or anchor: put a field on
   the wall away from the base's exit, never across it. Each map needs one `naturals`, one
   `forward` and one `contested` expansion per player; the bots expand to `naturals`.
2. **Generate**: `scripts/map.ps1 -Mode Generate -Map <id> -Force`. The generator roughens
   the carved edges into coastlines and coves, grows each forest rectangle into a grove,
   fills anything unreachable, and then checks that no walking distance between bases and
   anchors moved by more than a few percent from the layout as written, repairing it where
   it did. It writes `maps/<id>.tmx`, the export `src/maps/<id>_tiled.lua`, and a preview
   at `artifacts/map-<id>.png`. Look at the preview.
3. **Register** the id in `src/maps.lua` (`M.tiled`, `M.info`, `M.list`), in the
   `ValidateSet` of `scripts/run.ps1`, and give it a row of expectations in
   `tests/balance.lua` (`SHIPPING`: width, height, minimum walkable percent). The tests then
   check symmetry, that no patch is on rock or a road, the fields at every base, that both
   factions spawn cleanly, and that the Command's coverage reaches every main patch.
4. A `.tmx` may be hand-edited in Tiled afterwards and re-exported with
   `scripts/map.ps1`; regenerating overwrites hand edits, which is why it needs `-Force`.
   Twin Marches is generated from `tools/tiled/twin_marches_legacy.lua`, which predates the
   shared helpers, and regenerates byte for byte.

Tiled 1.12.2 is not installed on the desk machine, so `scripts/map.ps1 -Mode Check` has not
been run against these exports; the generator writes the same Lua that Tiled's exporter
would, which was proven on Twin Marches when the exporter was written.

## Ideas not built

Layouts worth trying next, each a different question: a four-start map for 2v2 or
free-for-all (the simulation takes four players; the bots only know one enemy); a map with
an island field that only flyers and drop pods can reach; a mirror-symmetric map, which
needs the generator's rotation to become a choice; and a small 128×128 rush map.
