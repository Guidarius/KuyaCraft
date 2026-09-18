-- Worker harvesting (simulation version 21), driven through the real command path on a
-- copy of the fixture whose worker may harvest gold: forty ticks a load, eight per trip.
local Sim=require('src.sim')
local F=require('src.sim.fixed')
local Codec=require('src.sim.codec')
local Maps=require('src.maps')
local Fixture=require('tests.fixture_content')
local M={}
local function eq(a,b,message) assert(a==b,(message or 'values differ')..': '..tostring(a)..' != '..tostring(b)) end
local function content()
    local C=Codec.copy(Fixture)
    C.units.worker.harvest={gold=40};C.units.worker.carry=8;C.rules.harvestSearch=1536
    return C
end
-- A 24-cell map: player one's headquarters at (2,2), a one-cell gold patch four cells east
-- of its footprint at (9,3), and whatever else a scenario adds.
local function world(resources,C)
    local m=Maps.create('harvest',24);m.camps={}
    m.resources=resources or {{x=9,y=3,resource='gold',amount=5000,size=1}}
    local w=Sim.create({seed=3,players={{faction='bastion'},{faction='wild'}}},C or content(),m)
    -- Only one worker, so no other worker wanders into the scenario.
    local first
    for _,id in ipairs(w.order) do local e=w.entities[id];if e.owner==1 and e.category=='unit' then if e.kind=='worker' and not first then first=e else e.alive=false end end end
    return w,first
end
local function step(w,n,commands) for i=1,n do Sim.step(w,i==1 and (commands or {}) or {}) end end
-- `offset` numbers a second command issued on the same tick, so it is not a duplicate.
local function command(w,p,kind,e,args,offset)
    args=args or {};args.entity=e
    return {tick=w.tick+1,player=p,sequence=w.players[p].sequence+1+(offset or 0),kind=kind,args=args}
