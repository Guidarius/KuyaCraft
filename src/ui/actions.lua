local C=require('src.content')
local Sim=require('src.sim')
local A={}
-- Presentation-only selection and availability. The simulation validates again at execution.
function A.context(app)
 local ids={};for _,id in ipairs(app.selected) do ids[#ids+1]=id end;table.sort(ids)
 local signature=table.concat(ids,',');local ctx={units={},workers={},entities={},signature=signature}
 for _,id in ipairs(ids) do local e=app:entity(id);if e and e.owner==app.player then
  ctx.entities[#ctx.entities+1]=e
  if e.alive and e.category=='unit' then ctx.units[#ctx.units+1]=e;if e.kind=='worker' then ctx.workers[#ctx.workers+1]=e end end
 end end
 ctx.onlyWorkers=#ctx.workers>0 and #ctx.workers==#ids
 ctx.onlyUnits=#ctx.units>0 and #ctx.units==#ids
 if #ids==1 and #ctx.entities==1 then local e=ctx.entities[1];ctx.single=e;if e.upgrades then ctx.hero=e end end
 if app.cardSelection~=signature then app.cardSelection=signature;app.cardPage=nil;app.building=nil;app.targetMode=nil;app.attackMove=nil end
 if app.cardPage=='build' and not ctx.onlyWorkers or app.cardPage=='abilities' and not ctx.hero then app.cardPage=nil;app.building=nil;app.targetMode=nil end
 return ctx
end
function A.costs(app,cost,entity,extra)
 local result={};local keys={};for key in pairs(cost or {}) do keys[#keys+1]=key end;table.sort(keys)
 for _,key in ipairs(keys) do local value=cost[key];if value>0 then
  local available=key=='mana' and (entity and entity.mana or 0) or app.view.player.resources[key] or 0
  result[#result+1]={key=key,label=key,amount=value,available=available,short=available<value}
 end end
 for _,item in ipairs(extra or {}) do item.short=item.available<item.amount;result[#result+1]=item end
 return result
end
local function missing(costs)
 for _,cost in ipairs(costs) do if cost.short then return 'Insufficient '..cost.label end end
end
function A.upgradeReason(app,hero,milestone)
 if not hero or not hero.alive then return 'Hero is dead' end
 if hero.upgrades[milestone] then return 'Already learned' end
 if milestone>1 and not hero.upgrades[milestone-1] then return 'Learn the previous tier first' end
 if hero.xp<C.rules.xpThresholds[milestone] then return 'Requires '..C.rules.xpThresholds[milestone]..' XP' end
end
function A.openAbilities(app)
 app.selected={app.view.player.hero};A.context(app);app.cardPage='abilities';app.overlay=nil
end
function A.activate(app,action)
 local current;for _,candidate in ipairs(A.list(app)) do if candidate.id==action.id then current=candidate;break end end
 if not current then require('src.ui.command_feedback').notify(app,'rejected','Selection changed',action.id);return false end
 action=current
 if action.reason then require('src.ui.command_feedback').notify(app,'rejected',action.reason,action.id,action.costs);return false end
 if not action.run then return false end
 app.activeAction=action.id;action.run();app.activeAction=nil
 require('src.ui.command_feedback').notify(app,action.menu and 'menu' or 'click',nil,action.id)
 return true
end
function A.list(app)
 local ctx=A.context(app);local e=ctx.single;local list={}
 local locked=app.playback and 'Replay is read-only' or app.world.result and 'Match has ended' or app.network and not app.network.ready and 'Waiting for match to start' or nil
 local function add(id,label,key,fn,reason,tip,costs,menu)
  list[#list+1]={id=id,label=label,key=key or '',run=fn,reason=(not menu and locked) or reason,tip=tip,costs=costs,menu=menu}
 end
 local function back() add('back-card','Back','escape',function() app.cardPage=nil;app.building=nil;app.targetMode=nil end,nil,'Return to commands.',nil,true);list[#list].slot=9 end
 if app.cardPage=='build' then
  for i,kind in ipairs({'barracks','tower','outpost','depot'}) do local d=C.buildings[kind];local costs=A.costs(app,d.cost)
   add(kind,d.label,({'q',app.settings.bindings.tower or 't','e','r'})[i],function() app.building=kind;app.targetMode=nil end,missing(costs),
    'Place '..d.label..'. '..(d.buildTicks/C.rules.tickRate)..' seconds. Shift queues another site. One selected worker builds each site.',costs)
  end
  back();return list
 elseif app.cardPage=='abilities' then
  local hero=ctx.hero;local faction=C.factions[app.view.player.faction]
  for tier,choices in ipairs(faction.upgrades) do for choice,label in ipairs(choices) do
   local costs=A.costs(app,nil,hero,{{key='xp',label='XP',amount=C.rules.xpThresholds[tier],available=hero.xp}})
   local learned=hero.upgrades[tier];local reason=learned and (learned==choice and 'Learned' or 'Other choice learned') or A.upgradeReason(app,hero,tier)
   add('ability-'..tier..'-'..choice,label,({'q','w','e','r','t','y'})[(tier-1)*2+choice],function()
    app.overlay='upgrade';app.upgradeMilestone=tier;app.upgradeChoice=choice
   end,reason,'Tier '..tier..': '..A.upgrades[app.view.player.faction][tier][choice]..' Choose one per tier; permanent. XP is a threshold, not spent.',costs)
   list[#list].slot=(tier-1)*3+choice;list[#list].badge='T'..tier;list[#list].status=learned and (learned==choice and 'Learned' or 'Excluded') or nil
  end end
  back();return list
 end
 if #ctx.units>0 then
  add('move','Move','m',function() app.targetMode='move' end,nil,'Click a destination. Shift appends.')
  add('attack','Attack move',app.settings.bindings.attack,function() app.targetMode='attack_move' end,nil,'Engage enemies on the way.')
  add('stop','Stop',app.settings.bindings.stop,function() for _,unit in ipairs(ctx.units) do app:command('stop',unit.id) end end,nil,'Stop and clear orders for selected units.')
  add('hold','Hold',app.settings.bindings.hold,function() for _,unit in ipairs(ctx.units) do app:command('hold',unit.id) end end,nil,'Stand still and fire. Never chase or yield.')
 end
 if ctx.onlyWorkers then
  add('build-menu','Build',app.settings.bindings.build,function() app.cardPage='build' end,nil,'Choose a building. Costs and requirements appear on each card.',nil,true)
  add('harvest','Harvest','g',function() app.targetMode='harvest' end,nil,'Click a visible resource. Orders all selected workers.')
 end
 if e and e.category=='building' then
  local dead=not e.alive and 'Building destroyed' or nil
  local roster=e.kind=='hq' and {'worker'} or e.kind=='barracks' and C.factions[app.view.player.faction].roster or {}
  for i,kind in ipairs(roster) do local d=C.units[kind]
   local costs=A.costs(app,d.cost,e,{{key='food',label='food',amount=d.food,available=C.rules.population-Sim.population(app.world,app.player)}})
   local reason=dead or e.remaining>0 and 'Building unfinished' or #e.queue>=5 and 'Production queue full' or d.tech and not app.view.player.tech and 'Requires HQ advancement' or missing(costs)
   add('recruit-'..kind,d.label,({'q','w','e','r'})[i],function() app:command('recruit',e.id,{unit=kind}) end,reason,
    'Train '..d.label..'; '..(d.buildTicks/C.rules.tickRate)..' seconds.'..(d.tech and ' Requires HQ advancement.' or ''),costs)
  end
  if e.kind=='hq' then local tech=C.rules.tech;local costs=A.costs(app,tech.cost,e)
   add('research',e.researchRemaining and ('Advancing '..math.ceil(e.researchRemaining/20)..'s') or app.view.player.tech and 'Advanced HQ' or 'Advance HQ','t',function() app:command('research',e.id) end,
    dead or e.remaining>0 and 'Building unfinished' or app.view.player.tech and 'Already researched' or e.researchRemaining and 'Research in progress' or missing(costs),
    'Unlock support and heavy troops; '..(tech.ticks/C.rules.tickRate)..' seconds. Worker production continues.',costs)
   if e.researchRemaining then add('cancel-research','Cancel advance','delete',function() app:command('cancel',e.id,{research=true}) end,dead,'Refund 50%.') end
  end
  if e.remaining>0 then add('cancel','Cancel site','delete',function() app:command('cancel',e.id) end,dead,'Refund 50% of construction cost.') end
 end
 if ctx.hero then local hero=ctx.hero;local dead=not hero.alive and 'Hero is dead' or nil
  if hero.alive then
   add('stance','Stance '..hero.stance,'q',function() app:command('toggle',hero.id) end,nil,'Switch defensive/recovery and offensive/pursuit stance.')
   add('passive',hero.kind=='warden' and 'Protection' or 'Recovery','',nil,'Passive',hero.kind=='warden' and 'Nearby allies take reduced damage.' or 'Recover health out of combat.')
  else local gold,ticks=Sim.revival(C,hero);local costs=A.costs(app,{gold=gold},hero);local hq=app:entity(app.view.player.hq)
   add('revive','Revive','v',function() app:command('revive',hero.id) end,hero.reviveRemaining and 'Revival in progress' or (not hq or not hq.alive) and 'Requires living headquarters' or missing(costs),'Return at headquarters in '..ticks/C.rules.tickRate..' seconds.',costs)
  end
  local available=0;for tier in ipairs(C.rules.xpThresholds) do if not A.upgradeReason(app,hero,tier) then available=available+1 end end
  add('abilities','Abilities'..(available>0 and ' +'..available or ''),'u',function() app.cardPage='abilities' end,dead,'View all three tiers. Each tier grants one permanent choice.',nil,true)
 end
 return list
end
A.upgrades={
 bastion={{'Protection radius: 6 → 8 cells.','Protection reduces damage by an additional 2.'},{'Attack damage +6.','Maximum and current health +240.'},{'Attack period reduced by 4 ticks (0.20s).','Protection radius +2 cells.'}},
 wild={{'Out-of-combat recovery: 8 → 14 health per second.','Entering combat after 8s out of combat grants +4 speed for 2s.'},{'Attack damage +6.','Maximum and current health +200.'},{'Attack period reduced by 4 ticks (0.20s).','Nearby allies recover 4 health per second out of combat.'}}
}
return A
