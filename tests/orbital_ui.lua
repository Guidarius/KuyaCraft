-- The orbital model (src/ui/orbital.lua): everything the Megacorp's sidebar and card show,
-- worked out from a view alone. Driven here by a real world so the view's `orbit` summary
-- is covered too.
local C=require('src.content')
local Sim=require('src.sim')
local F=require('src.sim.fixed')
local O=require('src.ui.orbital')
local T={}
local function eq(a,b,message) assert(a==b,(message or 'values differ')..': '..tostring(a)..' != '..tostring(b)) end
local function world()
    return Sim.create({seed=5,players={{faction='megacorp'},{faction='orders'}}},C,{id='orbital_fixture',width=64,height=64,starts={{x=8,y=12},{x=52,y=52}},blocked={},resources={},camps={}})
end
local function command(w,kind,args) local hq=w.players[1].hq;args=args or {};args.entity=hq;return {tick=w.tick+1,player=1,sequence=w.players[1].sequence+1,kind=kind,args=args} end
local function step(w,n,cs) for i=1,n do Sim.step(w,i==1 and cs or {}) end end
local function building(w,kind,x,y)
    local id=w.nextId;w.nextId=id+1;local d=C.buildings[kind]
    local e={id=id,kind=kind,category='building',owner=1,alive=true,x=F.center(x),y=F.center(y),size=d.size,hp=d.hp,maxHp=d.hp,remaining=0,queue={},order={kind='stop'},orders={},path={},pathIndex=1,cooldown=0,lastCombat=-1000}
    w.entities[id]=e;w.order[#w.order+1]=id;w.navVersion=w.navVersion+1;w.blocked=Sim.recomputeBlocked(w);return e
end
local function model(w) return O.model(Sim.view(w,1),C) end
function T.run()
    local w=world();w.players[1].resources={substrate=5000,charge=5000};step(w,1)
    assert(O.active(Sim.view(w,1),C),'the Megacorp has no orbital interface');assert(not O.active(Sim.view(w,2),C),'the Orders have one');eq(O.model(Sim.view(w,2),C),nil)
    -- Nothing ordered: five empty frames, one slot, one free pod, two locked, nothing to launch.
    local m=model(w)
    eq(m.slots,1);eq(m.queueMax,5);eq(#m.frames,5);eq(m.frames[1].state,'empty');eq(m.count,0)
    eq(m.pips[1],'free');eq(m.pips[2],'locked');eq(m.pips[3],'locked');eq(m.launch.state,'empty');eq(#m.seats,4);assert(m.seats[1].empty)
    -- Three orders with one slot: the first produces with progress, the others wait by number.
    for _,kind in ipairs({'mc_barracks','orbital_relay','requisition_office'}) do step(w,1,{command(w,'requisition',{building=kind})}) end
    step(w,100);m=model(w)
    eq(m.frames[1].state,'producing');eq(m.frames[2].state,'waiting');eq(m.frames[3].state,'waiting');eq(m.frames[2].position,2);eq(m.frames[4].state,'empty')
    local barracks=C.buildings.mc_barracks.buildTicks
    assert(math.abs(m.frames[1].progress-(1-m.frames[1].seconds*20/barracks))<.06,'progress does not follow the build time');eq(m.frames[1].seconds,math.ceil((barracks-102)/20));assert(not m.blocked)
    -- Finished and not landed: READY, and it blocks the ones behind it, which the model says.
    step(w,barracks);m=model(w)
    eq(m.frames[1].state,'ready');eq(m.ready,1);eq(m.frames[2].state,'waiting');assert(m.blocked and m.frames[2].blocked,'a ready building holding the slot was not reported as blocking')
    eq(O.nextReady(m,0),1);eq(O.nextReady(m,1),1,'the only ready item does not wrap to itself')
    -- Landed: a descent with its countdown, and the queue moves up and produces again.
    assert(Sim.placement(Sim.view(w,1),C,'mc_barracks',14,20,true));step(w,1,{command(w,'land',{index=1,x=14,y=20})});m=model(w)
    eq(#m.landings,1);eq(m.landings[1].label,'Barracks');eq(m.landings[1].seconds,math.ceil((C.rules.descentTicks-0)/20));eq(m.frames[1].state,'producing');eq(m.frames[1].kind,'orbital_relay');assert(not m.blocked)
    -- Two Offices: a second slot, so two items produce at once, and two more pods unlock.
    building(w,'requisition_office',20,30);building(w,'requisition_office',26,30);step(w,1);m=model(w)
    eq(m.slots,2);eq(m.frames[1].state,'producing');eq(m.frames[2].state,'producing');eq(m.pips[2],'free');eq(m.pips[3],'free');eq(m.unlocked,3)
    -- The pod: seats in load order, the heavy one marked; ready to launch; then cooling, with the
    -- cooldown reported while the next pod is loaded; then every pod away.
    step(w,C.rules.descentTicks+2);building(w,'armory',32,30);step(w,1)
    for _,unit in ipairs({'associate','enforcer'}) do step(w,1,{command(w,'pod_load',{unit=unit})}) end;m=model(w)
    eq(m.loaded,2);eq(m.seats[1].kind,'associate');eq(m.seats[2].kind,'enforcer');assert(m.seats[2].heavy and not m.seats[1].heavy);assert(m.seats[3].empty);eq(m.launch.state,'ready')
    step(w,1,{command(w,'pod_launch',{x=14,y=26})});m=model(w)
    eq(m.launch.state,'cooling');eq(m.launch.seconds,math.ceil(C.rules.podCooldown/20));eq(m.inFlight,1);eq(m.pips[1],'flight');eq(m.free,2);eq(m.flights[1].count,2);assert(m.launch.progress<.05)
    step(w,1,{command(w,'pod_load',{unit='associate'})});step(w,20);m=model(w);eq(m.launch.state,'cooling');eq(m.loaded,1);assert(m.launch.progress>.05)
    -- A seat is refunded on its own (simulation version 27): the price back, the gap closed.
    step(w,1,{command(w,'pod_load',{unit='enforcer'})});local before=w.players[1].resources.substrate
    step(w,1,{command(w,'cancel',{pod=true,seat=1})});m=model(w)
    eq(w.players[1].resources.substrate,before+C.units.associate.cost.substrate);eq(m.loaded,1);eq(m.seats[1].kind,'enforcer')
    local events=Sim.step(w,{command(w,'cancel',{pod=true,seat=4})});local reason;for _,ev in ipairs(events) do if ev.kind=='rejected' then reason=ev.reason end end;eq(reason,'nothing to cancel')
    -- The summary is derived, never stored: a snapshot round trip reproduces the same model.
    local clone=Sim.restore(Sim.snapshot(w));eq(Sim.serializeCanonical(clone),Sim.serializeCanonical(w));eq(O.model(Sim.view(clone,1),C).launch.state,model(w).launch.state);assert(w.players[1].orbit==nil,'the orbit summary was stored on the player')
end
return T
