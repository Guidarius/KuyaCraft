-- A playable art fixture. Only setup differs; subsequent actions use normal commands.
local Sim=require('src.sim')
local Content=require('src.content')
local F=require('src.sim.fixed')
local Codec=require('src.sim.codec')
local M={}
function M.world()
 local map={id='orders_art_lab',width=64,height=64,starts={{x=8,y=8},{x=54,y=54}},blocked={},resources={},camps={}}
 for i=1,6 do map.resources[i]={x=5+(i-1)%3*2,y=17+math.floor((i-1)/3)*2,resource='substrate',amount=10000} end
 local w=Sim.create({seed=921,players={{faction='orders'},{faction='megacorp'}}},Content,map)
 w.players[1].resources={substrate=5000,charge=5000}
 local function building(kind,x,y,remaining)
  local d=Content.buildings[kind];local id=w.nextId;w.nextId=id+1
  local e={id=id,kind=kind,category='building',owner=1,alive=true,x=F.center(x),y=F.center(y),size=d.size,hp=d.hp,maxHp=d.hp,remaining=remaining or 0,queue={},order={kind='stop'},orders={},path={},pathIndex=1,cooldown=0,lastCombat=-1000}
  w.entities[id]=e;w.order[#w.order+1]=id;return e
 end
 building('depot',13,8);building('barracks',17,8);building('sanctum',22,8)
 for i,kind in ipairs({'keep','depot','barracks','sanctum'}) do building(kind,9+(i-1)*5,15,Content.buildings[kind].buildTicks) end
 local unit=require('tests.control_scenarios').unit
 for i,kind in ipairs({'worker','footman','crossbow','gryphon','reliquary'}) do
  for j=1,3 do local e=unit(w,kind,1,12+(i-1)*3,24+(j-1)*2)
   if kind=='worker' and j==2 then e.carrying=8;e.carryResource='substrate' end
  end
 end
 -- Nearby enemy targets for contact poses; stationary until attacked.
 for i,kind in ipairs({'associate','medic','enforcer'}) do local e=unit(w,kind,2,36,22+i*3);e.order={kind='hold'} end
 w.blocked=Sim.recomputeBlocked(w);w.navVersion=w.navVersion+1;Sim.step(w,{})
 return w
end
function M.create(options)
 local app=require('src.app').create({faction='orders',opponent='megacorp',map='open_fields',settings=Codec.copy(require('src.ui.settings').defaults)})
 app.world=M.world();app.view=Sim.view(app.world,1);app.selected={};app.previous={}
 app.observation=require('src.ui.observation').create();app.observation:update(app.view)
 app.feedback:reset();app.juice:reset();app.tickCommands=function() return {} end
 app.noAutoSave=true;app.settings.edgeScroll=false;app.settings.dayNight=false
 app.save=function(self) self.message='Art fixture: start a skirmish to record a replay.';return false end
 app.recording=require('src.replay').create(app.world.config,Content,app.world.map)
 app.message='Orders art lab: buildings north, mixed army centre, Megacorp targets east. Normal controls; restart to reset construction.'
 require('src.ui.camera').center(app,F.center(21),F.center(19))
 if options['orders-test'] then
  local draw=app.draw
  app.draw=function(self)
   if not self.ordersChecked then require('tests.orders_presentation').run(self);self.ordersChecked=true end
   local before=Sim.serializeCanonical(self.world);draw(self)
   assert(Sim.serializeCanonical(self.world)==before,'Orders rendering mutated simulation')
   assert(#self.sprites.diagnostics==0,'Orders art diagnostics')
  end
 end
 return app
end
function M.check()
 local w=M.world();local G=require('src.sim.geometry')
 for _,id in ipairs(w.order) do local e=w.entities[id]
  if e.alive and e.category=='unit' and not Content.units[e.kind].flying then assert(G.terrain(w,e.x,e.y,G.radius(w,e)),'Art fixture intersects terrain') end
 end
end
return M
