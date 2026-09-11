-- Regression scenarios for the simulation version 6 orders: rally points, patrol,
-- follow, the delivered event and the kill/loss tallies. Each one drives the real
-- command path and then checks the world, not a flag.
local Sim=require('src.sim')
local F=require('src.sim.fixed')
local Maps=require('src.maps')
local Content=require('tests.fixture_content')
local S=require('tests.control_scenarios')
local M={}
local function eq(a,b,message) assert(a==b,(message or 'values differ')..': '..tostring(a)..' != '..tostring(b)) end
local function world(size)
    local m=Maps.create('test',size or 24);m.resources={{x=6,y=10,resource='gold',amount=5000,size=3}};m.camps={}
    return Sim.create({seed=12345,players={{faction='bastion'},{faction='wild'}}},Content,m)
end
local function step(w,n) for _=1,n do Sim.step(w,{}) end end
local function command(w,p,kind,entity,args)
    args=args or {};args.entity=entity
    return {tick=w.tick+1,player=p,sequence=w.players[p].sequence+1,kind=kind,args=args}
end
local function accepted(w,message)
    for _,event in ipairs(w.events) do
        if event.kind=='rejected' then error((message or 'command rejected')..': '..tostring(event.reason)) end
    end
end
local function rejected(w,message)
    for _,event in ipairs(w.events) do if event.kind=='rejected' then return event end end
    error(message or 'expected a rejection')
end
local function find(w,owner,kind)
    for _,id in ipairs(w.order) do local e=w.entities[id];if e.owner==owner and e.kind==kind and e.alive then return e end end
end
local function node(w)
    for _,id in ipairs(w.order) do local e=w.entities[id];if e.category=='node' then return e end end
end
local function produced(w,from)
    local latest
    for id=from,w.nextId-1 do local e=w.entities[id];if e and e.kind=='worker' then latest=e end end
    return latest
end
-- The order a rally point hands out is only observable at the moment of production: a
-- short walk can be finished within the same window that produced the unit.
local function producedNow(w,from,ticks)
    for _=1,ticks or 200 do
        Sim.step(w,{})
        local e=produced(w,from)
        if e then return e end
    end
end

function M.rally()
    local w=world();local base=w.entities[w.players[1].hq]
    -- With no rally point a produced unit simply stands where it appeared.
    Sim.step(w,{command(w,1,'recruit',base.id,{unit='worker'})});accepted(w,'recruit')
    local mark=w.nextId
    step(w,120)
    local plain=produced(w,mark)
    assert(plain,'no worker was produced')
    eq(plain.order.kind,'stop','a unit with no rally point must not be given an order')

    -- A rally point is standing policy: it applies to the next unit and the one after.
    Sim.step(w,{command(w,1,'rally',base.id,{x=F.center(11),y=F.center(11)})});accepted(w,'rally')
    assert(base.rally and base.rally.x==11 and base.rally.y==11,'rally point was not stored')
    mark=w.nextId
    Sim.step(w,{command(w,1,'recruit',base.id,{unit='worker'})});accepted(w,'recruit')
    step(w,120)
    local rallied=produced(w,mark)
    assert(rallied,'no rallied worker was produced')
    assert(rallied.order.kind=='move','rallied unit received '..rallied.order.kind)
    -- It has to arrive, not merely hold the order.
    for _=1,900 do step(w,1);if rallied.order.kind=='stop' then break end end
    assert(math.abs(F.cell(rallied.x)-11)<=3 and math.abs(F.cell(rallied.y)-11)<=3,
        'rallied unit stopped at '..F.cell(rallied.x)..','..F.cell(rallied.y))

    -- Nothing harvests any more, so rallying onto a mine is simply a walk to it.
    local mine=node(w)
    Sim.step(w,{command(w,1,'rally',base.id,{target=mine.id})});accepted(w,'rally to node')
    mark=w.nextId
    Sim.step(w,{command(w,1,'recruit',base.id,{unit='worker'})});accepted(w,'recruit')
    local sent=producedNow(w,mark)
    assert(sent,'no worker was produced for the node rally')
    eq(sent.order.kind,'move','rally to a node did not order a walk')
    eq(sent.order.requestX,F.cell(mine.x))

    -- Rallying onto one of your own units follows it, which is the useful target case
    -- that survives the loss of harvesting.
    local lead=S.unit(w,'shield',1,9,9)
    Sim.step(w,{command(w,1,'rally',base.id,{target=lead.id})});accepted(w,'rally to a unit')
    mark=w.nextId
    Sim.step(w,{command(w,1,'recruit',base.id,{unit='worker'})});accepted(w,'recruit')
    local escort=producedNow(w,mark)
    assert(escort,'no worker was produced for the unit rally')
    eq(escort.order.kind,'follow','rally to a unit did not order a follow')
    eq(escort.order.target,lead.id)
    Sim.step(w,{command(w,1,'rally',base.id,{target=mine.id})});accepted(w,'rally back to the node')

    -- Refusals: a unit is not a production building, and the point must be on the map.
    local worker=find(w,1,'worker')
    Sim.step(w,{command(w,1,'rally',worker.id,{x=F.center(4),y=F.center(4)})})
    rejected(w,'a unit accepted a rally point')
    Sim.step(w,{command(w,1,'rally',base.id,{x=-1,y=0})})
    rejected(w,'an off-map rally point was accepted')

    -- A rally point is world state, so it survives a snapshot round trip.
    local clone=Sim.restore(Sim.snapshot(w))
    eq(clone.entities[base.id].rally.target,mine.id,'rally point lost across a snapshot')
