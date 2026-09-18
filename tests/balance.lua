-- The Orders profile, measured: opening numbers, harvesting income, co-construction, the
-- keep's reach and lives, production and refunds, the footman duel, the map, and the bot.
-- Numbers here are the design reference's, converted; the pacing report is how they are
-- judged (docs/FACTIONS.md, docs/BALANCE_AND_PACING.md).
local C=require('src.content')
local Sim=require('src.sim')
local Codec=require('src.sim.codec')
local F=require('src.sim.fixed')
local P=require('src.sim.path')
local S=require('tests.control_scenarios')
local B={}
local function eq(a,b,message) assert(a==b,(message or 'values differ')..': '..tostring(a)..' != '..tostring(b)) end
local function step(w,n,cs) for i=1,n do Sim.step(w,i==1 and cs or {}) end end
-- A 64-cell arena: player one's keep at (8,12), and whatever patches a case adds.
local function world(resources)
 return Sim.create({seed=71,players={{faction='orders'},{faction='orders'}}},C,{id='balance_fixture',width=64,height=64,starts={{x=8,y=12},{x=52,y=52}},blocked={},resources=resources or {},camps={}})
end
local function workers(w) local out={};for _,id in ipairs(w.order) do local e=w.entities[id];if e.owner==1 and e.kind=='worker' and e.alive then out[#out+1]=e end end;return out end
local function isolated()
 local w=world();for _,id in ipairs(w.order) do local e=w.entities[id];if e.category=='unit' then e.alive=false end end;return w
end
local function building(w,kind,x,y,remaining)
 local id=w.nextId;w.nextId=id+1;local d=C.buildings[kind]
 local e={id=id,kind=kind,category='building',owner=1,alive=true,x=F.center(x),y=F.center(y),size=d.size,hp=d.hp,maxHp=d.hp,remaining=remaining or 0,queue={},order={kind='stop'},orders={},path={},pathIndex=1,cooldown=0,lastCombat=-1000}
 w.entities[id]=e;w.order[#w.order+1]=id;for cy=y,y+d.size-1 do for cx=x,x+d.size-1 do w.blocked[P.key(w.map,cx,cy)]=true end end;w.navVersion=w.navVersion+1;return e
end
local function node(w,x,y) for _,id in ipairs(w.order) do local e=w.entities[id];if e.category=='node' and F.cell(e.x)==x and F.cell(e.y)==y then return e end end end
local function rejected(events) for _,ev in ipairs(events) do if ev.kind=='rejected' then return ev.reason end end end
-- Substrate per minute from `count` workers on one patch four cells from the keep, in
-- steady state: the first two minutes fill the pipeline, the third is measured.
function B.patchIncome(count,resource)
 resource=resource or 'substrate'
 local w=world({{x=15,y=13,resource=resource,amount=1000000,size=1}});local patch=node(w,15,13)
 local list=workers(w);local commands={}
 for i=1,count do commands[#commands+1]=S.command(w,list[i],'harvest',{target=patch.id},w.players[1].sequence+i) end
 for i=count+1,#list do list[i].alive=false end
 step(w,1,commands);step(w,2400)
 local before=w.players[1].resources[resource];local clone=Sim.restore(Sim.snapshot(w))
 step(w,1200);step(clone,1200);eq(Sim.serializeCanonical(w),Sim.serializeCanonical(clone))
 return w.players[1].resources[resource]-before,w
end
function B.register(test)
 test('unit','balance profile: exact times, definitions and the opening',function()
  assert(require('src.content_validate')(C));local T=require('src.content_time');eq(T.ticks(1.45),29);assert(not pcall(T.ticks,.03));eq(T.cells(.375),96)
  local w=world();eq(Sim.unitCount(w,1),4);eq(Sim.population(w,1),4);eq(w.players[1].resources.substrate,400);eq(w.players[1].resources.charge,0)
  eq(Sim.supplyCap(w,1),C.buildings.keep.supply,'the starting keep alone sets the cap')
  assert(not w.players[1].hero,'the Orders have no hero')
  local keys={};for _,key in ipairs(C.rules.resources) do keys[key]=true end
  for id,d in pairs(C.units) do for key in pairs(d.cost) do assert(keys[key],id..' costs an unknown resource') end;assert(d.food>=0 and d.food==math.floor(d.food)) end
  for id,d in pairs(C.buildings) do for key in pairs(d.cost) do assert(keys[key],id..' costs an unknown resource') end end
 end)
 test('simulation','balance: one worker on a patch, and a second one adds less than another full share',function()
  local one=B.patchIncome(1);local two,w=B.patchIncome(2)
  print('BALANCE substrate/min: one worker='..one..' two on one patch='..two)
  assert(one>=60 and one<=200,'one worker on a near patch pays '..one..' a minute, outside 60-200')
  assert(two>one,'a second worker on the patch added nothing');assert(two<one*2,'a second worker on one patch doubled income, so the patch is not exclusive')
  local charge=B.patchIncome(1,'charge')
  print('BALANCE charge/min: one worker='..charge)
  assert(charge<one,'charge should take longer to load than substrate')
 end)
 test('simulation','balance: several workers raise a site faster, with diminishing returns',function()
  local function finish(count)
   local w=world();local list=workers(w);for i=1,4 do list[i].x=F.center(16+i);list[i].y=F.center(12) end
   step(w,1);step(w,1,{S.command(w,list[1],'build',{building='depot',x=18,y=14})})
   local site=w.entities[w.nextId-1];eq(site.kind,'depot')
   for i=2,count do step(w,1,{S.command(w,list[i],'build',{target=site.id})}) end
   local started,ticks
   for t=1,3000 do step(w,1);if not started and site.remaining<C.buildings.depot.buildTicks then started=t end;if site.remaining==0 then ticks=t;break end end
   assert(ticks,'the site never finished');return ticks-started
  end
  local one,two,four=finish(1),finish(2),finish(4)
  print('BALANCE build ticks for a depot: one='..one..' two='..two..' four='..four)
  assert(math.abs(two*C.rules.coBuild[2]-one*100)<=one*8,'two builders should build at '..C.rules.coBuild[2]..' percent: '..one..' against '..two)
  assert(math.abs(four*C.rules.coBuild[4]-one*100)<=one*8,'four builders should build at '..C.rules.coBuild[4]..' percent: '..one..' against '..four)
 end)
 test('simulation','balance: the keep shoots to seven cells and a second keep is a life',function()
  local w=isolated();local keep=w.entities[w.players[1].hq]
  -- Seven cells from the keep's east edge is in reach; nine is not.
  local near=S.unit(w,'footman',2,8+4+6,13);local far=S.unit(w,'footman',2,8+4+9,20)
  step(w,80);assert(near.hp<near.maxHp,'the keep did not shoot a footman six cells away');eq(far.hp,far.maxHp,'the keep shot a footman nine cells away')
  local second=building(w,'keep',30,30)
  keep.hp=0;step(w,1);assert(not w.players[1].defeated,'defeated with a second keep standing')
  second.hp=0;step(w,1);assert(w.players[1].defeated,'not defeated with both keeps gone')
 end)
 test('simulation','balance: supply, production, requirements and the 75 percent refund',function()
  local w=world();local keep=w.entities[w.players[1].hq];w.players[1].resources={substrate=10000,charge=10000}
  -- Nothing trains an army without a barracks, and the barracks needs a standing keep.
  local hall=building(w,'barracks',20,12)
  step(w,1,{S.command(w,hall,'recruit',{unit='footman'})});eq(#hall.queue,1);eq(Sim.population(w,1),6)
  step(w,1,{S.command(w,hall,'recruit',{unit='footman'})});eq(#hall.queue,2);eq(Sim.population(w,1),8)
  -- The cap is ten from the keep alone: four workers and two footmen leave room for two.
  step(w,1,{S.command(w,hall,'recruit',{unit='gryphon'})});eq(rejected(w.events),'cannot recruit','a gryphon fitted under a full cap')
  building(w,'depot',20,18);eq(Sim.supplyCap(w,1),18)
  step(w,1,{S.command(w,hall,'recruit',{unit='gryphon'})});eq(#hall.queue,3);eq(Sim.population(w,1),11)
  -- A queued item that has not started refunds everything; the one in training refunds 75 percent.
  local substrate,charge=w.players[1].resources.substrate,w.players[1].resources.charge
  step(w,1,{S.command(w,hall,'cancel',{index=3})});eq(w.players[1].resources.substrate,substrate+150);eq(w.players[1].resources.charge,charge+50)
  step(w,1,{S.command(w,hall,'cancel',{index=1})});eq(w.players[1].resources.substrate,substrate+150+37);eq(#hall.queue,1)
  -- A site refunds the same share.
  local worker=workers(w)[1];worker.x=F.center(30);worker.y=F.center(12);step(w,1)
  substrate=w.players[1].resources.substrate
  step(w,1,{S.command(w,worker,'build',{building='depot',x=32,y=12})});local site=w.entities[w.nextId-1];eq(site.kind,'depot');eq(w.players[1].resources.substrate,substrate-100)
  step(w,1,{S.command(w,site,'cancel')});eq(w.players[1].resources.substrate,substrate-25)
  -- Construction health grows with progress and keeps damage taken.
  step(w,1,{S.command(w,worker,'build',{building='depot',x=32,y=12})});site=w.entities[w.nextId-1];assert(site.hp<100);site.hp=site.hp-20
  local clone=Sim.restore(Sim.snapshot(w));step(w,700);step(clone,700);eq(site.remaining,0);eq(site.hp,C.buildings.depot.hp-20);eq(Sim.serializeCanonical(w),Sim.serializeCanonical(clone))
 end)
 test('simulation','balance: measured footman duel and cadence',function()
  local w=isolated();local a=S.unit(w,'footman',1,24,24);local b=S.unit(w,'footman',2,25,24);b.x=a.x+210
  local shots={};for _=1,1000 do for _,ev in ipairs(Sim.step(w,{})) do if ev.kind=='attack' and ev.source==a.id then shots[#shots+1]=w.tick end end;if not a.alive or not b.alive then break end end
  for i=2,#shots do eq(shots[i]-shots[i-1],C.units.footman.cooldown) end
  print('BALANCE footman duel seconds: '..w.tick/20)
  assert(w.tick>=200 and w.tick<=400,'a footman duel took '..w.tick..' ticks');assert(not a.alive and not b.alive)
 end)
 test('simulation','balance: the sanctum needs a barracks and the reliquary heals from the air',function()
  local w=world();w.players[1].resources={substrate=10000,charge=10000};local view=Sim.view(w,1)
  local ok,reason=Sim.placement(view,C,'sanctum',18,12);assert(not ok);eq(reason,'Requires Barracks')
  building(w,'barracks',20,12);view=Sim.view(w,1);local placed,why=Sim.placement(view,C,'sanctum',14,17);assert(placed,'the sanctum was refused with a barracks standing: '..tostring(why))
  -- A hurt footman three cells from a reliquary heals twelve a second; the keep heals nobody.
  local v=isolated();local hurt=S.unit(v,'footman',1,22,22);hurt.hp=50;local reliquary=S.unit(v,'reliquary',1,25,22)
  step(v,100);eq(hurt.hp,50+12*5,'the reliquary did not heal twelve a second')
  local alone=isolated();local lonely=S.unit(alone,'footman',1,22,22);lonely.hp=50;step(alone,100);eq(lonely.hp,50)
  -- Nothing but the crossbow can touch it: a footman ordered at it is refused.
  local foe=S.unit(v,'reliquary',2,30,22);foe.order={kind='hold'}
  eq(rejected(Sim.step(v,{S.command(v,hurt,'attack',{target=foe.id})})),'cannot attack air')
  local bow=S.unit(v,'crossbow',1,27,22);assert(not rejected(Sim.step(v,{S.command(v,bow,'attack',{target=foe.id})})))
 end)
 test('unit','direct copy matches codec round trip and isolates aliases',function()
  local shared={n=7};local data={a=shared,b=shared,values={true,false,3,'hello'},[-4]='negative key'}
  local copy=Codec.copy(data);eq(Codec.encode(copy),Codec.encode(Codec.decode(Codec.encode(data))))
  copy.a.n=9;eq(data.a.n,7);eq(copy.b.n,7)
  local cycle={};cycle.self=cycle;assert(not pcall(Codec.copy,cycle));assert(not pcall(Codec.copy,{fraction=.1}));assert(not pcall(Codec.copy,{fn=function() end}))
 end)
 test('unit','Twin Marches: footprint safety, symmetry and fields at every base',function()
  local m=require('src.maps').create();eq(m.width,192);eq(m.height,192);local cells={}
  for _,n in ipairs(m.resources) do for y=n.y,n.y+(n.size or 1)-1 do for x=n.x,n.x+(n.size or 1)-1 do local k=P.key(m,x,y);assert(not cells[k],'overlapping resources at '..x..','..y);cells[k]=n.resource
   assert(not m.blocked[k],'a patch on impassable ground at '..x..','..y);assert(not m.unbuildable[k],'a patch on a road at '..x..','..y) end end end
  for y=0,191 do for x=0,191 do local k,r=P.key(m,x,y),P.key(m,191-x,191-y)
   eq(m.blocked[k],m.blocked[r]);eq(m.unbuildable[k],m.unbuildable[r]);eq(cells[k],cells[r])
  end end
  -- Each base site (both starts, both naturals, both forward and both contested anchors)
  -- has at least four substrate patches and one charge geyser within fourteen cells.
  local sites={}
  for p,s in ipairs(m.starts) do sites[#sites+1]={x=s.x+2,y=s.y+2,name='start '..p,patches=7} end
  for _,kind in ipairs({'naturals','forward','contested'}) do for p,a in ipairs(m.anchors[kind]) do sites[#sites+1]={x=a.x,y=a.y,name=kind..' '..p,patches=4} end end
  for _,site in ipairs(sites) do
   local patches,geysers=0,0
   for _,n in ipairs(m.resources) do
    local dx,dy=n.x-site.x,n.y-site.y
    if dx*dx+dy*dy<=14*14 then if n.resource=='substrate' then patches=patches+1 elseif n.resource=='charge' then geysers=geysers+1 end end
   end
   assert(patches>=site.patches,site.name..' has '..patches..' substrate patches within fourteen cells');assert(geysers>=1,site.name..' has no charge geyser within fourteen cells')
  end
  eq(#m.camps,0,'the pivot map has no camps');assert(m.controlPoints==nil,'the pivot map has no control points')
  local open=0;for y=0,m.height-1 do for x=0,m.width-1 do if not m.blocked[P.key(m,x,y)] then open=open+1 end end end
  assert(open*2>m.width*m.height,'less than half of the map is walkable ('..open..' cells)')
  local w=Sim.create({seed=1,players={{faction='orders'},{faction='orders'}}},C,m);S.clearance(w);eq(Sim.unitCount(w,1),4)
 end)
 -- The bot's economy: idle workers go to patches, a depot goes up before the cap binds, and a
 -- stopped site gets a worker back.
 test('unit','bot: sends workers to patches, raises a depot ahead of the cap, and returns to a stopped site',function()
  local Bot=require('src.bot')
  local w=Sim.create({seed=1,players={{faction='orders'},{faction='orders'}}},C,require('src.maps').create())
  w.tick=20
  local kinds={};for _,c in ipairs(Bot.commands(Sim.view(w,1),C)) do kinds[c.kind]=(kinds[c.kind] or 0)+1;if c.kind=='harvest' then assert(w.entities[c.args.target].resource=='substrate','a worker was sent to something other than substrate first') end end
  assert(kinds.build==1,'the bot did not start a depot with four workers against a cap of ten')
  eq(kinds.harvest,3,'the bot did not send every worker but the builder to harvest')
  local site=building(w,'barracks',30,30,200);site.stalled=true;w.tick=6000
  local resume;for _,c in ipairs(Bot.commands(Sim.view(w,1),C)) do if c.kind=='build' and c.args.target==site.id then resume=c end end
  assert(resume,'the bot ignored a stopped site');eq(w.entities[resume.args.entity].kind,'worker')
  site.remaining=0;site.stalled=nil
  for _,c in ipairs(Bot.commands(Sim.view(w,1),C)) do assert(not (c.kind=='build' and c.args.target==site.id),'the bot kept sending workers to a finished building') end
 end)
end
return B
