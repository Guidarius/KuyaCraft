local C=require('src.content')
local Sim=require('src.sim')
local Codec=require('src.sim.codec')
local F=require('src.sim.fixed')
local P=require('src.sim.path')
local S=require('tests.control_scenarios')
local B={}
local function eq(a,b) assert(a==b,tostring(a)..' != '..tostring(b)) end
local function step(w,n,cs) for i=1,n do Sim.step(w,i==1 and cs or {}) end end
local function world(resources)
 return Sim.create({seed=71,players={{faction='bastion'},{faction='wild'}}},C,{id='balance_fixture',width=64,height=64,starts={{x=8,y=12},{x=52,y=52}},blocked={},resources=resources or {},camps={}})
end
local function workers(w) local out={};for _,id in ipairs(w.order) do local e=w.entities[id];if e.owner==1 and e.kind=='worker' then out[#out+1]=e end end;return out end
local function isolated()
 local w=world();for _,id in ipairs(w.order) do local e=w.entities[id];if e.category=='unit' then e.alive=false end end;return w
end
local function building(w,kind,x,y)
 local id=w.nextId;w.nextId=id+1;local d=C.buildings[kind]
 local e={id=id,kind=kind,category='building',owner=1,alive=true,x=F.center(x),y=F.center(y),size=d.size,hp=d.hp,maxHp=d.hp,remaining=0,queue={},order={kind='stop'},orders={},path={},pathIndex=1,cooldown=0,lastCombat=-1000}
 w.entities[id]=e;w.order[#w.order+1]=id;for cy=y,y+d.size-1 do for cx=x,x+d.size-1 do w.blocked[P.key(w.map,cx,cy)]=true end end;w.navVersion=w.navVersion+1;return e
end
function B.income(count,resource)
 local w=world({{x=8,y=6,resource=resource or 'gold',amount=12000,size=resource=='lumber' and 1 or 3}})
 local ws=workers(w);if count==6 then ws[6]=S.unit(w,'worker',1,13,10) end
 local cs={};for i,e in ipairs(ws) do e.x=F.center(7+i);e.y=F.center(10);cs[#cs+1]=S.command(w,e,'harvest',{target=1},i) end
 step(w,600,cs);local before=w.players[1].resources[resource or 'gold'];local clone=Sim.restore(Sim.snapshot(w))
 step(w,1200);step(clone,1200);eq(Sim.serializeCanonical(w),Sim.serializeCanonical(clone))
 return w.players[1].resources[resource or 'gold']-before,w
end
function B.register(test)
 test('unit','balance profile: exact times, definitions and weighted opening',function()
  assert(require('src.content_validate')(C));local T=require('src.content_time');eq(T.ticks(1.45),29);assert(not pcall(T.ticks,.03));eq(T.cells(.375),96)
  local w=world();eq(Sim.unitCount(w,1),6);eq(Sim.population(w,1),10);eq(w.players[1].resources.gold,500)
  for _,d in pairs(C.units) do assert(d.food>=0 and d.food==math.floor(d.food));eq(d.cooldown,math.floor(d.cooldown)) end
 end)
 test('simulation','balance: gold throughput, slot cap and hauling snapshots',function()
  local five,w=B.income(5);local six=B.income(6)
  print('BALANCE gold/min: five='..five..' six='..six);assert(five>=500 and five<=600,'five-worker income outside 500–600/min');assert(six<=600 and six<=five+10,'sixth worker bypassed cap');eq(#w.entities[1].slots,5)
 end)
 test('simulation','balance: lumber hauling rate at a nearby drop-off',function()
  local w=world({{x=8,y=4,resource='lumber',amount=10000,size=1}});local e=workers(w)[1];e.x=F.center(9);e.y=F.center(8)
  step(w,600,{S.command(w,e,'harvest',{target=1})});local before=w.players[1].resources.lumber;step(w,1200);local rate=w.players[1].resources.lumber-before
  print('BALANCE lumber/min, one worker: '..rate);assert(rate>=40 and rate<=55,'lumber route outside target')
 end)
 test('simulation','balance: food, tech, independent production and research cancellation',function()
  local w=world();local hq=w.entities[w.players[1].hq];local hall=building(w,'barracks',20,12);w.players[1].resources={gold=10000,lumber=10000}
  step(w,1,{S.command(w,hall,'recruit',{unit='medic'})});eq(w.events[1].kind,'rejected')
  step(w,1,{S.command(w,hq,'research')});eq(hq.researchRemaining,1999)
  step(w,1,{S.command(w,hq,'recruit',{unit='worker'})});eq(Sim.population(w,1),11)
  step(w,300);eq(#hq.queue,0);assert(hq.researchRemaining>0)
  local gold=w.players[1].resources.gold;step(w,1,{S.command(w,hq,'cancel',{research=true})});eq(w.players[1].resources.gold,gold+200)
  step(w,1,{S.command(w,hq,'research')});local clone=Sim.restore(Sim.snapshot(w));step(w,1999);step(clone,1999);assert(w.players[1].tech);eq(Sim.serializeCanonical(w),Sim.serializeCanonical(clone))
  step(w,1,{S.command(w,hall,'recruit',{unit='medic'})});eq(#hall.queue,1);eq(Sim.population(w,1),13)
  w.content.rules.population=13;step(w,1,{S.command(w,hall,'recruit',{unit='shield'})});eq(#hall.queue,1)
 end)
 test('simulation','balance: construction health growth preserves damage and refund',function()
  local w=world();local e=workers(w)[1];e.x=F.center(17);e.y=F.center(14)
  step(w,1);step(w,1,{S.command(w,e,'build',{building='barracks',x=18,y=13})})
  local site=w.entities[w.nextId-1];eq(site.kind,'barracks');assert(site.hp<200);site.hp=site.hp-75
  local clone=Sim.restore(Sim.snapshot(w));step(w,1300);step(clone,1300);eq(site.remaining,0);eq(site.hp,1425);eq(Sim.serializeCanonical(w),Sim.serializeCanonical(clone))
 end)
 test('simulation','balance: measured shield duel and cadence',function()
  local w=isolated();local a=S.unit(w,'shield',1,24,24);local b=S.unit(w,'shield',2,25,24);b.x=a.x+210
  local shots={};for _=1,1000 do for _,ev in ipairs(Sim.step(w,{})) do if ev.kind=='attack' and ev.source==a.id then shots[#shots+1]=w.tick end end;if not a.alive or not b.alive then break end end
  for i=2,#shots do eq(shots[i]-shots[i-1],28) end
  print('BALANCE shield duel seconds: '..w.tick/20);assert(w.tick>=800 and w.tick<=900);assert(not a.alive and not b.alive)
 end)
 test('simulation','balance: short melee approaches both bodies and building edges',function()
  local w=isolated();local attacker=S.unit(w,'shield',1,20,22);local target=building(w,'barracks',25,22);target.owner=2
  step(w,1);step(w,1,{S.command(w,attacker,'attack',{target=target.id})})
  local clone=Sim.restore(Sim.snapshot(w));step(w,400);step(clone,400);assert(target.hp<target.maxHp,'short melee could not reach building');eq(Sim.serializeCanonical(w),Sim.serializeCanonical(clone))
  S.clearance(w)
 end)
 test('simulation','balance: earned revival tiers and reserved hero food',function()
  local w=world();local hero=w.entities[w.players[1].hero];hero.xp=1000;hero.alive=false;hero.hp=0
  local gold,ticks=Sim.revival(C,hero);eq(gold,250);eq(ticks,1200);eq(Sim.population(w,1),10)
  step(w,1,{S.command(w,hero,'revive')});step(w,1199);assert(hero.alive);eq(hero.xp,1000);eq(#hero.upgrades,0)
 end)
 test('simulation','balance: supports choose different injured units and exclude buildings',function()
  local w=isolated();local a=S.unit(w,'shield',1,22,22);local b=S.unit(w,'shield',1,23,22);a.hp=100;b.hp=200
  S.unit(w,'medic',1,22,24);S.unit(w,'medic',1,23,24);local hall=building(w,'barracks',25,23);hall.hp=100
  step(w,20);eq(a.hp,112);eq(b.hp,212);eq(hall.hp,100)
 end)
 test('simulation','balance: carried resources survive destroyed drop-off',function()
  local w=world({{x=20,y=6,resource='gold',amount=100,size=3}});local e=workers(w)[1];local a=building(w,'outpost',20,12);local b=building(w,'outpost',30,12)
  w.content.buildings.hq.dropoff={};e.x=F.center(20);e.y=F.center(10);e.cargo=10;e.cargoType='gold';e.order={kind='harvest',target=1}
  step(w,1);a.alive=false;w.navVersion=w.navVersion+1;local before=w.players[1].resources.gold
  local clone=Sim.restore(Sim.snapshot(w));step(w,500);step(clone,500);assert(w.players[1].resources.gold>=before+10);eq(Sim.serializeCanonical(w),Sim.serializeCanonical(clone));assert(b.alive)
 end)
 test('simulation','balance: easy camp reward, leash and delayed reset',function()
  local w=isolated();local hero=w.entities[w.players[1].hero];hero.alive=true;hero.x=F.center(24);hero.y=F.center(24)
  local a=S.unit(w,'shield',1,24,25);local b=S.unit(w,'shield',1,24,26)
  local n=S.unit(w,'scout',0,27,24);n.home={x=n.x,y=n.y};local n2=S.unit(w,'scout',0,27,26);n2.home={x=n2.x,y=n2.y}
  local gold=w.players[1].resources.gold
  for _=1,2400 do Sim.step(w,{});if not n.alive and not n2.alive then break end end
  assert(hero.alive and a.alive and b.alive and not n.alive and not n2.alive,'easy camp fixture outcome');eq(hero.xp,60);eq(w.players[1].resources.gold,gold+40)
  local reset=isolated();local guard=S.unit(reset,'neutral',0,30,25);guard.home={x=F.center(18),y=F.center(25)};guard.hp=100
  step(reset,1);assert(guard.returning and not guard.attack);local arrived
  for _=1,500 do Sim.step(reset,{});if guard.homeSince then arrived=reset.tick;break end end
  assert(arrived,'camp failed to return home');step(reset,59);eq(guard.hp,100);step(reset,1);eq(guard.hp,guard.maxHp)
 end)
 test('simulation','balance: forest succession uses known reachable nodes',function()
  local w=world({{x=16,y=12,resource='lumber',amount=10},{x=16,y=14,resource='lumber',amount=100},{x=55,y=4,resource='lumber',amount=100}})
  local e=workers(w)[1];e.x=F.center(15);e.y=F.center(12);step(w,1)
  step(w,1,{S.command(w,e,'harvest',{target=1})});step(w,800)
  assert(not w.entities[1].alive);eq(e.order.target,2);assert(w.entities[3].amount==100)
  for _,observed in ipairs(Sim.view(w,2).entities) do assert(not observed.slots and not observed.economySearch,'private scheduler leaked') end
 end)
 test('simulation','balance: hidden mine depletion does not cancel a worker remotely',function()
  local w=world({{x=40,y=40,resource='gold',amount=100,size=3}});local e=workers(w)[1];e.order={kind='harvest',target=1}
  local clone=Sim.restore(Sim.snapshot(w));clone.entities[1].alive=false
  step(w,1);step(clone,1);eq(Codec.encode(e.order),Codec.encode(clone.entities[e.id].order));eq(e.order.kind,'harvest');eq(e.x,clone.entities[e.id].x);eq(e.y,clone.entities[e.id].y)
 end)
 test('simulation','balance: merged sight spans equal circular visibility oracle',function()
  -- This validates the radial span merge against a naive circle, so it must run with
  -- the radial rule. Line of sight deliberately produces a different field: it stops at
  -- obstructions and originates at a building's centre rather than its corner. That
  -- field has its own scenarios in tests/vision_scenarios.lua, one of which proves the
  -- two agree exactly on open ground.
  local w=world();w.content.rules.lineOfSight=false
  for i=1,40 do S.unit(w,i%2==0 and 'shield' or 'crossbow',1,15+i%12,20+math.floor(i/12)) end
  step(w,1);local expected={}
  for _,id in ipairs(w.order) do local e=w.entities[id];if e.alive and e.owner==1 then local d=w.content.units[e.kind] or w.content.buildings[e.kind];local cx,cy=F.cell(e.x),F.cell(e.y)
   for y=math.max(0,cy-d.sight),math.min(w.map.height-1,cy+d.sight) do for x=math.max(0,cx-d.sight),math.min(w.map.width-1,cx+d.sight) do if (x-cx)^2+(y-cy)^2<=d.sight^2 then expected[P.key(w.map,x,y)]=true end end end
  end end
  eq(Codec.encode(expected),Codec.encode(w.players[1].visible))
 end)
 test('unit','direct copy matches codec round trip and isolates aliases',function()
  local shared={n=7};local data={a=shared,b=shared,values={true,false,3,'hello'},[-4]='negative key'}
  local copy=Codec.copy(data);eq(Codec.encode(copy),Codec.encode(Codec.decode(Codec.encode(data))))
  copy.a.n=9;eq(data.a.n,7);eq(copy.b.n,7)
  local cycle={};cycle.self=cycle;assert(not pcall(Codec.copy,cycle));assert(not pcall(Codec.copy,{fraction=.1}));assert(not pcall(Codec.copy,{fn=function() end}))
 end)
 test('unit','Twin Marches: footprint safety, symmetry and finite resources',function()
  local m=require('src.maps').create();eq(m.width,128);eq(m.height,112);local cells={}
  for _,n in ipairs(m.resources) do for y=n.y,n.y+(n.size or 1)-1 do for x=n.x,n.x+(n.size or 1)-1 do local k=P.key(m,x,y);assert(not cells[k],'overlapping resources at '..x..','..y);cells[k]=n.resource end end end
  for y=0,111 do for x=0,127 do eq(m.blocked[P.key(m,x,y)],m.blocked[P.key(m,127-x,111-y)]);eq(cells[P.key(m,x,y)],cells[P.key(m,127-x,111-y)]) end end
  local w=Sim.create({seed=1,players={{faction='bastion'},{faction='wild'}}},C,m);S.clearance(w)
 end)
end
return B