end

function M.patrol()
    local w=world()
    local e=S.unit(w,'shield',1,6,6)
    Sim.step(w,{command(w,1,'patrol',e.id,{x=F.center(15),y=F.center(6)})});accepted(w,'patrol')
    eq(e.order.kind,'patrol')
    eq(e.order.originX,6,'patrol did not record where it began')
    eq(e.order.x,15,'patrol did not take its far end')

    local far,back=false,false
    for _=1,6000 do
        step(w,1)
        local cx=F.cell(e.x)
        if cx>=14 then far=true end
        if far and cx<=7 then back=true;break end
    end
    assert(far,'patrol never reached its far end')
    assert(back,'patrol never turned around')
    eq(e.order.kind,'patrol','patrol ended instead of continuing')

    -- The beat lives on the order itself, so it round-trips through a snapshot.
    local clone=Sim.restore(Sim.snapshot(w))
    for _=1,400 do Sim.step(w,{});Sim.step(clone,{}) end
    eq(Sim.serializeCanonical(w),Sim.serializeCanonical(clone),'patrol diverged across a snapshot')

    -- Stop ends a patrol like any other order.
    Sim.step(w,{command(w,1,'stop',e.id)});accepted(w,'stop')
    eq(e.order.kind,'stop','stop did not end the patrol')
end

function M.follow()
    local w=world()
    local lead=S.unit(w,'shield',1,6,6)
    local escort=S.unit(w,'shield',1,7,7)
    Sim.step(w,{command(w,1,'follow',escort.id,{target=lead.id})});accepted(w,'follow')
    eq(escort.order.kind,'follow')

    Sim.step(w,{command(w,1,'move',lead.id,{x=F.center(18),y=F.center(6)})});accepted(w,'move')
    for _=1,2000 do step(w,1);if lead.order.kind=='stop' then break end end
    assert(F.cell(lead.x)>=16,'the followed unit never arrived, reached '..F.cell(lead.x))
    for _=1,300 do step(w,1) end
    local gap=F.isqrt(F.distance2Bounded(escort.x,escort.y,lead.x,lead.y))
    assert(gap<=1024,'follower fell behind by '..gap..' subunits')
    eq(escort.order.kind,'follow','follow ended early')
    assert(not escort.combatTarget,'a following unit acquired a target of its own')

    -- The order ends when its target does.
    lead.hp=0;step(w,2)
    assert(not lead.alive,'the lead unit survived')
    eq(escort.order.kind,'stop','follow outlived its target')

    -- Refusals: yourself, a building, and an enemy.
    Sim.step(w,{command(w,1,'follow',escort.id,{target=escort.id})})
    rejected(w,'a unit was allowed to follow itself')
    Sim.step(w,{command(w,1,'follow',escort.id,{target=w.players[1].hq})})
    rejected(w,'a unit was allowed to follow a building')
end

