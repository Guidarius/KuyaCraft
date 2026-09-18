-- The Megacorp's territory and orbital logistics (simulation version 24), on the shipping
-- content: coverage against a brute-force oracle, placement inside it, rig income at the
-- online and offline rates, the call-down queue from requisition to landing, and the
-- unique headquarters.
local C=require('src.content')
local Sim=require('src.sim')
local Codec=require('src.sim.codec')
local F=require('src.sim.fixed')
local P=require('src.sim.path')
local M={}
local function eq(a,b,message) assert(a==b,(message or 'values differ')..': '..tostring(a)..' != '..tostring(b)) end
-- Player one is the Megacorp with its Command at (8,12); player two the Orders far away.
local function world(resources)
 return Sim.create({seed=5,players={{faction='megacorp'},{faction='orders'}}},C,{id='mc_fixture',width=64,height=64,starts={{x=8,y=12},{x=52,y=52}},blocked={},resources=resources or {},camps={}})
end
local function step(w,n,cs) for i=1,n do Sim.step(w,i==1 and cs or {}) end end
local function command(w,p,kind,e,args) args=args or {};args.entity=e;return {tick=w.tick+1,player=p,sequence=w.players[p].sequence+1,kind=kind,args=args} end
local function building(w,kind,owner,x,y)
 local id=w.nextId;w.nextId=id+1;local d=C.buildings[kind]
 local e={id=id,kind=kind,category='building',owner=owner,alive=true,x=F.center(x),y=F.center(y),size=d.size,hp=d.hp,maxHp=d.hp,remaining=0,queue={},order={kind='stop'},orders={},path={},pathIndex=1,cooldown=0,lastCombat=-1000}
 w.entities[id]=e;w.order[#w.order+1]=id;w.navVersion=w.navVersion+1;w.blocked=Sim.recomputeBlocked(w);return e
end
local function node(w,x,y) for _,id in ipairs(w.order) do local e=w.entities[id];if e.category=='node' and F.cell(e.x)==x and F.cell(e.y)==y then return e end end end
local function find(w,p,kind) for _,id in ipairs(w.order) do local e=w.entities[id];if e.owner==p and e.kind==kind and e.alive then return e end end end
local function rejected(events) for _,ev in ipairs(events) do if ev.kind=='rejected' then return ev.reason end end end
-- What coverage should be: every cell within a source's radius of its footprint centre.
local function oracle(w,p)
 local set={}
 for _,id in ipairs(w.order) do local e=w.entities[id]
  if e.alive and e.owner==p and (e.category=='unit' or e.remaining==0) then
   local d=C.units[e.kind] or C.buildings[e.kind]
   if d.coverage then local r=d.coverage/256;local cx,cy=F.cell(e.x+((e.size or 1)-1)*128),F.cell(e.y+((e.size or 1)-1)*128)
    for y=0,w.map.height-1 do for x=0,w.map.width-1 do if (x-cx)*(x-cx)+(y-cy)*(y-cy)<=r*r then set[P.key(w.map,x,y)]=true end end end
   end
  end
 end
 return set
end

function M.opening()
 local w=world();eq(Sim.unitCount(w,1),1);local blimp=find(w,1,'command_blimp');assert(blimp,'the Megacorp starts without its Blimp')
 eq(w.players[1].resources.substrate,400);eq(Sim.supplyCap(w,1),10);assert(not w.players[1].hero)
 assert(C.units.command_blimp.flying and (C.units.command_blimp.food or 0)==0)
 -- The Command cannot be requisitioned; nothing but a listed building can.
 local hq=w.entities[w.players[1].hq]
 eq(rejected(Sim.step(w,{command(w,1,'requisition',hq.id,{building='orbital_command'})})),'cannot requisition')
 eq(rejected(Sim.step(w,{command(w,1,'requisition',hq.id,{building='keep'})})),'cannot requisition')
 -- Nor can the Orders requisition anything.
 local keep=w.entities[w.players[2].hq]
 eq(rejected(Sim.step(w,{command(w,2,'requisition',keep.id,{building='depot'})})),'cannot requisition')
end

function M.coverage()
 local w=world();step(w,1)
 eq(Codec.encode(w.players[1].coverage),Codec.encode(oracle(w,1)),'coverage disagrees with the oracle at the start')
 assert(w.players[2].coverage==nil,'the Orders have coverage')
 building(w,'orbital_relay',1,40,12);step(w,1)
 eq(Codec.encode(w.players[1].coverage),Codec.encode(oracle(w,1)),'a relay was not added')
 -- The Blimp carries its own: coverage follows it as it flies.
 local blimp=find(w,1,'command_blimp')
 step(w,1,{command(w,1,'move',blimp.id,{x=F.center(30),y=F.center(40)})});step(w,120)
 assert(F.cell(blimp.y)>20,'the blimp did not fly');eq(Codec.encode(w.players[1].coverage),Codec.encode(oracle(w,1)),'coverage did not follow the blimp')
 -- And a dead relay is gone from it at once.
 local relay=find(w,1,'orbital_relay');relay.hp=0;step(w,1)
 eq(Codec.encode(w.players[1].coverage),Codec.encode(oracle(w,1)),'a dead relay still covers')
 assert(not w.players[1].coverage[P.key(w.map,52,12)],'a cell only the dead relay reached is still covered')
end

function M.placement()
 local w=world();w.players[1].resources.substrate=10000;step(w,1)
 local view=Sim.view(w,1)
 assert(Sim.placement(view,C,'mc_barracks',14,20),'a site inside coverage was refused')
 local ok,reason=Sim.placement(view,C,'mc_barracks',40,40);assert(not ok);eq(reason,'Outside relay coverage')
 -- A prepaid item ignores the price; an unpaid one does not.
 w.players[1].resources.substrate=0;view=Sim.view(w,1)
 ok,reason=Sim.placement(view,C,'mc_barracks',14,20);assert(not ok);eq(reason,'Insufficient resources')
 assert(Sim.placement(view,C,'mc_barracks',14,20,true),'a prepaid item was charged again')
end

function M.rigIncome()
 -- One patch inside the Command's coverage, one only a relay reaches.
 local w=world({{x=14,y=10,resource='substrate',amount=100000,size=1},{x=44,y=12,resource='substrate',amount=100000,size=1},{x=15,y=16,resource='charge',amount=100000,size=2}})
 local relay=building(w,'orbital_relay',1,40,12)
 local near=building(w,'substrate_rig',1,14,10);near.mine=node(w,14,10).id
 local far=building(w,'substrate_rig',1,44,12);far.mine=node(w,44,12).id
 local gas=building(w,'charge_rig',1,15,16);gas.mine=node(w,15,16).id
 step(w,1);local before,charge=w.players[1].resources.substrate,w.players[1].resources.charge
 local clone=Sim.restore(Sim.snapshot(w));step(w,1200);step(clone,1200);eq(Sim.serializeCanonical(w),Sim.serializeCanonical(clone))
 eq(w.players[1].resources.substrate-before,85*2,'two online rigs pay exactly 85 a minute each')
 eq(w.players[1].resources.charge-charge,100,'a charge rig pays exactly 100 a minute')
 eq(node(w,14,10).amount,100000-85,'the rig did not drain its patch by what it paid')
 -- The relay dies: the far rig drops to its offline rate, the near one does not.
 relay.hp=0;step(w,1);before=w.players[1].resources.substrate
 step(w,1200);eq(w.players[1].resources.substrate-before,85+36,'an uncovered rig did not fall to its offline rate')
end

function M.callDown()
 local w=world();local hq=w.entities[w.players[1].hq];w.players[1].resources.substrate=1000;step(w,1)
 eq(rejected(Sim.step(w,{command(w,1,'requisition',hq.id,{building='mc_barracks'})})),nil,'a requisition was refused')
 eq(w.players[1].resources.substrate,850,'the price was not paid at requisition');eq(#w.players[1].callDown,1)
 eq(rejected(Sim.step(w,{command(w,1,'land',hq.id,{index=1,x=14,y=20})})),'nothing ready to land')
 -- Produced in orbit for its build time, then ready.
 local ready;for _=1,C.buildings.mc_barracks.buildTicks do for _,ev in ipairs(Sim.step(w,{})) do if ev.kind=='call_down_ready' then ready=w.tick end end end
 assert(ready,'the item never became ready');eq(w.players[1].callDown[1].remaining,0)
 -- A landing outside coverage is refused with the placement's reason; inside, it descends.
 eq(rejected(Sim.step(w,{command(w,1,'land',hq.id,{index=1,x=40,y=40})})),'Outside relay coverage')
 assert(not rejected(Sim.step(w,{command(w,1,'land',hq.id,{index=1,x=14,y=20})})),'a landing inside coverage was refused')
 eq(#w.players[1].callDown,0);eq(#w.players[1].landings,1)
 local clone=Sim.restore(Sim.snapshot(w))
 local landed;for _=1,C.rules.descentTicks do Sim.step(clone,{});for _,ev in ipairs(Sim.step(w,{})) do if ev.kind=='landed' then landed=w.entities[ev.entity] end end end
 assert(landed and landed.kind=='mc_barracks' and landed.remaining==0 and landed.hp==landed.maxHp,'the barracks did not land complete')
 eq(Sim.serializeCanonical(w),Sim.serializeCanonical(clone));eq(#w.players[1].landings,0)
 -- A blocked site sends the item back to the head of the queue, ready, and nothing is lost.
 step(w,1,{command(w,1,'requisition',hq.id,{building='orbital_relay'})});step(w,C.buildings.orbital_relay.buildTicks)
 assert(not rejected(Sim.step(w,{command(w,1,'land',hq.id,{index=1,x=14,y=26})})))
 building(w,'bunker',1,14,26)
 local blocked;for _=1,C.rules.descentTicks do for _,ev in ipairs(Sim.step(w,{})) do if ev.kind=='landing_blocked' then blocked=true end end end
 assert(blocked,'a blocked landing was not reported');eq(#w.players[1].callDown,1);eq(w.players[1].callDown[1].remaining,0);eq(w.players[1].callDown[1].kind,'orbital_relay')
 -- Cancelling refunds three quarters.
 local substrate=w.players[1].resources.substrate
 step(w,1,{command(w,1,'cancel',hq.id,{callDown=1})});eq(w.players[1].resources.substrate,substrate+93);eq(#w.players[1].callDown,0)
 -- The queue holds five and refuses a sixth.
 for i=1,5 do w.players[1].resources.substrate=10000;step(w,1,{command(w,1,'requisition',hq.id,{building='substrate_rig'})}) end
 eq(#w.players[1].callDown,5);eq(rejected(Sim.step(w,{command(w,1,'requisition',hq.id,{building='substrate_rig'})})),'call-down queue full')
end

function M.tier()
 local w=world();local hq=w.entities[w.players[1].hq];w.players[1].resources.substrate=10000;step(w,1)
 for _=1,2 do step(w,1,{command(w,1,'requisition',hq.id,{building='mc_barracks'})}) end
 local first=w.players[1].callDown[1].remaining
 step(w,100);eq(w.players[1].callDown[1].remaining,first-100);eq(w.players[1].callDown[2].remaining,C.buildings.mc_barracks.buildTicks,'a second item progressed with one slot')
 building(w,'requisition_office',1,14,20);building(w,'requisition_office',1,14,24);eq(Sim.tier(w,1),2)
 step(w,100);eq(w.players[1].callDown[2].remaining,C.buildings.mc_barracks.buildTicks-100,'two offices did not open a second slot')
end

function M.uniqueHq()
 local w=world();building(w,'orbital_relay',1,20,20);step(w,1)
 local hq=w.entities[w.players[1].hq];hq.hp=0;step(w,1)
 assert(w.players[1].defeated,'the Megacorp survived the loss of its Command with a relay standing')
end
return M
