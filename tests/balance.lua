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
-- Gold per minute from one extractor with its mine `distance` cells from the
-- headquarters. Runs long enough for the carrier pipeline to fill before measuring, so
-- this is steady-state income and not the first delivery's latency.
function B.extractorIncome(distance)
 local mineX=8+distance
 local w=world({{x=mineX,y=12,resource='gold',amount=1000000,size=3}})
 local site=building(w,'extractor',mineX,12);site.mine=1
 step(w,1)
 -- Fill the pipeline: the first carriers are still walking, so their gold has not landed.
 step(w,2400)
 local before=w.players[1].resources.gold;local clone=Sim.restore(Sim.snapshot(w))
 step(w,1200);step(clone,1200);eq(Sim.serializeCanonical(w),Sim.serializeCanonical(clone))
 return w.players[1].resources.gold-before,w
end
function B.register(test)
 test('unit','balance profile: exact times, definitions and weighted opening',function()
  assert(require('src.content_validate')(C));local T=require('src.content_time');eq(T.ticks(1.45),29);assert(not pcall(T.ticks,.03));eq(T.cells(.375),96)
  local w=world();eq(Sim.unitCount(w,1),4);eq(Sim.population(w,1),8);eq(w.players[1].resources.gold,650)
  assert(C.rules.startingResources.lumber==nil,'lumber has come back')
  for id,d in pairs(C.units) do assert(d.cost.lumber==nil,id..' still costs lumber') end
  for id,d in pairs(C.buildings) do assert(d.cost.lumber==nil,id..' still costs lumber') end
  for _,d in pairs(C.units) do assert(d.food>=0 and d.food==math.floor(d.food));eq(d.cooldown,math.floor(d.cooldown)) end
 end)
 test('simulation','balance: a near mine pays full rate and a far one pays less',function()
  -- A short route is limited by the emission interval, a long one by how many deliveries
  -- can be in flight, so income falls as roughly 1/distance past the crossover. This is
  -- the whole economic argument of docs/RESOURCE_FLOW.md, measured.
  local near=B.extractorIncome(4)
  local far,w=B.extractorIncome(40)
  print('BALANCE gold/min: near='..near..' far='..far)
  local rules=C.rules
  local expected=rules.carrierPayload*1200/rules.carrierEmitTicks
  assert(near>=expected*0.85 and near<=expected*1.05,'near mine income '..near..' is not close to the interval-limited '..expected)
  assert(far<near*0.75,'a mine ten times further away paid '..far..' against '..near..', so distance costs nothing')
  assert(far>0,'a distant mine paid nothing at all')
  -- The in-flight cap is what bounds carrier entities, so it has to actually hold.
  local live=0
  for _,id in ipairs(w.order) do local e=w.entities[id];if e.category=='carrier' and e.alive then live=live+1 end end
  assert(live<=rules.carrierSlots,'in-flight carriers exceeded the slot cap: '..live)
 end)
 test('simulation','balance: a shorter route restores a distant mine',function()
  -- The answer to the distance penalty is a forward drop-off, and it has to work.
  local far=B.extractorIncome(40)
  local mineX=48
  local w=world({{x=mineX,y=12,resource='gold',amount=1000000,size=3}})
  local site=building(w,'extractor',mineX,12);site.mine=1
  building(w,'outpost',mineX+4,12)
  step(w,1);step(w,2400)
  local before=w.players[1].resources.gold;step(w,1200)
  local withOutpost=w.players[1].resources.gold-before
  print('BALANCE gold/min: far='..far..' far+outpost='..withOutpost)
  assert(withOutpost>far*1.4,'an outpost beside a distant mine did not restore its rate: '..withOutpost..' against '..far)
 end)
 test('simulation','balance: food, tech, independent production and research cancellation',function()
  local w=world();local hq=w.entities[w.players[1].hq];local hall=building(w,'barracks',20,12);w.players[1].resources={gold=10000}
  step(w,1,{S.command(w,hall,'recruit',{unit='medic'})});eq(w.events[1].kind,'rejected')
  step(w,1,{S.command(w,hq,'research')});eq(hq.researchRemaining,1999)
  step(w,1,{S.command(w,hq,'recruit',{unit='worker'})});eq(Sim.population(w,1),9)
  step(w,300);eq(#hq.queue,0);assert(hq.researchRemaining>0)
  local gold=w.players[1].resources.gold;step(w,1,{S.command(w,hq,'cancel',{research=true})});eq(w.players[1].resources.gold,gold+300)
  step(w,1,{S.command(w,hq,'research')});local clone=Sim.restore(Sim.snapshot(w));step(w,1999);step(clone,1999);assert(w.players[1].tech);eq(Sim.serializeCanonical(w),Sim.serializeCanonical(clone))
  step(w,1,{S.command(w,hall,'recruit',{unit='medic'})});eq(#hall.queue,1);eq(Sim.population(w,1),11)
  w.content.rules.population=11;step(w,1,{S.command(w,hall,'recruit',{unit='shield'})});eq(#hall.queue,1)
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
  local gold,ticks=Sim.revival(C,hero);eq(gold,250);eq(ticks,1200);eq(Sim.population(w,1),8)
  step(w,1,{S.command(w,hero,'revive')});step(w,1199);assert(hero.alive);eq(hero.xp,1000);eq(#hero.upgrades,0)
 end)
 test('simulation','balance: supports choose different injured units and exclude buildings',function()
  local w=isolated();local a=S.unit(w,'shield',1,22,22);local b=S.unit(w,'shield',1,23,22);a.hp=100;b.hp=200
  S.unit(w,'medic',1,22,24);S.unit(w,'medic',1,23,24);local hall=building(w,'barracks',25,23);hall.hp=100
  step(w,20);eq(a.hp,112);eq(b.hp,212);eq(hall.hp,100)
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
  local m=require('src.maps').create();eq(m.width,192);eq(m.height,192);local cells={}
  for _,n in ipairs(m.resources) do for y=n.y,n.y+(n.size or 1)-1 do for x=n.x,n.x+(n.size or 1)-1 do local k=P.key(m,x,y);assert(not cells[k],'overlapping resources at '..x..','..y);cells[k]=n.resource end end end
  for y=0,191 do for x=0,191 do local k,r=P.key(m,x,y),P.key(m,191-x,191-y)
   eq(m.blocked[k],m.blocked[r]);eq(m.unbuildable[k],m.unbuildable[r]);eq(cells[k],cells[r])
  end end
  local w=Sim.create({seed=1,players={{faction='bastion'},{faction='wild'}}},C,m);S.clearance(w)
 end)
 test('unit','Twin Marches: roads join every gold mine to the others and to both headquarters',function()
  local m=require('src.maps').create();local width,height=m.width,m.height
  -- The network's nodes are road cells and the footprints roads end against. A mine or a
  -- headquarters is a junction: a carrier walking a road arrives at its doorstep.
  local junction,names={},{}
  local function footprint(x0,y0,size,name)
   names[#names+1]=name
   for y=y0,y0+size-1 do for x=x0,x0+size-1 do local k=P.key(m,x,y);assert(not m.unbuildable[k],name..' is paved over');junction[k]=name end end
  end
  for i,n in ipairs(m.resources) do if n.resource=='gold' then footprint(n.x,n.y,n.size,'gold mine '..i) end end
  for p,s in ipairs(m.starts) do footprint(s.x,s.y,C.buildings.hq.size,'headquarters '..p) end
  for y=0,height-1 do for x=0,width-1 do local k=P.key(m,x,y)
   if m.unbuildable[k] then assert(not m.blocked[k],'road cell '..x..','..y..' is impassable') end
  end end
  for _,c in ipairs(m.camps) do assert(not m.unbuildable[P.key(m,c.x,c.y)],'a camp stands on a road at '..c.x..','..c.y) end
  local s=m.starts[1];local queue={{s.x,s.y}};local seen={[P.key(m,s.x,s.y)]=true};local reached={};local head=1
  while queue[head] do
   local x,y=queue[head][1],queue[head][2];head=head+1
   local here=junction[P.key(m,x,y)];if here then reached[here]=true end
   for _,d in ipairs({{1,0},{-1,0},{0,1},{0,-1}}) do
    local nx,ny=x+d[1],y+d[2]
    if nx>=0 and ny>=0 and nx<width and ny<height then local k=P.key(m,nx,ny)
     if not seen[k] and (m.unbuildable[k] or junction[k]) then seen[k]=true;queue[#queue+1]={nx,ny} end
    end
   end
  end
  for _,name in ipairs(names) do assert(reached[name],name..' is not on the road network') end
  -- Enforced by the simulation, not just drawn: a watchtower on the natural road is
  -- refused, and an extractor still goes on the home mine at the end of its road.
  local w=Sim.create({seed=1,players={{faction='bastion'},{faction='wild'}}},C,m);local view=Sim.view(w,1)
  local ok,reason=Sim.placement(view,C,'tower',30,21);assert(not ok,'a watchtower was allowed on a road');eq(reason,'Cannot build on a road')
  assert(Sim.placement(view,C,'extractor',m.resources[1].x,m.resources[1].y),'extractor refused on the home mine')
 end)
 test('unit','Twin Marches: paired control points on open, unbuildable ground',function()
  local m=require('src.maps').create();eq(#m.controlPoints,2)
  local a,b=m.controlPoints[1],m.controlPoints[2];eq(b.x,191-a.x);eq(b.y,191-a.y)
  local radius=C.rules.control.radius/256
  for _,p in ipairs(m.controlPoints) do
   for y=p.y-radius,p.y+radius do for x=p.x-radius,p.x+radius do
    if (x-p.x)*(x-p.x)+(y-p.y)*(y-p.y)<=radius*radius then local k=P.key(m,x,y)
     assert(not m.blocked[k],'control circle blocked at '..x..','..y);assert(m.unbuildable[k],'control circle buildable at '..x..','..y)
    end
   end end
   for _,c in ipairs(m.camps) do assert((c.x-p.x)*(c.x-p.x)+(c.y-p.y)*(c.y-p.y)>(radius+6)*(radius+6),'a camp sits on a control point') end
  end
  -- The interior is open ground: most of the map can be walked, where the first 192-cell
  -- layout was mostly rock.
  local open=0;for y=0,m.height-1 do for x=0,m.width-1 do if not m.blocked[P.key(m,x,y)] then open=open+1 end end end
  assert(open*2>m.width*m.height,'less than half of the map is walkable ('..open..' cells)')
  local w=Sim.create({seed=1,players={{faction='bastion'},{faction='wild'}}},C,m);eq(#w.control.points,2);eq(w.control.holder,0)
 end)
end
return B
