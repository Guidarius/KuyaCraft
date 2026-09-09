local M = {}
function M.create(name, size)
    if not size and (not name or name=='twin_marches') then return require('src.maps.twin_marches')() end
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