end
local function node(w,x,y) for _,id in ipairs(w.order) do local e=w.entities[id];if e.category=='node' and (not x or (F.cell(e.x)==x and F.cell(e.y)==y)) then return e end end end
local function find(w,p,kind) for _,id in ipairs(w.order) do local e=w.entities[id];if e.owner==p and e.kind==kind and e.alive then return e end end end
local function rejected(events) for _,ev in ipairs(events) do if ev.kind=='rejected' then return ev.reason end end end
-- Runs `n` ticks and collects the deliveries, with the tick each landed on.
local function run(w,n,commands)
    local deliveries={}
    for i=1,n do
        for _,ev in ipairs(Sim.step(w,i==1 and (commands or {}) or {})) do
            if ev.kind=='delivered' then deliveries[#deliveries+1]={tick=w.tick,entity=ev.entity,amount=ev.amount,resource=ev.resource,x=ev.x,y=ev.y} end
        end
    end
    return deliveries
end
local function building(w,kind,owner,x,y,remaining)
    local d=w.content.buildings[kind];local id=w.nextId;w.nextId=id+1
    local e={id=id,kind=kind,category='building',owner=owner,alive=true,x=F.center(x),y=F.center(y),size=d.size,hp=d.hp,maxHp=d.hp,remaining=remaining or 0,queue={},order={kind='stop'},orders={},path={},pathIndex=1,cooldown=0,lastCombat=-1000}
    w.entities[id]=e;w.order[#w.order+1]=id;w.navVersion=w.navVersion+1;w.blocked=Sim.recomputeBlocked(w);return e
end

function M.cadence()
    local w,worker=world();local patch=node(w);local before=w.players[1].resources.gold
    local deliveries=run(w,800,{command(w,1,'harvest',worker.id,{target=patch.id})})
    assert(#deliveries>=4,'only '..#deliveries..' deliveries in 800 ticks')
    for _,d in ipairs(deliveries) do eq(d.amount,8);eq(d.resource,'gold');eq(d.entity,worker.id) end
    eq(w.players[1].resources.gold,before+8*#deliveries,'the ledger disagrees with the deliveries')
    eq(patch.amount,5000-8*#deliveries-(worker.carrying or 0),'the patch disagrees with the deliveries')
    -- Steady state is a fixed round trip: every interval after the first is the same.
    for i=3,#deliveries do eq(deliveries[i].tick-deliveries[i-1].tick,deliveries[2].tick-deliveries[1].tick,'trip '..i..' took a different time') end
    assert(deliveries[2].tick-deliveries[1].tick>40,'a round trip is shorter than loading alone')
    -- The worker is still at work, with nothing queued behind the standing order.
    eq(worker.order.kind,'harvest');eq(#worker.orders,0)
end

function M.patches()
    -- Two workers, one patch and a second free patch three cells further: the second worker
    -- finds the patch busy and hops to the free one, and nobody ever loads at an occupied patch.
    local w,a=world({{x=9,y=3,resource='gold',amount=5000,size=1},{x=9,y=6,resource='gold',amount=5000,size=1}})
    local b=Codec.copy(a);b.id=w.nextId;w.nextId=b.id+1;b.x=a.x+256;w.entities[b.id]=b;w.order[#w.order+1]=b.id
    local near,far=node(w,9,3),node(w,9,6)
    local seen={};local exclusive=true
    local deliveries=run(w,900,{command(w,1,'harvest',a.id,{target=near.id}),command(w,1,'harvest',b.id,{target=near.id},1)})
    for _,d in ipairs(deliveries) do seen[d.entity]=(seen[d.entity] or 0)+1 end
    assert((seen[a.id] or 0)>=2 and (seen[b.id] or 0)>=2,'both workers should be delivering: '..tostring(seen[a.id])..' and '..tostring(seen[b.id]))
    assert(a.order.target~=b.order.target,'the second worker never hopped to the free patch')
    -- With one patch only, the second waits its turn and the patch is never double-loaded.
    w,a=world();b=Codec.copy(a);b.id=w.nextId;w.nextId=b.id+1;b.x=a.x+256;w.entities[b.id]=b;w.order[#w.order+1]=b.id
    local patch=node(w);seen={}
    for i=1,900 do
        for _,ev in ipairs(Sim.step(w,i==1 and {command(w,1,'harvest',a.id,{target=patch.id}),command(w,1,'harvest',b.id,{target=patch.id},1)} or {})) do
            if ev.kind=='delivered' then seen[ev.entity]=(seen[ev.entity] or 0)+1 end
        end
        if a.harvestUntil and b.harvestUntil then exclusive=false end
        if a.harvestUntil then eq(patch.occupant,a.id) end
        if b.harvestUntil then eq(patch.occupant,b.id) end
    end
    assert(exclusive,'two workers loaded at one patch at once')
    assert((seen[a.id] or 0)>=1 and (seen[b.id] or 0)>=1,'the waiting worker never got its turn')
    eq(a.order.kind,'harvest');eq(b.order.kind,'harvest')
end

function M.depletion()
    local w,worker=world({{x=9,y=3,resource='gold',amount=16,size=1}});local patch=node(w)
    local ended,depleted=false,false
    for i=1,600 do
        for _,ev in ipairs(Sim.step(w,i==1 and {command(w,1,'harvest',worker.id,{target=patch.id})} or {})) do
            if ev.kind=='harvest_ended' then ended=true;eq(ev.reason,'exhausted') end
            if ev.kind=='depleted' then depleted=true;eq(ev.entity,patch.id) end
        end
    end
    assert(depleted,'the patch never depleted');assert(not patch.alive,'a depleted patch is still alive')
    assert(ended,'the worker never reported the end of its job')
    eq(worker.order.kind,'stop','the worker is not idle');eq(worker.carrying,0)
    assert(not w.blocked[require('src.sim.path').key(w.map,9,3)],'a depleted patch still blocks the cell')
    -- With another patch of the same resource within reach, the worker moves on instead.
    w,worker=world({{x=9,y=3,resource='gold',amount=8,size=1},{x=9,y=6,resource='gold',amount=5000,size=1}})
    patch=node(w,9,3);local other=node(w,9,6)
    local deliveries=run(w,700,{command(w,1,'harvest',worker.id,{target=patch.id})})
    assert(#deliveries>=2,'the worker did not move on to the next patch');eq(worker.order.target,other.id)
end

function M.dropoff()
    -- The patch is far from the headquarters and an outpost site stands beside it. Loads go
    -- to the headquarters until the outpost is complete, then to the outpost.
    local w,worker=world({{x=18,y=3,resource='gold',amount=5000,size=1}});local patch=node(w)
    w.players[1].visible[require('src.sim.path').key(w.map,18,3)]=true
    local site=building(w,'outpost',1,18,6,100);local hq=w.entities[w.players[1].hq]
    local deliveries=run(w,700,{command(w,1,'harvest',worker.id,{target=patch.id})})
    assert(#deliveries>=1,'no delivery to the headquarters')
    local first=deliveries[1]
    assert(F.distance2Bounded(first.x,first.y,hq.x,hq.y)<F.distance2Bounded(first.x,first.y,site.x,site.y),'delivered to a site under construction')
    site.remaining=0
    deliveries=run(w,400)
    assert(#deliveries>=1,'no delivery after the outpost finished')
    local last=deliveries[#deliveries]
    assert(F.distance2Bounded(last.x,last.y,site.x,site.y)<F.distance2Bounded(last.x,last.y,hq.x,hq.y),'the finished outpost was not preferred')
end

function M.returnCargo()
    local w,worker=world();local patch=node(w)
    step(w,1,{command(w,1,'harvest',worker.id,{target=patch.id})})
    local ticks=0;while (worker.carrying or 0)==0 and ticks<400 do step(w,1);ticks=ticks+1 end
    assert(worker.carrying==8,'the worker never loaded')
    -- Sent elsewhere, it keeps its load and frees the patch; told to return, it delivers and stops.
    step(w,1,{command(w,1,'move',worker.id,{x=F.center(12),y=F.center(12)})})
    eq(worker.carrying,8);assert(patch.occupant==nil,'a worker that left still occupies the patch');assert(worker.harvestUntil==nil)
    local before=w.players[1].resources.gold
    local deliveries=run(w,400,{command(w,1,'harvest',worker.id,{deliver=true})})
    eq(#deliveries,1);eq(w.players[1].resources.gold,before+8);eq(worker.carrying,0);eq(worker.order.kind,'stop')
    -- Nothing to return: the order ends at once.
    step(w,1,{command(w,1,'harvest',worker.id,{deliver=true})});step(w,1);eq(worker.order.kind,'stop')
end

function M.snapshot()
    local w,worker=world();local patch=node(w)
    step(w,1,{command(w,1,'harvest',worker.id,{target=patch.id})})
    local ticks=0;while not worker.harvestUntil and ticks<400 do step(w,1);ticks=ticks+1 end
    assert(worker.harvestUntil and patch.occupant==worker.id,'never started loading')
    local clone=Sim.restore(Sim.snapshot(w))
    for _=1,300 do Sim.step(w,{});Sim.step(clone,{});eq(Sim.serializeCanonical(w),Sim.serializeCanonical(clone)) end
    assert(w.players[1].resources.gold>Fixture.rules.startingResources.gold,'nothing delivered after the snapshot')
    -- The load and the loading are visible to everyone; the patch's occupant is nobody's
    -- business, not even its owner's, since a node belongs to no one.
    local view=Sim.view(w,1)
    local seen,laden;for _,e in ipairs(view.entities) do if e.id==patch.id then seen=e elseif e.id==worker.id then laden=e end end
    assert(seen and seen.occupant==nil,'a view can read who is loading at a patch')
    assert(laden and (laden.carrying~=nil or laden.harvestUntil~=nil),'the view hides the load')
end

function M.rally()
    local w,worker=world();local patch=node(w);local hq=w.entities[w.players[1].hq]
    w.players[1].resources.gold=10000
    step(w,1,{command(w,1,'rally',hq.id,{target=patch.id})})
    local from=w.nextId
    step(w,1,{command(w,1,'recruit',hq.id,{unit='worker'})});step(w,120)
    local fresh;for id=from,w.nextId-1 do local e=w.entities[id];if e and e.kind=='worker' then fresh=e end end
    assert(fresh,'no worker was produced');eq(fresh.order.kind,'harvest');eq(fresh.order.target,patch.id)
    -- Rallied onto a patch it cannot work, a unit just walks to it, as before.
    w,worker=world({{x=9,y=6,resource='lumber',amount=5000,size=1}});patch=node(w);hq=w.entities[w.players[1].hq]
    w.players[1].resources.gold=10000
    step(w,1,{command(w,1,'rally',hq.id,{target=patch.id})})
    -- Caught on the tick it appears, before the short walk ends.
    from=w.nextId;step(w,1,{command(w,1,'recruit',hq.id,{unit='worker'})});fresh=nil
    for _=1,120 do
        step(w,1)
        for id=from,w.nextId-1 do local e=w.entities[id];if e and e.kind=='worker' then fresh=e end end
        if fresh then break end
    end
    assert(fresh,'no worker was produced');eq(fresh.order.kind,'move')
end

function M.rejections()
    local w,worker=world({{x=9,y=3,resource='gold',amount=5000,size=1},{x=9,y=6,resource='lumber',amount=5000,size=1},{x=20,y=20,resource='gold',amount=5000,size=1}})
    local gold,lumber,hidden=node(w,9,3),node(w,9,6),node(w,20,20)
    local shield=Codec.copy(worker);shield.id=w.nextId;w.nextId=shield.id+1;shield.kind='shield';w.entities[shield.id]=shield;w.order[#w.order+1]=shield.id
    eq(rejected(Sim.step(w,{command(w,1,'harvest',shield.id,{target=gold.id})})),'cannot harvest')
    eq(rejected(Sim.step(w,{command(w,1,'harvest',worker.id,{target=lumber.id})})),'cannot harvest that')
    eq(rejected(Sim.step(w,{command(w,1,'harvest',worker.id,{target=worker.id})})),'cannot harvest that')
    eq(rejected(Sim.step(w,{command(w,1,'harvest',worker.id,{target=hidden.id})})),'target not visible')
    assert(not rejected(Sim.step(w,{command(w,1,'harvest',worker.id,{target=gold.id})})),'a legal harvest was refused')
    eq(worker.order.kind,'harvest');eq(worker.order.resource,'gold')
end

function M.rightClick()
    -- The presentation's right-click intent: a worker sent onto a patch it can work is
    -- given a harvest order, a soldier a move.
    local Input=require('src.ui.input')
    local w,worker=world();local patch=node(w)
    local shield=Codec.copy(worker);shield.id=w.nextId;w.nextId=shield.id+1;shield.kind='shield';w.entities[shield.id]=shield;w.order[#w.order+1]=shield.id
    Sim.step(w,{})
    local audio={};function audio:play() end;function audio:ack() end;function audio:selected() end
    local app={world=w,content=w.content,view=Sim.view(w,1),player=1,selected={worker.id,shield.id},settings={bindings={}},clock=0,queue={},audio=audio}
    function app:entity(id) for _,e in ipairs(self.view.entities) do if e.id==id then return e end end end
    function app:command(kind,id,args) self.queue[#self.queue+1]={kind=kind,id=id,args=args} end
    local keyboard=love.keyboard.isDown;love.keyboard.isDown=function() return false end
    local ok,err=pcall(Input.intent,app,patch.x,patch.y,app:entity(patch.id))
    love.keyboard.isDown=keyboard
    assert(ok,err)
    eq(#app.queue,2)
    local byId={};for _,c in ipairs(app.queue) do byId[c.id]=c end
    eq(byId[worker.id].kind,'harvest');eq(byId[worker.id].args.target,patch.id)
    eq(byId[shield.id].kind,'move')
end
return M
