-- Twin Marches: a 192x192 1v1 map, authored in Tiled at maps/twin_marches.tmx.
--
-- The layout is the code-authored map (tools/tiled/twin_marches_legacy.lua) with organic
-- rock edges and forest clumps. Each base has a curved line of one-cell substrate patches
-- a few cells from its keep and a two-cell charge geyser at the end of it: seven patches at
-- the main, six at the natural, four at the forward and contested corner sites. Bases and
-- anchors sit where they always did, and the map is symmetric under a 180-degree rotation
-- (tests/balance.lua checks it). Roads are walkable ground nobody may build on. There are
-- no neutral camps and no control points.
--
-- Edit the layout (or the .tmx in Tiled), then run scripts/map.ps1 to refresh
-- twin_marches_tiled.lua; the generator writes both files.
local Tiled=require('src.maps.tiled')
return function()
    return Tiled.convert(require('src.maps.twin_marches_tiled'))
end
