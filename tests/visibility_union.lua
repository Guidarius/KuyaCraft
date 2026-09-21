local Sim=require('src.sim')
local Codec=require('src.sim.codec')
local Vision=require('src.sim.vision')
local Stats=require('src.sim.stats')
local F=require('src.sim.fixed')
local R=require('tests.responsiveness')
local S=require('tests.control_scenarios')
local T={}
function T.run()
 local w=R.world();local a=S.unit(w,'associate',2,20,20);local b=S.unit(w,'associate',2,22,20)
 a.hp=1000000;a.maxHp=a.hp;a.cooldown=1000000;b.hp=a.hp;b.maxHp=a.hp;b.cooldown=a.cooldown
 local aid,bid=a.id,b.id;local siteId
 local explored={Codec.copy(w.players[1].explored),Codec.copy(w.players[2].explored)}
 for tick=1,180 do
  a=w.entities[aid];b=w.entities[bid]
  if tick==40 then a.owner=1 elseif tick==60 then a.owner=2
  elseif tick==70 then b.alive=false elseif tick==80 then b.alive=true
  elseif tick==90 then
   local d=w.content.buildings.mc_barracks;siteId=w.nextId;w.nextId=siteId+1
   w.entities[siteId]={id=siteId,kind='mc_barracks',category='building',owner=2,alive=true,x=F.center(26),y=F.center(30),size=d.size,hp=d.hp,maxHp=d.hp,remaining=100,queue={},order={kind='stop'},orders={},path={},pathIndex=1,cooldown=0,lastCombat=-1000}
   w.order[#w.order+1]=siteId;w.navVersion=w.navVersion+1;w.blocked=Sim.recomputeBlocked(w)
  elseif tick==100 then w.entities[siteId].remaining=0
  elseif tick==110 then w.entities[siteId].alive=false;w.navVersion=w.navVersion+1;w.blocked=Sim.recomputeBlocked(w)
  elseif tick==120 then a.kind='command_blimp' -- Changed sight/radius input, without changing shared content.
  elseif tick==140 then S.wall(w,25,8,35)
  elseif tick==150 then w=Sim.restore(Sim.snapshot(w));a=w.entities[aid]
  end
  local commands=tick==1 and {S.command(w,a,'move',{x=F.center(28),y=F.center(24)})} or {}
  local clone=tick%15==0 and Sim.restore(Sim.snapshot(w))
  Sim.step(w,commands)
  if clone then Sim.step(clone,commands);assert(Sim.serializeCanonical(w)==Sim.serializeCanonical(clone),'warm/cold vision cache changed future state') end
  -- A new world gives the reference path no cached fields or union bookkeeping.
  local cold=Sim.restore(Sim.snapshot(w))
  for p=1,2 do
   local visible={}
   for _,id in ipairs(cold.order) do local e=cold.entities[id]
    if e.alive and e.owner==p and e.category~='projectile' then Vision.field(cold,e,Stats.sight(cold,e),visible,explored[p]) end
   end
   assert(Codec.encode(visible)==Codec.encode(w.players[p].visible),'incremental visible grid differs from full rebuild at '..tick..' P'..p)
   assert(Codec.encode(explored[p])==Codec.encode(w.players[p].explored),'exploration differs from full rebuild at '..tick..' P'..p)
   local before=Codec.encode(w.players[p])
   Vision.union(w,p,w.players[p].visible,w.players[p].explored,Stats.sight)
   assert(Codec.encode(w.players[p])==before,'repeat union changed an unchanged player')
  end
 end
end
return T
