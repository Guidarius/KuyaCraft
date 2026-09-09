local F = require('src.sim.fixed')
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
function P.request(w,e,gx,gy)
    if not P.walkable(w,gx,gy) then e.blockedReason='destination blocked';e.goal=nil;w.searches[e.id]=nil;return false end
    e.blockedReason=nil
    local sx,sy = F.cell(e.x),F.cell(e.y)
    local start = P.key(w.map,sx,sy)
    local h = heuristic(sx,sy,gx,gy)
    e.laneX=math.abs(gx-sx)>=math.abs(gy-sy) and (gx>=sx and 1 or -1) or 0
    e.laneY=math.abs(gx-sx)<math.abs(gy-sy) and (gy>=sy and 1 or -1) or 0
    e.path,e.pathIndex = {},1
    e.goal = {x=gx,y=gy}
    if not e.detour or e.detour.untilTick<=w.tick then
        local direct=directPath(w,e,sx,sy,gx,gy)
        if direct then e.path=direct;w.searches[e.id]=nil;if #direct==0 then e.goal=nil end;return true end
    end
    w.searches[e.id] = {open={ {x=sx,y=sy,key=start,g=0,h=h,f=h} }, costs={[start]=0},
        closed={}, parents={}, gx=gx,gy=gy, version=w.navVersion, expanded=0, laneX=math.abs(gx-sx)>=math.abs(gy-sy) and (gx>=sx and 1 or -1) or 0, laneY=math.abs(gx-sx)<math.abs(gy-sy) and (gy>=sy and 1 or -1) or 0}
    return true
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
        e.pathIndex=1; w.searches[id]=nil
        if #e.path==0 then
            if e.x~=F.center(s.gx) or e.y~=F.center(s.gy) then e.path={{x=s.gx,y=s.gy}} else e.goal=nil end
        end
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
    for _=1,w.content.rules.pathBudget do
        local found=false
        for _=1,count do
            w.pathCursor=w.pathCursor%count+1
            local id=w.order[w.pathCursor]
            if w.searches[id] then expand(w,id,w.searches[id]); found=true; break end
        end
        if not found then break end
    end
end
return P
