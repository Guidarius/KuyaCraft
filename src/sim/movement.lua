local F=require('src.sim.fixed')
local G=require('src.sim.geometry')
local Path=require('src.sim.path')
local Stats=require('src.sim.stats')
local M={}
local rotations={{256,0},{229,114},{229,-114},{181,181},{181,-181},{0,256},{0,-256},{-181,181},{-181,-181}}
local function scale(v) local n=math.floor(math.abs(v)/256);return v<0 and -n or n end
local function direction(e) return e.laneX==1 and 0 or e.laneX==-1 and 1 or e.laneY==1 and 2 or 3 end
local function binKey(x,y) return F.cell(y)*256+F.cell(x) end
local function bins(w)
    local out={directions={}}
    for _,id in ipairs(w.order) do local e=w.entities[id];if e.alive and e.category=='unit' then
        local key=binKey(e.x,e.y);out[key]=out[key] or {};out[key][#out[key]+1]=id
        if e.goal then out.directions[key*4+direction(e)]=true end
    end end
    return out
end
local function opposed(b,e)
    local d=direction(e);local opposite=d%2==0 and d+1 or d-1
    for cy=F.cell(e.y)-3,F.cell(e.y)+3 do for cx=F.cell(e.x)-3,F.cell(e.x)+3 do
        if b.directions[(cy*256+cx)*4+opposite] then return true end
    end end
    return nil
end
-- Neighbour lookups run once per proposal per tick and previously allocated a
-- fresh table each time, plus an empty one per missed bin. The results are
-- consumed immediately and never retained, so they go into a reusable buffer;
-- the caller gets the count rather than relying on the array length.
local scratch={}
local function nearby(w,b,x,y,r,out)
    r=r or 1
    out=out or scratch
    local n=0
    local entities=w.entities
    for cy=F.cell(y)-r,F.cell(y)+r do for cx=F.cell(x)-r,F.cell(x)+r do
        local bin=b[cy*256+cx]
        if bin then for i=1,#bin do n=n+1;out[n]=entities[bin[i]] end end
    end end
    for i=#out,n+1,-1 do out[i]=nil end
    return out,n
end
local function clear(w,e,x,y,neighbors)
    local r=G.radius(w,e)
    local cx,cy=F.cell(x),F.cell(y)
    if e.goal and (cx~=e.goal.x or cy~=e.goal.y) and not (e.opposed and Path.lanePosition(w,x,y,r,e.laneX or 0,e.laneY or 0) or not e.opposed and Path.laneAllowed(w,cx,cy,e.laneX or 0,e.laneY or 0)) and (e.opposed and Path.lanePosition(w,e.x,e.y,r,e.laneX or 0,e.laneY or 0) or not e.opposed and Path.laneAllowed(w,F.cell(e.x),F.cell(e.y),e.laneX or 0,e.laneY or 0)) then return false end
    if not G.terrain(w,x,y,r) or not G.terrain(w,math.floor((e.x+x)/2),math.floor((e.y+y)/2),r) then return false end
    for _,other in ipairs(neighbors) do if other.id~=e.id then
        local gap=G.separation(w,e,other)
        if math.abs(x-other.x)<gap and math.abs(y-other.y)<gap and F.distance2Bounded(x,y,other.x,other.y)<gap*gap then return false,other end
    end end
    return true
end
-- Resolved centrally so a slow, a haste or a root reaches movement the same way the
-- hero stance bonuses already do. See src/sim/stats.lua.
local speed=Stats.speed
local function choices(w,e,tx,ty)
    local dx,dy=F.vector(tx-e.x,ty-e.y,speed(w,e))
    -- Integer rotation coefficients have length <= 256. Normalize once,
    -- then rotate without repeated square-root work or exceeding unit speed.
    local out={}
    for i=1,(e.waitTicks or 0)>=10 and 9 or 7 do
        local v=rotations[i];local sx,sy=scale(dx*v[1]-dy*v[2]),scale(dy*v[1]+dx*v[2])
        if sx~=0 or sy~=0 then
            local x,y=e.x+sx,e.y+sy;local score=F.distance2Bounded(x,y,tx,ty);local at=#out+1
            while at>1 and score<out[at-1] do
                out[at],out[at+1],out[at+2]=out[at-3],out[at-2],out[at-1];at=at-3
            end
            out[at],out[at+1],out[at+2]=x,y,score
        end
    end
    return out
end
-- Who may be asked to step aside. A unit that is going somewhere is not a bystander and
-- is left alone; so is one holding position, one in the middle of a swing, one that has
-- a target it is fighting, and a worker on a building site, which must stay in work
-- range or construction stalls. A unit that cannot move -- rooted, stunned -- is not
-- asked either: shoving it aside would move a unit its own status holds in place.
-- Everything else is scenery that can shuffle.
local function yieldable(w,e,other,yields)
    if other.id==e.id or other.owner~=e.owner then return false end
    if not Stats.canMove(w,other) then return false end
    if other.goal or other.attack or other.combatTarget then return false end
    local kind=other.order.kind
    if kind=='hold' or kind=='build' then return false end
    if (other.suppressAcquireUntil or -1)>=w.tick then return false end
    return not yields[other.id]
end
-- Which way a bystander steps: perpendicular to the mover's heading, on the side it is
-- already standing. Always stepping the same way made a group part like a zip in one
-- direction and pile up on that side; choosing by which side of the line the bystander
-- sits makes a crowd open down the middle, which is both faster and what it looks like
-- when people get out of the way.
local function aside(e,other,tx,ty)
    local ox,oy=tx-e.x,ty-e.y
    local cross=ox*(other.y-e.y)-oy*(other.x-e.x)
    local sx,sy
    if cross<0 then sx,sy=F.vector(oy,-ox,256) else sx,sy=F.vector(-oy,ox,256) end
    return {x=other.x+sx,y=other.y+sy}
end
-- The move loop holds its neighbour list across several clear() calls, so it uses a
-- buffer of its own rather than the one the proposal scan reuses.
local moveScratch={}
-- Longest wait first, entity id as the tiebreaker: a total order, defined once rather
-- than as a fresh closure on every tick.
local function byWaitThenId(a,b)
    local av,bv=a.e.waitTicks or 0,b.e.waitTicks or 0
    if av~=bv then return av>bv end
    return a.e.id<b.e.id
end
function M.step(w,halt,route)
    Path.step(w)
    local before=bins(w);local proposals={};local yields={}
    for _,id in ipairs(w.order) do local e=w.entities[id]
        if e.alive and e.category=='unit' and e.order.kind~='hold' and Stats.canMove(w,e) then
            local cx,cy=F.cell(e.x),F.cell(e.y);local lx,ly=e.laneX or 0,e.laneY or 0
            local laneArea=e.goal and (not Path.laneAllowed(w,cx,cy,lx,ly) or not Path.laneAllowed(w,cx+ly,cy-lx,lx,ly) or not Path.laneAllowed(w,cx-ly,cy+lx,lx,ly))
            e.opposed=laneArea and opposed(before,e) or nil
            -- The navigation set changed since this path was made: something was built,
            -- destroyed or depleted. Re-check the route once, here, rather than trusting
            -- it until the unit walks into the new obstacle.
            if e.pathVersion and e.pathVersion~=w.navVersion then
                e.pathVersion=w.navVersion
                if e.goal and not Path.pathClear(w,e) then
                    local goal=e.goal;halt(w,e);route(w,e,goal.x,goal.y)
                end
            end
            local node=e.path[e.pathIndex]
            if node then
                if not Path.walkable(w,node.x,node.y) then
                    local goal=e.goal;halt(w,e);if goal then route(w,e,goal.x,goal.y) end
                else
                    local tx,ty=node.px or F.center(node.x),node.py or F.center(node.y)
                    local dx,dy=F.vector(tx-e.x,ty-e.y,speed(w,e))
                    proposals[#proposals+1]={e=e,fx=e.x+dx,fy=e.y+dy,tx=tx,ty=ty}
                    -- A bystander steps out of the road as soon as it is actually in the
                    -- road. The old rule waited for the mover to be stuck for ten ticks
                    -- -- half a second of visible shoving before anyone reacted -- and
                    -- only ever moved units whose order was literally `stop`, so an
                    -- army standing on a finished attack-move was immovable scenery.
                    -- Warcraft 3 parts for a passing unit immediately, and that is most
                    -- of why marching through your own camp there feels like walking
                    -- rather than barging.
                    local nudged=(e.waitTicks or 0)>=3
                    local list,count=nearby(w,before,e.x,e.y)
                    for i=1,count do
                        local other=list[i]
                        if yieldable(w,e,other,yields) then
                            local gap=G.separation(w,e,other)
                            if nudged or F.distance2Bounded(e.x+dx,e.y+dy,other.x,other.y)<gap*gap then
                                yields[other.id]=aside(e,other,tx,ty)
                            end
                        end
                    end
                end
            end
        end
    end
    for _,id in ipairs(w.order) do local e=w.entities[id];local yield=yields[id]
        if yield then
            e.yieldOrigin=e.yieldOrigin or e.restAnchor or {x=e.x,y=e.y}
            local dx,dy=F.vector(yield.x-e.yieldOrigin.x,yield.y-e.yieldOrigin.y,256)
            proposals[#proposals+1]={e=e,choices=choices(w,e,e.yieldOrigin.x+dx,e.yieldOrigin.y+dy),yielding=true}
        end
    end
    table.sort(proposals,byWaitThenId)
    -- The candidate lists use frozen positions. Reservations use the accepted
    -- positions, so a later mover cannot overlap an earlier mover or swap through it.
    -- Nothing has moved since `before` was built, so the reservation index starts as
    -- exactly the same content; it is updated in place below rather than rebuilt from
    -- scratch, which is why the bins are only walked once per tick instead of twice.
    -- `before` is not read again after this point.
    local live=before
    for _,p in ipairs(proposals) do
        local e=p.e;local oldX,oldY=e.x,e.y;local neighbors=nearby(w,live,e.x,e.y,1,moveScratch);local ax,ay
        if not p.choices and clear(w,e,p.fx,p.fy,neighbors) then ax,ay=p.fx,p.fy
        else
            local candidates=p.choices or choices(w,e,p.tx,p.ty)
            for i=1,#candidates,3 do
                local x,y=candidates[i],candidates[i+1]
                if (not p.yielding or F.distance2Bounded(x,y,e.yieldOrigin.x,e.yieldOrigin.y)<=256*256) and clear(w,e,x,y,neighbors) then ax,ay=x,y;break end
            end
        end
        if ax then
            e.x,e.y=ax,ay
            local oldKey,newKey=binKey(oldX,oldY),binKey(e.x,e.y)
            if oldKey~=newKey then
                local old=live[oldKey];for i,id in ipairs(old) do if id==e.id then table.remove(old,i);break end end
                live[newKey]=live[newKey] or {};live[newKey][#live[newKey]+1]=e.id
            end
            if not p.yielding then
                local dist=F.distance2Bounded(e.x,e.y,p.tx,p.ty)
                if not e.bestWaypointDistance or dist<e.bestWaypointDistance then e.waitTicks=0;e.bestWaypointDistance=dist else e.waitTicks=(e.waitTicks or 0)+1 end
                if e.x==p.tx and e.y==p.ty then
                    e.pathIndex=e.pathIndex+1;e.bestWaypointDistance=nil;e.waitTicks=0
                    if not e.path[e.pathIndex] then halt(w,e);e.navigation='arrived' end
                end
            end
        elseif not p.yielding then e.waitTicks=(e.waitTicks or 0)+1 end
        if not p.yielding and (e.waitTicks or 0)>=10 and not e.path[e.pathIndex+1] and e.goal and F.distance2Bounded(e.x,e.y,F.center(e.goal.x),F.center(e.goal.y))<=F.sq(G.radius(w,e)+32) then
            halt(w,e);e.navigation='arrived'
        end
        if not p.yielding and (e.waitTicks or 0)>=10 then
            e.navigation='congested'
            if w.tick>=(e.rerouteAt or 0) and e.goal then
                local cells={}
                for _,other in ipairs(neighbors) do if other.id~=e.id then cells[Path.key(w.map,F.cell(other.x),F.cell(other.y))]=true end end
                e.detour={cells=cells,untilTick=w.tick+40};e.rerouteAt=w.tick+20
                local goal=e.goal;Path.request(w,e,goal.x,goal.y);e.bestWaypointDistance=nil
            end
        elseif not p.yielding and e.goal then e.navigation='moving' end
        if e.detour and e.detour.untilTick<=w.tick then e.detour=nil end
    end
end
return M
