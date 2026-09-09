local T={}
local Sim=require('src.sim');local C=require('tests.fixture_content');local Maps=require('src.maps');local Codec=require('src.sim.codec')
local function world()
 local map=Maps.create('test',40);map.resources={{x=6,y=6,resource='gold',amount=500}};map.camps={}
 return Sim.create({seed=11,players={{faction='bastion'},{faction='wild'}}},C,map)
end
local function command(w,kind,id,args) args=args or {};args.entity=id;return {tick=w.tick+1,player=1,sequence=w.players[1].sequence+1,kind=kind,args=args} end
local function worker(w) for _,id in ipairs(w.order) do if w.entities[id].owner==1 and w.entities[id].kind=='worker' then return w.entities[id] end end end
function T.queues()
 local w=world();local e=worker(w)
 Sim.step(w,{command(w,'move',e.id,{x=8*256+128,y=8*256+128})})
 Sim.step(w,{command(w,'move',e.id,{x=9*256+128,y=8*256+128,append=true})});assert(#e.orders==1)
 local clone=Sim.restore(Sim.snapshot(w));for _=1,200 do Sim.step(w,{});Sim.step(clone,{}) end
 assert(Sim.serializeCanonical(w)==Sim.serializeCanonical(clone));assert(e.order.kind=='stop' and #e.orders==0);assert(math.floor(e.x/256)==9)
 Sim.step(w,{command(w,'move',e.id,{x=100,y=100})});Sim.step(w,{command(w,'move',e.id,{x=400,y=400,append=true})})
 Sim.step(w,{command(w,'stop',e.id)});assert(#e.orders==0 and e.order.kind=='stop')
end
function T.construction()
 local w=world();local e=worker(w);local before=w.players[1].resources.gold
 Sim.step(w,{command(w,'move',e.id,{x=8*256+128,y=8*256+128})})
 Sim.step(w,{command(w,'build',e.id,{building='barracks',x=7,y=4,append=true})})
 assert(#e.orders==1 and e.order.kind=='move');local site=w.entities[e.orders[1].target]
 assert(site and site.remaining==C.buildings.barracks.buildTicks);assert(w.players[1].resources.gold==before-120)
 for _=1,400 do Sim.step(w,{}) end;assert(site.remaining==0 and e.order.kind=='stop')
end
function T.combat()
 local w=world();local a=w.entities[w.players[1].hero];local b=w.entities[w.players[2].hero]
 a.x=2560;a.y=2560;b.x=2816;b.y=2560
 Sim.step(w,{});assert(a.attack and a.attack.impact>w.tick and b.hp==b.maxHp)
 local original=b.hp;Sim.step(w,{command(w,'move',a.id,{x=100,y=100})})
 for _=1,4 do Sim.step(w,{}) end;assert(b.hp==original,'cancelled windup dealt damage')
 local u=world();local hero=u.entities[u.players[1].hero];local enemy=u.entities[u.players[2].hero]
 hero.x=2560;hero.y=2560;enemy.x=2816;enemy.y=2560
 Sim.step(u,{});local clone=Sim.restore(Sim.snapshot(u))
 for _=1,4 do Sim.step(u,{});Sim.step(clone,{}) end
 assert(enemy.hp<enemy.maxHp);assert(Sim.serializeCanonical(u)==Sim.serializeCanonical(clone))
 local cooldown=hero.cooldown;Sim.step(u,{command(u,'move',hero.id,{x=100,y=100})});assert(hero.cooldown==cooldown-1,'movement reset cadence')
end
function T.fog()
 local w=world();local memory=require('src.ui.observation').create();local node=w.entities[1]
 local v=Sim.view(w,1);memory:update(v);assert(memory.memory[node.id])
 for _,id in ipairs(w.order) do local e=w.entities[id];if e.owner==1 then e.x=30*256;e.y=2*256 end end
 Sim.step(w,{})
 local clone=Sim.restore(Sim.snapshot(w));clone.entities[1].amount=1;clone.entities[1].alive=false
 local a,b=Sim.view(w,1),Sim.view(clone,1)
 assert(Codec.encode(a)==Codec.encode(b),'hidden resource leaked')
 local other=require('src.ui.observation').create();other.memory=Codec.copy(memory.memory)
 memory:update(a);other:update(b);assert(Codec.encode(memory.markers)==Codec.encode(other.markers))
 assert(memory.memory[1].amount==500)
 local hidden=clone.entities[clone.players[2].hero];hidden.x=35*256;hidden.y=35*256
 Sim.step(w,{});Sim.step(clone,{})
 -- Only compare private event recipients; hidden activity never becomes an alert input.
 for _,event in ipairs(Sim.eventsFor(clone,1)) do assert(event.entity~=hidden.id) end
end
function T.minimap()
 local M=require('src.ui.minimap')
 for _,map in ipairs({{width=40,height=28},{width=28,height=40},{width=20,height=20}}) do
  local r=M.bounds(map,{x=10,y=10,w=190,h=160});assert(math.abs(r.w/map.width-r.h/map.height)<.001)
  for _,p in ipairs({{0,0},{5*256,7*256},{map.width*256-1,map.height*256-1}}) do local x,y=M.position(map,r,r.x+p[1]/256*r.cell,r.y+p[2]/256*r.cell);assert(math.abs(x-p[1])<=1 and math.abs(y-p[2])<=1) end
  assert(not M.position(map,r,r.x-1,r.y));local x,y=M.position(map,r,-999,9999,true);assert(x==0 and y==map.height*256-1)
 end
end
function T.lobby()
 local N=require('src.net.session');local m=Maps.create('test',24);local config={seed=1,players={{faction='bastion'},{faction='wild'}}}
 local host=N.create({host='127.0.0.1:*',manualLobby=true},config,C,m)
 local client=N.create({join=host.host:get_socket_address(),manualLobby=true},config,C,m)
 local function wait(check)
  local deadline=love.timer.getTime()+3
  repeat host:poll();client:poll();assert(not host.error,host.error);assert(not client.error,client.error);if check() then return end;love.timer.sleep(.001) until love.timer.getTime()>deadline
  error('lobby timeout')
 end
 wait(function() return host.compatible and client.compatible end)
 assert(not host.ready and not client.ready and not host:startMatch())
 host:setLobby('wild',true);client:setLobby('bastion',true)
 wait(function() return host.config.players[2].faction=='bastion' end)
 assert(not host.lobbyReady[1],'faction change must invalidate readiness')
 host:setLobby('wild',true)
 wait(function() return client.lobbyReady[1] and client.lobbyReady[2] end)
 assert(host:startMatch());wait(function() return client.ready end)
 assert(Codec.encode(host.config)==Codec.encode(client.config));host:close();client:close()
end
return T
