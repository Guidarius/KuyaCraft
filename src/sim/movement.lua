local F=require('src.sim.fixed')
local G=require('src.sim.geometry')
local Path=require('src.sim.path')
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
local function speed(w,e)
    local n=w.content.units[e.kind].speed
    if e.kind=='beastkeeper' and e.stance==2 then n=n+(w.content.rules.pursuitSpeed or 8) end
    if e.sprintUntil and w.tick<e.sprintUntil then n=n+(w.content.rules.sprintSpeed or 12) end
    return n
end
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
        if e.alive and e.category=='unit' and e.order.kind~='hold' then
            local cx,cy=F.cell(e.x),F.cell(e.y);local lx,ly=e.laneX or 0,e.laneY or 0
            local laneArea=e.goal and (not Path.laneAllowed(w,cx,cy,lx,ly) or not Path.laneAllowed(w,cx+ly,cy-lx,lx,ly) or not Path.laneAllowed(w,cx-ly,cy+lx,lx,ly))
            e.opposed=laneArea and opposed(before,e) or nil
            local node=e.path[e.pathIndex]
            if node then
                if not Path.walkable(w,node.x,node.y) then
                    local goal=e.goal;halt(w,e);if goal then route(w,e,goal.x,goal.y) end
                else
                    local tx,ty=node.px or F.center(node.x),node.py or F.center(node.y)
                    local dx,dy=F.vector(tx-e.x,ty-e.y,speed(w,e))
                    proposals[#proposals+1]={e=e,fx=e.x+dx,fy=e.y+dy,tx=tx,ty=ty}
                    if (e.waitTicks or 0)>=10 then
                        for _,other in ipairs(nearby(w,before,e.x,e.y)) do
                            if other.id~=id and other.owner==e.owner and other.order.kind=='stop' and not other.goal and not other.attack and (other.suppressAcquireUntil or -1)<w.tick and F.distance2Bounded(e.x,e.y,other.x,other.y)<F.sq(G.radius(w,e)+G.radius(w,other)+64) and not yields[other.id] then
                                local dx,dy=tx-e.x,ty-e.y;local sx,sy=F.vector(-dy,dx,256)
                                yields[other.id]={x=other.x+sx,y=other.y+sy}
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
            local dx,dy=e.x-oldX,e.y-oldY
            if e.lastMove and dx*e.lastMove.x+dy*e.lastMove.y<0 then e.reversals=(e.reversals or 0)+1 end
            e.lastMove={x=dx,y=dy}
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
            e.blockedTicks=e.waitTicks;e.navigation='congested';e.maxWaitTicks=math.max(e.maxWaitTicks or 0,e.waitTicks)
            if w.tick>=(e.rerouteAt or 0) and e.goal then
                local cells={}
                for _,other in ipairs(neighbors) do if other.id~=e.id then cells[Path.key(w.map,F.cell(other.x),F.cell(other.y))]=true end end
                e.detour={cells=cells,untilTick=w.tick+40};e.rerouteAt=w.tick+20
                local goal=e.goal;Path.request(w,e,goal.x,goal.y);e.bestWaypointDistance=nil
            end
        elseif not p.yielding and e.goal then e.navigation='moving';e.blockedTicks=0 end
        if e.detour and e.detour.untilTick<=w.tick then e.detour=nil end
    end
end
return M
