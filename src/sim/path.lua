local F = require('src.sim.fixed')
local G = require('src.sim.geometry')
local P = {}
local dirs = { {0,-1,10}, {1,0,10}, {0,1,10}, {-1,0,10}, {1,-1,14}, {1,1,14}, {-1,1,14}, {-1,-1,14} }
local function less(a,b)
    return a.f<b.f or a.f==b.f and (a.h<b.h or a.h==b.h and a.key<b.key)
end
local function push(heap,node)
    local i=#heap+1
    while i>1 do local parent=math.floor(i/2);if not less(node,heap[parent]) then break end;heap[i]=heap[parent];i=parent end
    heap[i]=node
end
local function pop(heap)
    local first=heap[1];local last=table.remove(heap)
    if #heap>0 then
        local i=1
        while i*2<=#heap do
            local child=i*2
            if child<#heap and less(heap[child+1],heap[child]) then child=child+1 end
            if not less(heap[child],last) then break end
            heap[i]=heap[child];i=child
        end
        heap[i]=last
    end
    return first
end
function P.key(map,x,y) return y * map.width + x + 1 end
function P.walkable(w,x,y)
    return x >= 0 and y >= 0 and x < w.map.width and y < w.map.height and not w.blocked[P.key(w.map,x,y)]
end
-- Keep right through two-cell passages, including their short approach apron.
-- This static rule gives counterflow separate lanes before bodies meet.
local function laneAllowed(w,x,y,lx,ly)
    if lx~=0 then
        for offset=-2,2 do local cx=x+offset
            if P.walkable(w,cx,y) and P.walkable(w,cx,y+lx) and not P.walkable(w,cx,y-lx) and not P.walkable(w,cx,y+2*lx) then return false end
        end
    elseif ly~=0 then
        for offset=-2,2 do local cy=y+offset
            if P.walkable(w,x,cy) and P.walkable(w,x-ly,cy) and not P.walkable(w,x+ly,cy) and not P.walkable(w,x-2*ly,cy) then return false end
        end
    end
    return true
end
function P.laneAllowed(w,x,y,lx,ly)
    if lx==0 and ly==0 then return true end
    if not w.laneCache or w.laneCache.version~=w.navVersion then w.laneCache={version=w.navVersion,values={}} end
    local direction=lx==1 and 0 or lx==-1 and 1 or ly==1 and 2 or 3
    local key=((y+3)*262+x+3)*4+direction
    local value=w.laneCache.values[key]
    if value==nil then value=laneAllowed(w,x,y,lx,ly);w.laneCache.values[key]=value end
    return value
end
function P.lanePosition(w,x,y,r,lx,ly)
    local cx,cy=F.cell(x),F.cell(y)
    if not P.laneAllowed(w,cx,cy,lx,ly) then return false end
    -- Reserve body clearance at the dividing line, not merely separate cells.
    if lx~=0 and not P.laneAllowed(w,cx,cy-lx,lx,ly) then
        if lx>0 and y-cy*256<r or lx<0 and (cy+1)*256-y<r then return false end
    elseif ly~=0 and not P.laneAllowed(w,cx+ly,cy,lx,ly) then
        if ly>0 and (cx+1)*256-x<r or ly<0 and x-cx*256<r then return false end
    end
    return true
end
-- Path smoothing, the string pull.
--
-- A* returns the cell-by-cell parent chain, and walking it literally is what made every
-- march across open ground a staircase of 45-degree hops between cell centres. This
-- keeps only the waypoints that actually constrain the route: a node survives when the
-- straight line past it would put the unit's body through terrain or would break the
-- keep-right rule in a narrow passage. In the open a forty-cell march becomes one
-- straight line; around a corner the route bends at the corner and nowhere else.
--
-- The result is a subsequence of the original nodes. The final node (including its
-- optional precise endpoint) is never dropped: arrival compares against that endpoint.
local function lineClear(w,x0,y0,x1,y1,r,lx,ly)
    local dx,dy=x1-x0,y1-y0
    local span=math.abs(dx)>math.abs(dy) and math.abs(dx) or math.abs(dy)
    -- Never step further than the body radius, so consecutive samples overlap and the
    -- swept circle is covered rather than sampled through.
    local step=r<128 and r or 128
    if step<1 then step=1 end
    local steps=math.floor(span/step)+1
    for i=0,steps do
        if w.metrics.smoothChecks>=(w.content.rules.smoothBudget or 4096) then return nil end
        w.metrics.smoothChecks=w.metrics.smoothChecks+1
        local x=x0+F.mulDiv(dx,i,steps)
        local y=y0+F.mulDiv(dy,i,steps)
        if not G.terrain(w,x,y,r) then return false end
        if not P.laneAllowed(w,F.cell(x),F.cell(y),lx,ly) then return false end
    end
    return true
