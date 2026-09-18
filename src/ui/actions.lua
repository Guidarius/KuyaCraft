local Sim=require('src.sim')
local Selection=require('src.ui.selection')
local Input
local A={}
-- Presentation-only selection and availability. The simulation validates again at execution.
function A.context(app)
 local ids={};for _,id in ipairs(app.selected) do ids[#ids+1]=id end;table.sort(ids)
 local signature=table.concat(ids,',')..':'..tostring(app.subgroupKind or '');local ctx={units={},workers={},entities={},signature=signature}
 for _,id in ipairs(ids) do local e=app:entity(id);if e and e.owner==app.player then
  ctx.entities[#ctx.entities+1]=e
  if e.alive and e.category=='unit' then ctx.units[#ctx.units+1]=e;if e.kind=='worker' then ctx.workers[#ctx.workers+1]=e end end
 end end
 ctx.onlyWorkers=#ctx.workers>0 and #ctx.workers==#ids
 ctx.canBuild=ctx.onlyWorkers or (app.subgroupKind=='worker' and #ctx.workers>0)
 ctx.onlyUnits=#ctx.units>0 and #ctx.units==#ids
 local primary=app:entity(Selection.primary(app));ctx.single=primary
 if primary and primary.owner==app.player and primary.upgrades then ctx.hero=primary end
 if app.cardSelection~=signature then app.cardSelection=signature;app.cardPage=nil;app.building=nil;app.targeting=nil end
 if app.cardPage=='build' and not ctx.canBuild or app.cardPage=='abilities' and not ctx.hero then app.cardPage=nil;app.building=nil;app.targeting=nil end
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
 local C=app.content
 if not hero or not hero.alive then return 'Hero is dead' end
 if hero.upgrades[milestone] then return 'Already learned' end
 if milestone>1 and not hero.upgrades[milestone-1] then return 'Learn the previous tier first' end
 if hero.xp<C.rules.xpThresholds[milestone] then return 'Requires '..C.rules.xpThresholds[milestone]..' XP' end
end
function A.openAbilities(app)
 app.selected={app.view.player.hero};A.context(app);app.cardPage='abilities';app.overlay=nil
end
-- An order issued from the card, a hotkey or the HUD is answered exactly like a right-click: the
-- ordered units flash and their acknowledgement plays, on the click, once.
function A.order(app,units,kind)
 Input=Input or require('src.ui.input')
 local ordered={}
 for _,unit in ipairs(units) do
  if app:command(kind,unit.id)~=false then ordered[#ordered+1]={id=unit.id,kind=unit.kind,command=kind} end
 end
 if #ordered>0 then Input.acknowledge(app,ordered) end
 return #ordered>0
end
function A.activate(app,action)
 local current;for _,candidate in ipairs(A.list(app)) do if candidate.id==action.id then current=candidate;break end end
 if not current then require('src.ui.command_feedback').notify(app,'rejected','Selection changed',action.id);return false end
 action=current
 if action.reason then require('src.ui.command_feedback').notify(app,'rejected',action.reason,action.id,action.costs);return false end
 if not action.run then return false end
 app.activeAction=action.id;action.run();app.activeAction=nil
 -- An order has already been acknowledged by the units that received it; a UI click on top would
 -- be a second cue for one command.
 if action.acknowledges then app.uiNotice={kind='click',time=app.clock,action=action.id}
 else require('src.ui.command_feedback').notify(app,action.menu and 'menu' or 'click',nil,action.id) end
 return true
end
function A.list(app)
 local C=app.content;local ctx=A.context(app);local e=app:entity(Selection.primary(app));local list={}
 Input=Input or require('src.ui.input')
 local locked=app.playback and 'Replay is read-only' or app.world.result and 'Match has ended' or app.network and not app.network.ready and 'Waiting for match to start' or nil
 local function add(id,label,key,fn,reason,tip,costs,menu)
  list[#list+1]={id=id,label=label,key=key or '',run=fn,reason=(not menu and locked) or reason,tip=tip,costs=costs,menu=menu}
 end
 local function back() add('back-card','Back','escape',function() app.cardPage=nil;app.building=nil;app.targeting=nil end,nil,'Return to commands.',nil,true);list[#list].slot=9 end
 local faction=C.factions[app.view.player.faction]
 -- The name of the first unmet requirement, for a card's reason line.
 local function requirement(d)
  local kind=Sim.missingRequirement(app.view,app.player,d.requires)
  if kind then return 'Requires '..((C.buildings[kind] or C.units[kind] or {}).label or kind) end
 end
 if app.cardPage=='build' then
  -- Without a build list, every building but the faction's headquarters, in id order.
  local kinds=faction.buildings
  if not kinds then kinds={};for id in pairs(C.buildings) do if id~=Sim.hqKind(faction) then kinds[#kinds+1]=id end end;table.sort(kinds) end
  for i,kind in ipairs(kinds) do local d=C.buildings[kind];local costs=A.costs(app,d.cost)
   local key=kind=='tower' and (app.settings.bindings.tower or 't') or ({'q','w','e','r','a','s','d','f'})[i]
   add(kind,d.label,key,function() app.building=kind;app.targeting=nil end,requirement(d) or missing(costs),
    'Place '..d.label..'. '..(d.buildTicks/C.rules.tickRate)..' seconds. Shift queues another site. One selected worker builds each site.',costs)
   list[#list].stats=require('src.ui.tooltip').statsFor(d,'building');list[#list].lines=require('src.ui.tooltip').purpose(kind,d)
  end
  back();return list
 elseif app.cardPage=='abilities' then
  local hero=ctx.hero;local faction=C.factions[app.view.player.faction]
  for tier,choices in ipairs(faction.upgrades) do for choice,label in ipairs(choices) do
   local costs=A.costs(app,nil,hero,{{key='xp',label='XP',amount=C.rules.xpThresholds[tier],available=hero.xp}})
   local learned=hero.upgrades[tier];local reason=learned and (learned==choice and 'Learned' or 'Other choice learned') or A.upgradeReason(app,hero,tier)
   add('ability-'..tier..'-'..choice,label,({'q','w','e','r','t','y'})[(tier-1)*2+choice],function()
    app.overlay='upgrade';app.upgradeMilestone=tier;app.upgradeChoice=choice
   end,reason,'Tier '..tier..': '..((A.upgrades[app.view.player.faction] or {})[tier] or {})[choice]..' Choose one per tier; permanent. XP is a threshold, not spent.',costs)
   list[#list].slot=(tier-1)*3+choice;list[#list].badge='T'..tier;list[#list].status=learned and (learned==choice and 'Learned' or 'Excluded') or nil
  end end
  back();return list
 end
 if #ctx.units>0 then
  add('move','Move','m',function() Input.arm(app,'move') end,nil,'Click a destination. Shift appends.')
  add('attack','Attack move',app.settings.bindings.attack,function() Input.arm(app,'attack_move') end,nil,'Engage enemies on the way.')
  add('stop','Stop',app.settings.bindings.stop,function() A.order(app,ctx.units,'stop') end,nil,'Stop and clear orders for selected units.');list[#list].acknowledges=true
  add('hold','Hold',app.settings.bindings.hold,function() A.order(app,ctx.units,'hold') end,nil,'Stand still and fire. Never chase or yield.');list[#list].acknowledges=true
 end
 if ctx.canBuild then
  add('build-menu','Build',app.settings.bindings.build,function() app.cardPage='build' end,nil,'Choose a building. Costs and requirements appear on each card.',nil,true)
  -- Harvest arms a patch target, the way move arms a destination; a laden worker can also be
  -- told to bring its load back, then stop.
  if ctx.workers[1] and (C.units[ctx.workers[1].kind] or {}).harvest then
   add('harvest','Harvest','g',function() Input.arm(app,'harvest') end,nil,'Click a patch or geyser to harvest it. Workers keep going until it is empty.')
   local laden={};for _,u in ipairs(ctx.workers) do if (u.carrying or 0)>0 then laden[#laden+1]=u end end
   if #laden>0 then add('return-cargo','Return cargo','c',function() for _,u in ipairs(laden) do app:command('harvest',u.id,{deliver=true}) end;Input.acknowledge(app,{{id=laden[1].id,kind=laden[1].kind,command='harvest'}}) end,nil,'Bring the load to a drop-off, then stop.');list[#list].acknowledges=true end
  end
 end
 if #ctx.units>0 then add('patrol','Patrol','p',function() Input.arm(app,'patrol') end,nil,'Patrol to a point and engage enemies along the way.') end
 if e and e.owner==app.player and e.category=='building' then
  local dead=not e.alive and 'Building destroyed' or nil
  local roster=Sim.producesFor(C,faction,e.kind)
  local cap=app.view.player.supplyCap or C.rules.population
  for i,kind in ipairs(roster) do local d=C.units[kind]
   local costs=A.costs(app,d.cost,e,{{key='food',label='food',amount=d.food or 1,available=cap-Sim.population(app.world,app.player)}})
   local reason=dead or e.remaining>0 and 'Building unfinished' or #e.queue>=5 and 'Production queue full' or d.tech and not app.view.player.tech and 'Requires HQ advancement' or requirement(d) or missing(costs)
   add('recruit-'..kind,d.label,({'q','w','e','r'})[i],function() app:command('recruit',e.id,{unit=kind}) end,reason,
    'Train '..d.label..'; '..(d.buildTicks/C.rules.tickRate)..' seconds.'..(d.tech and ' Requires HQ advancement.' or ''),costs)
   list[#list].stats=require('src.ui.tooltip').statsFor(d,'unit');list[#list].lines=d.tech and {'Requires HQ advancement.'} or {}
  end
  if e.kind==Sim.hqKind(faction) and C.rules.tech then local tech=C.rules.tech;local costs=A.costs(app,tech.cost,e)
   add('research',e.researchRemaining and ('Advancing '..math.ceil(e.researchRemaining/20)..'s') or app.view.player.tech and 'Advanced HQ' or 'Advance HQ','t',function() app:command('research',e.id) end,
    dead or e.remaining>0 and 'Building unfinished' or app.view.player.tech and 'Already researched' or e.researchRemaining and 'Research in progress' or missing(costs),
    'Unlock support and heavy troops; '..(tech.ticks/C.rules.tickRate)..' seconds. Worker production continues.',costs)
   if e.researchRemaining then add('cancel-research','Cancel advance','delete',function() app:command('cancel',e.id,{research=true}) end,dead,'Refund 50%.') end
  end
  if e.remaining>0 then add('cancel','Cancel site','delete',function() app:command('cancel',e.id) end,dead,'Refund 50% of construction cost.') end
 end
 if ctx.hero then local hero=ctx.hero;local dead=not hero.alive and 'Hero is dead' or nil
  if hero.alive then
   add('stance','Stance '..hero.stance,'z',function() A.order(app,{hero},'toggle') end,nil,'Switch defensive/recovery and offensive/pursuit stance.');list[#list].acknowledges=true
  else local gold,ticks=Sim.revival(C,hero);local costs=A.costs(app,{gold=gold},hero);local hq=app:entity(app.view.player.hq)
   add('revive','Revive','v',function() app:command('revive',hero.id) end,hero.reviveRemaining and 'Revival in progress' or (not hq or not hq.alive) and 'Requires living headquarters' or missing(costs),'Return at headquarters in '..ticks/C.rules.tickRate..' seconds.',costs)
  end
  local available=0;for tier in ipairs(C.rules.xpThresholds) do if not A.upgradeReason(app,hero,tier) then available=available+1 end end
  add('abilities','Abilities'..(available>0 and ' +'..available or ''),'u',function() app.cardPage='abilities' end,dead,'View all three tiers. Each tier grants one permanent choice.',nil,true)
 end
 -- Abilities. The button says what stops it being usable, because "nothing happened" is
 -- the worst answer a command card can give: not enough mana, still cooling down, or the
 -- unit is dead. Cooldown is shown as the seconds left, which is the number a player
 -- actually counts.
 local unitDef=e and e.owner==app.player and C.units[e.kind]
 if unitDef and unitDef.abilities then
  for _,id in ipairs(unitDef.abilities) do
   local spec=C.abilities[id]
   if spec then
    local remaining=e.cooldowns and e.cooldowns[id] and (e.cooldowns[id]-app.world.tick) or 0
    local cost=spec.cost and spec.cost.mana or 0
    local reason=not e.alive and 'Unit is dead' or nil
    if not reason and remaining>0 then reason='Ready in '..math.ceil(remaining/20)..'s' end
    if not reason and cost>0 and (e.mana or 0)<cost then reason='Needs '..cost..' mana' end
    local label=spec.label
    if remaining>0 then label=label..' '..math.ceil(remaining/20)..'s' end
    local how=spec.target=='none' and 'Cast where you stand.' or spec.target=='unit' and 'Click a target.'
     or spec.target=='direction' and 'Click to aim the line.' or 'Click the ground.'
    local tip=(spec.tip or '')..'  '..how
    add('ability-'..id,label,spec.hotkey or '',function() Input.arm(app,'cast',id) end,reason,tip,A.costs(app,spec.cost,e));list[#list].slot=spec.slot
    list[#list].title=spec.label;list[#list].lines={spec.tip or '',{how,{.62,.66,.62}}}
    list[#list].stats={'Cooldown '..string.format('%g',(spec.cooldown or 0)/20)..'s',(spec.range or 0)>0 and ('Range '..string.format('%g',spec.range/256)) or nil}
   end
  end
 end
 local occupied={}
 for _,action in ipairs(list) do if action.slot then occupied[action.slot]=true end end
 local slot=1
 for _,action in ipairs(list) do if not action.slot then while occupied[slot] do slot=slot+1 end;action.slot=slot;occupied[slot]=true end end
 return list
end
A.upgrades={
 bastion={{'Protection radius: 6 → 8 cells.','Protection reduces damage by an additional 2.'},{'Attack damage +6.','Maximum and current health +240.'},{'Attack period reduced by 4 ticks (0.20s).','Protection radius +2 cells.'}},
 wild={{'Out-of-combat recovery: 8 → 14 health per second.','Entering combat after 8s out of combat grants +4 speed for 2s.'},{'Attack damage +6.','Maximum and current health +200.'},{'Attack period reduced by 4 ticks (0.20s).','Nearby allies recover 4 health per second out of combat.'}}
}
return A