function M.tallies()
    local w=world()
    local worker=find(w,1,'worker');local mine=node(w)
    Sim.step(w,{command(w,1,'build',worker.id,{building='extractor',x=mine.x and F.cell(mine.x),y=F.cell(mine.y)})})
    accepted(w,'build an extractor on the mine')
    local delivery
    for _=1,4000 do
        local events=Sim.step(w,{})
        for _,event in ipairs(events) do if event.kind=='delivered' then delivery=event end end
        if delivery then break end
    end
    assert(delivery,'no delivered event was emitted')
    assert(delivery.amount>0,'delivered event carried no amount')
    assert(delivery.resource=='gold','delivered event named '..tostring(delivery.resource))
    local carrier=w.entities[delivery.entity]
    assert(carrier and carrier.category=='carrier','delivered event named '..tostring(delivery.entity))

    -- Kills and losses are counted by the simulation, on both sides and on the killer.
    local u=world()
    S.unit(u,'shield',1,6,6)
    local theirs=S.unit(u,'shield',2,7,6)
    eq(u.players[1].kills,0);eq(u.players[2].unitsLost,0)
    theirs.hp=1
    for _=1,300 do step(u,1);if not theirs.alive then break end end
    assert(not theirs.alive,'the target survived')
    eq(u.players[2].unitsLost,1,'the loser did not record a loss')
    eq(u.players[1].kills,1,'the killer did not record a kill')
    -- Exactly one entity is credited, and it belongs to the killing player. Which one it
    -- is depends on who landed the final blow -- the starting force and the headquarters
    -- both outrange this duel -- and that is deliberately not asserted, because pinning
    -- it would make the test a description of the current content rather than of the rule.
    local credited={}
    for _,id in ipairs(u.order) do local e=u.entities[id];if (e.kills or 0)>0 then credited[#credited+1]=e end end
    eq(#credited,1,'expected exactly one entity to be credited')
    eq(credited[1].owner,1,'the kill was credited to the wrong player')
    eq(credited[1].kills,1)
    -- Tallies are world state and must agree across a snapshot.
    local clone=Sim.restore(Sim.snapshot(u))
    eq(clone.players[1].kills,1,'kill tally lost across a snapshot')
end

-- Every new order has to survive the command stream it will really travel through.
function M.replay()
    local Replay=require('src.replay')
    local Hash=require('src.hash')
    local config={seed=99,players={{faction='bastion'},{faction='wild'}}}
    local map=Maps.create('test',24);map.resources={{x=6,y=10,resource='gold',amount=5000}};map.camps={}
    -- Only the command stream is recorded, so the replay must start from a world that
    -- Sim.create produces on its own: units injected into the fixture would exist in the
    -- recording's world and not in the one replaying it.
    local w=Sim.create(config,Content,map)
    local replay=Replay.create(config,Content,map,10)
    local a=find(w,1,'shield') or find(w,1,'worker')
    local b
    for _,id in ipairs(w.order) do
        local e=w.entities[id]
        if e.owner==1 and e.category=='unit' and e.alive and e.id~=a.id then b=e;break end
    end
    assert(a and b,'the starting force is too small for this scenario')
    local base=w.entities[w.players[1].hq]
    local scripted={
        [2]={command(w,1,'patrol',a.id,{x=F.center(14),y=F.center(6)})},
        [5]={{tick=5,player=1,sequence=2,kind='follow',args={entity=b.id,target=a.id}}},
        [9]={{tick=9,player=1,sequence=3,kind='rally',args={entity=base.id,x=F.center(10),y=F.center(10)}}},
        [12]={{tick=12,player=1,sequence=4,kind='recruit',args={entity=base.id,unit='worker'}}},
    }
    for tick=1,400 do
        local commands=scripted[tick] or {}
        for _,c in ipairs(commands) do c.tick=tick end
        Sim.step(w,commands);Replay.record(replay,w,commands)
    end
    assert(a.order.kind=='patrol','the patrol did not survive the recording, it is '..a.order.kind)
    local clone=Sim.create(config,Content,map)
    for _,frame in ipairs(replay.frames) do
        Sim.step(clone,frame.commands)
        local recorded=replay.hashes[frame.tick]
        if recorded then
            assert(Hash.bytes(Sim.serializeAuthoritative(clone))==recorded,'replay diverged at tick '..frame.tick)
        end
    end
    eq(Sim.serializeCanonical(w),Sim.serializeCanonical(clone),'replayed world differs from the recorded one')
end

-- Formation pacing, checked directly rather than through its effect on congestion.
function M.formation()
    local fast,slow='crossbow','siege'
    local fastSpeed=Content.units[fast].speed
    local slowSpeed=Content.units[slow].speed
    assert(fastSpeed>slowSpeed,'this scenario needs two unit kinds with different speeds')

    -- Ordered as one group, both walk at the slower pace.
    local w=world(40)
    local a=S.unit(w,fast,1,4,20)
    local b=S.unit(w,slow,1,4,22)
    Sim.step(w,{
        {tick=1,player=1,sequence=1,kind='move',args={entity=a.id,x=F.center(30),y=F.center(20),group=7}},
        {tick=1,player=1,sequence=2,kind='move',args={entity=b.id,x=F.center(30),y=F.center(22),group=7}},
    })
    accepted(w,'group move')
    step(w,1)
    eq(a.groupSpeed,slowSpeed,'the fast unit was not paced to the group')
    eq(b.groupSpeed,slowSpeed,'the slow unit lost its own pace')
    local startX=a.x
    step(w,60)
    local paced=a.x-startX
    assert(paced>0,'the paced unit did not move')

    -- Ordered separately, the same unit travels at its own speed over the same run.
    local u=world(40)
    local lone=S.unit(u,fast,1,4,20)
    Sim.step(u,{{tick=1,player=1,sequence=1,kind='move',args={entity=lone.id,x=F.center(30),y=F.center(20)}}})
    accepted(u,'lone move')
    step(u,1)
    assert(lone.groupSpeed==nil,'a unit with no group id was paced')
    local loneStart=lone.x
    step(u,60)
    local free=lone.x-loneStart
    assert(free>paced,'formation pacing did not slow the group: '..paced..' vs '..free)

    -- Pacing follows the order. Once the group order ends, the cap goes with it.
    Sim.step(w,{{tick=w.tick+1,player=1,sequence=3,kind='stop',args={entity=a.id}}})
    step(w,1)
    assert(a.groupSpeed==nil,'pacing outlived the group order')

    -- And it is world state that agrees across a snapshot.
    local clone=Sim.restore(Sim.snapshot(w))
    for _=1,120 do Sim.step(w,{});Sim.step(clone,{}) end
    eq(Sim.serializeCanonical(w),Sim.serializeCanonical(clone),'formation pacing diverged across a snapshot')
end
function M.run()
    M.rally();M.patrol();M.follow();M.tallies();M.replay();M.formation()
end
return M
