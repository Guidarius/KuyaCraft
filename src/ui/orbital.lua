-- The Megacorp's orbital logistics as the interface shows them. `O.model` is a pure function
-- of the player's view and the content: the sidebar draws it and the Orbital Command's card
-- reads it, so the two can never disagree, and it can be tested with no window.
--
-- What it answers at a glance: which requisitions are producing (and how far along), which
-- are READY to land, which are waiting and whether a ready one is blocking them; how many
-- orbit slots and queue places there are; who sits in the open pod; how many pods exist,
-- are away, or are still locked; and whether a pod can launch now, and if not, why and when.
local O={}
O.WIDTH=136
function O.active(view,content)
    local faction=content.factions[view.player.faction]
    return faction~=nil and faction.coverage==true and view.player.orbit~=nil
end
local function seconds(ticks) return math.max(0,math.ceil(ticks/20)) end
function O.model(view,content)
    local p=view.player;local orbit=p.orbit
    if not orbit then return nil end
    local tick=view.tick;local queue=p.callDown or {}
    local m={slots=orbit.slots,queueMax=orbit.queueMax,count=#queue,ready=0,producing=0,waiting=0,frames={},
        landings={},flights={},seats={},pips={},capacity=orbit.podCapacity}
    -- An item in one of the first `slots` places is produced; a finished one stays in its
    -- place until it is landed, and until then nothing behind it moves up into production.
    local readyInSlot=false
    for i=1,orbit.queueMax do
        local item=queue[i]
        if not item then m.frames[i]={index=i,state='empty'}
        else
            local d=content.buildings[item.kind];local total=math.max(1,d.buildTicks or 1)
            local state=item.remaining==0 and 'ready' or i<=orbit.slots and 'producing' or 'waiting'
            if state=='ready' and i<=orbit.slots then readyInSlot=true end
            m[state]=m[state]+1
            m.frames[i]={index=i,state=state,kind=item.kind,label=d.label,progress=1-item.remaining/total,seconds=seconds(item.remaining),position=i}
        end
    end
    -- Waiting behind a finished building that has not been landed is the one stall the
    -- player causes themselves, so it is named.
    m.blocked=readyInSlot and m.waiting>0
    for _,frame in ipairs(m.frames) do if frame.state=='waiting' then frame.blocked=m.blocked end end
    for i,landing in ipairs(p.landings or {}) do
        local d=content.buildings[landing.kind];local half=(d and d.size or 1)*128
        m.landings[i]={kind=landing.kind,label=d and d.label or landing.kind,seconds=seconds(landing.at-tick),x=landing.x*256+half,y=landing.y*256+half}
    end
    local pods=p.pods or {open={kinds={}},inFlight={},cooldownUntil=0}
    for i=1,orbit.podCapacity do
        local kind=pods.open.kinds[i];local d=kind and content.units[kind]
        m.seats[i]=kind and {index=i,kind=kind,label=d.label,heavy=(d.garrisonSlots or 1)>1,cost=d.cost} or {index=i,empty=true}
    end
    m.loaded=#pods.open.kinds
    local soonest
    for i,pod in ipairs(pods.inFlight) do
        local left=pod.at-tick;soonest=math.min(soonest or left,left)
        m.flights[i]={seconds=seconds(left),count=#pod.kinds,x=pod.x*256+128,y=pod.y*256+128}
    end
    m.inFlight=#pods.inFlight;m.unlocked=orbit.podsUnlocked;m.free=math.max(0,orbit.podsUnlocked-m.inFlight)
    for i=1,orbit.podsMax do m.pips[i]=i<=m.inFlight and 'flight' or i<=orbit.podsUnlocked and 'free' or 'locked' end
    -- The launch dial. The cooldown is always reported, because "how long until the next pod"
    -- is worth knowing while the pod is still being loaded; the state is what stops a launch now.
    local cooling=math.max(0,(pods.cooldownUntil or 0)-tick)
    local launch={cooldown=cooling,cooldownSeconds=seconds(cooling),progress=1-cooling/math.max(1,orbit.podCooldown)}
    if m.free==0 then launch.state='away';launch.seconds=seconds(soonest or 0);launch.reason='Every pod is away; the next lands in '..launch.seconds..'s'
    elseif cooling>0 then launch.state='cooling';launch.seconds=launch.cooldownSeconds;launch.reason='Next pod in '..launch.seconds..'s'
    elseif m.loaded==0 then launch.state='empty';launch.reason='Load a unit first'
    else launch.state='ready' end
    m.launch=launch
    return m
end
-- The queue index of the next building ready to land after `after`, wrapping; nil when none.
function O.nextReady(model,after)
    if not model or model.ready==0 then return nil end
    local n=model.queueMax
    for step=1,n do
        local i=((after or 0)+step-1)%n+1
        if model.frames[i].state=='ready' then return i end
    end
end
return O
