local F = require('src.sim.fixed')

local Codec = require('src.sim.codec')
local Path = require('src.sim.path')
local G=require('src.sim.geometry')
local Movement=require('src.sim.movement')
local Carriers=require('src.sim.carriers')
local Vision=require('src.sim.vision')
-- Version 5: replay/network checkpoints hash authoritative state only. Older
-- replays store whole-world hashes and are rejected rather than misreported as
-- divergence. See Sim.serializeAuthoritative.
-- Version 6: rally points, patrol and follow orders; per-player and per-entity kill
-- and loss tallies; a `delivered` event carrying the exact amount and resource.
-- Version 7: write-only entity state removed (reversals, maxWaitTicks, blockedTicks,
-- harvestStatus, lastMove) along with the unused PRNG, so checkpoints stop hashing
-- fields nothing reads. No rule changes.
local Sim = { VERSION = 8 }
local function ids(w) return w.order end
local function def(w,e) return w.content.units[e.kind] or w.content.buildings[e.kind] end
-- emit takes ownership of its payload: every caller builds a fresh table for the
-- call, so copying it defensively duplicated one table per event per tick for no
-- observable difference. Events live only for the tick that produced them and are
-- excluded from snapshots and canonical serialization, so this cannot reach state.
-- Callers must therefore not pass a table they still hold (see the victory site).
local function emit(w,kind,data)
    data=data or {};data.kind=kind;data.tick=w.tick;data.index=#w.events+1;data.audience={}
    local e=w.entities[data.entity or data.target or data.source]
    if e then data.x=e.x;data.y=e.y;data.owner=e.owner;data.unitKind=e.kind end
    for player=1,#w.players do
        local permitted=data.player and data.player==player or not data.player and (not e or e.owner==player or Sim.visible(w,player,e))
        -- An impact may be heard by the victim's owner without revealing a hidden attacker.
        if permitted then data.audience[player]=true end
    end
    local source=w.entities[data.source]
    if source then data.sx=source.x;data.sy=source.y;data.sourceAudience={};for player=1,#w.players do if Sim.visible(w,player,source) then data.sourceAudience[player]=true end end end
    w.events[#w.events+1]=data
end
-- Event payloads are flat: every field is a scalar except the two audience sets,
-- which are removed here anyway. A shallow copy is therefore exactly equivalent
-- to the canonical deep copy this used to make, at a fraction of the cost.
function Sim.eventsFor(w,player)
    local out={}
    for _,event in ipairs(w.events) do if event.audience[player] then
        local copy={}
        for key,value in pairs(event) do copy[key]=value end
        copy.audience=nil
        local source=w.entities[copy.source]
        if source and not (event.sourceAudience and event.sourceAudience[player]) then copy.source=nil;copy.sx=nil;copy.sy=nil end;copy.sourceAudience=nil
        out[#out+1]=copy
    end end
    return out
end
local function occupied(w,x,y,except)
    for _,id in ipairs(ids(w)) do
        local e=w.entities[id]
        if e.alive and e.category=='unit' and e.id~=except and G.rectangleDistance2(e.x,e.y,x*256,y*256,(x+1)*256,(y+1)*256)<F.sq(G.radius(w,e)) then return true end
    end
    return false
end
-- Free-cell search, outward ring by ring. The ring used to be found by walking the
-- whole (2r+1)^2 square and discarding everything but its edge, which makes the search
-- cubic in the radius to produce a quadratic number of candidates; each candidate also
-- cost a table and each ring a fresh comparator. Now only the perimeter is walked, into
-- reused parallel arrays sorted through an index permutation.
--
-- Candidates are ordered by (distance, cell key), a total order over distinct cells, so
-- the result does not depend on the order they were found in and this returns exactly
-- what the square scan did.
local candX,candY,candKey,candDistance={},{},{},{}
local candOrder={}
local function lessCandidate(a,b)
    if candDistance[a]~=candDistance[b] then return candDistance[a]<candDistance[b] end
    return candKey[a]<candKey[b]
end
local function nearest(w,x,y,except,claimed,radius)
    radius=radius or (except and G.radius(w,w.entities[except])) or 112
    local unit=except and w.entities[except]
    local map=w.map;local width,height=map.width,map.height
    local ux,uy=0,0;if unit then ux,uy=unit.x,unit.y end
    -- Not re-entrant: the scratch arrays are shared. Nothing reachable from G.free or
    -- Path.walkable calls back into this, and every caller is a leaf of one step phase.
    local count=0
    local function consider(cx,cy)
        if cx<0 or cy<0 or cx>=width or cy>=height then return end
        local key=Path.key(map,cx,cy)
        if (claimed and claimed[key]) or not Path.walkable(w,cx,cy) then return end
        count=count+1
        candX[count]=cx;candY[count]=cy;candKey[count]=key
        candDistance[count]=unit and F.distance2Bounded(ux,uy,F.center(cx),F.center(cy)) or 0
    end
    for r=0,math.max(width,height) do
        count=0
        if r==0 then consider(x,y)
        else
            for cx=x-r,x+r do consider(cx,y-r);consider(cx,y+r) end
            for cy=y-r+1,y+r-1 do consider(x-r,cy);consider(x+r,cy) end
        end
        if count>0 then
            for i=1,count do candOrder[i]=i end
            for i=#candOrder,count+1,-1 do candOrder[i]=nil end
            table.sort(candOrder,lessCandidate)
            for i=1,count do
                local c=candOrder[i]
                if G.free(w,F.center(candX[c]),F.center(candY[c]),radius,except) then return candX[c],candY[c] end
            end
        end
    end
end

-- Single definition of how w.blocked derives from the map and standing buildings,
-- shared with the regression test that proves the derivation (see Sim.recomputeBlocked).
local function rebuild(w) w.blocked=Sim.recomputeBlocked(w) end
local function spawn(w,kind,owner,x,y,category)
    G.invalidate(w)
    local d=w.content.units[kind] or w.content.buildings[kind]
    local id=w.nextId; w.nextId=id+1
    local e={id=id,kind=kind,owner=owner,x=F.center(x),y=F.center(y),category=category or 'unit',
        alive=true,hp=d and d.hp or 1,maxHp=d and d.hp or 1,size=d and d.size or 1,cooldown=0,
        path={},pathIndex=1,order={kind='stop'},orders={},lastCombat=-1000}
    if d and d.hero then e.xp=0; e.upgrades={}; e.stance=1 end
    if category=='building' then e.queue={}; e.remaining=0 end
    w.entities[id]=e; w.order[#w.order+1]=id
    return e
end
local function inRange(e,t,range)
    local tx,ty=t.x,t.y
    if t.category=='building' or t.category=='node' then
        tx=math.max(t.x-128,math.min(e.x,t.x-128+t.size*256))
        ty=math.max(t.y-128,math.min(e.y,t.y-128+t.size*256))
    end
    return F.distance2Bounded(e.x,e.y,tx,ty)<=range*range
end
local function halt(w,e)
    if #e.path>0 then e.path={} end;e.pathIndex=1;e.goal=nil;e.waitTicks=0;e.bestWaypointDistance=nil;w.searches[e.id]=nil
end
local function route(w,e,x,y)
    if not e.goal or e.goal.x~=x or e.goal.y~=y then Path.request(w,e,x,y) end
end
local function approachTarget(w,e,t,range)
    if inRange(e,t,range) then halt(w,e); return true end
    if not e.goal and not w.searches[e.id] and w.tick>=(e.retryAt or 0) then
        local x,y
        if w.content.rules.profile and (t.category=='building' or t.category=='node') then
            local score;local r=math.ceil(range/256)
            for cy=math.max(0,F.cell(t.y)-r),math.min(w.map.height-1,F.cell(t.y)+t.size+r-1) do
                for cx=math.max(0,F.cell(t.x)-r),math.min(w.map.width-1,F.cell(t.x)+t.size+r-1) do
                    local px,py=F.center(cx),F.center(cy);local dist=F.distance2Bounded(e.x,e.y,px,py)
                    if (not score or dist<score) and inRange({x=px,y=py},t,range) and G.free(w,px,py,G.radius(w,e),e.id) then x,y,score=cx,cy,dist end
                end
            end
        else x,y=nearest(w,F.cell(t.x),F.cell(t.y),e.id) end
        if x then route(w,e,x,y) end
        e.retryAt=w.tick+20
    end
    return false
end
local sightSpans={}
-- Scratch reused across ticks and players. Sight marking writes a sparse +1/-1 delta
-- per covered row; the flush then prefix-sums each row. Both used to be rebuilt from
-- nothing every tick, and the flush scanned the entire map width for every covered
-- row, so a 128x112 map cost about 14,000 iterations per player per tick regardless
-- of how much of it anyone could actually see. Tracking the covered rows and the span
-- of each makes the cost proportional to what is visible. Every delta written is
-- cleared during the flush that consumes it, so these never leak between worlds.
local rowDeltas={}
local rowMin,rowMax,rowList={},{},{}
local function visibility(w)
    local width,height=w.map.width,w.map.height
    for p=1,#w.players do
        local player=w.players[p]
        -- Reused rather than replaced: this table is shared by reference into views.
        local visible=player.visible
        if visible then for key in pairs(visible) do visible[key]=nil end else visible={};player.visible=visible end
        local explored=player.explored
        player.knownResources=player.knownResources or {}
        -- Line of sight walks each observer's own shadow field, so overlapping armies
        -- cannot share the work the way the radial span fill does. Radial visibility
        -- stays available as a content rule for maps and profiles that want it, and
        -- because it is markedly cheaper with a large army on screen.
        if w.content.rules.lineOfSight then
            for _,id in ipairs(w.order) do local e=w.entities[id]
                if e.alive and e.owner==p then Vision.field(w,e,def(w,e).sight,visible,explored) end
            end
            Sim.knownResources(w,p,player)
        else
        local rowCount=0
        for _,id in ipairs(w.order) do local e=w.entities[id]
            if e.alive and e.owner==p then
                local sight=def(w,e).sight;local spans=sightSpans[sight]
                if not spans then spans={};for dy=-sight,sight do spans[dy]=F.isqrt(sight*sight-dy*dy) end;sightSpans[sight]=spans end
                local cx,cy=F.cell(e.x),F.cell(e.y)
                local top=cy-sight;if top<0 then top=0 end
                local bottom=cy+sight;if bottom>height-1 then bottom=height-1 end
                for y=top,bottom do
                    local reach=spans[y-cy]
                    local row=rowDeltas[y];if not row then row={};rowDeltas[y]=row end
                    local left=cx-reach;if left<0 then left=0 end
                    local right=cx+reach;if right>width-1 then right=width-1 end
                    right=right+1
                    if rowMin[y] then
                        if left<rowMin[y] then rowMin[y]=left end
                        if right>rowMax[y] then rowMax[y]=right end
                    else
                        rowCount=rowCount+1;rowList[rowCount]=y;rowMin[y]=left;rowMax[y]=right
                    end
                    row[left]=(row[left] or 0)+1;row[right]=(row[right] or 0)-1
                end
            end
        end
        -- Prefix-sum sight intervals before touching cells. Same circular visibility,
        -- much less repeated work for a packed army; all caches derive solely from sight.
        -- Every +1 is matched by a -1 at or before rowMax, so coverage is back to zero
        -- by the end of the span and nothing outside it could have been visible.
        for i=1,rowCount do
            local y=rowList[i];local row=rowDeltas[y];local base=y*width+1
            local coverage=0
            for x=rowMin[y],rowMax[y] do
                local delta=row[x]
                if delta then coverage=coverage+delta;row[x]=nil end
                if coverage>0 then local key=base+x;visible[key]=true;explored[key]=true end
            end
            rowMin[y]=nil;rowMax[y]=nil
        end
        Sim.knownResources(w,p,player)
        end
    end
end
-- Resource nodes never move, so a remembered entry stays correct for as long as it
-- exists; rebuilding one per visible node per tick allocated thousands of identical
-- tables a second. Only a first sighting or a witnessed depletion changes anything, and
-- an unseen node keeps whatever was last observed.
function Sim.knownResources(w,p,player)
    if not w.content.rules.profile then return end
    local known=player.knownResources
    for _,id in ipairs(w.order) do local n=w.entities[id]
        if n.category=='node' and Sim.visible(w,p,n) then
            if not n.alive then known[id]=nil
            elseif not known[id] then known[id]={id=id,x=n.x,y=n.y,size=n.size,resource=n.resource} end
        end
    end
end
function Sim.visible(w,player,e)
    if e.owner==player then return true end
    local p=w.players[player]
    if not p then return false end
    if (e.size or 1)==1 then return p.visible[Path.key(w.map,F.cell(e.x),F.cell(e.y))]==true end
    for y=F.cell(e.y),F.cell(e.y)+(e.size or 1)-1 do
        for x=F.cell(e.x),F.cell(e.x)+(e.size or 1)-1 do
            if p.visible[Path.key(w.map,x,y)] then return true end
        end
    end
    return false
end
-- A view is a read-only observation, produced once per tick per observer and
-- also inside build validation. It used to deep-copy the immutable map and every
-- entity wholesale, then delete the fields an enemy must not see. Both halves were
-- expensive: map.blocked alone is thousands of sorted keys that never change, and
-- copy-then-delete means the cost of a field is paid before it is discarded.
--
-- Instead the observable surface is an explicit whitelist. Anything not named here
-- -- schedulers, searches, detours, lane state, reservation bookkeeping -- is not
-- observable by anyone, so a new private field cannot leak by default. Immutable
-- world data is shared by reference; callers must treat views as read-only.
local VIEW_FIELDS={'id','kind','owner','x','y','category','alive','hp','maxHp','size','cooldown',
    'deathTick','navigation','blockedReason','lastOrderFailure','waitTicks','pathIndex','combatTarget',
    'nextCommitTick','attackTick','remaining','produced','researchRemaining',
    'reviveRemaining','resource','amount','campTier','stance','xp','healthCapacity','kills','payload','mine'}
-- Fields an observer may only see on entities it owns.
local OWNER_FIELDS={'researchRemaining','reviveRemaining','xp','payload','mine'}
local ownerOnly={};for _,name in ipairs(OWNER_FIELDS) do ownerOnly[name]=true end
local function shallow(t) local out={};for key,value in pairs(t) do out[key]=value end;return out end
local function shallowArray(t) local out={};for i=1,#t do out[i]=shallow(t[i]) end;return out end
local function viewEntity(w,e,own)
    local copy={}
    for i=1,#VIEW_FIELDS do
        local name=VIEW_FIELDS[i]
        if own or not ownerOnly[name] then copy[name]=e[name] end
    end
    -- Order/queue shapes are tables; an enemy sees a unit standing still with nothing queued.
    -- Orders, queue entries and upgrades are flat records of scalars, so a shallow
    -- copy is equivalent to the canonical one and skips building and sorting a key
    -- array per record -- which, at two per own unit per tick, dominated view cost.
    if own then
        copy.order=shallow(e.order);copy.orders=shallowArray(e.orders)
        if e.queue then copy.queue=shallowArray(e.queue) end
        if e.upgrades then copy.upgrades=shallow(e.upgrades) end
        if e.goal then copy.goal={x=e.goal.x,y=e.goal.y} end
        -- A rally point is your own standing policy and is drawn for you alone.
        if e.rally then copy.rally={x=e.rally.x,y=e.rally.y,target=e.rally.target} end
        copy.pathLength=#e.path
    else
        copy.order={kind='stop'};copy.orders={};copy.pathLength=0
    end
    if e.home then copy.home={x=e.home.x,y=e.home.y} end
    -- The attack phase drives animation for both sides; the target id is private.
    local a=e.attack
    if a then copy.attack={start=a.start,impact=a.impact,finish=a.finish,period=a.period,dx=a.dx,dy=a.dy,target=own and a.target or nil} end
    return copy
end
function Sim.view(w,player)
    local p=w.players[player]
    local out={tick=w.tick,result=w.result,
        map={width=w.map.width,height=w.map.height,starts=w.map.starts,anchors=w.map.anchors,blocked=w.map.blocked},
        entities={},byId={},
        player={faction=p.faction,hq=p.hq,hero=p.hero,sequence=p.sequence,defeated=p.defeated,tech=p.tech,
            kills=p.kills,unitsLost=p.unitsLost,buildingsLost=p.buildingsLost,
            resources=Codec.copy(p.resources),visible=p.visible,explored=p.explored,knownResources=p.knownResources}}
    for _,id in ipairs(ids(w)) do
        local e=w.entities[id]
        if (e.alive or e.owner==player or (e.deathTick and w.tick-e.deathTick<40)) and Sim.visible(w,player,e) then
            local copy=viewEntity(w,e,e.owner==player)
            out.entities[#out.entities+1]=copy;out.byId[id]=copy
        end
    end
    return out
end
function Sim.create(config,content,map)
    F.check(map.width,8,256); F.check(map.height,8,256)
    assert(#config.players>=2 and #config.players<=4,'two to four players required')
    -- Content is a shared, immutable definition table: nothing in the simulation
    -- writes to it, and 'content references and definition isolation' fails if that
    -- ever stops being true. Holding a reference avoids deep-copying the whole
    -- catalogue on every world creation, which replay seeking does repeatedly.
    -- The map is still copied, because callers do build worlds by editing a map.
        -- The simulation is deliberately free of randomness: no damage variance, no
    -- scatter, no rolls. Every outcome follows from orders and content alone, which is
    -- what makes a replay reproduce exactly. src/sim/rng.lua and its golden-sequence
    -- test are kept so randomness can be reintroduced as a considered change rather
    -- than rebuilt from nothing; config.seed is retained as part of match identity.
    local w={version=Sim.VERSION,tick=0,config=Codec.copy(config),content=Codec.copy(content),map=Codec.copy(map),
        players={},entities={},order={},nextId=1,searches={},pathCursor=0,navVersion=0,blocked={},events={},metrics={pathExpansions=0,directChecks=0}}
    for p=1,#config.players do
        local faction=config.players[p].faction or 'bastion'
        assert(content.factions[faction],'unknown faction')
        w.players[p]={faction=faction,resources=Codec.copy(content.rules.startingResources or {gold=650}),sequence=0,visible={},explored={},defeated=false,
            kills=0,unitsLost=0,buildingsLost=0}
    end
    for _,node in ipairs(map.resources or {}) do
        F.check(node.x,0,map.width-1); F.check(node.y,0,map.height-1)
        local e=spawn(w,'resource',0,node.x,node.y,'node'); e.resource=node.resource; e.amount=node.amount;e.size=node.size or 1
    end
    for p=1,#w.players do
        local start=map.starts[p]
        local hq=spawn(w,'hq',p,start.x,start.y,'building'); w.players[p].hq=hq.id
    end
    rebuild(w)
    for p=1,#w.players do
        local start=map.starts[p]; local faction=content.factions[w.players[p].faction]
        local initial={faction.hero,'worker','worker',faction.roster[1],faction.roster[2]}
        if content.rules.startingWorkers then initial={faction.hero};for _=1,content.rules.startingWorkers do initial[#initial+1]='worker' end end
        for slot,kind in ipairs(initial) do
            local x,y=nearest(w,start.x+3,start.y+3,nil,nil,content.units[kind].radius)
            if content.rules.profile and map.unitStarts and map.unitStarts[p] and map.unitStarts[p][slot] then x=map.unitStarts[p][slot].x;y=map.unitStarts[p][slot].y;assert(G.free(w,F.center(x),F.center(y),content.units[kind].radius),'invalid authored spawn') end
            assert(x,'map has no spawn space')
            local e=spawn(w,kind,p,x,y)
            if content.units[kind].hero then w.players[p].hero=e.id end
        end
    end
    for _,camp in ipairs(map.camps or {}) do
        local e=spawn(w,camp.kind or 'neutral',0,camp.x,camp.y); e.home={x=e.x,y=e.y};e.campTier=camp.tier
    end
    visibility(w)
    return w
end
local function afford(player,cost)
    for _,key in ipairs(Codec.keys(cost)) do if (player.resources[key] or 0)<cost[key] then return false end end
    return true
end
local function spend(player,cost,sign)
    for _,key in ipairs(Codec.keys(cost)) do player.resources[key]=(player.resources[key] or 0)-(sign or 1)*cost[key] end
end
function Sim.population(w,p)
    local n=0
    for _,id in ipairs(ids(w)) do
        local e=w.entities[id]
        if e.owner==p then
            if e.category=='unit' and (e.alive or (def(w,e).hero and w.content.rules.profile)) then n=n+(def(w,e).food or 1) end
            if e.alive and e.queue then for _,q in ipairs(e.queue) do n=n+(w.content.units[q.kind].food or 1) end end
        end
    end
    return n
end
function Sim.unitCount(w,p)
    local count=0;for _,id in ipairs(w.order) do local e=w.entities[id];if e.alive and e.owner==p and e.category=='unit' then count=count+1 end end;return count
end
function Sim.revival(content,hero)
    local tiers=0;for _,threshold in ipairs(content.rules.xpThresholds) do if (hero.xp or 0)>=threshold then tiers=tiers+1 end end
    return content.rules.reviveCost+tiers*(content.rules.reviveTierCost or 0),content.rules.reviveTicks+tiers*(content.rules.reviveTierTicks or 0)
end
-- The gold mine whose footprint exactly matches this one, if there is such a mine.
-- An extractor may only be built on a mine, and only squarely on it.
function Sim.mineAt(view,x,y,size)
    for _,e in ipairs(view.entities) do
        if e.alive and e.category=='node' and e.resource=='gold'
            and F.cell(e.x)==x and F.cell(e.y)==y and e.size==size then return e end
    end
end
function Sim.placement(view,content,kind,x,y)
    local d=content.buildings[kind]
    if not d or kind=='hq' or not F.integer(x,0,view.map.width-d.size) or not F.integer(y,0,view.map.height-d.size) then return false,'Outside map' end
    if not afford(view.player,d.cost) then return false,'Insufficient resources' end
    local mine
    if d.extractor then
        local found=Sim.mineAt(view,x,y,d.size)
        if not found then return false,'Extractors go on a gold mine' end
        if found.amount and found.amount<=0 then return false,'Mine is exhausted' end
        mine=found.id
    end
    for cy=y,y+d.size-1 do for cx=x,x+d.size-1 do
        local key=cy*view.map.width+cx+1
        -- An extractor's footprint is exactly the mine's. Seeing the mine is the whole
        -- of what you need to know to put a building on it, and mines sit against
        -- terrain that hides a cell or two of their own footprint often enough that the
        -- per-cell rule would arbitrarily rule out some of them.
        if not mine and not view.player.visible[key] then return false,'Unseen footprint' end
        if not mine and view.map.blocked[key] then return false,'Impassable terrain' end
        for _,other in ipairs(view.entities) do
            if other.alive and other.category=='unit' and G.rectangleDistance2(other.x,other.y,cx*256,cy*256,(cx+1)*256,(cy+1)*256)<F.sq(content.units[other.kind].radius) then return false,'Occupied footprint' end
            -- An extractor is placed on its mine, so the mine it covers is not in its way.
            -- Carriers never obstruct anything.
            if other.alive and other.category~='unit' and other.category~='carrier' and other.id~=mine
                and cx>=F.cell(other.x) and cx<F.cell(other.x)+other.size and cy>=F.cell(other.y) and cy<F.cell(other.y)+other.size then return false,'Occupied footprint' end
        end
    end end
    return true,'Ready to build'
end
local function clearCombat(e)
    e.attack=nil;e.attackTick=nil;e.combatTarget=nil;e.engagement=nil;e.retryAt=nil;e.yieldOrigin=nil;e.rangeLatch=nil;e.rangeLostAt=nil;e.chaseTarget=nil;e.chaseX=nil;e.chaseY=nil
end
local function setOrder(w,e,order,append)
    if append and e.order.kind~='stop' then
        if #e.orders>=32 then return false end
        e.orders[#e.orders+1]=order
    else
        local old=e.order
        e.rally=e.rally
        local same=old.kind==order.kind and old.target==order.target and old.x==order.x and old.y==order.y
        e.orders={}
        if same and (order.kind=='move' or order.kind=='attack_move' or order.kind=='attack') then return true end
        halt(w,e);clearCombat(e);e.order=order;e.reroutes=0;e.blockedReason=nil;e.lastOrderFailure=nil;e.restAnchor=nil;e.navigation='idle';e.detour=nil;e.rerouteAt=nil
        e.suppressAcquireUntil=w.tick
        if order.x then route(w,e,order.x,order.y) end
    end
    return true
end
Sim.setOrder=setOrder
local function nextOrder(w,e)
    local blocked=e.blockedReason
    local rest=e.order.x and {x=F.center(e.order.x),y=F.center(e.order.y)} or nil
    halt(w,e);clearCombat(e);e.order=table.remove(e.orders,1) or {kind='stop'};e.reroutes=0;e.blockedReason=nil
    e.navigation=blocked and 'failed' or 'idle';e.lastOrderFailure=blocked;e.restAnchor=e.order.kind=='stop' and not blocked and rest or nil
    if e.order.x then route(w,e,e.order.x,e.order.y) end
end
local function reject(w,c,reason) emit(w,'rejected',{player=c.player or 0,sequence=c.sequence or 0,reason=reason}) end
local commandKinds={move=true,attack=true,attack_move=true,stop=true,hold=true,build=true,recruit=true,toggle=true,upgrade=true,revive=true,cancel=true,research=true,
    rally=true,patrol=true,follow=true}
-- Orders that take a destination slot and are reserved against other units' slots.
local destinationKinds={move=true,attack_move=true,patrol=true}
local function apply(w,c)
    if type(c)~='table' or not F.integer(c.player,1,#w.players) or not F.integer(c.sequence,1,2147483646) or c.tick~=w.tick or not commandKinds[c.kind] or type(c.args)~='table' then
        reject(w,type(c)=='table' and c or {},'malformed command'); return
    end
    local p=w.players[c.player]
    if p.defeated or c.sequence<=p.sequence then reject(w,c,'duplicate, stale, or defeated'); return end
    p.sequence=c.sequence
    local a=c.args
    local e=F.integer(a.entity,1) and w.entities[a.entity] or nil
    if not e or e.owner~=c.player then reject(w,c,'invalid ownership'); return end
    local d=def(w,e)
    if a.append~=nil and type(a.append)~='boolean' then reject(w,c,'invalid queue flag');return end
    if a.group~=nil and not F.integer(a.group,1,2147483646) then reject(w,c,'invalid command group');return end
    if a.append and c.kind~='stop' and c.kind~='hold' and #e.orders>=32 then reject(w,c,'order queue full');return end
    if c.kind=='revive' then
        local hq=w.entities[p.hq]
        local cost,ticks=Sim.revival(w.content,e)
        if not d.hero or e.alive or e.reviveRemaining or not hq.alive or not afford(p,{gold=cost}) then reject(w,c,'cannot revive'); return end
        spend(p,{gold=cost}); e.reviveRemaining=ticks; return
    end
    if not e.alive then reject(w,c,'entity is dead'); return end
    if c.kind=='toggle' then
        if not d.hero then reject(w,c,'not a hero'); return end
        e.stance=e.stance==1 and 2 or 1; return
    elseif c.kind=='upgrade' then
        if not d.hero or not F.integer(a.milestone,1,3) or not F.integer(a.choice,1,2) or e.xp<w.content.rules.xpThresholds[a.milestone] or e.upgrades[a.milestone] or a.milestone>1 and not e.upgrades[a.milestone-1] then reject(w,c,'invalid upgrade'); return end
        e.upgrades[a.milestone]=a.choice;emit(w,'upgraded',{entity=e.id,milestone=a.milestone,choice=a.choice})
        if a.milestone==2 and a.choice==2 then local bonus=w.content.rules.heroHealth and w.content.rules.heroHealth[e.kind] or 180;e.maxHp=e.maxHp+bonus;e.hp=e.hp+bonus end
        return
    elseif c.kind=='research' then
        local tech=w.content.rules.tech
        if not tech or e.kind~='hq' or e.remaining>0 or p.tech or e.researchRemaining or not afford(p,tech.cost) then reject(w,c,'cannot research');return end
        spend(p,tech.cost);e.researchRemaining=tech.ticks;return
    elseif c.kind=='recruit' then
        local ud=w.content.units[a.unit]
        local allowed=a.unit=='worker' and e.kind=='hq'
        if e.kind=='barracks' then
            for _,kind in ipairs(w.content.factions[p.faction].roster) do if kind==a.unit then allowed=true end end
        end
        if not ud or not allowed or e.remaining>0 or #e.queue>=5 or (ud.tech and not p.tech) or Sim.population(w,c.player)+(ud.food or 1)>w.content.rules.population or not afford(p,ud.cost) then reject(w,c,'cannot recruit'); return end
        spend(p,ud.cost); e.queue[#e.queue+1]={kind=a.unit,remaining=ud.buildTicks}; return
    elseif c.kind=='cancel' then
        if e.category~='building' then reject(w,c,'cannot cancel'); return end
        if a.research then
            if not e.researchRemaining then reject(w,c,'no research');return end
            local refund={};for _,key in ipairs(Codec.keys(w.content.rules.tech.cost)) do refund[key]=math.floor(w.content.rules.tech.cost[key]/2) end;spend(p,refund,-1);e.researchRemaining=nil;return
        end
        if e.remaining>0 then local refund={}; for _,key in ipairs(Codec.keys(d.cost)) do refund[key]=math.floor(d.cost[key]/2) end; spend(p,refund,-1); e.alive=false; w.navVersion=w.navVersion+1; rebuild(w)
        elseif #e.queue>0 then local index=a.index or #e.queue;if not F.integer(index,1,#e.queue) then reject(w,c,'invalid queue slot');return end;local item=table.remove(e.queue,index);local cost=w.content.units[item.kind].cost;if w.content.rules.profile and item.remaining<w.content.units[item.kind].buildTicks then local refund={};for _,key in ipairs(Codec.keys(cost)) do refund[key]=math.floor(cost[key]/2) end;cost=refund end;spend(p,cost,-1)
        else reject(w,c,'nothing to cancel') end
        return
    elseif c.kind=='build' then
        local bd=w.content.buildings[a.building]
        if not d.worker then reject(w,c,'worker required'); return end
        if a.target then
            local site=w.entities[a.target]
            if not site or not site.alive or site.owner~=e.owner or site.category~='building' or site.remaining<=0 then reject(w,c,'invalid site'); return end
            site.builder=e.id;setOrder(w,e,{kind='build',target=site.id},a.append);return
        end
        local view=Sim.view(w,c.player)
        local valid,reason=Sim.placement(view,w.content,a.building,a.x,a.y)
        if not valid then reject(w,c,reason);return end
        -- An extractor stands on its mine, and a mine is a blocked, occupied footprint by
        -- construction. Those two checks are therefore skipped for it; Sim.placement has
        -- already established that the footprint is exactly a live mine.
        local mine=bd.extractor and Sim.mineAt(view,a.x,a.y,bd.size) or nil
        for y=a.y,a.y+bd.size-1 do for x=a.x,a.x+bd.size-1 do
            if not mine and not p.visible[Path.key(w.map,x,y)] then reject(w,c,'blocked or unseen footprint'); return end
            if not mine and (not Path.walkable(w,x,y) or occupied(w,x,y)) then reject(w,c,'blocked or unseen footprint'); return end
        end end
        spend(p,bd.cost)
        local site=spawn(w,a.building,c.player,a.x,a.y,'building'); site.remaining=bd.buildTicks; site.builder=e.id;if w.content.rules.constructionHealth then site.hp=math.ceil(bd.hp/10);site.healthCapacity=site.hp end
        if mine then site.mine=mine.id end
        w.navVersion=w.navVersion+1; rebuild(w);setOrder(w,e,{kind='build',target=site.id},a.append);return
    elseif c.kind=='rally' then
        -- A rally point belongs to the building, not to an order queue: it is standing
        -- policy for whatever the building produces next, and survives until replaced.
        if e.category~='building' or not e.queue then reject(w,c,'cannot rally');return end
        if a.target then
            local t=w.entities[a.target]
            if not t or not t.alive or not Sim.visible(w,c.player,t) then reject(w,c,'invalid rally target');return end
            e.rally={target=t.id}
        else
            if not F.integer(a.x,0,w.map.width*256-1) or not F.integer(a.y,0,w.map.height*256-1) then reject(w,c,'invalid rally point');return end
            e.rally={x=F.cell(a.x),y=F.cell(a.y)}
        end
        return
    end
    if e.category~='unit' then reject(w,c,'unit required'); return end
    if c.kind=='stop' or c.kind=='hold' then setOrder(w,e,{kind=c.kind},false);e.suppressAcquireUntil=w.tick;return end
    if destinationKinds[c.kind] then
        if not F.integer(a.x,0,w.map.width*256-1) or not F.integer(a.y,0,w.map.height*256-1) then reject(w,c,'invalid position'); return end
        local rx,ry=F.cell(a.x),F.cell(a.y)
        -- Equivalent orders preserve their slot even after occupying it. Patrol is
        -- excluded: reissuing it must be able to reset the beat to the current position.
        if c.kind~='patrol' and not a.append and e.order.kind==c.kind and e.order.requestX==rx and e.order.requestY==ry then
            e.orders={};w.commandClaims[Path.key(w.map,e.order.x,e.order.y)]=true;return
        end
        -- A 240-unit group move applies 240 of these commands in one tick. Allocating
        -- a fresh claims table per command, and a `reserve` closure per entity inside
        -- the scan, meant tens of thousands of short-lived objects for one order. The
        -- table is a per-tick scratch that is cleared and refilled, and the closure is
        -- inlined; the scan itself still runs per command because each unit must not
        -- see its own reservations, and the set changes as earlier commands are applied.
        local claims=w.claimScratch
        for key in pairs(claims) do claims[key]=nil end
        for key in pairs(w.commandClaims) do claims[key]=true end
        local map=w.map
        for _,id in ipairs(w.order) do local other=w.entities[id]
            if other.alive and other.owner==e.owner and id~=e.id then
                local active=other.order
                if active.x then claims[Path.key(map,active.x,active.y)]=true end
                local queued=other.orders
                for i=1,#queued do local o=queued[i];if o.x then claims[Path.key(map,o.x,o.y)]=true end end
            end
        end
        local x,y=nearest(w,rx,ry,e.id,claims)
        if not x then reject(w,c,'no destination');return end
        local order={kind=c.kind,x=x,y=y,requestX=rx,requestY=ry,group=a.group}
        -- A patrol beat runs between where the unit was standing when ordered and the
        -- point clicked. Both ends are stored on the order so the route survives
        -- snapshots and replays without any extra per-entity state.
        if c.kind=='patrol' then order.originX,order.originY=F.cell(e.x),F.cell(e.y) end
        setOrder(w,e,order,a.append)
        w.commandClaims[Path.key(w.map,x,y)]=true;return
    end
    local target=F.integer(a.target,1) and w.entities[a.target] or nil
    if not target or not target.alive or not Sim.visible(w,c.player,target) then reject(w,c,'target unavailable'); return end
    if c.kind=='attack' and (target.owner==e.owner or target.category=='node') then reject(w,c,'invalid enemy'); return end
    -- Follow keeps station on another of your own units and never picks a fight of its
    -- own; a unit cannot be ordered to follow itself.
    if c.kind=='follow' and (target.owner~=e.owner or target.category~='unit' or target.id==e.id) then reject(w,c,'invalid follow target'); return end
    setOrder(w,e,{kind=c.kind,target=target.id},a.append)
end
-- Send a freshly produced unit to its building's rally point. Rallying onto something
-- walks to it; nothing harvests any more, so a mine is just a place on the map. Rallying
-- onto a unit follows it, which is the useful case that remains.
function Sim.applyRally(w,e,unit)
    local rally=e.rally
    if not rally then return end
    if rally.target then
        local t=w.entities[rally.target]
        if not t or not t.alive then e.rally=nil;return end
        if t.category=='unit' and t.owner==unit.owner and t.id~=unit.id then
            Sim.setOrder(w,unit,{kind='follow',target=t.id},false)
        else
            -- A mine or a building occupies its own cells, so walk to a free one beside
            -- it rather than to a cell nothing can stand on.
            local tx,ty=F.cell(t.x),F.cell(t.y)
            local x,y=nearest(w,tx,ty,unit.id)
            if x then Sim.setOrder(w,unit,{kind='move',x=x,y=y,requestX=tx,requestY=ty},false) end
        end
        return
    end
    -- A free cell near the point, so successive units spread out instead of stacking.
    local x,y=nearest(w,rally.x,rally.y,unit.id)
    if x then Sim.setOrder(w,unit,{kind='move',x=x,y=y,requestX=rally.x,requestY=rally.y},false) end
end
local function hq(w,p) return w.entities[w.players[p].hq] end
-- A carrier reaching its drop-off is credited and recycled. It leaves no corpse: it
-- walked into the base. Recycling rather than accumulating dead entities is what keeps
-- w.order bounded -- a twenty minute match emits thousands of deliveries.
local function deliver(w,carrier)
    local ledger=w.players[carrier.owner].resources
    local amount=carrier.payload or 0
    ledger.gold=(ledger.gold or 0)+amount
    carrier.alive=false;carrier.spent=true;carrier.deathTick=nil;carrier.payload=0
    emit(w,'delivered',{entity=carrier.id,amount=amount,resource='gold'})
end
-- Extractors emit. Income is bounded two ways: never more often than carrierEmitTicks,
-- and never more than carrierSlots deliveries in flight, which is what makes a distant
-- mine pay less and also caps how many carrier entities can exist.
local function extraction(w)
    local rules=w.content.rules
    local slots=rules.carrierSlots or 9
    -- One pass for both halves. This runs every tick in every match, including the many
    -- that never build an extractor, so it censuses and collects sites together and
    -- returns immediately when there is nothing emitting.
    local inFlight,idle,sites={},{},nil
    for _,id in ipairs(w.order) do
        local e=w.entities[id]
        if e.category=='carrier' then
            if e.alive then inFlight[e.source]=(inFlight[e.source] or 0)+1
            elseif not e.deathTick or w.tick-e.deathTick>=(rules.carrierCorpseTicks or 40) then
                local pool=idle[e.source];if not pool then pool={};idle[e.source]=pool end
                pool[#pool+1]=e
            end
        elseif e.alive and e.category=='building' and e.remaining==0 then
            local d=def(w,e)
            if d and d.extractor then sites=sites or {};sites[#sites+1]=e end
        end
    end
    if not sites then return end
    do
        for _,e in ipairs(sites) do
            local id=e.id
            local mine=w.entities[e.mine]
            if mine and mine.alive and mine.amount>0 and Carriers.route(w,e,route) then
                if w.tick>=(e.nextEmit or 0) and (inFlight[id] or 0)<slots then
                    local payload=math.min(rules.carrierPayload or 8,mine.amount)
                    local pool=idle[id]
                    local carrier=pool and table.remove(pool)
                    if not carrier then carrier=spawn(w,'carrier',e.owner,F.cell(e.x),F.cell(e.y),'carrier') end
                    carrier.alive=true;carrier.spent=nil;carrier.deathTick=nil
                    carrier.hp=carrier.maxHp;carrier.source=id;carrier.payload=payload
                    carrier.leg=1;carrier.routeSerial=e.routeSerial
                    carrier.x=e.x+((e.size or 1)-1)*128;carrier.y=e.y+((e.size or 1)-1)*128
                    mine.amount=mine.amount-payload
                    e.nextEmit=w.tick+(rules.carrierEmitTicks or 16)
                    inFlight[id]=(inFlight[id] or 0)+1
                    if mine.amount<=0 then mine.alive=false;w.navVersion=w.navVersion+1;rebuild(w);emit(w,'depleted',{entity=mine.id}) end
                end
            end
        end
    end
end
local function economy(w)
    for _,id in ipairs(ids(w)) do
        local e=w.entities[id]
        if e.reviveRemaining then
            e.reviveRemaining=math.max(0,e.reviveRemaining-1)
            if e.reviveRemaining==0 and hq(w,e.owner).alive then
                local home=hq(w,e.owner); local x,y=nearest(w,F.cell(home.x)+3,F.cell(home.y)+3,e.id)
                if x then e.alive=true;e.hp=e.maxHp;e.x=F.center(x);e.y=F.center(y);e.reviveRemaining=nil;G.invalidate(w);e.order={kind='stop'};e.cooldown=0;e.nextCommitTick=nil;clearCombat(e); emit(w,'revived',{entity=e.id}) end
            end
        end
        if e.alive then
            if e.order.kind=='build' then local site=w.entities[e.order.target];if not site or not site.alive or site.remaining==0 then nextOrder(w,e) end end
            -- Keep station on the followed unit. approachTarget already halts once inside
            -- the gap and re-routes after the target has moved out of it, which is exactly
            -- follow behaviour; the order ends when the target does.
            if e.order.kind=='follow' then
                local lead=w.entities[e.order.target]
                if not lead or not lead.alive then nextOrder(w,e)
                else approachTarget(w,e,lead,G.radius(w,e)+G.radius(w,lead)+96) end
            end
            local d=def(w,e)
            if e.category=='building' then
                if e.researchRemaining then e.researchRemaining=e.researchRemaining-1;if e.researchRemaining==0 then e.researchRemaining=nil;w.players[e.owner].tech=true;emit(w,'researched',{entity=e.id}) end end
                if e.remaining>0 then
                    local builder=w.entities[e.builder]
                    if builder and builder.alive and builder.order.kind=='build' and builder.order.target==e.id and approachTarget(w,builder,e,400) then e.remaining=e.remaining-1;if e.healthCapacity then local capacity=math.ceil(d.hp/10)+math.floor((d.hp-math.ceil(d.hp/10))*(d.buildTicks-e.remaining)/d.buildTicks);e.hp=e.hp+capacity-e.healthCapacity;e.healthCapacity=capacity end; if e.remaining==0 then nextOrder(w,builder);emit(w,'constructed',{entity=e.id}) end end
                elseif #e.queue>0 then
                    local q=e.queue[1]; q.remaining=math.max(0,q.remaining-1)
                    if q.remaining==0 then
                        local x,y=nearest(w,F.cell(e.x)+e.size,F.cell(e.y)+e.size,nil,nil,w.content.units[q.kind].radius)
                        if x then
                            local unit=spawn(w,q.kind,e.owner,x,y);e.produced=(e.produced or 0)+1;table.remove(e.queue,1);e.productionBlocked=nil
                            Sim.applyRally(w,e,unit)
                            emit(w,'recruited',{entity=unit.id})
                        elseif not e.productionBlocked then e.productionBlocked=true;emit(w,'production_blocked',{entity=e.id}) end
                    end
                end
            elseif e.category=='carrier' and e.alive then
                Carriers.advance(w,e,deliver)
            end
        end
    end
    extraction(w)
end
-- Formation pacing. A group move arrives together only if its members travel together,
-- so every unit under a shared group id walks at the slowest member's speed while that
-- order stands. Recomputed each tick from the orders currently held: membership is
-- whatever still carries the id, so casualties and new orders re-pace the group
-- immediately, and nothing has to be cleaned up when a unit leaves it. Derived from
-- content speeds and order state alone, so it is identical on every peer.
local groupPace={}
local function formation(w)
    if not w.content.rules.formationPacing then return end
    for key in pairs(groupPace) do groupPace[key]=nil end
    local units=w.content.units
    for _,id in ipairs(w.order) do local e=w.entities[id]
        if e.alive and e.category=='unit' then
            local order=e.order
            local group=order.group
            if group and destinationKinds[order.kind] then
                local pace=units[e.kind].speed
                local slowest=groupPace[group]
                if not slowest or pace<slowest then groupPace[group]=pace end
            end
        end
    end
    for _,id in ipairs(w.order) do local e=w.entities[id]
        if e.alive and e.category=='unit' then
            local order=e.order
            local group=order.group
            e.groupSpeed=(group and destinationKinds[order.kind]) and groupPace[group] or nil
        end
    end
end
local function movement(w) formation(w);Movement.step(w,halt,route) end
-- Turn a patrol around: the beat's two ends swap, so the unit walks back the way it
-- came. Both ends live on the order itself, so a patrolling unit survives a snapshot,
-- a replay and a rejoin with its beat intact.
local function reversePatrol(w,e)
    local o=e.order
    local x,y=o.originX,o.originY
    o.originX,o.originY=o.x,o.y
    o.x,o.y=x,y
    o.requestX,o.requestY=x,y
    halt(w,e);e.navigation='idle';e.blockedReason=nil
    route(w,e,o.x,o.y)
end
local function finishOrders(w)
    for _,id in ipairs(ids(w)) do local e=w.entities[id]
        local kind=e.order.kind
        if e.alive and (kind=='move' or kind=='attack_move' or kind=='patrol') and not e.goal and not w.searches[id] and not e.combatTarget then
            local arrived=e.x==F.center(e.order.x) and e.y==F.center(e.order.y) or e.navigation=='arrived' and F.distance2Bounded(e.x,e.y,F.center(e.order.x),F.center(e.order.y))<=F.sq(G.radius(w,e)+32)
            if kind=='patrol' then
                -- A patrol that cannot reach one end turns around rather than stopping:
                -- the point of the order is that it does not need attention.
                if e.blockedReason then emit(w,'blocked',{entity=e.id,reason=e.blockedReason});reversePatrol(w,e)
                elseif arrived then reversePatrol(w,e)
                else route(w,e,e.order.x,e.order.y) end
            elseif e.blockedReason then emit(w,'blocked',{entity=e.id,reason=e.blockedReason});nextOrder(w,e)
            elseif arrived then nextOrder(w,e)
            else route(w,e,e.order.x,e.order.y) end
        end
    end
end
local function enemyTarget(w,e,candidates)
    local best,distance;local d=def(w,e);local sight=d.sight*256;local ex,ey=e.x,e.y
    -- The phase's candidate lists contain only live, hostile, non-resource entities.
    for _,target in ipairs(candidates) do
        if math.abs(ex-target.x)<=sight and math.abs(ey-target.y)<=sight then
            local dist=F.distance2Bounded(ex,ey,target.x,target.y)
            if dist<=sight*sight and (not best or dist<distance or dist==distance and target.id<best.id) and (e.owner==0 or Sim.visible(w,e.owner,target)) then
                local shooting=G.weaponRange(w,e,target)
                local chasing=e.order.kind~='hold' and (e.engagement and F.distance2Bounded(target.x,target.y,e.engagement.x,e.engagement.y)<=F.sq(w.content.rules.acquireRange or 768) or not e.engagement and dist<=F.sq(w.content.rules.acquireRange or 768))
                if shooting or chasing then best=target;distance=dist end
            end
        end
    end
    return best
end
local function validTarget(w,e,t)
    return t and t.alive and t.owner~=e.owner and t.category~='node' and (e.owner==0 or Sim.visible(w,e.owner,t))
end
local function approachWeapon(w,e,t)
    if G.weaponRange(w,e,t) then halt(w,e);return end
    local weapon=def(w,e)
    local contact=w.content.rules.profile and weapon.range<256 and t.category=='unit'
    if contact then
        local gap=G.radius(w,e)+G.radius(w,t)+weapon.range-16
        if F.distance2Bounded(e.x,e.y,t.x,t.y)<=F.sq(gap+384) then
            local dx,dy=F.vector(e.x-t.x,e.y-t.y,gap);local x,y=t.x+dx,t.y+dy
            if G.free(w,x,y,G.radius(w,e),e.id) and G.terrain(w,math.floor((e.x+x)/2),math.floor((e.y+y)/2),G.radius(w,e)) then
                e.path={{x=F.cell(x),y=F.cell(y),px=x,py=y}};e.pathIndex=1;e.goal={x=F.cell(x),y=F.cell(y)};w.searches[e.id]=nil;return
            end
        end
    end
    if (e.goal or w.searches[e.id]) and e.chaseTarget==t.id and e.chaseX==F.cell(t.x) and e.chaseY==F.cell(t.y) then return end
    if w.tick<(e.retryAt or 0) then return end
    e.chaseTarget=t.id;e.chaseX=F.cell(t.x);e.chaseY=F.cell(t.y)
    local d=def(w,e);local radius=math.ceil((d.range+G.radius(w,e)+G.radius(w,t))/256)+1
    local best,score
    for y=math.max(0,F.cell(t.y)-radius),math.min(w.map.height-1,F.cell(t.y)+radius+(t.size or 1)) do
        for x=math.max(0,F.cell(t.x)-radius),math.min(w.map.width-1,F.cell(t.x)+radius+(t.size or 1)) do
            if Path.walkable(w,x,y) then
                local px,py=F.center(x),F.center(y);local distance=F.distance2Bounded(e.x,e.y,px,py)
                if (not score or distance<score) and G.weaponRangeAt(w,e,px,py,t,contact and 256 or w.content.rules.profile and d.range<256 and t.category=='building' and 0 or -32) and G.free(w,px,py,G.radius(w,e),e.id) then best={x=x,y=y};score=distance end
            end
        end
    end
    if best then route(w,e,best.x,best.y) end
    e.retryAt=w.tick+20+e.id%7
end
local function combatOrders(w)
    local candidates={}
    for owner=0,#w.players do candidates[owner]={} end
    for _,id in ipairs(w.order) do local e=w.entities[id];if e.alive and e.category~='node' then
        for owner=0,#w.players do if owner~=e.owner then local list=candidates[owner];list[#list+1]=e end end
    end end
    for _,id in ipairs(w.order) do local e=w.entities[id];local d=def(w,e)
        if e.alive and d and d.damage then
            local kind=e.order.kind;local target
            if kind=='attack' then
                target=w.entities[e.order.target]
                if not validTarget(w,e,target) then nextOrder(w,e);target=nil end
            elseif kind~='move' and kind~='build' and kind~='follow' and not d.worker and w.tick>(e.suppressAcquireUntil or -1) then
                target=w.entities[e.combatTarget]
                if not validTarget(w,e,target) or (kind=='hold' and not G.weaponRange(w,e,target)) or (e.engagement and not G.weaponRange(w,e,target) and (F.distance2Bounded(target.x,target.y,e.engagement.x,e.engagement.y)>F.sq(w.content.rules.acquireRange or 768) or F.distance2Bounded(e.x,e.y,e.engagement.x,e.engagement.y)>F.sq(w.content.rules.acquireRange or 768))) then target=nil end
                if not target then target=enemyTarget(w,e,candidates[e.owner]) end
                if target and not e.engagement then e.engagement={x=e.x,y=e.y} end
            end
            if e.home and F.distance2Bounded(e.x,e.y,e.home.x,e.home.y)>F.sq(w.content.rules.campLeash or 5*256) then target=nil;e.returning=true end
            if w.content.rules.profile and e.home and not target and F.distance2Bounded(e.x,e.y,e.home.x,e.home.y)>100*100 then e.returning=true end
            if e.returning then
                target=nil
                if approachTarget(w,e,{x=e.home.x,y=e.home.y},100) then e.homeSince=e.homeSince or w.tick;if w.tick-e.homeSince>=(w.content.rules.campResetTicks or 0) and w.tick-e.lastCombat>=(w.content.rules.campResetTicks or 0) then e.returning=nil;e.hp=e.maxHp;e.engagement=nil;e.homeSince=nil end else e.homeSince=nil end
            end
            if e.attack and w.tick<=e.attack.impact and (not target or target.id~=e.attack.target or not G.weaponRange(w,e,target)) then e.attack=nil end
            if not target and e.combatTarget then halt(w,e) end
            e.combatTarget=target and target.id or nil
            if target then
                if G.weaponRange(w,e,target) then halt(w,e);e.retryAt=nil;e.rangeLatch=target.id;e.rangeLostAt=nil
                elseif e.rangeLatch==target.id and G.weaponRange(w,e,target,32) and w.tick-(e.rangeLostAt or w.tick)<2 then e.rangeLostAt=e.rangeLostAt or w.tick;halt(w,e)
                elseif e.category=='unit' and kind~='hold' then e.rangeLatch=nil;e.rangeLostAt=nil;approachWeapon(w,e,target) end
            elseif (kind=='attack_move' or kind=='patrol') and not e.returning then
                if not e.goal and not w.searches[id] then route(w,e,e.order.x,e.order.y) end
                -- Keep the leash until the unit has advanced a cell along its order.
                if e.engagement and F.distance2Bounded(e.x,e.y,e.engagement.x,e.engagement.y)>256*256 then e.engagement=nil end
            end
        end
    end
end
local function protection(w,e,protectors)
    local reduction=0
    for _,hero in ipairs(protectors) do
        if hero.alive and hero.owner==e.owner and hero.kind=='warden' then
            local radius=hero.upgrades[1]==1 and (w.content.rules.auraWide or 1536) or (w.content.rules.auraRadius or 1024)
            if hero.upgrades[3]==2 then radius=radius+(w.content.rules.auraExtra or 256) end
            if inRange(e,hero,radius) then reduction=math.max(reduction,(hero.stance==1 and 3 or 1)+(hero.upgrades[1]==2 and (w.content.rules.auraDeep or 3) or 0)) end
        end
    end
    return reduction
end
local function combat(w)
    local hits={};local protectors={}
    for _,id in ipairs(w.order) do local e=w.entities[id];if e.alive and e.kind=='warden' then protectors[#protectors+1]=e end end
    for _,id in ipairs(ids(w)) do
        local e=w.entities[id]; local d=def(w,e)
        if e.alive and d then
            e.cooldown=math.max(0,(e.nextCommitTick or 0)-w.tick)
            if e.attack then
                local phase=e.attack
                if w.tick==phase.impact then
                    local target=w.entities[phase.target]
                    if validTarget(w,e,target) and G.weaponRange(w,e,target) then
                        phase.committed=true;e.nextCommitTick=w.tick+phase.period;e.cooldown=phase.period
                        local damage=d.damage
                        if e.upgrades and e.upgrades[2]==1 then damage=damage+(w.content.rules.heroDamage or 8) end
                        if e.kind=='warden' and e.stance==2 then damage=damage+(w.content.rules.offensiveDamage or 6) end
                        if e.kind=='beastkeeper' and e.stance==2 then damage=math.max(1,damage-(w.content.rules.pursuitPenalty or 5)) end
                        if e.kind=='beastkeeper' and e.upgrades[1]==2 and w.tick-e.lastCombat>(w.content.rules.outOfCombatTicks or 60) then e.sprintUntil=w.tick+40 end
                        hits[#hits+1]={source=e.id,target=target.id,damage=math.max(1,damage-protection(w,target,protectors))}
                        e.lastCombat=w.tick;e.attackTick=w.tick;emit(w,'attack',{source=e.id,target=target.id})
                    end
                end
                if w.tick>=phase.finish then e.attack=nil end
            end
            if e.kind=='beastkeeper' and w.tick-e.lastCombat>(w.content.rules.outOfCombatTicks or 60) and w.tick%20==0 then
                local old=e.hp;e.hp=math.min(e.maxHp,e.hp+(e.upgrades[1]==1 and (w.content.rules.recoveryUpgrade or 12) or (w.content.rules.recovery or 5)));if e.hp>old then emit(w,'healed',{entity=e.id}) end
                if e.upgrades[3]==2 then
                    for _,allyId in ipairs(ids(w)) do local ally=w.entities[allyId]; if ally.alive and ally.category=='unit' and ally.owner==e.owner and w.tick-ally.lastCombat>(w.content.rules.outOfCombatTicks or 60) and inRange(e,ally,1024) then ally.hp=math.min(ally.maxHp,ally.hp+4) end end
                end
            end
            if d.heal and not w.content.rules.profile and w.tick%20==0 then
                for _,allyId in ipairs(ids(w)) do local ally=w.entities[allyId]; if ally.alive and ally.owner==e.owner and inRange(e,ally,768) then local old=ally.hp;ally.hp=math.min(ally.maxHp,ally.hp+d.heal);if ally.hp>old then emit(w,'healed',{entity=ally.id}) end end end
            end
            if d.damage and (e.category~='building' or e.remaining==0) then
                local target=w.entities[e.combatTarget]
                if validTarget(w,e,target) and G.weaponRange(w,e,target) then
                    halt(w,e)
                    local period=d.cooldown-(e.upgrades and e.upgrades[3]==1 and (w.content.rules.quickTicks or 5) or 0)
                    local windup=d.windup
                    if not e.attack and w.tick+windup>=(e.nextCommitTick or 0) then
                        e.attack={target=target.id,start=w.tick,impact=w.tick+windup,finish=w.tick+period,period=period,dx=target.x-e.x,dy=target.y-e.y}
                        emit(w,'windup',{source=e.id,target=target.id})
                    end
                end
            end
        end
    end
    local killers={};local killerSource={}
    for _,hit in ipairs(hits) do
        local e=w.entities[hit.target];e.hp=e.hp-hit.damage;if e.kind=='beastkeeper' and e.upgrades[1]==2 and w.tick-e.lastCombat>(w.content.rules.outOfCombatTicks or 60) then e.sprintUntil=w.tick+40 end;e.lastCombat=w.tick
        -- First attacker to land a blow this tick takes credit, matching the existing
        -- bounty and experience rule.
        if not killers[e.id] then killers[e.id]=w.entities[hit.source].owner;killerSource[e.id]=hit.source end
    end
    local navChanged,deathChanged=false,false
    for _,id in ipairs(ids(w)) do
        local e=w.entities[id]
        if e.alive and e.hp<=0 then
            e.alive=false;e.hp=0;halt(w,e);e.orders={};e.attack=nil;e.deathTick=w.tick;deathChanged=true
            emit(w,'death',{entity=id})
            if e.category=='building' then navChanged=true end
            local killer=killers[id]
            -- Authoritative tallies. The interface previously counted these from the
            -- events it happened to observe, which under-reports a kill made out of
            -- sight; these are part of the world and agree between peers.
            -- A killed carrier destroys its gold rather than handing it over: denial
            -- punishes without compounding a lead the way stealing would.
            if e.category=='carrier' then e.payload=0 end
            if e.owner>0 and e.category~='carrier' then
                local owner=w.players[e.owner]
                if e.category=='unit' then owner.unitsLost=(owner.unitsLost or 0)+1
                else owner.buildingsLost=(owner.buildingsLost or 0)+1 end
            end
            if killer and killer>0 and killer~=e.owner then
                w.players[killer].kills=(w.players[killer].kills or 0)+1
                local source=w.entities[killerSource[id] or 0]
                if source then source.kills=(source.kills or 0)+1 end
            end
            if e.category=='unit' and not def(w,e).worker and killer and killer>0 and killer~=e.owner then
                local bounty=def(w,e).bounty;if bounty then w.players[killer].resources.gold=w.players[killer].resources.gold+bounty end
                local hero=w.entities[w.players[killer].hero]
                if hero.alive and inRange(hero,e,w.content.rules.xpRange) then local ed=def(w,e);hero.xp=hero.xp+(ed.xp or (ed.hero and (w.content.rules.heroXp or 80) or w.content.rules.combatXpPerFood and ed.food*w.content.rules.combatXpPerFood or 30)) end
            end
        end
    end
    if navChanged then w.navVersion=w.navVersion+1;rebuild(w) end;if w.content.rules.profile then require('src.sim.healing').step(w,emit) end; return deathChanged
end
function Sim.step(w,commands)
    w.tick=w.tick+1;w.events={};w.metrics.pathExpansions=0;w.metrics.directChecks=0
    if w.result then return w.events end
    -- Both live only for the command-application part of the step and are removed
    -- before it returns, so neither reaches snapshots or canonical serialization.
    w.commandClaims={};w.claimScratch={};G.beginStep(w)
    local ordered={}
    for i=1,#commands do ordered[i]=commands[i] end
    table.sort(ordered,function(a,b)
        if type(a)~='table' or type(b)~='table' then return type(a)<type(b) end
        local ap,bp=F.integer(a.player) and a.player or 0,F.integer(b.player) and b.player or 0
        if ap~=bp then return ap<bp end
        local as,bs=F.integer(a.sequence) and a.sequence or 0,F.integer(b.sequence) and b.sequence or 0
        if as~=bs then return as<bs end
        return Codec.byteLess(Codec.encode(a),Codec.encode(b))
    end)
    for _,c in ipairs(ordered) do local before=#w.events;apply(w,c);local rejected=false;for i=before+1,#w.events do if w.events[i].kind=='rejected' then rejected=true end end;if not rejected then emit(w,'accepted',{player=c.player,sequence=c.sequence,entity=c.args.entity}) end end
    w.commandClaims=nil;w.claimScratch=nil
    combatOrders(w);economy(w);movement(w);visibility(w);finishOrders(w); if combat(w) then visibility(w) end
    local survivors={}
    for p=1,#w.players do
        w.players[p].defeated=not hq(w,p).alive
        if not w.players[p].defeated then survivors[#survivors+1]=p end
    end
    -- w.result is retained world state; emit owns what it is given, so hand it a copy.
    if #survivors<=1 then w.result={winner=survivors[1] or 0,tick=w.tick};emit(w,'victory',{winner=w.result.winner,tick=w.tick}) end
    G.endStep(w);return w.events
end
function Sim.snapshot(w)
    local copy=Codec.copy(w); copy.events={};return copy
end
function Sim.restore(snapshot)
    assert(snapshot.version==Sim.VERSION,'unsupported simulation snapshot')
    return Codec.copy(snapshot)
end
function Sim.serializeCanonical(w)
    local events=w.events;w.events=nil
    local ok,bytes=pcall(Codec.encode,w);w.events=events
    assert(ok,bytes);return bytes
end
-- Periodic checkpoints exist to detect divergence between peers, and between a
-- replay and the match that recorded it. They therefore need exactly the state
-- that can change a future tick.
--
-- serializeCanonical encodes the whole world, which re-proves things already
-- established elsewhere and charges tens of thousands of keys to do it:
--   content and map are fixed for the match and are covered by the replay
--     header's contentHash/mapHash and by the build fingerprint;
--   w.blocked and the lane cache are derived from map.blocked plus the standing
--     buildings, all of which are covered here (a regression test recomputes
--     w.blocked and asserts it matches);
--   player.explored is written by the simulation but never read by it -- it is
--     fog rendering state, which AGENTS.md places outside canonical state;
--   metrics are per-tick counters reset at the top of every step.
-- Everything that survives a tick and can steer the next one is included, so a
-- real divergence still fails at the first checkpoint after it happens.
-- serializeCanonical remains the tool for whole-state equivalence assertions and
-- desync dumps, where completeness matters more than cost.
function Sim.serializeAuthoritative(w)
    local players={}
    for p=1,#w.players do
        local player=w.players[p]
        players[p]={faction=player.faction,resources=player.resources,sequence=player.sequence,
            defeated=player.defeated,hq=player.hq,hero=player.hero,tech=player.tech,
            kills=player.kills,unitsLost=player.unitsLost,buildingsLost=player.buildingsLost,
            visible=player.visible,knownResources=player.knownResources}
    end
    local ok,bytes=pcall(Codec.encode,{version=w.version,tick=w.tick,config=w.config,
        players=players,entities=w.entities,order=w.order,nextId=w.nextId,result=w.result,
        searches=w.searches,pathCursor=w.pathCursor,navVersion=w.navVersion})
    assert(ok,bytes);return bytes
end
-- Exposed so a regression test can prove w.blocked is recomputable, which is what
-- justifies leaving it out of the authoritative checkpoint.
function Sim.recomputeBlocked(w)
    local blocked=Codec.copy(w.map.blocked)
    for _,id in ipairs(w.order) do
        local e=w.entities[id]
        -- Carriers are not obstructions: they walk through everything but terrain.
        if e.alive and e.category~='unit' and e.category~='carrier' then
            local size=e.size or 1
            for y=F.cell(e.y),F.cell(e.y)+size-1 do
                for x=F.cell(e.x),F.cell(e.x)+size-1 do blocked[Path.key(w.map,x,y)]=true end
            end
        end
    end
    return blocked
end
return Sim