end
-- How far ahead a single pull may reach. Long enough that an ordinary cross-map march
-- collapses to a handful of segments, and bounded so that smoothing a path stays linear
-- in its length; `rules.smoothBudget` bounds the per-tick total on top of that.
local LOOKAHEAD=32
local function smooth(w,e,path)
    local n=#path
    if n<3 then return path end
    local r=G.radius(w,e)
    if r<=0 then return path end
    -- A congested unit keeps the cell-by-cell path. Local steering resolves a crowd by
    -- making progress toward the *next waypoint*, and it does that by sidestepping: with
    -- a waypoint thirty cells away almost no sidestep reduces the distance, so a unit in
    -- a press stops registering progress and waits instead of filtering through. Fine
    -- waypoints are what let a queue dissolve. Straightening is for the open field, and
    -- a unit that has just been stuck is by definition not in the open field.
    if e.detour and e.detour.untilTick>w.tick then return path end
    if w.metrics.smoothChecks>=(w.content.rules.smoothBudget or 4096) then return path end
    local lx,ly=e.laneX or 0,e.laneY or 0
    local out={}
    local ax,ay=e.x,e.y
    local i=1
    while i<=n do
        local limit=i+LOOKAHEAD;if limit>n then limit=n end
        -- Farthest first, walking back until a straight line is clear. Reachability is
        -- not monotonic along a turning path, so a binary search would settle for a
        -- nearer waypoint and leave a visible kink; taking the first clear line from the
        -- far end always finds the longest jump inside the window. In the open the first
        -- test succeeds, which is also the cheapest case. Every accepted waypoint was
        -- tested as a straight line in its own right, so a dropped node can never put a
        -- body through anything, and the final node survives because the scan stops at it.
        local best=i
        for k=limit,i+1,-1 do
            local clear=lineClear(w,ax,ay,path[k].px or F.center(path[k].x),path[k].py or F.center(path[k].y),r,lx,ly)
            if clear==nil then
                for j=i,n do out[#out+1]=path[j] end
                return out
            end
            if clear then best=k;break end
        end
        out[#out+1]=path[best]
        ax,ay=path[best].px or F.center(path[best].x),path[best].py or F.center(path[best].y)
        i=best+1
    end
    return out
end
P.smooth=smooth
-- Exact endpoints live on orders/goals and therefore survive queues and snapshots.
-- Only the last waypoint is refined; global navigation still works in whole cells.
local function finish(w,e,path)
    local goal=e.goal
    if goal.px then
        if #path==0 then path[1]={x=goal.x,y=goal.y} end
        path[#path].px,path[#path].py=goal.px,goal.py
    end
    e.path=smooth(w,e,path);e.pathIndex=1;e.pathVersion=w.navVersion
    if #path==0 then e.goal=nil end
end
-- Is the route still there? A completed path used to be trusted forever: only the very
-- next waypoint was tested for walkability, so a war hall dropped ten cells ahead went
-- unnoticed until the unit walked into it and spent ten ticks stuck before the
-- congestion reroute fired. In-flight searches already compare against `w.navVersion`;
-- this gives finished paths the same treatment, checked once when that version moves
-- rather than every tick. Only the next few segments are walked, because that is where
-- a new obstacle can matter before the next check.
local SEGMENTS=3
function P.pathClear(w,e)
    local path=e.path
    if not path then return true end
    local x0,y0=e.x,e.y
    for k=0,SEGMENTS-1 do
        local node=path[e.pathIndex+k]
        if not node then return true end
        if not P.walkable(w,node.x,node.y) then return false end
        local x1,y1=node.px or F.center(node.x),node.py or F.center(node.y)
        local dx,dy=x1-x0,y1-y0
        local span=math.abs(dx)>math.abs(dy) and math.abs(dx) or math.abs(dy)
        if span>0 then
            local steps=math.floor(span/128)+1
            for i=0,steps do
                if not P.walkable(w,F.cell(x0+F.mulDiv(dx,i,steps)),F.cell(y0+F.mulDiv(dy,i,steps))) then return false end
            end
        end
        x0,y0=x1,y1
    end
    return true
end
local function heuristic(x,y,gx,gy)
    local dx,dy = math.abs(x-gx),math.abs(y-gy)
    return 10 * math.max(dx,dy) + 4 * math.min(dx,dy)
end
local function directPath(w,e,sx,sy,gx,gy)
    local path={};local x,y=sx,sy
    while x~=gx or y~=gy do
        if w.metrics.directChecks>=w.content.rules.directPathBudget then return nil end
        w.metrics.directChecks=w.metrics.directChecks+1
        local dx=x==gx and 0 or x<gx and 1 or -1
        local dy=y==gy and 0 or y<gy and 1 or -1
        local nx,ny=x+dx,y+dy
        if not P.walkable(w,nx,ny) or not P.laneAllowed(w,nx,ny,e.laneX,e.laneY) or
            (dx~=0 and dy~=0 and (not P.walkable(w,x+dx,y) or not P.walkable(w,x,y+dy))) then return nil end
        path[#path+1]={x=nx,y=ny};x,y=nx,ny
    end
    if #path==0 and (e.x~=F.center(gx) or e.y~=F.center(gy)) then path[1]={x=gx,y=gy} end
    return path
end
function P.request(w,e,gx,gy,independent)
    if not P.walkable(w,gx,gy) then e.blockedReason='destination blocked';e.goal=nil;w.searches[e.id]=nil;return false end
    e.blockedReason=nil
    local sx,sy = F.cell(e.x),F.cell(e.y)
    local start = P.key(w.map,sx,sy)
    local h = heuristic(sx,sy,gx,gy)
    e.laneX=math.abs(gx-sx)>=math.abs(gy-sy) and (gx>=sx and 1 or -1) or 0
    e.laneY=math.abs(gx-sx)<math.abs(gy-sy) and (gy>=sy and 1 or -1) or 0
    e.path,e.pathIndex = {},1
    e.goal = {x=gx,y=gy}
    if e.order.x==gx and e.order.y==gy then e.goal.px,e.goal.py=e.order.px,e.order.py end
    if not e.detour or e.detour.untilTick<=w.tick then
        local direct=directPath(w,e,sx,sy,gx,gy)
        if direct then finish(w,e,direct);w.searches[e.id]=nil;return true end
    end
    local group=not independent and w.content.rules.sharedPaths and e.order.group
    if e.detour and e.detour.untilTick>w.tick then group=nil end
    if e.order.x~=gx or e.order.y~=gy then group=nil end
    local radius=G.radius(w,e)
    if group then
        for _,id in ipairs(w.order) do
            local s=w.searches[id];local other=w.entities[id]
            if id~=e.id and s and not s.leader and other.alive and other.goal and
                s.group==group and s.owner==e.owner and s.version==w.navVersion and
                s.radius==radius and s.laneX==e.laneX and s.laneY==e.laneY and
                math.abs(s.sx-sx)<=12 and math.abs(s.sy-sy)<=12 and
                math.abs(s.gx-gx)<=12 and math.abs(s.gy-gy)<=12 then
                w.searches[e.id]={leader=id,leaderGX=s.gx,leaderGY=s.gy,gx=gx,gy=gy,
                    group=group,owner=e.owner,version=w.navVersion,radius=radius,laneX=e.laneX,laneY=e.laneY}
                return true
            end
        end
    end
    w.searches[e.id] = {open={ {x=sx,y=sy,key=start,g=0,h=h,f=h} }, costs={[start]=0},
        sx=sx,sy=sy,group=group,owner=e.owner,radius=radius,
        closed={}, parents={}, gx=gx,gy=gy, version=w.navVersion, expanded=0, laneX=math.abs(gx-sx)>=math.abs(gy-sy) and (gx>=sx and 1 or -1) or 0, laneY=math.abs(gx-sx)<math.abs(gy-sy) and (gy>=sy and 1 or -1) or 0}
    return true
end
-- Share terrain work, not a unit's steering or its destination. Followers connect
-- to a nearby raw waypoint and receive their own chain and their own final slot.
-- Both connectors consume the existing direct-route budget. A failed connection
-- falls back to ordinary A*, and congestion always reroutes independently.
local function followers(w,id,path)
    for _,otherId in ipairs(w.order) do
        local s=w.searches[otherId]
        if s and s.leader==id then
            local e=w.entities[otherId]
            if not e.alive or not e.goal then w.searches[otherId]=nil
            else
                local prefix,join
                for k=math.min(16,#path),1,-1 do
                    local n=path[k]
                    if math.abs(n.x-F.cell(e.x))<=16 and math.abs(n.y-F.cell(e.y))<=16 then
                        prefix=directPath(w,e,F.cell(e.x),F.cell(e.y),n.x,n.y)
                        if prefix then join=k;break end
                    end
                end
                local last=path[#path]
                local suffix=last and (last.x==s.gx and last.y==s.gy and {} or directPath(w,e,last.x,last.y,s.gx,s.gy))
                if prefix and suffix then
                    for k=join+1,#path do local n=path[k];prefix[#prefix+1]={x=n.x,y=n.y} end
                    for k=1,#suffix do prefix[#prefix+1]=suffix[k] end
                    finish(w,e,prefix);w.searches[otherId]=nil
                else P.request(w,e,s.gx,s.gy,true) end
            end
        end
    end
end
local function expand(w,id,s)
    local e = w.entities[id]
    if not e or not e.alive or not e.goal then w.searches[id]=nil; return end
    if s.version ~= w.navVersion then if not P.request(w,e,s.gx,s.gy) then w.searches[id]=nil;e.goal=nil;e.blockedReason='destination blocked' end; return end
    if #s.open == 0 then e.goal=nil; e.blockedReason='unreachable'; w.searches[id]=nil; return end
    local n=pop(s.open)
    if s.closed[n.key] then return end
    s.closed[n.key]=true; s.expanded=s.expanded+1; w.metrics.pathExpansions=w.metrics.pathExpansions+1
    if n.x==s.gx and n.y==s.gy then
        local reverse,key={},n.key
        while s.parents[key] do
            reverse[#reverse+1]={x=(key-1)%w.map.width,y=math.floor((key-1)/w.map.width)}
            key=s.parents[key]
        end
        e.path={}
        for i=#reverse,1,-1 do e.path[#e.path+1]=reverse[i] end
        if #e.path==0 then
            if e.x~=F.center(s.gx) or e.y~=F.center(s.gy) then e.path={{x=s.gx,y=s.gy}} end
        end
        followers(w,id,e.path)
        finish(w,e,e.path);w.searches[id]=nil
        return
    end
    for i=1,#dirs do
        local d=dirs[i]; local x,y=n.x+d[1],n.y+d[2]
        if P.walkable(w,x,y) and ((x==s.gx and y==s.gy) or P.laneAllowed(w,x,y,s.laneX,s.laneY)) and (i<=4 or (P.walkable(w,n.x+d[1],n.y) and P.walkable(w,n.x,n.y+d[2]))) then
            local key=P.key(w.map,x,y); local penalty=e.detour and e.detour.untilTick>w.tick and e.detour.cells[key] and 80 or 0;local lane=not P.walkable(w,x+s.laneY,y-s.laneX) and 60 or 0;local cost=n.g+d[3]+penalty+lane
            if not s.closed[key] and (not s.costs[key] or cost<s.costs[key]) then
                s.costs[key]=cost; s.parents[key]=n.key
                local h=heuristic(x,y,s.gx,s.gy)
                push(s.open,{x=x,y=y,key=key,g=cost,h=h,f=cost+h})
            end
        end
    end
end
function P.step(w)
    local count=#w.order
    if count==0 then return end
    -- Rebuild the small active schedule in stable world order. Waiting followers
    -- spend no expansions; cancelled/dead leaders cause deterministic promotion.
    local active={}
    for index,id in ipairs(w.order) do
        local s=w.searches[id]
        if s and s.leader then
            local leader=w.searches[s.leader];local source=w.entities[s.leader]
            if s.version~=w.navVersion or not leader or leader.leader or not source.alive or not source.goal or
                leader.gx~=s.leaderGX or leader.gy~=s.leaderGY or leader.group~=s.group then
                local e=w.entities[id]
                if e.alive and e.goal then P.request(w,e,s.gx,s.gy) else w.searches[id]=nil end
                s=w.searches[id]
            end
        end
        if s and not s.leader then active[#active+1]={id=id,index=index} end
    end
    if #active==0 then return end
    local cursor=0
    for i=1,#active do if active[i].index<=w.pathCursor then cursor=i end end
    for _=1,w.content.rules.pathBudget do
        local found=false
        for _=1,#active do
            cursor=cursor%#active+1
            local entry=active[cursor];local s=w.searches[entry.id]
            if s and not s.leader then
                w.pathCursor=entry.index;expand(w,entry.id,s);found=true;break
            end
        end
        if not found then break end
    end
end
return P
