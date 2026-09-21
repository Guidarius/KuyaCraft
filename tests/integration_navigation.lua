-- Shipping controls combined with the vehicle-sized Enforcer, rather than the
-- earlier small-radius heavy used by the original route-sharing regressions.
local Sim=require('src.sim')
local F=require('src.sim.fixed')
local G=require('src.sim.geometry')
local Path=require('src.sim.path')
local R=require('tests.responsiveness')
local S=require('tests.control_scenarios')
local T={}
local function wall(w,x,y)
 local key=Path.key(w.map,x,y);w.map.blocked[key]=true;w.blocked[key]=true
end
local function crossing()
 local w=R.world();w.content.rules.pathBudget=1
 for y=0,63 do if y~=26 and y~=27 then wall(w,32,y) end end
 w.navVersion=w.navVersion+1
 local a=S.unit(w,'enforcer',2,18,20);local b=S.unit(w,'enforcer',2,18,24)
 for i,e in ipairs({a,b}) do
  e.order={kind='move',x=40+i*2,y=26,group=71}
  Path.request(w,e,e.order.x,e.order.y)
 end
 assert(w.searches[b.id] and w.searches[b.id].leader==a.id,'fixture did not share a vehicle route')
 return w,a,b
end
function T.register(test)
 test('simulation','vehicle clearance remains valid with no optional smoothing budget',function()
  local w=R.world();w.content.rules.smoothBudget=0
  for x=16,44 do wall(w,x,25);wall(w,x,28) end;w.navVersion=w.navVersion+1
  local e=S.unit(w,'enforcer',2,12,26)
  Sim.step(w,{S.command(w,e,'move',{x=F.center(48),y=F.center(26)})})
  for _=1,1000 do
   Sim.step(w,{});assert(G.terrain(w,e.x,e.y,160),'vehicle crossed terrain')
   assert(w.metrics.smoothChecks==0,'required clearance spent the optional smoothing budget')
   if e.order.kind=='stop' then break end
  end
  assert(e.x==F.center(48) and e.y==F.center(26),'smoothing exhaustion turned a valid route into a blocked route')
 end)
 test('simulation','shared vehicle routes retain offsets and connect from the route end',function()
  local w,a,b=crossing()
  for _=1,4000 do Sim.step(w,{});if not w.searches[a.id] then break end end
  assert(not w.searches[a.id] and #a.path>0,'leader did not find the passage')
  assert(not w.searches[b.id] and #b.path>0,'follower rejected its safe suffix connector')
  for _,e in ipairs({a,b}) do for _,n in ipairs(e.path) do
   assert(G.terrain(w,n.px or F.center(n.x),n.py or F.center(n.y),160),'shared path discarded a vehicle clearance offset')
  end end
  local clone=Sim.restore(Sim.snapshot(w))
  for tick=1,1400 do
   Sim.step(w,{});Sim.step(clone,{})
   assert(G.terrain(w,a.x,a.y,160) and G.terrain(w,b.x,b.y,160),'shared vehicle movement crossed a wall')
   if tick%100==0 then assert(Sim.serializeCanonical(w)==Sim.serializeCanonical(clone),'shared vehicle restore diverged') end
  end
  assert(a.order.kind=='stop' and b.order.kind=='stop' and a.x>32*256 and b.x>32*256,'shared vehicles failed to arrive')
 end)
 test('determinism','shared vehicle follower survives leader cancellation and terrain changes',function()
  local w,a,b=crossing();Sim.step(w,{S.command(w,a,'hold')})
  wall(w,30,24);w.navVersion=w.navVersion+1
  local clone=Sim.restore(Sim.snapshot(w))
  for tick=1,2400 do
   Sim.step(w,{});Sim.step(clone,{})
   assert(G.terrain(w,b.x,b.y,160),'promoted vehicle crossed terrain')
   if tick%100==0 then assert(Sim.serializeCanonical(w)==Sim.serializeCanonical(clone),'promoted vehicle restore diverged') end
  end
  assert(b.order.kind=='stop' and b.x>32*256,'promoted vehicle was stranded')
 end)
end
return T
