-- Worker harvesting, Brood War style. A worker ordered onto a resource node walks to it,
-- claims it if nobody else is loading there, loads for the resource's harvest time, walks
-- its load to the nearest completed drop-off it owns, is paid, and goes back. One worker
-- loads at a patch at a time: a second arrival hops to a free patch of the same resource
-- nearby, or waits its turn if there is none. A worker keeps its load through any other
-- order and can be told to return it.
--
-- Everything here is driven from the economy phase in `w.order`, with the same helpers
-- the rest of the simulation uses (passed in as `api`), so a harvesting worker walks,
-- halts and yields exactly like any other unit.
local F=require('src.sim.fixed')
local H={}
-- Whether this definition may harvest this node at all.
function H.canHarvest(d,node)
    return d~=nil and d.harvest~=nil and node~=nil and node.category=='node' and d.harvest[node.resource]~=nil
end
-- Where a load goes: the nearest completed drop-off the worker's owner has, by squared
-- distance with the entity id as a total-order tiebreak.
function H.dropoff(w,e)
    local best,bestDistance
    for _,id in ipairs(w.order) do
        local b=w.entities[id]
        if b.alive and b.owner==e.owner and b.category=='building' and b.remaining==0 then
            local d=w.content.buildings[b.kind]
            if d and d.dropoff then
                local distance=F.distance2Bounded(e.x,e.y,b.x,b.y)
                if not bestDistance or distance<bestDistance or (distance==bestDistance and id<best.id) then best=b;bestDistance=distance end
            end
        end
    end
    return best
end
-- The nearest living node of a resource within `radius` of the worker, measured to the
-- node's centre; `free` restricts it to patches nobody is loading at. Distance then id,
-- so every peer picks the same patch.
function H.nearestNode(w,e,resource,radius,free,except)
    local best,bestDistance
    for _,id in ipairs(w.order) do
        local n=w.entities[id]
        if n.alive and n.category=='node' and n.resource==resource and id~=except and (not free or not n.occupant) then
            local size=n.size or 1
            local distance=F.distance2Bounded(e.x,e.y,n.x+(size-1)*128,n.y+(size-1)*128)
            if distance<=radius*radius and (not bestDistance or distance<bestDistance or (distance==bestDistance and id<best.id)) then best=n;bestDistance=distance end
        end
    end
    return best
end
-- Called whenever a worker leaves its harvest order, or dies: the patch it was loading at
-- is free again and the half-finished load is lost. What it already carries is kept.
function H.release(w,e)
    local o=e.order
    if o and o.kind=='harvest' and o.target then
        local n=w.entities[o.target]
        if n and n.occupant==e.id then n.occupant=nil end
    end
    e.harvestUntil=nil
end
function H.step(w,e,api)
    local d=api.def(w,e);local o=e.order
    local search=w.content.rules.harvestSearch or 1536
    -- Half a cell past the body: any cell touching the patch or the drop-off, corners
    -- included, is close enough to work from, so the worker stops where the free-cell
    -- search first puts it instead of hunting for a side it cannot always reach.
    local reach=api.radius(w,e)+128
    if (e.carrying or 0)>0 then
        -- Loaded: walk it home. With nowhere to deliver, stand and keep it.
        local drop=H.dropoff(w,e)
        if not drop then return end
        if api.approachTarget(w,e,drop,reach) then
            local ledger=w.players[e.owner].resources;local resource=e.carryResource
            ledger[resource]=(ledger[resource] or 0)+e.carrying
            api.emit(w,'delivered',{entity=e.id,amount=e.carrying,resource=resource})
            e.carrying=0;e.carryResource=nil
            if o.deliver or not o.target then api.nextOrder(w,e) end
        end
        return
    end
    if not o.target then api.nextOrder(w,e);return end
    local node=w.entities[o.target]
    if not node or not node.alive then
        -- The patch is gone. The nearest of its resource within twice the search range
        -- takes over; otherwise the job is done and the worker says so.
        local next=H.nearestNode(w,e,o.resource,2*search,false,o.target)
        if next then o.target=next.id;e.harvestUntil=nil;return end
        api.emit(w,'harvest_ended',{entity=e.id,reason='exhausted'});api.nextOrder(w,e);return
    end
    if e.harvestUntil then
        if node.occupant~=e.id then e.harvestUntil=nil;return end
        if w.tick>=e.harvestUntil then
            local amount=math.min(d.carry or 8,node.amount)
            node.amount=node.amount-amount;node.occupant=nil
            e.carrying=amount;e.carryResource=node.resource;e.harvestUntil=nil
            if node.amount<=0 then node.alive=false;w.navVersion=w.navVersion+1;api.rebuild(w);api.emit(w,'depleted',{entity=node.id}) end
        end
        return
    end
    if api.approachTarget(w,e,node,reach) then
        if not node.occupant or node.occupant==e.id then
            node.occupant=e.id;e.harvestUntil=w.tick+d.harvest[node.resource]
            api.emit(w,'harvest_started',{entity=e.id,target=node.id})
        else
            local free=H.nearestNode(w,e,node.resource,search,true,node.id)
            if free then o.target=free.id end
        end
    end
end
return H
