-- Drop pods and garrisons (simulation version 25), on the shipping content: the pod cycle
-- from loading to landing with its cooldown, limit and refund, and units inside buildings.
local C=require('src.content')
local Sim=require('src.sim')
local F=require('src.sim.fixed')
local M={}
local function eq(a,b,message) assert(a==b,(message or 'values differ')..': '..tostring(a)..' != '..tostring(b)) end
local function world(resources)
 return Sim.create({seed=5,players={{faction='megacorp'},{faction='orders'}}},C,{id='pod_fixture',width=64,height=64,starts={{x=8,y=12},{x=52,y=52}},blocked={},resources=resources or {},camps={}})
end
local function step(w,n,cs) for i=1,n do Sim.step(w,i==1 and cs or {}) end end
local function command(w,p,kind,e,args) args=args or {};args.entity=e;return {tick=w.tick+1,player=p,sequence=w.players[p].sequence+1,kind=kind,args=args} end
local function building(w,kind,owner,x,y)
 local id=w.nextId;w.nextId=id+1;local d=C.buildings[kind]
 local e={id=id,kind=kind,category='building',owner=owner,alive=true,x=F.center(x),y=F.center(y),size=d.size,hp=d.hp,maxHp=d.hp,remaining=0,queue={},order={kind='stop'},orders={},path={},pathIndex=1,cooldown=0,lastCombat=-1000}
 w.entities[id]=e;w.order[#w.order+1]=id;w.navVersion=w.navVersion+1;w.blocked=Sim.recomputeBlocked(w);return e
end
local function unit(w,kind,owner,x,y)
 local d=C.units[kind];local id=w.nextId;w.nextId=id+1
 local e={id=id,kind=kind,owner=owner,x=F.center(x),y=F.center(y),category='unit',alive=true,hp=d.hp,maxHp=d.hp,size=1,cooldown=0,path={},pathIndex=1,order={kind='stop'},orders={},lastCombat=-1000}
 w.entities[id]=e;w.order[#w.order+1]=id;return e
end
local function rejected(events) for _,ev in ipairs(events) do if ev.kind=='rejected' then return ev.reason end end end
local function units(w,p,kind) local out={};for _,id in ipairs(w.order) do local e=w.entities[id];if e.alive and e.owner==p and e.kind==kind then out[#out+1]=e end end;return out end

function M.cycle()
 local w=world();local hq=w.entities[w.players[1].hq];w.players[1].resources={substrate=1000,charge=1000};step(w,1)
 -- Nothing loads without its building; a loaded unit is paid for and counts against supply.
 eq(rejected(Sim.step(w,{command(w,1,'pod_load',hq.id,{unit='associate'})})),'requirement missing')
 building(w,'mc_barracks',1,14,20);step(w,1)
 local before=Sim.population(w,1)
 for _=1,2 do assert(not rejected(Sim.step(w,{command(w,1,'pod_load',hq.id,{unit='associate'})})),'loading refused') end
 eq(w.players[1].resources.substrate,900);eq(Sim.population(w,1),before+2);eq(#w.players[1].pods.open.kinds,2)
 eq(rejected(Sim.step(w,{command(w,1,'pod_load',hq.id,{unit='medic'})})),'requirement missing')
 -- Launched onto covered ground only, then a descent, then the troops stand on a ring.
 eq(rejected(Sim.step(w,{command(w,1,'pod_launch',hq.id,{x=40,y=40})})),'Outside relay coverage')
 assert(not rejected(Sim.step(w,{command(w,1,'pod_launch',hq.id,{x=14,y=26})})),'a launch inside coverage was refused')
 eq(#w.players[1].pods.open.kinds,0);eq(#w.players[1].pods.inFlight,1);eq(Sim.population(w,1),before+2,'in-flight troops left the supply count')
 assert(not rejected(Sim.step(w,{command(w,1,'pod_load',hq.id,{unit='associate'})})))
 eq(rejected(Sim.step(w,{command(w,1,'pod_launch',hq.id,{x=14,y=26})})),'pod on cooldown')
 local clone=Sim.restore(Sim.snapshot(w));local landed
 for _=1,C.rules.descentTicks do Sim.step(clone,{});for _,ev in ipairs(Sim.step(w,{})) do if ev.kind=='pod_landed' then landed=true end end end
 assert(landed,'the pod never landed');eq(Sim.serializeCanonical(w),Sim.serializeCanonical(clone))
 local troops=units(w,1,'associate');eq(#troops,2)
 for _,t in ipairs(troops) do assert(math.abs(F.cell(t.x)-14)<=2 and math.abs(F.cell(t.y)-26)<=2,'a trooper landed far from the pod') end
 eq(Sim.population(w,1),before+3,'landed troops are counted twice or not at all')
 -- With no Requisition Office there is one pod: a second launch waits until it has landed.
 w.players[1].pods.cooldownUntil=0
 assert(not rejected(Sim.step(w,{command(w,1,'pod_launch',hq.id,{x=14,y=26})})))
 for _=1,C.rules.podCapacity do step(w,1,{command(w,1,'pod_load',hq.id,{unit='associate'})}) end
 eq(rejected(Sim.step(w,{command(w,1,'pod_load',hq.id,{unit='associate'})})),'pod is full')
 w.players[1].pods.cooldownUntil=0
 eq(rejected(Sim.step(w,{command(w,1,'pod_launch',hq.id,{x=14,y=26})})),'no pod available')
 -- Cancelling the open pod refunds everything in it.
 local substrate=w.players[1].resources.substrate
 step(w,1,{command(w,1,'cancel',hq.id,{pod=true})});eq(w.players[1].resources.substrate,substrate+200);eq(#w.players[1].pods.open.kinds,0)
end

function M.garrison()
 local w=world();w.players[1].resources={substrate=10000,charge=10000}
 local bunker=building(w,'bunker',1,14,20);local office=building(w,'requisition_office',1,14,26)
 local a=unit(w,'associate',1,12,20);local b=unit(w,'associate',1,12,21);local heavy=unit(w,'enforcer',1,12,22);local c=unit(w,'associate',1,12,23)
 -- The footman is given the health of a wall so the Associates' stacks (version 26) cannot burst it inside the test.
 local foe=unit(w,'footman',2,20,21);foe.order={kind='hold'};foe.hp=4000;foe.maxHp=4000;step(w,1)
 -- A flyer may not garrison; a walker walks in; the enforcer takes two slots, so the fourth is refused.
 local blimp=units(w,1,'command_blimp')[1]
 eq(rejected(Sim.step(w,{command(w,1,'garrison',blimp.id,{target=bunker.id})})),'cannot garrison')
 for _,e in ipairs({a,b,heavy,c}) do step(w,1,{command(w,1,'garrison',e.id,{target=bunker.id})}) end
 local full;for _=1,200 do for _,ev in ipairs(Sim.step(w,{})) do if ev.kind=='garrison_full' then full=ev.entity end end end
 assert(a.garrisoned==bunker.id and b.garrisoned==bunker.id and heavy.garrisoned==bunker.id,'the troops did not step inside')
 eq(full,c.id,'the fourth was not turned away');assert(not c.garrisoned);eq(#bunker.occupants,3)
 -- Inside: unseen and untargetable by the enemy, invisible to its view, but shooting out.
 eq(rejected(Sim.step(w,{command(w,2,'attack',foe.id,{target=a.id})})),'target unavailable')
 local seen=false;for _,e in ipairs(Sim.view(w,2).entities) do if e.id==a.id then seen=true end end;assert(not seen,'the enemy sees a garrisoned unit')
 local own=false;for _,e in ipairs(Sim.view(w,1).entities) do if e.id==a.id then own=e.garrisoned==bunker.id end end;assert(own,'the owner cannot see its garrisoned unit')
 local hp=foe.hp;step(w,60);assert(foe.hp<hp,"the bunker's occupants did not fire");assert(not foe.combatTarget,'the footman found a target inside the bunker')
 -- Office occupants shelter and cannot fight.
 step(w,1,{command(w,1,'garrison',c.id,{target=office.id})});step(w,200);eq(c.garrisoned,office.id)
 local foe2=unit(w,'footman',2,18,27);foe2.order={kind='hold'};local hp2=foe2.hp;step(w,60);eq(foe2.hp,hp2,'an office occupant fought')
 -- Unloading puts everyone back outside; a bunker's death ejects whoever is inside.
 step(w,1,{command(w,1,'unload',office.id)});assert(not c.garrisoned and not office.occupants)
 bunker.hp=0;step(w,1);assert(not bunker.alive);assert(not a.garrisoned and not b.garrisoned and not heavy.garrisoned,"the bunker's death left units inside")
 assert(a.alive and heavy.alive)
end
return M
