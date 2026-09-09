local Camera=require('src.ui.camera')
local Selection=require('src.ui.selection')
local Mini=require('src.ui.minimap')
local Actions=require('src.ui.actions')
local Feedback=require('src.ui.command_feedback')
local I={}
local function shift() return love.keyboard.isDown('lshift','rshift') end
function I.intent(app,x,y,target,kind)
 if app.playback then return end
 Actions.context(app)
 if kind=='harvest' and (not target or target.category~='node' or not target.alive) then Feedback.notify(app,'rejected','Choose a visible resource','harvest',nil,x,y);return end
 local count=0;app.commandGroup=(app.commandGroup or 0)+1
 for _,id in ipairs(app.selected) do
  local e=app:entity(id)
  if e and e.alive and e.category=='unit' then
   local command=kind;local args={append=shift(),group=app.commandGroup}
   if not command then
    if target and target.category=='node' and e.kind=='worker' then command='harvest'
    elseif target and target.owner==app.player and target.remaining and target.remaining>0 and e.kind=='worker' then command='build'
    elseif target and target.owner~=app.player and target.category~='node' then command='attack'
    else command='move' end
   end
   if command=='harvest' or command=='attack' or command=='build' then args.target=target and target.id else args.x=x;args.y=y end
   if app:command(command,id,args) then count=count+1 else return end
  end
 end
 if count>0 then local cue=(kind=='attack_move' or target and target.owner~=app.player and target.category~='node') and 'attack_order' or 'move';app.orderMarker={x=x,y=y,time=app.clock,tick=app.world.tick,group=app.commandGroup};Feedback.notify(app,cue,'Order issued',nil,nil,x,y) else Feedback.notify(app,'rejected','Select a unit to issue commands',nil,nil,x,y) end
