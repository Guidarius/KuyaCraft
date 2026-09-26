local Sim=require('src.sim')
local C=require('src.content')
local F=require('src.sim.fixed')
local G=require('src.sim.geometry')
local Path=require('src.sim.path')
local S=require('tests.control_scenarios')
local T={}
local function world()
 local w=Sim.create({seed=71,players={{faction='megacorp'},{faction='orders'}}},C,
  {id='enforcer_clearance',width=64,height=64,starts={{x=8,y=8},{x=54,y=54}},blocked={},resources={},camps={}})
 for _,id in ipairs(w.order) do local e=w.entities[id];if e.category=='unit' then e.alive=false end end
 return w
end
local function wall(w,x,y)
 local k=y*w.map.width+x+1;w.map.blocked[k]=true;w.blocked[k]=true
end
function T.twoCells()
 local w=world();for x=16,44 do wall(w,x,25);wall(w,x,28) end;w.navVersion=w.navVersion+1
 local e=S.unit(w,'enforcer',1,12,26)
 Sim.step(w,{S.command(w,e,'move',{x=F.center(48),y=F.center(26)})})
 local clone;local crossed=false
 for tick=1,800 do
  Sim.step(w,{})
  assert(G.terrain(w,e.x,e.y,C.units.enforcer.radius),'vehicle penetrated corridor wall')
  if F.cell(e.x)>=20 and F.cell(e.x)<=40 then
   assert(F.cell(e.y)==26 or F.cell(e.y)==27,'vehicle took an unnecessary detour around a fitting passage')
   crossed=true
  end
  if tick==120 then clone=Sim.restore(Sim.snapshot(w))
  elseif clone then Sim.step(clone,{});assert(Sim.serializeCanonical(w)==Sim.serializeCanonical(clone),'vehicle route diverged after restore') end
  if e.order.kind=='stop' then break end
 end
 assert(crossed and e.x==F.center(48) and e.y==F.center(26),'vehicle failed to cross two-cell passage')
end
function T.oneCell()
 for _,kind in ipairs({'associate','enforcer'}) do
  local w=world();for y=0,63 do if y~=26 then wall(w,32,y) end end;w.navVersion=w.navVersion+1
  local e=S.unit(w,kind,1,28,26)
  Sim.step(w,{S.command(w,e,'move',{x=F.center(36),y=F.center(26)})})
  for _=1,400 do Sim.step(w,{});assert(G.terrain(w,e.x,e.y,C.units[kind].radius),'unit entered a gap smaller than its body') end
  if kind=='associate' then assert(e.x==F.center(36),'infantry cannot use its narrow passage')
  else assert(e.x<32*256,'vehicle squeezed through one-cell gap') end
 end
end
function T.bins()
 local w=world();local a=S.unit(w,'enforcer',1,20,20);local b=S.unit(w,'enforcer',2,22,20)
 a.x=20*256+250;b.x=a.x+300;a.order={kind='hold'};b.order={kind='hold'}
 assert(F.cell(b.x)-F.cell(a.x)==2)
 assert(not G.free(w,a.x,a.y,160,a.id),'brute-force collision missed overlap')
 G.beginStep(w);assert(not G.free(w,a.x,a.y,160,a.id),'indexed collision missed a body two bins away');G.endStep(w)
 b.x=a.x+320;assert(G.free(w,a.x,a.y,160,a.id),'touching bodies should fit')
 -- A moving body must also see an enemy across two bins before stepping into it.
 b.x=a.x+330;b.hp=100000;b.maxHp=b.hp;a.hp=100000;a.maxHp=a.hp
 Sim.step(w,{S.command(w,a,'move',{x=F.center(25),y=a.y})})
 for _=1,60 do Sim.step(w,{});assert(F.distance2(a.x,a.y,b.x,b.y)>=320^2,'movement missed vehicle separation') end
 local px,py=Path.point(w,0,20,160)
 assert(px==160 and G.terrain(w,px,py,160),'map-edge clearance point is invalid')
end
function T.newObstacle()
 local w=world();local e=S.unit(w,'enforcer',1,12,26)
 Sim.step(w,{S.command(w,e,'move',{x=F.center(48),y=F.center(26)})})
 for tick=1,1000 do
  if tick==40 then
   for y=15,40 do wall(w,30,y) end;w.navVersion=w.navVersion+1
  end
  Sim.step(w,{})
  assert(G.terrain(w,e.x,e.y,160),'vehicle cut a corner around the new obstacle')
  if e.order.kind=='stop' then break end
 end
 assert(e.x==F.center(48) and e.y==F.center(26),'vehicle failed to reroute around new terrain')
end
function T.unload()
 local w=world();local d=C.buildings.bunker;local id=w.nextId;w.nextId=id+1
 local b={id=id,kind='bunker',category='building',owner=1,alive=true,x=F.center(20),y=F.center(20),
  size=d.size,hp=d.hp,maxHp=d.hp,remaining=0,queue={},order={kind='stop'},orders={},path={},pathIndex=1,cooldown=0,lastCombat=-1000}
 w.entities[id]=b;w.order[#w.order+1]=id
 local a=S.unit(w,'associate',1,20,20);local h=S.unit(w,'enforcer',1,20,20)
 a.garrisoned=id;h.garrisoned=id;b.occupants={a.id,h.id}
 local exit=20+d.size
 for x=exit-2,exit+5 do wall(w,x,exit-1);wall(w,x,exit+2) end
 w.blocked=Sim.recomputeBlocked(w);w.navVersion=w.navVersion+1
 Sim.step(w,{S.command(w,b,'unload')})
 assert(not a.garrisoned and not h.garrisoned,'unload failed')
 assert(G.terrain(w,h.x,h.y,160),'unload discarded the vehicle clearance offset')
 assert(G.terrain(w,a.x,a.y,80),'unload put infantry in terrain')
 assert(F.distance2(a.x,a.y,h.x,h.y)>=240^2,'unload overlapped a previously released unit')
end
return T
