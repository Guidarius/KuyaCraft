-- The map registry. The shipping maps are authored as layouts under tools/tiled, generated
-- into maps/<id>.tmx and exported to src/maps/<id>_tiled.lua (scripts/map.ps1); the rest are
-- small procedural scenarios the tests and the movement lab use.
local M = {}
-- Shipping 1v1 maps, in the order the skirmish screen offers them. Every one is symmetric
-- under a 180-degree rotation and gives each player a main, a natural, a third and a
-- contested field (docs/MAPS.md).
M.tiled = { 'twin_marches', 'the_narrows', 'open_reach', 'crossroads' }
M.info = {
    twin_marches = { label = 'Twin Marches', blurb = 'Corner bases on a diagonal, naturals to the side, long outer corridors.' },
    the_narrows = { label = 'The Narrows', blurb = 'North against south across a band of rock: one bridge, two long flank lanes.' },
    open_reach = { label = 'Open Reach', blurb = 'Almost all open ground. No chokepoints, four fields in reach of each base.' },
    crossroads = { label = 'Crossroads', blurb = 'A walled centre on the short road, two wide outer lanes, a back door each.' },
    river_pass = { label = 'River Pass (test)', blurb = 'A small procedural scenario.' },
    open_fields = { label = 'Open Fields (test)', blurb = 'A small empty scenario.' },
    movement_lab = { label = 'Movement Lab (test)', blurb = 'Pathfinding torture course.' },
}
-- Everything the skirmish screen cycles through.
M.list = { 'twin_marches', 'the_narrows', 'open_reach', 'crossroads', 'river_pass', 'open_fields', 'movement_lab' }
local isTiled = {}
for _, id in ipairs(M.tiled) do isTiled[id] = true end
function M.label(id) return M.info[id] and M.info[id].label or id end
function M.next(id)
    for i, name in ipairs(M.list) do if name == id then return M.list[i % #M.list + 1] end end
    return M.list[1]
end
function M.create(name, size)
    if not size and (not name or isTiled[name]) then
        return require('src.maps.tiled').convert(require('src.maps.' .. (name or 'twin_marches') .. '_tiled'))
    end
    if name=='movement_lab' then return require('src.sim.torture_map')() end
    local width, height = size or 40, size and size or 28
    local map = { id = name or 'river_pass', width = width, height = height, blocked = {}, resources = {}, camps = {}, starts = {} }
    map.starts = { { x = 2, y = 2 }, { x = width - 5, y = height - 5 },
        { x = 2, y = height - 5 }, { x = width - 5, y = 2 } }
    if not size and name~='open_fields' then
        for y = 2, height - 3 do
            if math.abs(y - math.floor(height / 2)) > 2 then map.blocked[y * width + math.floor(width / 2) + 1] = true end
        end
    end
    for i = 1, 4 do
        local s = map.starts[i]
        local dir = s.x < width / 2 and 1 or -1
        map.resources[#map.resources + 1] = { x = s.x + dir * 2, y = math.min(height - 1, s.y + 5), resource = 'gold', amount = 5000 }
        map.resources[#map.resources + 1] = { x = s.x + dir * 3, y = math.min(height - 1, s.y + 5), resource = 'lumber', amount = 4000 }
    end
    if not size and name~='open_fields' then
        map.camps = { { x = 11, y = 13 }, { x = 28, y = 13 } }
    end
    return map
end
return M
