-- Relay coverage: the Megacorp's territory. A faction with `coverage` has a per-player set
-- of cells inside the coverage radius of any of its completed buildings and living units
-- that carry a `coverage` radius. Binary, rebuilt every tick from the sources in `w.order`,
-- so a source that dies or moves changes the set at once and nothing has to be counted
-- down. It gates where buildings may land and what rigs earn, so it is authoritative
-- state and is checkpointed.
local F=require('src.sim.fixed')
local Path=require('src.sim.path')
local M={}
local spans={}
function M.update(w)
    for p=1,#w.players do
        local player=w.players[p]
        local faction=w.content.factions[player.faction]
        if faction and faction.coverage then
            -- Reused rather than replaced: this table is shared by reference into views.
            local grid=player.coverage
            if grid then for key in pairs(grid) do grid[key]=nil end else grid={};player.coverage=grid end
            local width,height=w.map.width,w.map.height
            for _,id in ipairs(w.order) do
                local e=w.entities[id]
                if e.alive and e.owner==p and (e.category=='unit' or (e.category=='building' and e.remaining==0)) then
                    local d=w.content.units[e.kind] or w.content.buildings[e.kind]
                    local radius=d and d.coverage
                    if radius then
                        local cells=math.floor(radius/256)
                        local size=(e.size or 1)-1
                        local cx,cy=F.cell(e.x+size*128),F.cell(e.y+size*128)
                        local s=spans[cells]
                        if not s then s={};for dy=-cells,cells do s[dy]=F.isqrt(cells*cells-dy*dy) end;spans[cells]=s end
                        for dy=-cells,cells do
                            local y=cy+dy
                            if y>=0 and y<height then
                                local reach=s[dy]
                                for x=math.max(0,cx-reach),math.min(width-1,cx+reach) do grid[Path.key(w.map,x,y)]=true end
                            end
                        end
                    end
                end
            end
        end
    end
end
-- Whether a cell is covered for a player. A faction without coverage is covered everywhere.
function M.covers(w,p,x,y)
    local grid=w.players[p].coverage
    if not grid then return true end
    return grid[Path.key(w.map,x,y)]==true
end
return M
