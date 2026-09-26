local F = require('src.sim.fixed')

local Codec = require('src.sim.codec')
local Path = require('src.sim.path')
local G=require('src.sim.geometry')
local Movement=require('src.sim.movement')
local Stats=require('src.sim.stats')
local Abilities=require('src.sim.abilities')
local Projectiles=require('src.sim.projectiles')
local Vision=require('src.sim.vision')
local Control=require('src.sim.control')
local Harvest=require('src.sim.harvest')
local Coverage=require('src.sim.coverage')
-- Version 5: replay/network checkpoints hash authoritative state only. Older
-- replays store whole-world hashes and are rejected rather than misreported as
-- divergence. See Sim.serializeAuthoritative.
-- Version 6: rally points, patrol and follow orders; per-player and per-entity kill
-- and loss tallies; a `delivered` event carrying the exact amount and resource.
-- Version 10: abilities and status effects. Adds the `cast` and `ping` commands, a
-- cast phase between order completion and combat, mana, cooldowns and a status list on
-- entities, and one effect list per tick that ability effects and attack hits are both
-- applied from. Statuses are the only thing that may change a statistic, and they do it
-- through src/sim/stats.lua.
-- Version 9: paths are string-pulled, so a route bends only where terrain makes it
-- bend instead of stepping cell centre to cell centre, and a finished path is
-- re-validated when the navigation set changes rather than trusted until the unit
-- walks into the new obstacle. Movement results change; replays before this are
-- rejected. Adds `e.pathVersion` and `rules.smoothBudget`.
-- Version 7: write-only entity state removed (reversals, maxWaitTicks, blockedTicks,
-- harvestStatus, lastMove) along with the unused PRNG, so checkpoints stop hashing
-- fields nothing reads. No rule changes.
-- Version 11: maps may carry `unbuildable`, a set of road cells that stay walkable but
-- refuse every building except an extractor on its own mine. Twin Marches is rebuilt at
-- 192x192 with roads joining every mine to the others and to both headquarters.
-- Version 12: control points. A map may name points; a player who owns every one of them
-- for rules.control.holdTicks without a break wins, recorded as result.reason 'control'.
-- Adds w.control, public in views and covered by authoritative checkpoints.
-- Version 13: a unit that cannot move (rooted, stunned) is never asked to step aside for a
-- passing ally. Movement results change where a held unit stood in someone's path.
-- Version 14: a unit blocked for 10 ticks may squeeze past a moving ally that is not heading
-- the same way, down to 65% of their combined radii, and allies closer than their usual spacing
-- are pushed apart by 8 subunits a tick. A congested unit no longer restarts a detour search
-- that is still running, and keeps walking its old path meanwhile. Fixes crowds deadlocking in
-- narrow gaps; crowd results change.
-- Version 15: a site records that it has stopped (no builder assigned) and emits build_stalled
-- once when it does; taking a site over releases the previous builder instead of leaving it
-- standing on a build order for ever.
-- Version 16: a carrier whose extractor is gone is retired where it stands and its load is lost,
-- instead of standing alive for the rest of the match holding gold nobody can collect.
-- Version 17: replaces that rule. A carrier whose extractor is gone keeps walking its cached
-- route and is paid on arrival, because the gold is already out of the ground and on the road.
-- Version 18: a group ordered somewhere keeps its shape. Each unit searches for its destination
-- from the ordered point offset by where it stands relative to the middle of its group, instead
-- of everyone searching outward from the same cell, so units stop crossing to reach equivalent
-- cells. Destinations are still distinct; which unit gets which cell changes. A unit blocked for
-- 30 ticks also proposes a move every fourth tick instead of every tick, staggered by id, so a
-- jammed crowd stops costing a steering pass per unit per tick; it still takes an opening within
-- a fifth of a second and ends up in the same place.
-- Version 19: formation slots belong to validated commands, and queued construction takes
-- a site over only when its order starts. Changes command-batch and builder handoff results.
-- Version 20: faction schema v2. A faction declares its headquarters kind, worker kind,
-- build list, starting resources and units, and how it is defeated ('all_hq': nothing of
-- its headquarters kind standing or under construction; 'unique_hq': the starting one
-- dies). Buildings declare what they produce, what they require, the supply they provide
-- and their armour. The ledger is keyed by rules.resources, and a carrier records which
-- resource it carries. Every new field defaults to the old behaviour when absent.
-- Version 21: worker harvesting. A `harvest` command and order: a worker with a `harvest`
-- table walks to a node, loads at a patch nobody else is loading at (hopping to a free one
-- nearby or waiting), carries the load to its nearest completed drop-off and repeats;
-- `deliver` returns what it holds. Adds `carrying`, `carryResource` and `harvestUntil` on
-- units and `occupant` on nodes; rallying a producer onto a harvestable node harvests it.
-- Version 22: the extractor and carrier economy is deleted (workers harvest instead), a site
-- is built by every worker holding a build order on it with diminishing returns
-- (rules.coBuild; `builders` and `work` on the site replace `builder`), a map may spawn
-- only camps its content defines, and a player without a hero neither earns experience
-- nor revives anyone.
-- Version 23: the air layer. A `flying` unit routes straight to its destination through
-- terrain and units, is in no collision bin and blocks nothing; it may be attacked only by
-- a `canAttackAir` weapon, which uses its `airDamage` when it has one; a `splash` weapon
-- also hits every enemy on the ground within its radius of the target.
-- Version 24: relay coverage and orbital logistics. A faction with `coverage` keeps a
-- per-player set of covered cells (rebuilt each tick from its `coverage` sources) that gates
-- where its buildings may land and whether a rig earns its online or offline rate; buildings
-- are `requisition`ed into a per-player call-down queue, produced in orbit, `land`ed on a
-- site after a descent and arrive complete, or return to the queue if the site is blocked.
-- Version 25: drop pods and garrisons. Pod units are `pod_load`ed into the open pod (cost
-- and supply paid then), `pod_launch`ed onto a covered cell, land after the descent on a
-- ring of free cells; pods in flight are limited by tier. A unit may `garrison` a building
-- with `garrison` slots: it is untargetable and unseen by the enemy, takes half splash,
-- fights from inside a `garrisonFights` building, and is `unload`ed or ejected on death.
-- Version 26: target stacks and channelled abilities. A hit from an `applyStacks` unit
-- adds a stack to its target (`stackFixed`, 200 per stack); at the target's threshold the
-- stacks burst for `rules.stacks.burst` armour-piercing damage, and they decay after a
-- grace period. An ability with `channel` keeps firing from its cast point every `period`
-- for `ticks`; the caster holds and any new order breaks it. `filter.air` / `filter.ground`.
-- Version 27: `cancel{pod=true,seat=i}` refunds one unit out of the open pod and closes the
-- gap; without `seat` it still refunds the whole pod. The owner's view gains `player.orbit`,
-- a derived summary (orbit slots, queue size, pods unlocked) the interface used to work out
-- from the world. No state is added.
-- Version 28: player-isolated groups, individual shipping movement speeds and
-- responsive navigation. Earlier replays/snapshots require their original build.
-- Version 29 integrates shared precise routes with vehicle clearance offsets.
-- Version 30: explicit garrison orders do not acquire or chase enemies en route.
local Sim = { VERSION = 30 }
local function ids(w) return w.order end
local function def(w,e) return w.content.units[e.kind] or w.content.buildings[e.kind] end
-- Airborne: a unit whose definition flies. Buildings and nodes never do.
local function airborne(w,e) if e.category~='unit' then return false end;local d=w.content.units[e.kind];return d~=nil and d.flying==true end
-- Faction schema v2. Every accessor here has a default that reproduces what content
-- relied on before the schema existed, so a definition naming none of the new fields
-- plays exactly as it did.
function Sim.factionOf(w,p) return w.content.factions[w.players[p].faction] end
function Sim.hqKind(faction) return faction.hq or 'hq' end
-- The unit that builds and harvests for this faction: named, defaulted to 'worker' when
-- the content has one, or false for a faction that has none.
function Sim.workerKind(content,faction)
    if faction.worker~=nil then return faction.worker or nil end
    return content.units.worker and 'worker' or nil
end
-- What a building of this kind trains for this faction.
function Sim.producesFor(content,faction,kind)
    local d=content.buildings[kind]
    if d and d.produces then return d.produces end
    if kind==Sim.hqKind(faction) then local worker=Sim.workerKind(content,faction);return worker and {worker} or {} end
    if kind=='barracks' then return faction.roster or {} end
    return {}
end
function Sim.produces(w,e) return Sim.producesFor(w.content,Sim.factionOf(w,e.owner),e.kind) end
function Sim.primaryResource(content) return (content.rules.resources or {'gold'})[1] end
-- The tier a player has reached: how many of its completed buildings carry `tier`.
-- How many pods a player may have in flight: the base plus one per tier, capped.
function Sim.podsUnlocked(w,p)
    local rules=w.content.rules
    return math.min(rules.podsMax or 3,(rules.podsBase or 1)+Sim.tier(w,p))
end
-- Stacks needed to burst a target: a base, more for armour, more for size. Fixed at 200
-- per stack so the decay can be fractional without a float.
function Sim.stackThreshold(w,target)
    local rules=w.content.rules.stacks or {}
    local armor=Stats.armor(w,target)
    return math.max(1,(rules.base or 5)+math.floor((rules.armorPercent or 150)*armor/100)+math.floor((rules.perHundredHp or 2)*(target.maxHp or 0)/100))
end
function Sim.tier(w,p)
    local n=0
    for _,id in ipairs(w.order) do local e=w.entities[id];if e.alive and e.owner==p and e.category=='building' and e.remaining==0 then local d=w.content.buildings[e.kind];if d and d.tier then n=n+1 end end end
    return n
end
-- The first named requirement the player has not completed, or nil. Works on a world
-- (entities by id, walked in w.order) and on a view (an array), so the HUD and the bot
-- give the same answer the command will.
function Sim.missingRequirement(source,owner,requires)
    if not requires then return nil end
    local function has(kind)
        if source.order then
            for _,id in ipairs(source.order) do local e=source.entities[id];if e.alive and e.owner==owner and e.kind==kind and (e.remaining or 0)==0 then return true end end
        else
            for _,e in ipairs(source.entities) do if e.alive and e.owner==owner and e.kind==kind and (e.remaining or 0)==0 then return true end end
        end
        return false
    end
    for _,kind in ipairs(requires) do if type(kind)=='string' and not has(kind) then return kind end end
    return nil