end
function I.mousepressed(app,x,y,button,presses)
 Actions.context(app)
 if button==2 and (app.building or app.targetMode or app.attackMove) then app.building=nil;app.targetMode=nil;app.attackMove=nil;app.audio:play('cancel');return end
 if app.widgets.context and app.widgets.context~=(app.overlay or 'match') then return end
 if button==1 then local hit,reason,item=app.widgets:click(x,y);if hit then if reason then Feedback.notify(app,'rejected',reason,item.id,item.details and item.details.costs) end;return end end
 if app.overlay then return end
 if app.timeline and y>=app.timeline.y and y<app.timeline.y+app.timeline.h and x>=app.timeline.x and x<app.timeline.x+app.timeline.w then
  app:requestSeek(math.floor((x-app.timeline.x)/app.timeline.w*#app.playback.frames));return
 end
 local s=app.settings.scale/100
 if app.minimap then
  local r=app.minimap;local wx,wy=Mini.position(app.view.map,r,x/s,y/s)
  if wx then
   if button==1 and love.keyboard.isDown('lalt','ralt') then app.localPing={x=wx,y=wy,time=app.clock}
   elseif button==1 and (app.targetMode or app.attackMove) then I.intent(app,wx,wy,nil,app.targetMode or 'attack_move');app.targetMode=nil;app.attackMove=nil
   elseif button==1 then app.capture='minimap';Camera.center(app,wx,wy)
   elseif button==2 then
    local target,best
    for _,e in ipairs(app.view.entities) do if e.alive and e.owner~=app.player and e.category~='node' then local d=(e.x-wx)^2+(e.y-wy)^2;if d<(5/r.cell*256)^2 and (not best or d<best) then target=e;best=d end end end
    I.intent(app,wx,wy,target)
   end
   return
  end
 end
 if not Camera.contains(app,x,y) then return end
 if button==3 then app.capture='pan';app.pan={x=x,y=y};return end
 if button==1 then
  if app.building then
   local wx,wy=app:position(x,y);local cx,cy=math.floor(wx/256),math.floor(wy/256)
   local valid,reason=require('src.sim').placement(app.view,require('src.content'),app.building,cx,cy)
   if valid then
    local issued=false
    for _,id in ipairs(app.selected) do local e=app:entity(id);if e and e.alive and e.owner==app.player and e.kind=='worker' then app.activeAction=app.building;issued=app:command('build',id,{building=app.building,x=cx,y=cy,append=shift()});app.activeAction=nil;if not issued then return end;break end end
    if issued then Feedback.notify(app,'build_order','Construction ordered',app.building,nil,wx,wy) else Feedback.notify(app,'rejected','Select workers to build',app.building,nil,wx,wy) end
    if issued and not shift() then app.awaitingPlacement=app.building;app.building=nil end
   else Feedback.notify(app,'rejected',reason,app.building,Actions.costs(app,require('src.content').buildings[app.building].cost),wx,wy) end
  elseif app.targetMode or app.attackMove then local wx,wy=app:position(x,y);I.intent(app,wx,wy,app:pick(x,y),app.targetMode or 'attack_move');app.targetMode=nil;app.attackMove=nil
  elseif presses and presses>=2 then
   local e=app:pick(x,y,true);if e then app.selected={};for _,v in ipairs(app.view.entities) do local sx,sy=app:screen(v.x,v.y);if v.alive and v.owner==app.player and v.kind==e.kind and Camera.contains(app,sx,sy) then app.selected[#app.selected+1]=v.id end end end
  else app.drag={x=x,y=y};app.capture='selection' end
 elseif button==2 then local wx,wy=app:position(x,y);I.intent(app,wx,wy,app:pick(x,y)) end
end
function I.mousemoved(app,x,y,dx,dy)
 if app.capture=='minimap' then local s=app.settings.scale/100;local wx,wy=Mini.position(app.view.map,app.minimap,x/s,y/s,true);Camera.center(app,wx,wy)
 elseif app.capture=='pan' then app.camera.x=app.camera.x+dx;app.camera.y=app.camera.y+dy;Camera.clamp(app) end
end
function I.mousereleased(app,x,y,button)
 if app.capture=='pan' and button==3 or app.capture=='minimap' and button==1 then app.capture=nil;return end
 if button~=1 or not app.drag then return end
 local drag=app.drag;app.drag=nil;app.capture=nil
 if not shift() then app.selected={} end
 if math.abs(x-drag.x)+math.abs(y-drag.y)<8 then local e=app:pick(x,y,true);if e then if shift() then Selection.toggle(app.selected,e.id) else app.selected={e.id} end end
 else for _,e in ipairs(app.view.entities) do if e.alive and e.owner==app.player and e.category=='unit' then local sx,sy=app:screen(e.x,e.y)
  if Camera.contains(app,sx,sy) and sx>=math.min(x,drag.x) and sx<=math.max(x,drag.x) and sy>=math.min(y,drag.y) and sy<=math.max(y,drag.y) then if shift() then Selection.toggle(app.selected,e.id) else app.selected[#app.selected+1]=e.id end end
 end end end
 table.sort(app.selected);Actions.context(app);app.audio:play('select')
end
function I.keypressed(app,key)
 if app.rebind then
  if key~='escape' and key~='f3' and key~='f5' and not tonumber(key) and key~='q' and key~='w' and key~='e' and key~='r' and key~='u' and key~='y' then
   for action,binding in pairs(app.settings.bindings) do if binding==key then app.settings.bindings[action]=app.settings.bindings[app.rebind] end end
   app.settings.bindings[app.rebind]=key;require('src.ui.settings').save(app.settings)
  end;app.rebind=nil;return
 end
 Actions.context(app)
 if key=='escape' then
  if app.building or app.targetMode or app.attackMove then app.building=nil;app.targetMode=nil;app.attackMove=nil
  elseif app.overlay then app.overlay=nil elseif app.cardPage then app.cardPage=nil else app.overlay='pause' end;app.audio:play('cancel');return
 end
 if app.overlay then return end
 local bindings=app.settings.bindings
 if key==bindings.hero then
  app.selected={app.view.player.hero};local e=app:entity(app.view.player.hero);if app.lastHero and app.clock-app.lastHero<.35 and e then Camera.center(app,e.x,e.y) end;app.lastHero=app.clock;Actions.context(app);app.audio:play('select')
 elseif key==bindings.alert then local a=app.alerts.items[1];if a and a.x then Camera.center(app,a.x,a.y) end
 elseif key=='tab' then
  if not app.subgroups or app.clock-(app.lastTab or -100)>2 then app.subgroups=Selection.groups(app);app.subgroupIndex=0 end
  if #app.subgroups>0 then app.subgroupIndex=app.subgroupIndex%#app.subgroups+1;app.selected=app.subgroups[app.subgroupIndex].ids end;app.lastTab=app.clock
 elseif tonumber(key) and tonumber(key)>=1 and tonumber(key)<=9 then
  local n=tonumber(key)
  if love.keyboard.isDown('lctrl','rctrl') then app.groups[n]=require('src.sim.codec').copy(app.selected)
  elseif app.groups[n] then app.selected={};for _,id in ipairs(app.groups[n]) do local e=app:entity(id);if e and e.alive then app.selected[#app.selected+1]=id end end
   if app.lastGroup==n and app.clock-(app.lastGroupTime or -100)<.35 then local e=app:entity(app.selected[1]);if e then Camera.center(app,e.x,e.y) end end
   app.lastGroup=n;app.lastGroupTime=app.clock
  end
 elseif key=='f3' then app.debugOrders=not app.debugOrders
 elseif key=='f5' then app:save()
 else for _,a in ipairs(Actions.list(app)) do if a.key==key then Actions.activate(app,a);break end end end
end
return I
