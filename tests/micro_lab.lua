-- Opt-in morning playtest fixture. Gameplay stats/rules are unmodified.
-- Initial placement/resources are fixture setup; every subsequent action uses commands.
local Sim=require('src.sim')
local Content=require('src.content')
local F=require('src.sim.fixed')
local S=require('tests.control_scenarios')
local M={}
function M.world()
 local map={id='micro_lab',width=64,height=64,starts={{x=8,y=8},{x=54,y=54}},blocked={},resources={},camps={}}
 -- A two-cell opening at y22-23; a wider alternative at y32-35.
 for y=10,43 do if not (y>=22 and y<=23 or y>=32 and y<=35) then map.blocked[y*64+31+1]=true end end
 for i=1,8 do map.resources[i]={x=6+(i-1)%2*2,y=16+math.floor((i-1)/2)*2,resource='substrate',amount=10000} end
 local w=Sim.create({seed=725,players={{faction='megacorp'},{faction='orders'}}},Content,map)
 w.players[1].resources={substrate=5000,charge=5000}
 local function building(kind,x,y)
  local d=Content.buildings[kind];local id=w.nextId;w.nextId=id+1
  local e={id=id,kind=kind,category='building',owner=1,alive=true,x=F.center(x),y=F.center(y),size=d.size,hp=d.hp,maxHp=d.hp,remaining=0,queue={},order={kind='stop'},orders={},path={},pathIndex=1,cooldown=0,lastCombat=-1000}
  w.entities[id]=e;w.order[#w.order+1]=id;return e
 end
 for i,n in ipairs(map.resources) do local rig=building('substrate_rig',n.x,n.y);rig.mine=i end
 building('mc_barracks',14,12);building('med_bay',18,12);building('armory',22,12)
 local bunker=building('bunker',20,18);building('orbital_relay',25,27)
 for i=1,6 do S.unit(w,'associate',1,16+(i-1)%3*2,24+math.floor((i-1)/3)*2) end
 S.unit(w,'medic',1,16,28);S.unit(w,'medic',1,18,28)
 S.unit(w,'enforcer',1,22,25);S.unit(w,'enforcer',1,24,25)
 for i=1,4 do local e=S.unit(w,'footman',2,40+(i-1)%2*2,22+math.floor((i-1)/2)*2);e.order={kind='hold'} end
 w.blocked=Sim.recomputeBlocked(w);w.navVersion=w.navVersion+1
 Sim.step(w,{})
 return w,bunker
end
function M.create(options)
 local Codec=require('src.sim.codec')
 local app=require('src.app').create({faction='megacorp',opponent='orders',map='open_fields',settings=Codec.copy(require('src.ui.settings').defaults)})
 app.world=M.world();app.view=Sim.view(app.world,1);app.selected={};app.previous={}
 app.observation=require('src.ui.observation').create();app.observation:update(app.view)
 app.feedback:reset();app.juice:reset();app.tickCommands=function() return {} end
 -- Fixture placement is not a normal match opening, so never export its temporary recording.
 app.noAutoSave=true;app.settings.edgeScroll=false;app.settings.dayNight=false
 app.save=function(self) self.message='Practice fixture: start a skirmish to record a replay.';return false end
 app.recording=require('src.replay').create(app.world.config,Content,app.world.map)
 for _,e in ipairs(app.view.entities) do if e.kind=='associate' then app.selected[#app.selected+1]=e.id end end
 app.message='Micro practice: 2-cell gap east, wider gap south. Bunker north; pods use the right sidebar. Restart to reset.'
 require('src.ui.camera').center(app,F.center(25),F.center(23))
 return app
end
function M.check()
 local w,b=M.world();local G=require('src.sim.geometry')
 for _,id in ipairs(w.order) do local e=w.entities[id]
  if e.alive and e.category=='unit' and not Content.units[e.kind].flying then assert(G.terrain(w,e.x,e.y,G.radius(w,e)),'micro fixture placement intersects terrain') end
 end
 local hq=w.players[1].hq
 for _,kind in ipairs({'associate','medic','enforcer'}) do
  local ev=Sim.step(w,{{tick=w.tick+1,player=1,sequence=w.players[1].sequence+1,kind='pod_load',args={entity=hq,unit=kind}}})
  for _,v in ipairs(ev) do assert(v.kind~='rejected',v.reason) end
 end
 local ev=Sim.step(w,{{tick=w.tick+1,player=1,sequence=w.players[1].sequence+1,kind='pod_launch',args={entity=hq,x=25,y=21}}})
 for _,v in ipairs(ev) do assert(v.kind~='rejected',v.reason) end
 local landed=false
 for _=1,Content.rules.descentTicks do for _,v in ipairs(Sim.step(w,{})) do if v.kind=='pod_landed' then landed=true end end end
 assert(landed,'practice pod did not land')
 S.clearance(w)
end
return M