end
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
        if e.alive and e.category=='unit' and e.id~=except and not airborne(w,e) and not e.garrisoned and G.rectangleDistance2(e.x,e.y,x*256,y*256,(x+1)*256,(y+1)*256)<F.sq(G.radius(w,e)) then return true end
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
local function nearest(w,x,y,except,claimed,radius,extraClaims)
    radius=radius or (except and G.radius(w,w.entities[except])) or 112
    local unit=except and w.entities[except]
    -- A flyer may be sent to any cell: it needs no walkable ground and no free body room.
    local aloft=unit and airborne(w,unit)
    local map=w.map;local width,height=map.width,map.height
    local ux,uy=0,0;if unit then ux,uy=unit.x,unit.y end
    -- Not re-entrant: the scratch arrays are shared. Nothing reachable from G.free or
    -- Path.walkable calls back into this, and every caller is a leaf of one step phase.
    local count=0
    local function consider(cx,cy)
        if cx<0 or cy<0 or cx>=width or cy>=height then return end
        local key=Path.key(map,cx,cy)
        if (claimed and claimed[key]) or (extraClaims and extraClaims[key]) or (not aloft and not Path.walkable(w,cx,cy)) then return end
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
                local px,py=F.center(candX[c]),F.center(candY[c])
                if not aloft and radius>127 then px,py=Path.point(w,candX[c],candY[c],radius) end
                if aloft or px and G.free(w,px,py,radius,except) then return candX[c],candY[c] end
            end
        end
    end
end

-- Single definition of how w.blocked derives from the map and standing buildings,
-- shared with the regression test that proves the derivation (see Sim.recomputeBlocked).
local function rebuild(w) w.blocked=Sim.recomputeBlocked(w) end
local function standAt(w,e,x,y)
    e.x,e.y=F.center(x),F.center(y)
    local d=w.content.units[e.kind]
    if not d.flying and d.radius>127 then
        local px,py=Path.point(w,x,y,d.radius);assert(px,'spawn lacks body clearance');e.x,e.y=px,py
    end
end
local function spawn(w,kind,owner,x,y,category)
    G.invalidate(w)
    local d=w.content.units[kind] or w.content.buildings[kind]
    local id=w.nextId; w.nextId=id+1
    local e={id=id,kind=kind,owner=owner,x=F.center(x),y=F.center(y),category=category or 'unit',
        alive=true,hp=d and d.hp or 1,maxHp=d and d.hp or 1,size=d and d.size or 1,cooldown=0,
        path={},pathIndex=1,order={kind='stop'},orders={},lastCombat=-1000}
    if e.category=='unit' then standAt(w,e,x,y) end
    if d and d.hero then e.xp=0; e.upgrades={}; e.stance=1 end
    -- A caster starts full. Mana is authoritative like every other integer here.
    if d and d.mana then e.mana=d.mana;e.maxMana=d.mana end
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
    if e.goal and e.goal.x==x and e.goal.y==y then return end
    -- A flyer's route is the straight line: one waypoint, no search, nothing to re-validate.
    if airborne(w,e) then
        local o=e.order;local exact=o.x==x and o.y==y
        local px,py=exact and o.px or F.center(x),exact and o.py or F.center(y)
        e.path={{x=x,y=y,px=px,py=py}};e.pathIndex=1;e.goal={x=x,y=y,px=px,py=py};e.pathVersion=w.navVersion;e.blockedReason=nil;w.searches[e.id]=nil;return
    end
    Path.request(w,e,x,y)
end
local function approachTarget(w,e,t,range)
    if inRange(e,t,range) then halt(w,e); return true end
    if not e.goal and not w.searches[e.id] and w.tick>=(e.retryAt or 0) then
        local x,y
        if w.content.rules.profile and (t.category=='building' or t.category=='node') then
            local score;local r=math.ceil(range/256)
            for cy=math.max(0,F.cell(t.y)-r),math.min(w.map.height-1,F.cell(t.y)+t.size+r-1) do
                for cx=math.max(0,F.cell(t.x)-r),math.min(w.map.width-1,F.cell(t.x)+t.size+r-1) do
                    local px,py=Path.point(w,cx,cy,G.radius(w,e))
                    if px then
                        local dist=F.distance2Bounded(e.x,e.y,px,py)
                        if (not score or dist<score) and inRange({x=px,y=py},t,range) and G.free(w,px,py,G.radius(w,e),e.id) then x,y,score=cx,cy,dist end
                    end
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
                if e.alive and e.owner==p and e.category~='projectile' then Vision.field(w,e,Stats.sight(w,e),visible,explored) end
            end
            Sim.knownResources(w,p,player)
        else
        local rowCount=0
        for _,id in ipairs(w.order) do local e=w.entities[id]
            if e.alive and e.owner==p and e.category~='projectile' then
                local sight=Stats.sight(w,e);local spans=sightSpans[sight]
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
    Coverage.update(w)
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
    'reviveRemaining','resource','amount','campTier','stance','xp','healthCapacity','kills','mine','stalled',
    'mana','maxMana',
    -- Stacks are public: the pips on a target are the tell that a burst is coming.
    'stackFixed',
    -- A worker's load and its loading are public: an enemy sees a laden worker walking home.
    'carrying','carryResource','harvestUntil','garrisoned','occupants',
    -- A shot in flight carries its heading so the renderer can point it the right way.
    'dx','dy','ability'}
-- Fields an observer may only see on entities it owns.
local OWNER_FIELDS={'researchRemaining','reviveRemaining','xp','mine','stalled','garrisoned','occupants'}
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
        -- Cooldowns are your own bookkeeping; an enemy learns that a spell is spent by
        -- watching it land, not by reading the caster's timers.
        if e.cooldowns then copy.cooldowns=shallow(e.cooldowns) end
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
    -- A cast in progress is public: seeing an enemy hero wind up is the information a
    -- player needs to react, and hiding it would make every spell arrive from nowhere.
    -- Which ability, and at what, is private until it lands.
    local cast=e.cast
    if cast then copy.cast={start=cast.start,point=cast.point,finish=cast.finish,dx=cast.dx,dy=cast.dy,
        ability=own and cast.ability or nil,target=own and cast.target or nil,x=own and cast.x or nil,y=own and cast.y or nil} end
    -- A channel is public like a cast: the barrage is falling where everyone can see it.
    local channel=e.channel
    if channel then copy.channel={start=channel.start,finish=channel.finish,x=channel.x,y=channel.y,ability=own and channel.ability or nil} end
    -- Statuses are public in both directions. A stunned enemy has to read as stunned, or
    -- the player cannot tell why their focus target stopped swinging.
    if e.statuses then
        local list={}
        for i=1,#e.statuses do local s=e.statuses[i];list[i]={id=s.id,['until']=s['until'],stacks=s.stacks} end
        copy.statuses=list
    end
    return copy
