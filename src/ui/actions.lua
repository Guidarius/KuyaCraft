local C=require('src.content')
local A={}
local function costText(cost) return (cost.gold or 0)..' gold / '..(cost.lumber or 0)..' lumber' end
function A.list(app)
 local e=app:entity(app.selected[1]);local list={};if not e then return list end
 local function add(id,label,key,fn,reason,tip) list[#list+1]={id=id,label=label,key=key,run=fn,reason=reason,tip=tip} end
 local function affordable(cost) for k,v in pairs(cost) do if (app.view.player.resources[k] or 0)<v then return 'Insufficient '..k end end end
 local dead=not e.alive and 'Unit is dead' or nil
 if e.category=='unit' then
  add('move','Move','m',function() app.targetMode='move' end,dead,'Active: click a destination. Shift appends.')
  add('attack','Attack move',app.settings.bindings.attack,function() app.targetMode='attack_move' end,dead,'Active: engage enemies on the way.')
  add('stop','Stop',app.settings.bindings.stop,function() for _,id in ipairs(app.selected) do app:command('stop',id) end end,dead,'Active: stop and clear the order queue.')
  add('hold','Hold',app.settings.bindings.hold,function() for _,id in ipairs(app.selected) do app:command('hold',id) end end,dead,'Stand still and fire at enemies in range. Never chase or yield.')
 end
 if e.kind=='worker' then
  for i,kind in ipairs({'barracks','tower','outpost','depot'}) do local d=C.buildings[kind]
   add(kind,d.label,({app.settings.bindings.build,app.settings.bindings.tower,'o','l'})[i],function() app.building=kind;app.targetMode=nil end,dead or affordable(d.cost),'Active: '..costText(d.cost)..'. Shift places another queued site.')
  end
  add('harvest','Harvest','g',function() app.targetMode='harvest' end,dead,'Active: click a visible resource.')
 end
 if e.category=='building' then
  local roster=e.kind=='hq' and {'worker'} or e.kind=='barracks' and C.factions[app.view.player.faction].roster or {}
  for i,kind in ipairs(roster) do local d=C.units[kind]
   local reason=dead or e.remaining>0 and 'Building unfinished' or #e.queue>=5 and 'Production queue full' or d.tech and not app.view.player.tech and 'Requires HQ advancement' or require('src.sim').population(app.world,app.player)+d.food>C.rules.population and 'Population limit' or affordable(d.cost)
   add('recruit-'..kind,d.label,({'q','w','e','r'})[i],function() app:command('recruit',e.id,{unit=kind}) end,reason,'Active: '..costText(d.cost)..'; '..(d.buildTicks/20)..' seconds.')
  end
  if e.kind=='hq' then
   local tech=C.rules.tech
   add('research',e.researchRemaining and ('Advancing '..math.ceil(e.researchRemaining/20)..'s') or app.view.player.tech and 'Advanced HQ' or 'Advance HQ','t',function() app:command('research',e.id) end,dead or app.view.player.tech and 'Already researched' or e.researchRemaining and 'Research in progress' or affordable(tech.cost),'Unlock support and heavy troops. '..costText(tech.cost)..'; 100 seconds. Worker production continues.')
   if e.researchRemaining then add('cancel-research','Cancel advance','delete',function() app:command('cancel',e.id,{research=true}) end,nil,'Refund 50%.') end
  end
  if e.remaining>0 then add('cancel','Cancel site','delete',function() app:command('cancel',e.id) end,nil,'Refund: 50% of construction cost.') end
 end
 if e.upgrades then
  add('stance','Stance '..e.stance,'q',function() app:command('toggle',e.id) end,dead,'Toggle: switch between defensive/recovery and offensive/pursuit stance.')
  add('passive',e.kind=='warden' and 'Protection aura' or 'Recovery','',nil,'Passive',e.kind=='warden' and 'Nearby allies take reduced damage.' or 'Recover health out of combat.')
 end
 return list
end
A.upgrades={
 bastion={{'Protection radius: 6 → 8 cells.','Protection reduces damage by an additional 2.'},{'Attack damage +6.','Maximum and current health +240.'},{'Attack period reduced by 4 ticks (0.20s).','Protection radius +2 cells.'}},
 wild={{'Out-of-combat recovery: 8 → 14 health per second.','Entering combat after 8s out of combat grants +4 speed for 2s.'},{'Attack damage +6.','Maximum and current health +200.'},{'Attack period reduced by 4 ticks (0.20s).','Nearby allies recover 4 health per second out of combat.'}}
}
return A
