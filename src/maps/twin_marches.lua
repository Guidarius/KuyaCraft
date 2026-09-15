-- Twin Marches: a 192x192 1v1 map, authored in Tiled at maps/twin_marches.tmx.
--
-- The layout is the code-authored map that preceded it (tools/tiled/twin_marches_legacy.lua)
-- with organic rock edges and forest clumps: every base, gold mine, road, camp, control point
-- and anchor sits in the same cell, and the map is symmetric under a 180-degree rotation
-- (tests/balance.lua checks both). Roads are walkable ground nobody may build on; they join
-- every gold mine to the others and to both headquarters.
--
-- Edit the .tmx in Tiled, then run scripts/map.ps1 to refresh twin_marches_tiled.lua.
local Tiled=require('src.maps.tiled')
return function()
    return Tiled.convert(require('src.maps.twin_marches_tiled'))
end