end
function Sim.view(w,player)
    local p=w.players[player]
    -- Control state is public: both players see who owns each point and the countdown.
    -- Orbital logistics at a glance, for a faction that has them: derived every time, never stored.
    local rules=w.content.rules;local faction=Sim.factionOf(w,player);local orbit
    if faction and faction.coverage then
        orbit={slots=1+(Sim.tier(w,player)>=2 and 1 or 0),queueMax=rules.callDownQueue or 5,podsUnlocked=Sim.podsUnlocked(w,player),
            podsMax=rules.podsMax or 3,podCapacity=rules.podCapacity or 4,podCooldown=rules.podCooldown or 300,descentTicks=rules.descentTicks or 200}
    end
    local out={tick=w.tick,result=w.result,control=w.control and Codec.copy(w.control),
        map={width=w.map.width,height=w.map.height,starts=w.map.starts,anchors=w.map.anchors,blocked=w.map.blocked,unbuildable=w.map.unbuildable,terrain=w.map.terrain},
        entities={},byId={},
        player={id=player,faction=p.faction,hq=p.hq,hero=p.hero,sequence=p.sequence,defeated=p.defeated,tech=p.tech,supplyCap=Sim.supplyCap(w,player),
            kills=p.kills,unitsLost=p.unitsLost,buildingsLost=p.buildingsLost,
            resources=Codec.copy(p.resources),visible=p.visible,explored=p.explored,knownResources=p.knownResources,
            coverage=p.coverage,orbit=orbit,callDown=p.callDown and Codec.copy(p.callDown),landings=p.landings and Codec.copy(p.landings),pods=p.pods and Codec.copy(p.pods)}}
    for _,id in ipairs(ids(w)) do
        local e=w.entities[id]
        -- A unit inside a building is its owner's knowledge alone.
        if (e.alive or e.owner==player or (e.deathTick and w.tick-e.deathTick<40)) and Sim.visible(w,player,e) and not (e.garrisoned and e.owner~=player) then
            local copy=viewEntity(w,e,e.owner==player)
            out.entities[#out.entities+1]=copy;out.byId[id]=copy
        end
    end
    return out
end
function Sim.create(config,content,map)
    F.check(map.width,8,256); F.check(map.height,8,256)
    -- Checked, not ordered: an out-of-range road key is a broken map, whatever order it is found in.
    for key in pairs(map.unbuildable or {}) do F.check(key,1,map.width*map.height) end
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
        players={},entities={},order={},nextId=1,searches={},pathCursor=0,navVersion=0,blocked={},events={},metrics={pathExpansions=0,directChecks=0,smoothChecks=0,bodyChecks=0}}
    for p=1,#config.players do
        local faction=config.players[p].faction or 'bastion'
        local definition=content.factions[faction]
        assert(definition,'unknown faction')
        local starting=definition.starting and definition.starting.resources or content.rules.startingResources or {gold=650}
        w.players[p]={faction=faction,resources=Codec.copy(starting),sequence=0,visible={},explored={},defeated=false,
            kills=0,unitsLost=0,buildingsLost=0}
    end
    for _,node in ipairs(map.resources or {}) do
        F.check(node.x,0,map.width-1); F.check(node.y,0,map.height-1)
        local e=spawn(w,'resource',0,node.x,node.y,'node'); e.resource=node.resource; e.amount=node.amount;e.size=node.size or 1
    end
    for p=1,#w.players do
        local start=map.starts[p]
        local hq=spawn(w,Sim.hqKind(content.factions[w.players[p].faction]),p,start.x,start.y,'building'); w.players[p].hq=hq.id
    end
    rebuild(w)
    for p=1,#w.players do
        local start=map.starts[p]; local faction=content.factions[w.players[p].faction]
        local initial
        if faction.starting and faction.starting.units then initial={};for i,kind in ipairs(faction.starting.units) do initial[i]=kind end
        elseif content.rules.startingWorkers then initial={faction.hero};for _=1,content.rules.startingWorkers do initial[#initial+1]='worker' end
        else initial={faction.hero,'worker','worker',faction.roster[1],faction.roster[2]} end
        for slot,kind in ipairs(initial) do
            local x,y=nearest(w,start.x+3,start.y+3,nil,nil,content.units[kind].radius)
            if content.rules.profile and map.unitStarts and map.unitStarts[p] and map.unitStarts[p][slot] then x=map.unitStarts[p][slot].x;y=map.unitStarts[p][slot].y;assert(G.free(w,F.center(x),F.center(y),content.units[kind].radius),'invalid authored spawn') end
            assert(x,'map has no spawn space')
            local e=spawn(w,kind,p,x,y)
            if content.units[kind].hero then w.players[p].hero=e.id end
        end
    end
    for _,camp in ipairs(map.camps or {}) do
        local kind=camp.kind or 'neutral'
        assert(content.units[kind],'the map places a camp of the unknown unit kind '..tostring(kind))
        local e=spawn(w,kind,0,camp.x,camp.y); e.home={x=e.x,y=e.y};e.campTier=camp.tier
    end
    Control.create(w,map)
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
    local pods=w.players[p].pods
    if pods then
        for _,kind in ipairs(pods.open.kinds) do n=n+(w.content.units[kind].food or 1) end
        for _,pod in ipairs(pods.inFlight) do for _,kind in ipairs(pod.kinds) do n=n+(w.content.units[kind].food or 1) end end
    end
    return n
end
-- The supply cap. A flat rule by default; with rules.supplyFromBuildings it is the sum of
-- what the player's completed buildings provide, clamped at the faction's ceiling, so
-- losing a depot really does cost the supply it gave.
function Sim.supplyCap(w,p)
    local rules=w.content.rules
    if not rules.supplyFromBuildings then return rules.population end
    local cap=0
    for _,id in ipairs(ids(w)) do
        local e=w.entities[id]
        if e.alive and e.owner==p and e.category=='building' and e.remaining==0 then cap=cap+(def(w,e).supply or 0) end
    end
    local ceiling=Sim.factionOf(w,p).supplyCap or rules.supplyCap or 200
    if cap>ceiling then cap=ceiling end
    return cap
end
-- Defeat, by the faction's rule. 'unique_hq' is the old rule: the headquarters the match
-- started with is the only one there is. 'all_hq' counts every standing headquarters of
-- the faction's kind, sites included, so an expansion is a life.
function Sim.defeated(w,p)
    local faction=Sim.factionOf(w,p)
    if (faction.defeat or 'all_hq')=='unique_hq' then return not w.entities[w.players[p].hq].alive end
    local kind=Sim.hqKind(faction)
    for _,id in ipairs(ids(w)) do
        local e=w.entities[id]
        if e.alive and e.owner==p and e.kind==kind then return false end
    end
    return true
end
function Sim.unitCount(w,p)
    local count=0;for _,id in ipairs(w.order) do local e=w.entities[id];if e.alive and e.owner==p and e.category=='unit' then count=count+1 end end;return count
end
function Sim.revival(content,hero)
    local tiers=0;for _,threshold in ipairs(content.rules.xpThresholds) do if (hero.xp or 0)>=threshold then tiers=tiers+1 end end
    return content.rules.reviveCost+tiers*(content.rules.reviveTierCost or 0),content.rules.reviveTicks+tiers*(content.rules.reviveTierTicks or 0)
end
-- The resource node whose footprint exactly matches this one, if there is such a node,
-- optionally of one resource. A building that stands on a node stands squarely on it.
function Sim.mineAt(view,x,y,size,resource)
    for _,e in ipairs(view.entities) do
        if e.alive and e.category=='node' and (resource==nil or e.resource==resource)
            and F.cell(e.x)==x and F.cell(e.y)==y and e.size==size then return e end
    end
end
function Sim.placement(view,content,kind,x,y,prepaid)
    local d=content.buildings[kind]
    local faction=content.factions[view.player.faction]
    if not d or not F.integer(x,0,view.map.width-d.size) or not F.integer(y,0,view.map.height-d.size) then return false,'Outside map' end
    -- The headquarters is buildable only by a faction that lists it and does not lose on
    -- its unique one; a faction with no build list keeps the old rule of never.
    if kind==Sim.hqKind(faction) and (not faction.buildings or faction.defeat=='unique_hq') then return false,'Cannot be built' end
    if faction.buildings then
        local listed=false;for _,id in ipairs(faction.buildings) do if id==kind then listed=true end end
        if not listed then return false,'Not available to your faction' end
    end
    if not prepaid and not afford(view.player,d.cost) then return false,'Insufficient resources' end
    local missing=Sim.missingRequirement(view,view.player.id,d.requires)
    if missing then return false,'Requires '..((content.buildings[missing] or content.units[missing] or {}).label or missing) end
    local mine
    local onNode=d.onNode or (d.extractor and 'gold') or nil
    if onNode then
        local found=Sim.mineAt(view,x,y,d.size,onNode)
        if not found then return false,'Must be built on a '..onNode..' node' end
        if found.amount and found.amount<=0 then return false,'Mine is exhausted' end
        mine=found.id
    end
    for cy=y,y+d.size-1 do for cx=x,x+d.size-1 do
        local key=cy*view.map.width+cx+1
        -- An extractor's footprint is exactly the mine's. Seeing the mine is the whole
        -- of what you need to know to put a building on it, and mines sit against
        -- terrain that hides a cell or two of their own footprint often enough that the
        -- per-cell rule would arbitrarily rule out some of them.
        -- Territory first: a coverage faction lands only where its relays reach, and that is
        -- the answer a player needs before whether the ground is seen.
        if faction.coverage and view.player.coverage and not view.player.coverage[key] then return false,'Outside relay coverage' end
        if not mine and not view.player.visible[key] then return false,'Unseen footprint' end
        if not mine and view.map.blocked[key] then return false,'Impassable terrain' end
        -- Roads keep every mine's way to the bases open, so nothing stands on one. The
        -- build command revalidates through here, which makes this authoritative.
        if not mine and view.map.unbuildable and view.map.unbuildable[key] then return false,'Cannot build on a road' end
        for _,other in ipairs(view.entities) do
            -- A flyer occupies no ground, so a site may go up beneath it.
            if other.alive and other.category=='unit' and not content.units[other.kind].flying and G.rectangleDistance2(other.x,other.y,cx*256,cy*256,(cx+1)*256,(cy+1)*256)<F.sq(content.units[other.kind].radius) then return false,'Occupied footprint' end
            -- A building placed on its node is not obstructed by that node.
            if other.alive and other.category~='unit' and other.id~=mine
                and cx>=F.cell(other.x) and cx<F.cell(other.x)+other.size and cy>=F.cell(other.y) and cy<F.cell(other.y)+other.size then return false,'Occupied footprint' end
        end
    end end
    return true,'Ready to build'
end
local function clearCombat(e)
    e.attack=nil;e.attackTick=nil;e.combatTarget=nil;e.engagement=nil;e.retryAt=nil;e.yieldOrigin=nil;e.rangeLatch=nil;e.rangeLostAt=nil;e.chaseTarget=nil;e.chaseX=nil;e.chaseY=nil
    -- A new order cancels a cast. Before the cast point nothing has been spent, so the
    -- mana and the cooldown are still there; after it, only the backswing is thrown
    -- away, which is the same bargain the attack phase offers for a committed swing.
    -- A channel is broken outright; its cooldown was charged at the cast point.
    e.cast=nil;e.channel=nil
end
local claimBuild
local function setOrder(w,e,order,append)
    if append and e.order.kind~='stop' then
        if #e.orders>=32 then return false end
        e.orders[#e.orders+1]=order
    else
        local old=e.order
        e.rally=e.rally
        local same=old.kind==order.kind and old.target==order.target and old.x==order.x and old.y==order.y and old.px==order.px and old.py==order.py
        e.orders={}
        if same and (order.kind=='move' or order.kind=='attack_move' or order.kind=='attack') then return true end
        halt(w,e);clearCombat(e);Harvest.release(w,e);e.order=order;e.reroutes=0;e.blockedReason=nil;e.lastOrderFailure=nil;e.restAnchor=nil;e.navigation='idle';e.detour=nil;e.rerouteAt=nil
        e.suppressAcquireUntil=w.tick
        if order.x then route(w,e,order.x,order.y) end
        claimBuild(w,e)
    end
    return true
end
Sim.setOrder=setOrder
local function nextOrder(w,e)
    local blocked=e.blockedReason
    local rest=e.order.x and {x=e.order.px or F.center(e.order.x),y=e.order.py or F.center(e.order.y)} or nil
    halt(w,e);clearCombat(e);Harvest.release(w,e);e.order=table.remove(e.orders,1) or {kind='stop'};e.reroutes=0;e.blockedReason=nil
    e.navigation=blocked and 'failed' or 'idle';e.lastOrderFailure=blocked;e.restAnchor=e.order.kind=='stop' and not blocked and rest or nil
    if e.order.x then route(w,e,e.order.x,e.order.y) end
    claimBuild(w,e)
end
-- Claim on activation, both for immediate orders and when a queued order starts. Merely
-- queuing work must not evict the current builder. Claim first, then release the previous
-- worker, whose own queue may start another construction job in turn.
claimBuild=function(w,e)
    if e.order.kind~='build' then return end
    local site=w.entities[e.order.target]
    if not site or not site.alive or site.owner~=e.owner or site.category~='building' or site.remaining<=0 then return end
    -- Joining, not taking over: a site is built by everyone holding a build order on it.
    local builders=site.builders or {}
    for _,id in ipairs(builders) do if id==e.id then return end end
    builders[#builders+1]=e.id;site.builders=builders
end
local function reject(w,c,reason) emit(w,'rejected',{player=c.player or 0,sequence=c.sequence or 0,reason=reason}) end
-- What cancelling gives back: a whole-percent share of every resource paid, floored.
local function refundOf(w,cost)
    local percent=w.content.rules.cancelRefundPercent or 50
    local out={};for _,key in ipairs(Codec.keys(cost)) do out[key]=math.floor(cost[key]*percent/100) end
    return out
end
local commandKinds={move=true,attack=true,attack_move=true,stop=true,hold=true,build=true,recruit=true,toggle=true,upgrade=true,revive=true,cancel=true,research=true,
    rally=true,patrol=true,follow=true,cast=true,ping=true,harvest=true,requisition=true,land=true,pod_load=true,pod_launch=true,garrison=true,unload=true}
-- Orders that take a destination slot and are reserved against other units' slots.
local destinationKinds={move=true,attack_move=true,patrol=true}
local function envelopeError(w,c,sequence)
    if type(c)~='table' or not F.integer(c.player,1,#w.players) or not F.integer(c.sequence,1,2147483646) or c.tick~=w.tick or not commandKinds[c.kind] or type(c.args)~='table' then return 'malformed command' end
    local p=w.players[c.player]
    if p.defeated or c.sequence<=(sequence or p.sequence) then return 'duplicate, stale, or defeated' end
end
local function commandEntity(w,c)
    local a=c.args
    local e=F.integer(a.entity,1) and w.entities[a.entity] or nil
    if not e or e.owner~=c.player then return nil,'invalid ownership' end
    if a.append~=nil and type(a.append)~='boolean' then return nil,'invalid queue flag' end
    if a.group~=nil and not F.integer(a.group,1,2147483646) then return nil,'invalid command group' end
    if a.append and c.kind~='stop' and c.kind~='hold' and #e.orders>=32 then return nil,'order queue full' end
    return e
end
local function validPosition(w,a)
    return F.integer(a.x,0,w.map.width*256-1) and F.integer(a.y,0,w.map.height*256-1)
end
-- Formation. A group ordered somewhere keeps its shape: each unit aims for the destination
-- offset by where it stands relative to the middle of its group, so a line arrives as a line and
-- units stop crossing each other to reach cells that are interchangeable anyway. Claimed cells
-- still guarantee distinct destinations; this only decides where each unit starts looking, and a
-- unit whose formation cell is unusable falls back to searching from the point that was clicked.
-- Offsets are clamped so that selecting units from opposite corners of the map still forms them
-- up around the destination rather than scattering them across it.
-- Scratch for the tick, like the claim set: derived from the commands, never stored.
local function planFormations(w,ordered)
    local groups,keys=nil,nil
    local sequences={}
    for _,c in ipairs(ordered) do
        local sequence=type(c)=='table' and sequences[c.player] or nil
        if not envelopeError(w,c,sequence) then
            -- apply consumes the sequence even when entity/argument validation rejects it.
            sequences[c.player]=c.sequence
            local e=destinationKinds[c.kind] and commandEntity(w,c)
            if e and e.alive and e.category=='unit' and c.args.group and not c.args.append and validPosition(w,c.args) then
                local key=c.player..':'..tostring(c.args.group)
                groups=groups or {};keys=keys or {}
                local list=groups[key]
                if not list then list={};groups[key]=list;keys[#keys+1]=key end
                list[#list+1]={e=e,command=c,x=F.cell(c.args.x),y=F.cell(c.args.y)}
            end
        end
    end
    if not keys then return end
    local slots={}
    for _,key in ipairs(keys) do
        local list=groups[key]
        if #list>1 then
            local sx,sy=0,0
            for _,item in ipairs(list) do sx=sx+F.cell(item.e.x);sy=sy+F.cell(item.e.y) end
            local cx,cy=math.floor(sx/#list),math.floor(sy/#list)
            local limit=math.ceil(math.sqrt(#list))+2
            for _,item in ipairs(list) do
                local dx=math.max(-limit,math.min(limit,F.cell(item.e.x)-cx))
                local dy=math.max(-limit,math.min(limit,F.cell(item.e.y)-cy))
                slots[item.command]={x=item.x+dx,y=item.y+dy}
            end
        end
    end
    w.groupSlots=slots
end
-- Counts keep overlapping queued reservations intact when this entity's old orders
-- are temporarily excluded. Rebuilt only after a non-movement command can change
-- another entity's orders; otherwise each accepted destination updates its own counts.
local function reserveOrder(w,o,counts,delta)
    if o.x then
        local key=Path.key(w.map,o.x,o.y)
        local n=(counts[key] or 0)+delta
        counts[key]=n>0 and n or nil
    end
end
local function reserveOrders(w,e,counts,delta)
    reserveOrder(w,e.order,counts,delta)
    for i=1,#e.orders do reserveOrder(w,e.orders[i],counts,delta) end
end
local function destination(w,c,e,a,claims)
    if not validPosition(w,a) then reject(w,c,'invalid position'); return end
    local rx,ry=F.cell(a.x),F.cell(a.y)
    -- Equivalent orders preserve their slot even after occupying it. Patrol is
    -- excluded: reissuing it must be able to reset the beat to the current position.
    if c.kind~='patrol' and not a.append and e.order.kind==c.kind and e.order.requestX==rx and e.order.requestY==ry and
        (not w.content.rules.preciseMovement or e.order.requestPX==a.x and e.order.requestPY==a.y) then
        e.orders={};w.commandClaims[Path.key(w.map,e.order.x,e.order.y)]=true;return
    end
    -- Its place in the formation first, then the point that was clicked.
    local slot=w.groupSlots and w.groupSlots[c]
    local x,y
    if slot then x,y=nearest(w,slot.x,slot.y,e.id,claims,nil,w.commandClaims) end
    if not x then x,y=nearest(w,rx,ry,e.id,claims,nil,w.commandClaims) end
    if not x then reject(w,c,'no destination');return end
    local order={kind=c.kind,x=x,y=y,requestX=rx,requestY=ry,group=a.group}
    if w.content.rules.preciseMovement then
        order.requestPX,order.requestPY=a.x,a.y
        local px,py=x*256+a.x%256,y*256+a.y%256
        -- Keep the click's offset in each assigned slot, provided the whole body
        -- fits. The coarse cell path remains unchanged. Unsafe edges use its centre.
        if airborne(w,e) or G.free(w,px,py,G.radius(w,e),e.id) then order.px,order.py=px,py end
    end
    -- A patrol beat runs between where the unit was standing when ordered and the
    -- point clicked. Both ends are stored on the order so the route survives
    -- snapshots and replays without any extra per-entity state.
    if c.kind=='patrol' then
        order.originX,order.originY=F.cell(e.x),F.cell(e.y)
        if w.content.rules.preciseMovement then order.originPX,order.originPY=e.x,e.y end
    end
    setOrder(w,e,order,a.append)
    w.commandClaims[Path.key(w.map,x,y)]=true;return
end
local function applyDestination(w,c,e,a)
    local owners=w.destinationClaims
    if not owners then owners={};w.destinationClaims=owners end
    local claims=owners[e.owner]
    if not claims then
        claims={};owners[e.owner]=claims
        for _,id in ipairs(w.order) do
            local other=w.entities[id]
            if other.alive and other.owner==e.owner then reserveOrders(w,other,claims,1) end
        end
    end
    reserveOrders(w,e,claims,-1)
    destination(w,c,e,a,claims)
    reserveOrders(w,e,claims,1)
end
local function apply(w,c)
    local reason=envelopeError(w,c)
    if reason then reject(w,type(c)=='table' and c or {},reason);return end
    if not destinationKinds[c.kind] then w.destinationClaims=nil end
    local p=w.players[c.player]
    p.sequence=c.sequence
    local a=c.args
    -- A ping is a message, not an order: it names no entity, changes no state, and is
    -- accepted only to be echoed as an event. It goes through the command stream rather
    -- than the network layer so that it is ordered, recorded in the replay and observed
    -- exactly like every other action, and so a marker can never appear for one player
    -- and not the other.
    if c.kind=='ping' then
        if not F.integer(a.x,0,w.map.width*256-1) or not F.integer(a.y,0,w.map.height*256-1) then reject(w,c,'invalid position');return end
        -- Addressed to the pinging player only, which in a 1v1 with no alliances is the
        -- whole of "your team". When teams exist this becomes the team's audience; it
        -- must never become everyone, or a ping would hand the enemy your attention.
        emit(w,'ping',{player=c.player,pingX=a.x,pingY=a.y});return
    end
    local e,entityError=commandEntity(w,c)
    if not e then reject(w,c,entityError);return end
    local d=def(w,e)
    if c.kind=='revive' then
        local hq=w.entities[p.hq]
        if not d.hero or not w.content.rules.xpThresholds then reject(w,c,'cannot revive'); return end
        local cost,ticks=Sim.revival(w.content,e)
        local price={[Sim.primaryResource(w.content)]=cost}
        if e.alive or e.reviveRemaining or not hq.alive or not afford(p,price) then reject(w,c,'cannot revive'); return end
        spend(p,price); e.reviveRemaining=ticks; return
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
        local allowed=false
        for _,kind in ipairs(Sim.produces(w,e)) do if kind==a.unit then allowed=true end end
        if ud and allowed and Sim.missingRequirement(w,c.player,ud.requires) then reject(w,c,'requirement missing'); return end
        if not ud or not allowed or e.remaining>0 or #e.queue>=5 or (ud.tech and not p.tech) or Sim.population(w,c.player)+(ud.food or 1)>Sim.supplyCap(w,c.player) or not afford(p,ud.cost) then reject(w,c,'cannot recruit'); return end
        spend(p,ud.cost); e.queue[#e.queue+1]={kind=a.unit,remaining=ud.buildTicks}; return
    elseif c.kind=='cancel' then
        if e.category~='building' then reject(w,c,'cannot cancel'); return end
        if a.pod then
            local pods=p.pods
            if e.id~=p.hq or not pods or #pods.open.kinds==0 then reject(w,c,'nothing to cancel');return end
            -- One seat: that unit is refunded in full (it was never trained) and those behind it move up.
            if a.seat~=nil then
                if not F.integer(a.seat,1,#pods.open.kinds) then reject(w,c,'nothing to cancel');return end
                local kind=table.remove(pods.open.kinds,a.seat);spend(p,w.content.units[kind].cost,-1);return
            end
            for _,kind in ipairs(pods.open.kinds) do spend(p,w.content.units[kind].cost,-1) end
            pods.open={kinds={}};return
        end
        if a.callDown then
            local queue=p.callDown or {}
            if e.id~=p.hq or not F.integer(a.callDown,1,#queue) then reject(w,c,'nothing to cancel');return end
            local item=table.remove(queue,a.callDown)
            spend(p,refundOf(w,w.content.buildings[item.kind].cost),-1);return
        end
        if a.research then
            if not e.researchRemaining then reject(w,c,'no research');return end
            spend(p,refundOf(w,w.content.rules.tech.cost),-1);e.researchRemaining=nil;return
        end
        if e.remaining>0 then spend(p,refundOf(w,d.cost),-1); e.alive=false; w.navVersion=w.navVersion+1; rebuild(w)
        elseif #e.queue>0 then local index=a.index or #e.queue;if not F.integer(index,1,#e.queue) then reject(w,c,'invalid queue slot');return end;local item=table.remove(e.queue,index);local cost=w.content.units[item.kind].cost;if w.content.rules.profile and item.remaining<w.content.units[item.kind].buildTicks then cost=refundOf(w,cost) end;spend(p,cost,-1)
        else reject(w,c,'nothing to cancel') end
        return
    elseif c.kind=='build' then
        local bd=w.content.buildings[a.building]
        if not d.worker then reject(w,c,'worker required'); return end
        if a.target then
            local site=w.entities[a.target]
            if not site or not site.alive or site.owner~=e.owner or site.category~='building' or site.remaining<=0 then reject(w,c,'invalid site'); return end
            setOrder(w,e,{kind='build',target=site.id},a.append);return
        end
        local view=Sim.view(w,c.player)
        local valid,reason=Sim.placement(view,w.content,a.building,a.x,a.y)
        if not valid then reject(w,c,reason);return end
        -- An extractor stands on its mine, and a mine is a blocked, occupied footprint by
        -- construction. Those two checks are therefore skipped for it; Sim.placement has
        -- already established that the footprint is exactly a live mine.
        local onNode=bd.onNode or (bd.extractor and 'gold') or nil
        local mine=onNode and Sim.mineAt(view,a.x,a.y,bd.size,onNode) or nil
        for y=a.y,a.y+bd.size-1 do for x=a.x,a.x+bd.size-1 do
            if not mine and not p.visible[Path.key(w.map,x,y)] then reject(w,c,'blocked or unseen footprint'); return end
            if not mine and (not Path.walkable(w,x,y) or occupied(w,x,y)) then reject(w,c,'blocked or unseen footprint'); return end
        end end
        spend(p,bd.cost)
        local site=spawn(w,a.building,c.player,a.x,a.y,'building'); site.remaining=bd.buildTicks;if w.content.rules.constructionHealth then site.hp=math.ceil(bd.hp/10);site.healthCapacity=site.hp end
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
    if c.kind=='requisition' then
        -- Orbital logistics: the price is paid now, the building is produced in orbit and
        -- lands later, complete, wherever the player then chooses inside coverage.
        local faction=Sim.factionOf(w,c.player);local bd=w.content.buildings[a.building]
        local listed=false;for _,id in ipairs(faction.buildings or {}) do if id==a.building then listed=true end end
        if not faction.coverage or e.id~=p.hq or not bd or not listed or a.building==Sim.hqKind(faction) then reject(w,c,'cannot requisition');return end
        if Sim.missingRequirement(w,c.player,bd.requires) then reject(w,c,'requirement missing');return end
        p.callDown=p.callDown or {}
        if #p.callDown>=(w.content.rules.callDownQueue or 5) then reject(w,c,'call-down queue full');return end
        if not afford(p,bd.cost) then reject(w,c,'cannot requisition');return end
        spend(p,bd.cost);p.callDown[#p.callDown+1]={kind=a.building,remaining=bd.buildTicks}
        emit(w,'requisitioned',{player=c.player,building=a.building});return
    elseif c.kind=='land' then
        local queue=p.callDown or {}
        local item=F.integer(a.index,1,#queue) and queue[a.index] or nil
        if e.id~=p.hq or not item or item.remaining>0 then reject(w,c,'nothing ready to land');return end
        local valid,reason=Sim.placement(Sim.view(w,c.player),w.content,item.kind,a.x,a.y,true)
        if not valid then reject(w,c,reason);return end
        table.remove(queue,a.index)
        p.landings=p.landings or {}
        p.landings[#p.landings+1]={kind=item.kind,x=a.x,y=a.y,at=w.tick+(w.content.rules.descentTicks or 200)}
        emit(w,'landing',{player=c.player,building=item.kind,landX=a.x,landY=a.y});return
    end
    if c.kind=='pod_load' then
        -- Cost and supply are paid at loading; the unit exists only when the pod lands.
        local faction=Sim.factionOf(w,c.player);local ud=w.content.units[a.unit];local rules=w.content.rules
        if not faction.coverage or e.id~=p.hq or not ud or not ud.pod then reject(w,c,'cannot load');return end
        if Sim.missingRequirement(w,c.player,ud.requires) then reject(w,c,'requirement missing');return end
        p.pods=p.pods or {open={kinds={}},inFlight={},cooldownUntil=0}
        if #p.pods.open.kinds>=(rules.podCapacity or 4) then reject(w,c,'pod is full');return end
        if Sim.population(w,c.player)+(ud.food or 1)>Sim.supplyCap(w,c.player) or not afford(p,ud.cost) then reject(w,c,'cannot load');return end
        spend(p,ud.cost);p.pods.open.kinds[#p.pods.open.kinds+1]=a.unit
        emit(w,'pod_loaded',{player=c.player,unit=a.unit});return
    elseif c.kind=='pod_launch' then
        local pods=p.pods;local rules=w.content.rules
        if e.id~=p.hq or not pods or #pods.open.kinds==0 then reject(w,c,'nothing to launch');return end
        if not F.integer(a.x,0,w.map.width-1) or not F.integer(a.y,0,w.map.height-1) then reject(w,c,'invalid position');return end
        if not Coverage.covers(w,c.player,a.x,a.y) then reject(w,c,'Outside relay coverage');return end
        if w.tick<(pods.cooldownUntil or 0) then reject(w,c,'pod on cooldown');return end
        if #pods.inFlight>=Sim.podsUnlocked(w,c.player) then reject(w,c,'no pod available');return end
        pods.inFlight[#pods.inFlight+1]={x=a.x,y=a.y,at=w.tick+(rules.descentTicks or 200),kinds=pods.open.kinds}
        pods.open={kinds={}};pods.cooldownUntil=w.tick+(rules.podCooldown or 300)
        emit(w,'pod_launched',{player=c.player,podX=a.x,podY=a.y});return
    elseif c.kind=='unload' then
        if e.category~='building' or not e.occupants or #e.occupants==0 then reject(w,c,'nothing to unload');return end
        local claimed={}
        for _,id in ipairs(e.occupants) do local o=w.entities[id]
            local x,y=nearest(w,F.cell(e.x)+e.size,F.cell(e.y)+e.size,nil,claimed,G.radius(w,o))
            if x then claimed[Path.key(w.map,x,y)]=true;standAt(w,o,x,y) end
            o.garrisoned=nil;G.invalidate(w);emit(w,'unloaded',{entity=o.id})
        end
        e.occupants=nil;G.invalidate(w);return
    end
    if e.category~='unit' then reject(w,c,'unit required'); return end
    if c.kind=='garrison' then
        local t=F.integer(a.target,1) and w.entities[a.target] or nil
        local bd=t and w.content.buildings[t.kind]
        if not t or not t.alive or t.owner~=e.owner or t.category~='building' or t.remaining>0 or not bd or not bd.garrison then reject(w,c,'cannot garrison there');return end
        if airborne(w,e) or e.garrisoned then reject(w,c,'cannot garrison');return end
        setOrder(w,e,{kind='garrison',target=t.id},a.append);return
    end
    if c.kind=='stop' or c.kind=='hold' then setOrder(w,e,{kind=c.kind},false);e.suppressAcquireUntil=w.tick;return end
    if c.kind=='harvest' then
        if not d.harvest then reject(w,c,'cannot harvest');return end
        -- No target: bring back what is carried, then stop.
        if a.deliver and a.target==nil then setOrder(w,e,{kind='harvest',deliver=true},a.append);return end
        local node=F.integer(a.target,1) and w.entities[a.target] or nil
        if not node or not node.alive or not Harvest.canHarvest(d,node) then reject(w,c,'cannot harvest that');return end
        if not Sim.visible(w,c.player,node) then reject(w,c,'target not visible');return end
        setOrder(w,e,{kind='harvest',target=node.id,resource=node.resource},a.append);return
    end
    if c.kind=='cast' then
        if e.category~='unit' then reject(w,c,'not a caster');return end
        local ability=Abilities.definition(w,a.ability)
        if not ability or not Abilities.has(w,e,a.ability) then reject(w,c,'unknown ability');return end
        if not Stats.canCast(w,e) then reject(w,c,'silenced');return end
        if not Abilities.ready(w,e,a.ability) then reject(w,c,'ability on cooldown');return end
        if not Abilities.affordable(w,e,ability) then reject(w,c,'not enough mana');return end
        local order={kind='cast',ability=a.ability}
        if ability.target=='unit' then
            local t=F.integer(a.target,1) and w.entities[a.target] or nil
            if not t or not Abilities.matches(w,e,t,ability.filter) then reject(w,c,'invalid ability target');return end
            -- You may only aim at what you can see. Separate from the legality check so
            -- the HUD can say which of the two went wrong.
            if not Sim.visible(w,c.player,t) then reject(w,c,'target not visible');return end
            order.target=t.id
        elseif ability.target~='none' then
            if not F.integer(a.x,0,w.map.width*256-1) or not F.integer(a.y,0,w.map.height*256-1) then reject(w,c,'invalid position');return end
            order.x,order.y=a.x,a.y
        end
        -- Range is deliberately not checked here. A cast is an order, so a caster too
        -- far away walks into range first, exactly as an attack order does.
        setOrder(w,e,order,a.append);return
    end
    if destinationKinds[c.kind] then return applyDestination(w,c,e,a) end
    local target=F.integer(a.target,1) and w.entities[a.target] or nil
    if not target or not target.alive or target.garrisoned or not Sim.visible(w,c.player,target) then reject(w,c,'target unavailable'); return end
    if c.kind=='attack' and (target.owner==e.owner or target.category=='node') then reject(w,c,'invalid enemy'); return end
    if c.kind=='attack' and airborne(w,target) and not d.canAttackAir then reject(w,c,'cannot attack air'); return end
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
        elseif t.category=='node' and Harvest.canHarvest(def(w,unit),t) then
            -- A producer rallied onto a patch its units can work sends them to work it.
            Sim.setOrder(w,unit,{kind='harvest',target=t.id,resource=t.resource},false)
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
local harvestApi={emit=emit,nextOrder=nextOrder,approachTarget=approachTarget,rebuild=rebuild,radius=G.radius,def=def}
-- The node whose footprint exactly matches this one, from the world rather than a view.
local function nodeAt(w,x,y,size,resource)
    for _,id in ipairs(w.order) do local e=w.entities[id]
        if e.alive and e.category=='node' and e.resource==resource and F.cell(e.x)==x and F.cell(e.y)==y and e.size==size then return e end
    end
end
-- Orbital logistics, per player: items in the queue are produced in orbit, one at a time
-- (two from the second Requisition Office), and a landing that reaches the ground on a
-- free site arrives complete; on a blocked site it goes back to the head of the queue, ready.
local function orbit(w)
    for pi=1,#w.players do local p=w.players[pi]
        if p.callDown then
            local slots=1+(Sim.tier(w,pi)>=2 and 1 or 0)
            for i,item in ipairs(p.callDown) do
                if i<=slots and item.remaining>0 then
                    item.remaining=item.remaining-1
                    if item.remaining==0 then emit(w,'call_down_ready',{player=pi,building=item.kind}) end
                end
            end
        end
        if p.pods then
            local i=1
            while p.pods.inFlight[i] do
                local pod=p.pods.inFlight[i]
                if w.tick>=pod.at then
                    -- The payload dispenses onto a ring of free cells around the point, in load
                    -- order, each on the nearest cell not yet taken.
                    table.remove(p.pods.inFlight,i);local claimed={}
                    for _,kind in ipairs(pod.kinds) do
                        local x,y=nearest(w,pod.x,pod.y,nil,claimed,w.content.units[kind].radius)
                        if x then claimed[Path.key(w.map,x,y)]=true;spawn(w,kind,pi,x,y) end
                    end
                    emit(w,'pod_landed',{player=pi,podX=pod.x,podY=pod.y})
                else i=i+1 end
            end
        end
        if p.landings then
            local i=1
            while p.landings[i] do
                local landing=p.landings[i]
                if w.tick>=landing.at then
                    table.remove(p.landings,i)
                    local bd=w.content.buildings[landing.kind];local free=true;local mine
                    if bd.onNode then mine=nodeAt(w,landing.x,landing.y,bd.size,bd.onNode);if not mine or mine.amount<=0 then free=false end
                    else
                        for y=landing.y,landing.y+bd.size-1 do for x=landing.x,landing.x+bd.size-1 do
                            if not Path.walkable(w,x,y) or occupied(w,x,y) then free=false end
                        end end
                    end
                    if free then
                        local site=spawn(w,landing.kind,pi,landing.x,landing.y,'building');site.remaining=0
                        if mine then site.mine=mine.id end
                        w.navVersion=w.navVersion+1;rebuild(w)
                        emit(w,'landed',{entity=site.id});emit(w,'constructed',{entity=site.id})
                    else
                        p.callDown=p.callDown or {};table.insert(p.callDown,1,{kind=landing.kind,remaining=0})
                        emit(w,'landing_blocked',{player=pi,building=landing.kind})
                    end
                else i=i+1 end
            end
        end
    end
end
-- A rig on a node earns its per-minute rate in 1/1200ths a tick, whole units only, at the
-- online figure while its own cell is covered and the offline one otherwise, and drains
-- the node by what it pays out. Exact per minute, integers throughout.
local function rigIncome(w,e,d)
    local mine=w.entities[e.mine or 0]
    if not (mine and mine.alive and mine.amount>0) then return end
    local player=w.players[e.owner]
    local covered=not player.coverage or player.coverage[Path.key(w.map,F.cell(e.x),F.cell(e.y))]==true
    local rate=covered and d.income or d.incomeOffline or d.income
    e.income=e.income or {}
    for _,key in ipairs(Codec.keys(rate)) do
        local acc=(e.income[key] or 0)+rate[key]
        local whole=math.floor(acc/1200);acc=acc-whole*1200
        if whole>mine.amount then whole=mine.amount end
        if whole>0 then player.resources[key]=(player.resources[key] or 0)+whole;mine.amount=mine.amount-whole end
        e.income[key]=acc
    end
    if mine.amount<=0 then mine.alive=false;w.navVersion=w.navVersion+1;rebuild(w);emit(w,'depleted',{entity=mine.id}) end
end
local function economy(w)
    orbit(w)
    for _,id in ipairs(ids(w)) do
        local e=w.entities[id]
        if e.reviveRemaining then
            e.reviveRemaining=math.max(0,e.reviveRemaining-1)
            if e.reviveRemaining==0 and hq(w,e.owner).alive then
                local home=hq(w,e.owner); local x,y=nearest(w,F.cell(home.x)+3,F.cell(home.y)+3,e.id)
                if x then e.alive=true;e.hp=e.maxHp;standAt(w,e,x,y);e.reviveRemaining=nil;G.invalidate(w);e.order={kind='stop'};e.cooldown=0;e.nextCommitTick=nil;clearCombat(e); emit(w,'revived',{entity=e.id}) end
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
            if e.order.kind=='harvest' then Harvest.step(w,e,harvestApi) end
            if e.order.kind=='garrison' then
                local b=w.entities[e.order.target]
                if not b or not b.alive or b.remaining>0 then nextOrder(w,e)
                elseif approachTarget(w,e,b,G.radius(w,e)+128) then
                    local bd=w.content.buildings[b.kind];local used=0
                    for _,id in ipairs(b.occupants or {}) do local o=w.entities[id];used=used+(w.content.units[o.kind].garrisonSlots or 1) end
                    if used+(def(w,e).garrisonSlots or 1)<=bd.garrison then
                        b.occupants=b.occupants or {};b.occupants[#b.occupants+1]=e.id
                        e.garrisoned=b.id;e.x=b.x+((b.size or 1)-1)*128;e.y=b.y+((b.size or 1)-1)*128
                        halt(w,e);clearCombat(e);e.order={kind='stop'};e.orders={};G.invalidate(w)
                        emit(w,'garrisoned',{entity=e.id,target=b.id})
                    else emit(w,'garrison_full',{entity=e.id,target=b.id});nextOrder(w,e) end
                end
            end
            local d=def(w,e)
            if e.category=='building' then
                if e.remaining==0 and d.income then rigIncome(w,e,d) end
                if e.researchRemaining then e.researchRemaining=e.researchRemaining-1;if e.researchRemaining==0 then e.researchRemaining=nil;w.players[e.owner].tech=true;emit(w,'researched',{entity=e.id}) end end
                if e.remaining>0 then
                    -- Every worker holding a build order on the site builds it. Assigned is not
                    -- the same as at work: one still walking is on its way. Several at work
                    -- build faster with diminishing returns (rules.coBuild, percent of a tick's
                    -- progress per tick by count). A site nobody is assigned to has stopped, and
                    -- says so once, so the player can be told and the bot can send someone back.
                    local kept,working={},0
                    for _,id in ipairs(e.builders or {}) do local b=w.entities[id]
                        if b and b.alive and b.order.kind=='build' and b.order.target==e.id then
                            kept[#kept+1]=id
                            if approachTarget(w,b,e,400) then working=working+1 end
                        end
                    end
                    e.builders=#kept>0 and kept or nil
                    if #kept==0 and not e.stalled then e.stalled=true;emit(w,'build_stalled',{entity=e.id})
                    elseif #kept>0 and e.stalled then e.stalled=nil end
                    if working>0 then
                        local steps=w.content.rules.coBuild
                        local rate=steps and steps[math.min(working,#steps)] or 100
                        e.work=(e.work or 0)+rate
                        while e.work>=100 and e.remaining>0 do
                            e.work=e.work-100;e.remaining=e.remaining-1
                            if e.healthCapacity then local capacity=math.ceil(d.hp/10)+math.floor((d.hp-math.ceil(d.hp/10))*(d.buildTicks-e.remaining)/d.buildTicks);e.hp=e.hp+capacity-e.healthCapacity;e.healthCapacity=capacity end
                        end
                        if e.work==0 then e.work=nil end
                        if e.remaining==0 then
                            e.work=nil;e.stalled=nil;e.builders=nil
                            for _,id in ipairs(kept) do nextOrder(w,w.entities[id]) end
                            emit(w,'constructed',{entity=e.id})
                        end
                    end
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
            end
        end
    end
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
                local pace=Stats.baseSpeed(w,e)
                local key=e.owner..':'..group
                local slowest=groupPace[key]
                if not slowest or pace<slowest then groupPace[key]=pace end
            end
        end
    end
    for _,id in ipairs(w.order) do local e=w.entities[id]
        if e.alive and e.category=='unit' then
            local order=e.order
            local group=order.group
            e.groupSpeed=(group and destinationKinds[order.kind]) and groupPace[e.owner..':'..group] or nil
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
    local px,py=o.originPX,o.originPY
    o.originX,o.originY=o.x,o.y
    o.originPX,o.originPY=o.px,o.py
    o.x,o.y=x,y
    o.px,o.py=px,py
    o.requestX,o.requestY=x,y
    o.requestPX,o.requestPY=px,py
    halt(w,e);e.navigation='idle';e.blockedReason=nil
    route(w,e,o.x,o.y)
end
local function finishOrders(w)
    for _,id in ipairs(ids(w)) do local e=w.entities[id]
        local kind=e.order.kind
        if e.alive and (kind=='move' or kind=='attack_move' or kind=='patrol') and not e.goal and not w.searches[id] and not e.combatTarget then
            local tx,ty=e.order.px or F.center(e.order.x),e.order.py or F.center(e.order.y)
            local arrived=e.x==tx and e.y==ty or e.navigation=='arrived' and F.distance2Bounded(e.x,e.y,tx,ty)<=F.sq(G.radius(w,e)+32)
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
-- Hostiles are bucketed into eight-cell blocks so acquisition looks at the ground near
-- the unit instead of at every enemy on the map. It used to be a linear scan of the whole
-- hostile list, once per damage-capable entity, every tick -- the single largest cost in
-- the combat phase at army scale. A fourteen-cell sight covers at most sixteen blocks.
--
-- The result is identical, not merely similar: the winner is chosen by a strict
-- improvement on (squared distance, entity id), which is a total order, so which order
-- the candidates were visited in cannot change the answer. The determinism harness is
-- what proves that claim rather than the argument.
local BLOCK=2048
local function blockKey(x,y) return math.floor(y/BLOCK)*512+math.floor(x/BLOCK) end
local function enemyTarget(w,e,blocks)
    local best,distance;local sight=Stats.sight(w,e)*256;local ex,ey=e.x,e.y
    -- A building looks out from the middle of its footprint, as its sight does, so a wide
    -- building does not lose reach on the side away from its origin cell.
    if e.category=='building' then ex=ex+((e.size or 1)-1)*128;ey=ey+((e.size or 1)-1)*128 end
    local x0,x1=math.floor((ex-sight)/BLOCK),math.floor((ex+sight)/BLOCK)
    local y0,y1=math.floor((ey-sight)/BLOCK),math.floor((ey+sight)/BLOCK)
    if x0<0 then x0=0 end
    if y0<0 then y0=0 end
    local acquire=F.sq(w.content.rules.acquireRange or 768)
    local chaseable=e.order.kind~='hold'
    local canAir=def(w,e).canAttackAir==true
    local engagement=e.engagement
    for by=y0,y1 do
        local row=by*512
        for bx=x0,x1 do
            local bin=blocks[row+bx]
            if bin then
                for i=1,#bin do
                    local target=bin[i]
                    if math.abs(ex-target.x)<=sight and math.abs(ey-target.y)<=sight then
                        local dist=F.distance2Bounded(ex,ey,target.x,target.y)
                        if dist<=sight*sight and (not best or dist<distance or dist==distance and target.id<best.id) and (canAir or not airborne(w,target)) and (e.owner==0 or Sim.visible(w,e.owner,target)) then
                            local shooting=G.weaponRange(w,e,target)
                            local chasing=chaseable and (engagement and F.distance2Bounded(target.x,target.y,engagement.x,engagement.y)<=acquire or not engagement and dist<=acquire)
                            if shooting or chasing then best=target;distance=dist end
                        end
                    end
                end
            end
        end
    end
    return best
end
local function validTarget(w,e,t)
    if not (t and t.alive and t.owner~=e.owner and t.category~='node' and not t.garrisoned and (e.owner==0 or Sim.visible(w,e.owner,t))) then return false end
    -- Only a weapon that can reach the air may be aimed at a flyer.
    if airborne(w,t) then local d=def(w,e);return d~=nil and d.canAttackAir==true end
    return true
end
local function approachWeapon(w,e,t)
    if G.weaponRange(w,e,t) then halt(w,e);return end
    local reach=Stats.range(w,e)
    local contact=w.content.rules.profile and reach<256 and t.category=='unit'
    if contact then
        local gap=G.radius(w,e)+G.radius(w,t)+reach-16
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
    local radius=math.ceil((reach+G.radius(w,e)+G.radius(w,t))/256)+1
    local best,score
    for y=math.max(0,F.cell(t.y)-radius),math.min(w.map.height-1,F.cell(t.y)+radius+(t.size or 1)) do
        for x=math.max(0,F.cell(t.x)-radius),math.min(w.map.width-1,F.cell(t.x)+radius+(t.size or 1)) do
            if Path.walkable(w,x,y) then
                local px,py=Path.point(w,x,y,G.radius(w,e))
                if px then
                    local distance=F.distance2Bounded(e.x,e.y,px,py)
                    if (not score or distance<score) and G.weaponRangeAt(w,e,px,py,t,contact and 256 or w.content.rules.profile and reach<256 and t.category=='building' and 0 or -32) and G.free(w,px,py,G.radius(w,e),e.id) then best={x=x,y=y};score=distance end
                end
            end
        end
    end
    if best then route(w,e,best.x,best.y) end
    e.retryAt=w.tick+20+e.id%7
end
-- The candidate bins are rebuilt every tick of every match: a table per owner, plus one per
-- occupied block, thousands of times a second, all of it garbage by the next tick. The tables
-- are kept and emptied instead. They are scratch: never read outside this function, never part
-- of the world, and refilled from w.order, so the order they are built in does not change.
local candidateScratch={}
local function combatOrders(w)
    local candidates=candidateScratch
    for owner=0,#w.players do
        local map=candidates[owner]
        if not map then map={};candidates[owner]=map
        else for _,bin in pairs(map) do for i=#bin,1,-1 do bin[i]=nil end end end
    end
    for _,id in ipairs(w.order) do local e=w.entities[id]
        if e.alive and e.category~='node' and e.category~='projectile' and not e.garrisoned then
            local key=blockKey(e.x,e.y)
            for owner=0,#w.players do
                if owner~=e.owner then
                    local map=candidates[owner]
                    local bin=map[key]
                    if not bin then bin={};map[key]=bin end
                    bin[#bin+1]=e
                end
            end
        end
    end
    for _,id in ipairs(w.order) do local e=w.entities[id];local d=def(w,e)
        local inside=e.garrisoned and w.entities[e.garrisoned]
        local mayFight=not inside or (w.content.buildings[inside.kind] or {}).garrisonFights==true
        -- A channelling caster is busy: it neither acquires nor chases until the channel ends.
        if e.alive and d and d.damage and mayFight and not e.channel then
            local kind=e.order.kind;local target
            if kind=='attack' then
                target=w.entities[e.order.target]
                if not validTarget(w,e,target) then nextOrder(w,e);target=nil end
            elseif kind~='move' and kind~='build' and kind~='follow' and kind~='garrison' and not d.worker and w.tick>(e.suppressAcquireUntil or -1) then
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
                elseif e.category=='unit' and kind~='hold' and not e.garrisoned then e.rangeLatch=nil;e.rangeLostAt=nil;approachWeapon(w,e,target) end
            elseif (kind=='attack_move' or kind=='patrol') and not e.returning then
                if not e.goal and not w.searches[id] then route(w,e,e.order.x,e.order.y) end
                -- Keep the leash until the unit has advanced a cell along its order.
                if e.engagement and F.distance2Bounded(e.x,e.y,e.engagement.x,e.engagement.y)>256*256 then e.engagement=nil end
            end
        end
    end
end
-- Walk a caster into range of its cast point. A cast is an order, so a caster that is
-- too far away closes the distance first, exactly as an attack order does; the range is
-- never checked when the command is accepted.
local function approachCast(w,e,ability,order)
    local t=order.target and w.entities[order.target]
    if t then return approachTarget(w,e,t,(ability.range or 0)+G.radius(w,e)+G.radius(w,t)) end
    if not order.x then return true end
    return approachTarget(w,e,{x=order.x,y=order.y,category='point'},(ability.range or 0)+G.radius(w,e))
end
-- The per-tick effect list. A module-level scratch array like the others in this file:
-- it exists only between the ability phase and the end of the combat phase, and never
-- reaches a snapshot or a hash.
local pendingEffects={}
-- The ability module owns casting and statuses but must not reach back into this file,
-- or the two would be circular. It gets the four things it needs instead.
-- Launch a shot. Reuses a spent projectile where one exists, exactly as the carrier
-- stream does, so a long battle does not grow the entity list without bound.
local function launch(w,e,ability,index,effect,order,px,py)
    local shot
    for _,id in ipairs(w.order) do
        local candidate=w.entities[id]
        if candidate.category=='projectile' and candidate.spent then shot=candidate;break end
    end
    if not shot then shot=spawn(w,'projectile',e.owner,F.cell(e.x),F.cell(e.y),'projectile') end
    shot.alive=true;shot.spent=nil;shot.deathTick=nil;shot.hit=nil
    shot.owner=e.owner;shot.x=e.x;shot.y=e.y
    shot.source=e.id;shot.ability=order.ability;shot.effectIndex=index
    shot.speed=effect.speed or 64;shot.radius=effect.radius or 96;shot.pierce=effect.pierce or nil
    if ability.target=='unit' then
        shot.target=order.target;shot.remaining=nil;shot.dx=0;shot.dy=0
    else
        shot.target=nil
        local dx,dy=F.vector((px or e.x)-e.x,(py or e.y)-e.y,shot.speed)
        if dx==0 and dy==0 then dx=shot.speed end
        shot.dx=dx;shot.dy=dy;shot.remaining=ability.range or 1024
    end
    emit(w,'projectile_launched',{entity=shot.id,source=e.id,ability=order.ability})
end
local abilityApi={emit=emit,halt=halt,nextOrder=nextOrder,approachCast=approachCast,launch=launch}
-- Damage, healing and status application, all in one place and all applied after every
-- source for the tick has been collected. Ability effects come first because they were
-- produced earlier in the tick, then the auto-attack hits; within each, the order is
-- `w.order`, so two peers apply exactly the same sequence.
local function applyEffects(w,list,killers,killerSource)
    local outOfCombat=w.content.rules.outOfCombatTicks or 60
    for _,fx in ipairs(list) do
        local target=w.entities[fx.target]
        if target and target.alive then
            if fx.kind=='damage' then
                if not Stats.invulnerable(w,target) then
                    target.hp=target.hp-fx.damage
                    -- Target stacks: one per hit from a stacking unit; at the threshold
                    -- they burst as one armour-piercing blow, appended to this same list
                    -- so it lands this tick and takes kill credit like any other hit.
                    if fx.stacks and target.hp>0 then
                        local rules=w.content.rules.stacks or {}
                        target.stackFixed=(target.stackFixed or 0)+(rules.perHit or 200);target.stackHit=w.tick
                        if target.stackFixed>=Sim.stackThreshold(w,target)*(rules.perHit or 200) then
                            target.stackFixed=nil;target.stackHit=nil
                            list[#list+1]={kind='damage',source=fx.source,target=target.id,damage=rules.burst or 45,pierce=true}
                            emit(w,'stack_burst',{entity=target.id,source=fx.source,damage=rules.burst or 45})
                        end
                    end
                    if target.kind=='beastkeeper' and target.upgrades[1]==2 and w.tick-target.lastCombat>outOfCombat then target.sprintUntil=w.tick+40 end
                    target.lastCombat=w.tick
                    -- First attacker to land a blow this tick takes credit, matching the
                    -- existing bounty and experience rule.
                    if not killers[target.id] then
                        local source=w.entities[fx.source]
                        if source then killers[target.id]=source.owner;killerSource[target.id]=fx.source end
                    end
                end
            elseif fx.kind=='heal' then
                local old=target.hp
                target.hp=math.min(target.maxHp,target.hp+fx.amount)
                if target.hp>old then emit(w,'healed',{entity=target.id}) end
            elseif fx.kind=='status' then
                Abilities.applyStatus(w,target,fx,abilityApi)
            end
        end
    end
end
local function combat(w,pending)
    local hits={};local protectors=Stats.protectors(w)
    for _,id in ipairs(ids(w)) do
        local e=w.entities[id]; local d=def(w,e)
        if e.alive and d then
            e.cooldown=math.max(0,(e.nextCommitTick or 0)-w.tick)
            -- Stacks fade once the hits stop: after the grace, a fixed amount a tick,
            -- faster on armour. Zero is nil so an unstacked unit serializes as before.
            if e.stackFixed then
                local rules=w.content.rules.stacks or {}
                if w.tick-(e.stackHit or 0)>(rules.grace or 15) then
                    e.stackFixed=e.stackFixed-((rules.decay or 30)+(rules.decayPerArmor or 6)*Stats.armor(w,e))
                    if e.stackFixed<=0 then e.stackFixed=nil;e.stackHit=nil end
                end
            end
            -- A channelling caster neither swings nor acquires; its weapon is the channel.
            if e.channel then e.attack=nil end
            if e.attack then
                local phase=e.attack
                if w.tick==phase.impact then
                    local target=w.entities[phase.target]
                    if validTarget(w,e,target) and G.weaponRange(w,e,target) then
                        phase.committed=true;e.nextCommitTick=w.tick+phase.period;e.cooldown=phase.period
                        if e.kind=='beastkeeper' and e.upgrades[1]==2 and w.tick-e.lastCombat>(w.content.rules.outOfCombatTicks or 60) then e.sprintUntil=w.tick+40 end
                        hits[#hits+1]={kind='damage',source=e.id,target=target.id,damage=math.max(1,Stats.damage(w,e,target)-Stats.armor(w,target,protectors)),stacks=d.applyStacks or nil}
                        e.lastCombat=w.tick;e.attackTick=w.tick;emit(w,'attack',{source=e.id,target=target.id})
                        -- Splash: every enemy on the ground within the radius of the target is hit
                        -- too, each against its own armour, in world order. Never allies, never air.
                        if d.splash and not airborne(w,target) then
                            for _,otherId in ipairs(ids(w)) do local other=w.entities[otherId]
                                if other.id~=target.id and other.alive and other.owner~=e.owner and other.category~='node' and other.category~='projectile' and not airborne(w,other) and inRange(target,other,d.splash) then
                                    local amount=math.max(1,Stats.damage(w,e,other)-Stats.armor(w,other,protectors))
                                    -- Inside a building, half of it gets through.
                                    if other.garrisoned then amount=math.max(1,math.floor(amount*(w.content.rules.garrisonDamagePercent or 50)/100)) end
                                    hits[#hits+1]={kind='damage',source=e.id,target=other.id,damage=amount}
                                end
                            end
                        end
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
            if d.damage and (e.category~='building' or e.remaining==0) and Stats.canAttack(w,e) and not e.channel then
                local target=w.entities[e.combatTarget]
                if validTarget(w,e,target) and G.weaponRange(w,e,target) then
                    halt(w,e)
                    local period=Stats.attackPeriod(w,e)
                    local windup=Stats.windup(w,e)
                    if not e.attack and w.tick+windup>=(e.nextCommitTick or 0) then
                        e.attack={target=target.id,start=w.tick,impact=w.tick+windup,finish=w.tick+period,period=period,dx=target.x-e.x,dy=target.y-e.y}
                        emit(w,'windup',{source=e.id,target=target.id})
                    end
                end
            end
        end
    end
    local killers={};local killerSource={}
    if pending then applyEffects(w,pending,killers,killerSource) end
    applyEffects(w,hits,killers,killerSource)
    local navChanged,deathChanged=false,false
    for _,id in ipairs(ids(w)) do
        local e=w.entities[id]
        if e.alive and e.hp<=0 then
            e.alive=false;e.hp=0;halt(w,e);Harvest.release(w,e);e.orders={};e.attack=nil;e.deathTick=w.tick;deathChanged=true
            if e.garrisoned then local b=w.entities[e.garrisoned];if b and b.occupants then for i=#b.occupants,1,-1 do if b.occupants[i]==id then table.remove(b.occupants,i) end end end;e.garrisoned=nil end
            if e.occupants then
                local claimed={}
                for _,oid in ipairs(e.occupants) do local o=w.entities[oid]
                    local x,y=nearest(w,F.cell(e.x)+e.size,F.cell(e.y)+e.size,nil,claimed,G.radius(w,o))
                    if x then claimed[Path.key(w.map,x,y)]=true;standAt(w,o,x,y) end
                    o.garrisoned=nil;G.invalidate(w);emit(w,'unloaded',{entity=o.id})
                end
                e.occupants=nil;G.invalidate(w)
            end
            emit(w,'death',{entity=id})
            if e.category=='building' then navChanged=true end
            local killer=killers[id]
            -- Authoritative tallies. The interface previously counted these from the
            -- events it happened to observe, which under-reports a kill made out of
            -- sight; these are part of the world and agree between peers.
            if e.owner>0 then
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
                local bounty=def(w,e).bounty;if bounty then local key=Sim.primaryResource(w.content);w.players[killer].resources[key]=(w.players[killer].resources[key] or 0)+bounty end
                local hero=w.entities[w.players[killer].hero or 0]
                if hero and hero.alive and inRange(hero,e,w.content.rules.xpRange) then local ed=def(w,e);hero.xp=hero.xp+(ed.xp or (ed.hero and (w.content.rules.heroXp or 80) or w.content.rules.combatXpPerFood and ed.food*w.content.rules.combatXpPerFood or 30)) end
            end
        end
    end
    if navChanged then w.navVersion=w.navVersion+1;rebuild(w) end;if w.content.rules.profile then require('src.sim.healing').step(w,emit) end; return deathChanged
end
function Sim.step(w,commands)
    w.tick=w.tick+1;w.events={};w.metrics.pathExpansions=0;w.metrics.directChecks=0;w.metrics.smoothChecks=0;w.metrics.bodyChecks=0
    -- Statuses are swept before commands, so nothing in the tick -- not a command, not
    -- a phase, not a view -- can observe one on a tick it is no longer active for.
    Abilities.expire(w,abilityApi)
    if w.result then return w.events end
    -- Both live only for the command-application part of the step and are removed
    -- before it returns, so neither reaches snapshots or canonical serialization.
    w.commandClaims={};w.destinationClaims=nil;G.beginStep(w)
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
    planFormations(w,ordered)
    for _,c in ipairs(ordered) do local before=#w.events;apply(w,c);local rejected=false;for i=before+1,#w.events do if w.events[i].kind=='rejected' then rejected=true end end;if not rejected then emit(w,'accepted',{player=c.player,sequence=c.sequence,entity=c.args.entity}) end end
    w.commandClaims=nil;w.destinationClaims=nil;w.groupSlots=nil
    -- Casts resolve after orders finish and before combat, so a stun landing this tick
    -- is already in force when the combat phase asks whether its victim may swing. The
    -- effects they produce join the tick's attack hits and are applied together, which
    -- is what makes a spell and a sword that land on the same tick resolve as one event
    -- rather than in whatever order the phases happen to run.
    combatOrders(w);economy(w);movement(w);visibility(w);finishOrders(w)
    for i=#pendingEffects,1,-1 do pendingEffects[i]=nil end
    Projectiles.step(w,pendingEffects,abilityApi)
    Abilities.step(w,pendingEffects,abilityApi)
    if combat(w,pendingEffects) then visibility(w) end
    local survivors={}
    for p=1,#w.players do
        w.players[p].defeated=Sim.defeated(w,p)
        if not w.players[p].defeated then survivors[#survivors+1]=p end
    end
    -- w.result is retained world state; emit owns what it is given, so hand it a copy.
    -- Headquarters are decided first, so destroying the last enemy one wins even on the
    -- tick a control hold would have run out.
    local controller=Control.step(w,emit)
    if #survivors<=1 then w.result={winner=survivors[1] or 0,tick=w.tick};emit(w,'victory',{winner=w.result.winner,tick=w.tick})
    elseif controller then w.result={winner=controller,tick=w.tick,reason='control'};emit(w,'victory',{winner=controller,tick=w.tick,reason='control'}) end
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
            visible=player.visible,knownResources=player.knownResources,
            coverage=player.coverage,callDown=player.callDown,landings=player.landings,pods=player.pods}
    end
    local ok,bytes=pcall(Codec.encode,{version=w.version,tick=w.tick,config=w.config,
        players=players,entities=w.entities,order=w.order,nextId=w.nextId,result=w.result,
        searches=w.searches,pathCursor=w.pathCursor,navVersion=w.navVersion,control=w.control})
    assert(ok,bytes);return bytes
end
-- Exposed so a regression test can prove w.blocked is recomputable, which is what
-- justifies leaving it out of the authoritative checkpoint.
function Sim.recomputeBlocked(w)
    local blocked=Codec.copy(w.map.blocked)
    for _,id in ipairs(w.order) do
        local e=w.entities[id]
        if e.alive and e.category~='unit' and e.category~='projectile' then
            local size=e.size or 1
            for y=F.cell(e.y),F.cell(e.y)+size-1 do
                for x=F.cell(e.x),F.cell(e.x)+size-1 do blocked[Path.key(w.map,x,y)]=true end
            end
        end
    end
    return blocked
end
return Sim
