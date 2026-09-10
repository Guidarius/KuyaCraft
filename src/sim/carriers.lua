-- Gold flow. An extractor built on a mine emits carriers that walk a cached route to the
-- nearest friendly drop-off, deliver their payload and are recycled. See
-- docs/RESOURCE_FLOW.md for the economics; this file is the mechanism.
--
-- Carriers are deliberately not units. They are their own category, so they never enter
-- the collision bins, never run crowd resolution, never take orders, cost no food and
-- cannot be selected. They pass through units and through each other and collide only
-- with terrain, which is the whole of the "vague mineral walking" feel: a loose stream
-- rather than a queue. They are ordinary targets for anything that wants to shoot them.
local F=require('src.sim.fixed')
local Path=require('src.sim.path')
local G=require('src.sim.geometry')
local M={}

-- Perpendicular spread, so a route reads as a stream rather than single file. Derived
-- from the entity id, so it is fixed for the life of a carrier and identical on every
-- peer. Seven lanes across roughly two thirds of a cell.
local LANES={-84,-56,-28,0,28,56,84}
function M.lane(id) return LANES[id%#LANES+1] end

-- Where an extractor sends its carriers: the nearest living drop-off it owns, by squared
-- distance with the entity id as a total-order tiebreak.
function M.dropoff(w,e)
    local best,bestDistance
    for _,id in ipairs(w.order) do
        local b=w.entities[id]
        if b.alive and b.owner==e.owner and b.category=='building' and b.remaining==0 then
            local d=w.content.buildings[b.kind]
            if d and d.dropoff then
                local distance=F.distance2Bounded(e.x,e.y,b.x,b.y)
                if not bestDistance or distance<bestDistance or (distance==bestDistance and id<best.id) then
                    best=b;bestDistance=distance
                end
            end
        end
    end
    return best
end

-- The route is one A* search per extractor, shared by every carrier it emits, refreshed
-- when the obstruction set changes or the destination does. No carrier ever calls the
-- pathfinder. The extractor is a building and never moves, so borrowing the ordinary
-- incremental search state on it is harmless.
-- A walkable cell touching the drop-off's footprint. The footprint itself is blocked, so
-- routing at its centre would simply fail; carriers walk to its doorstep instead.
-- Scanned in a fixed order and resolved by distance to the extractor, so the choice is
-- the same on every peer.
local function doorstep(w,e,target)
    local size=target.size or 1
    local x0,y0=F.cell(target.x),F.cell(target.y)
    local best,bestDistance
    for y=y0-1,y0+size do
        for x=x0-1,x0+size do
            if (x<x0 or x>=x0+size or y<y0 or y>=y0+size) and Path.walkable(w,x,y) then
                local distance=F.distance2Bounded(e.x,e.y,F.center(x),F.center(y))
                if not bestDistance or distance<bestDistance then best={x,y};bestDistance=distance end
            end
        end
    end
    return best
end
function M.route(w,e,route)
    local target=M.dropoff(w,e)
    local door=target and doorstep(w,e,target)
    if not door then e.path={};e.goal=nil;w.searches[e.id]=nil;e.routeTarget=nil;return false end
    local gx,gy=door[1],door[2]
    if e.routeTarget~=target.id or e.routeVersion~=w.navVersion or (#e.path==0 and not w.searches[e.id]) then
        if e.routeTarget~=target.id or e.routeVersion~=w.navVersion then
            e.routeTarget=target.id;e.routeVersion=w.navVersion;e.routeSerial=(e.routeSerial or 0)+1
            e.goal=nil;w.searches[e.id]=nil
        end
        route(w,e,gx,gy)
    end
    return #e.path>0 and not w.searches[e.id]
end

-- Target position for a carrier's current waypoint, offset into its lane. The offset is
-- perpendicular to the leg being walked, so the stream bends with the route.
local function waypoint(w,source,carrier)
    local path=source.path
    local node=path[carrier.leg]
    if not node then return nil end
    local x,y=F.center(node.x),F.center(node.y)
    local previous=path[carrier.leg-1]
    local fromX,fromY
    if previous then fromX,fromY=F.center(previous.x),F.center(previous.y)
    else fromX,fromY=source.x,source.y end
    local dx,dy=x-fromX,y-fromY
    if dx~=0 or dy~=0 then
        local px,py=F.vector(-dy,dx,M.lane(carrier.id))
        x=x+px;y=y+py
    end
    return x,y
end

-- One tick of travel. Carriers move on their own here rather than through the movement
-- phase, because they have no collision, no crowd resolution and no orders to service.
function M.advance(w,carrier,deliver)
    local source=w.entities[carrier.source]
    if not source or not source.alive or source.remaining>0 then return end
    -- The route changed underneath it: re-enter the new path at its nearest waypoint
    -- rather than walking a path that may no longer exist.
    if carrier.routeSerial~=source.routeSerial then
        carrier.routeSerial=source.routeSerial
        local best,bestDistance
        for i=1,#source.path do
            local node=source.path[i]
            local distance=F.distance2Bounded(carrier.x,carrier.y,F.center(node.x),F.center(node.y))
            if not bestDistance or distance<bestDistance then best=i;bestDistance=distance end
        end
        carrier.leg=best or 1
    end
    -- Arrived: touching the drop-off is what counts, not exhausting the waypoint list.
    -- The route ends at the doorstep, and a carrier in its lane may be a little to one
    -- side of it.
    local target=w.entities[source.routeTarget]
    if target and target.alive then
        local size=target.size or 1
        local reach=G.rectangleDistance2(carrier.x,carrier.y,
            F.cell(target.x)*256,F.cell(target.y)*256,
            (F.cell(target.x)+size)*256,(F.cell(target.y)+size)*256)
        if reach<=F.sq(320) then return deliver(w,carrier) end
    end
    local speed=w.content.units.carrier.speed
    for _=1,2 do
        local x,y=waypoint(w,source,carrier)
        if not x then return deliver(w,carrier) end
        local dx,dy=F.vector(x-carrier.x,y-carrier.y,speed)
        if dx==0 and dy==0 then carrier.leg=carrier.leg+1
        else carrier.x=carrier.x+dx;carrier.y=carrier.y+dy;return end
    end
end
return M
