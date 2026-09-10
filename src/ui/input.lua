local Codec=require('src.sim.codec')
local Content=require('src.content')
local Sim=require('src.sim')
local Actions=require('src.ui.actions')
local Camera=require('src.ui.camera')
local Selection=require('src.ui.selection')
local Mini=require('src.ui.minimap')
local I={}
local function shift() return love.keyboard.isDown('lshift','rshift') end
local function ctrl() return love.keyboard.isDown('lctrl','rctrl') end
-- Targeting is one record rather than a scatter of mode flags. `app.targeting` is nil
-- when nothing is armed, and otherwise says what the next click means: a command kind,
-- and for a cast the ability and its definition. Everything downstream -- the cursor,
-- the range ring, the area circle, the click handler and Escape -- reads this one place,
-- which is what lets an ability with a new target kind work without touching any of them.
-- `px,py` name the pointer in screen coordinates. It defaults to the real mouse, and is
-- an argument so that smart cast can be driven without one.
function I.arm(app,command,ability,px,py)
 app.building=nil
 if not command then app.targeting=nil;return end
 local spec=ability and Content.abilities and Content.abilities[ability] or nil
 -- A no-target ability has nothing to click: it fires where the caster stands.
 if spec and spec.target=='none' then app.targeting=nil;I.castAt(app,nil,nil,nil,ability);return end
 -- Smart cast: the key is the cast. Warcraft 3 added this because arming and then
 -- clicking is two actions for one decision, and in a fight the second one is the one
 -- you get wrong. Alt aims at yourself instead of at the cursor, which is the other half
 -- of the convention. With the pointer off the battlefield there is nothing to aim at,
 -- so it falls back to arming rather than casting at the HUD.
 if spec and app.settings.smartCast then
  if not px and love.mouse and love.mouse.getPosition then px,py=love.mouse.getPosition() end
  if px and Camera.contains(app,px,py) then
   local caster=app:entity(Selection.primary(app))
   if caster and love.keyboard.isDown('lalt','ralt') then return I.castAt(app,caster.x,caster.y,caster,ability) end
   local wx,wy=app:position(px,py)
   return I.castAt(app,wx,wy,app:pick(px,py),ability)
  end
 end
 app.targeting={command=command,ability=ability,spec=spec}
end
function I.disarm(app) app.targeting=nil;app.building=nil end
-- Every selected unit that owns the ability casts it. Out of range is not an error: the
-- caster walks, exactly as it does for an attack order.
function I.castAt(app,x,y,target,ability)
 if app.playback then return end
 local spec=Content.abilities and Content.abilities[ability]
 if not spec then return end
 local ordered={}
 for _,id in ipairs(app.selected) do
  local e=app:entity(id)
  local d=e and e.alive and Content.units[e.kind]
  local owns=false
  if d and d.abilities then for _,name in ipairs(d.abilities) do if name==ability then owns=true end end end
  if owns then
   local args={ability=ability,append=shift()}
   if spec.target=='unit' then
    if not target then app.message='Choose a target for '..spec.label;app.audio:play('rejected');return end
    args.target=target.id
   elseif spec.target~='none' then args.x=x;args.y=y end
   app:command('cast',id,args);ordered[#ordered+1]={id=id,kind=e.kind,command='cast'}
  end
 end
 if #ordered>0 then
  if x then app.orderMarker={x=x,y=y,time=app.clock,tick=app.world.tick,kind='cast'} end
  I.acknowledge(app,ordered);app.message=spec.label
 else app.message='Nothing selected can use '..spec.label;app.audio:play('rejected') end
end
-- What an armed click does. One place, so a new target kind is one branch here rather
-- than an edit in the world handler, the minimap handler and the cursor code.
function I.resolveTargeting(app,x,y,hit)
 local t=app.targeting
 if not t then return end
 app.targeting=nil
 if t.ability then return I.castAt(app,x,y,hit,t.ability) end
 I.intent(app,x,y,hit,t.command)
end
-- Whether the pointer is over something the armed ability may be aimed at. Only unit
-- targeting can be invalid at a given pixel; ground targeting is always legal, and out
-- of range is not invalid because the caster will walk.
function I.castLegal(app,spec,hit)
 if not spec then return true end
 if spec.target~='unit' then return true end
 if not hit or not hit.alive then return false end
 if hit.category=='node' or hit.category=='carrier' then return false end
 local filter=spec.filter or {enemy=true}
 if hit.category=='building' and not filter.building then return false end
 if hit.owner==app.player then return filter.ally==true or filter.self==true end
 return filter.enemy==true
end
function I.castShape(app,hit)
 local t=app.targeting
 if not t then return 'arrow' end
 if not I.castLegal(app,t.spec,hit) then return 'invalid' end
 return 'attack'
end
function I.intent(app,x,y,target,kind)
 if app.playback then return end
 local count=0;app.commandGroup=(app.commandGroup or 0)+1
 -- A right click with only buildings selected sets their rally point instead: the
 -- selection says what the click can possibly mean.
 if not kind then
  local buildings=0
  for _,id in ipairs(app.selected) do
   local e=app:entity(id)
   if e and e.alive then
    if e.category=='building' and e.queue then buildings=buildings+1
    elseif e.category=='unit' then buildings=-1000 end
   end
  end
  if buildings>0 then return I.rally(app,x,y,target) end
 end
 -- Warcraft 3 rule: an attack-move dropped directly onto an enemy is a focused attack
 -- on that enemy, not a walk to the ground it happens to be standing on. Without this
 -- the A key can never be used to focus fire, which is most of what it is for.
 local focus=kind=='attack_move' and target and target.alive and target.owner~=app.player and target.category~='node'
 local ordered={}
 for _,id in ipairs(app.selected) do
  local e=app:entity(id)
  if e and e.alive and e.category=='unit' then
   local command=focus and 'attack' or kind;local args={append=shift(),group=app.commandGroup}
   if not command then
    if target and target.owner==app.player and target.remaining and target.remaining>0 and e.kind=='worker' then command='build'
    elseif target and target.owner~=app.player and target.category~='node' then command='attack'
    -- Right-clicking one of your own live units falls in behind it.
    elseif target and target.owner==app.player and target.category=='unit' and target.id~=id then command='follow'
    else command='move' end
   end
   if command=='attack' or command=='build' or command=='follow' then args.target=target and target.id else args.x=x;args.y=y end
   app:command(command,id,args);count=count+1;ordered[#ordered+1]={id=id,kind=e.kind,command=command}
  end
 end
 if count>0 then
  app.orderMarker={x=x,y=y,time=app.clock,tick=app.world.tick,kind=kind or 'move'}
  I.acknowledge(app,ordered);app.message='Order issued'
 end
end
-- Warcraft 3 answers an order before the simulation has run: the unit's circle flashes
-- and it says something. That instant reply is what hides the command delay, which is
-- one tick offline and four in a network match. Both halves are local and cosmetic --
-- nothing here moves a unit or spends anything.
function I.acknowledge(app,ordered)
 local flash=app.ackFlash
 if flash then for key in pairs(flash) do flash[key]=nil end else flash={};app.ackFlash=flash end
 for _,entry in ipairs(ordered) do flash[entry.id]=true end
 app.ackFlashAt=app.clock
 local lead=ordered[1]
 if lead then app.audio:ack(lead.kind,lead.command) else app.audio:play('click') end
end
-- Set the rally point of every selected production building at once.
function I.rally(app,x,y,target)
 local count=0
 for _,id in ipairs(app.selected) do
  local e=app:entity(id)
  if e and e.alive and e.category=='building' and e.queue then
   if target and target.id~=id then app:command('rally',id,{target=target.id})
   else app:command('rally',id,{x=x,y=y}) end
   count=count+1
  end
 end
 if count>0 then
  app.orderMarker={x=x,y=y,time=app.clock,tick=app.world.tick,kind='move'}
  app.audio:play('click');app.message=count==1 and 'Rally point set' or (count..' rally points set')
 end
end
function I.mousepressed(app,x,y,button,presses)
 if button==2 and (app.building or app.targeting) then I.disarm(app);return end
 if app.widgets.context and app.widgets.context~=(app.overlay or 'match') then return end
 if button==1 then local hit,reason=app.widgets:click(x,y);if hit then if reason then app.message=reason;app.audio:play('rejected') end;return end end
 if app.overlay then return end
 if app.timeline and y>=app.timeline.y and y<app.timeline.y+app.timeline.h and x>=app.timeline.x and x<app.timeline.x+app.timeline.w then
  app:requestSeek(math.floor((x-app.timeline.x)/app.timeline.w*#app.playback.frames));return
 end
 local s=app.settings.scale/100
 if app.minimap then
  local r=app.minimap;local wx,wy=Mini.position(app.view.map,r,x/s,y/s)
  if wx then
   -- Alt-click pings. It goes through the command stream, so the marker appears for
   -- your ally too and is in the replay -- it used to be a local dot only you saw.
   if button==1 and love.keyboard.isDown('lalt','ralt') then app:command('ping',nil,{x=wx,y=wy});app.audio:play('click')
   elseif button==1 and app.targeting then I.resolveTargeting(app,wx,wy,nil)
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
   local valid,reason=Sim.placement(app.view,Content,app.building,cx,cy)
   if valid then
    for _,id in ipairs(app.selected) do local e=app:entity(id);if e and e.kind=='worker' then app:command('build',id,{building=app.building,x=cx,y=cy,append=shift()});break end end
    if not shift() then app.awaitingPlacement=app.building;app.building=nil end
   else app.message=reason;app.audio:play('rejected') end
  elseif app.targeting then local wx,wy=app:position(x,y);I.resolveTargeting(app,wx,wy,app:pick(x,y))
  elseif (presses and presses>=2) or ctrl() then I.selectSameKind(app,x,y)
  else app.drag={x=x,y=y};app.capture='selection' end
 elseif button==2 then local wx,wy=app:position(x,y);I.intent(app,wx,wy,app:pick(x,y)) end
end
function I.mousemoved(app,x,y,dx,dy)
 if app.capture=='minimap' then local s=app.settings.scale/100;local wx,wy=Mini.position(app.view.map,app.minimap,x/s,y/s,true);Camera.center(app,wx,wy)
 elseif app.capture=='pan' then app.camera.x=app.camera.x+dx;app.camera.y=app.camera.y+dy;app.cameraGlide=nil;Camera.clamp(app) end
 I.updateHover(app,x,y)
end
-- Recomputed on motion and once per simulation tick. Motion alone is not enough: with
-- the pointer held still over open ground, a unit that walks under it kept the old
-- cursor and the old hover ring until the mouse was nudged.
function I.refreshHover(app)
 if not (love.mouse and love.mouse.getPosition) then return end
 local x,y=love.mouse.getPosition()
 I.updateHover(app,x,y)
end
-- What the pointer is over, and what the pointer should look like there. Only inside
-- the world viewport; the HUD keeps the arrow.
function I.updateHover(app,x,y)
 if app.overlay or not Camera.contains(app,x,y) then app.hoverId=nil;I.setCursor(app,'arrow');return end
 local hit=app:pick(x,y)
 app.hoverId=hit and hit.id or nil
 app.hoverAt=app.clock
 local shape='arrow'
 if app.building then
  local wx,wy=app:position(x,y)
  local valid=Sim.placement(app.view,Content,app.building,math.floor(wx/256),math.floor(wy/256))
  shape=valid and 'build' or 'invalid'
 elseif app.targeting and app.targeting.ability then shape=I.castShape(app,hit)
 elseif app.targeting and (app.targeting.command=='attack_move' or app.targeting.command=='patrol') then shape='attack'
 elseif app.targeting and app.targeting.command=='move' then shape='move'
 elseif hit and hit.owner~=app.player and hit.owner~=0 and hit.category~='node' then shape='attack'
 -- A mine is inert: it reads as a place to build on, not a thing to click.
 elseif hit and hit.category=='node' then shape='build' end
 I.setCursor(app,shape)
end
-- Cursors are generated at runtime so the shape set works with no art in the tree; a
-- real cursor image can be dropped into app.cursorImages later and will be used instead.
local cursorCache={}
function I.setCursor(app,shape)
 if app.cursorShape==shape then return end
 app.cursorShape=shape
 if not (love.mouse and love.mouse.newCursor and love.image) then return end
 local cursor=cursorCache[shape]
 if cursor==nil then
  local ok,made=pcall(I.buildCursor,shape)
  cursor=ok and made or false;cursorCache[shape]=cursor
 end
 if cursor then pcall(love.mouse.setCursor,cursor) else pcall(love.mouse.setCursor) end
end
local CURSOR_COLORS={arrow={.92,.94,.9},move={.55,.95,.6},attack={1,.35,.3},build={.6,.8,1},invalid={1,.3,.3}}
function I.buildCursor(shape)
 local size=24
 local data=love.image.newImageData(size,size)
 local c=CURSOR_COLORS[shape] or CURSOR_COLORS.arrow
 local mid=size/2
 local function put(px,py,a)
  if px>=0 and py>=0 and px<size and py<size then data:setPixel(px,py,c[1],c[2],c[3],a) end
 end
 if shape=='arrow' then
  for i=0,15 do for j=0,math.floor(i/2) do put(i,j+i,1) end;put(i,i,1) end
 elseif shape=='invalid' then
  for i=-8,8 do put(mid+i,mid+i,1);put(mid+i,mid-i,1) end
 elseif shape=='attack' then
  for i=-10,10 do if math.abs(i)>2 then put(mid+i,mid,1);put(mid,mid+i,1) end end
  for a=0,63 do local r=7;put(mid+math.floor(r*math.cos(a/32*math.pi)),mid+math.floor(r*math.sin(a/32*math.pi)),1) end
 elseif shape=='build' then
  for i=-8,8 do put(mid+i,mid-5,1);put(mid+i,mid-3,1) end
  for j=-3,9 do put(mid,mid+j,1) end
 else
  for i=-8,8 do put(mid+i,mid,1);put(mid,mid+i,1) end
 end
 return love.mouse.newCursor(data,mid,shape=='arrow' and 0 or mid)
end
-- Box selection follows the Warcraft 3 priority rather than taking everything the
-- rectangle touched: your own units win over anything else caught in the same box, your
-- own buildings are only picked up when the box held no unit at all, and an enemy or
-- neutral is only ever selected alone, for inspection. Without this a drag across your
-- own line in front of a war hall silently mixes the hall into the army.
function I.boxSelect(app,x0,y0,x1,y1)
 local own,buildings,other={},{},{}
 for _,e in ipairs(app.view.entities) do
  if e.alive and e.category~='node' and e.category~='carrier' then
   local sx,sy=app:screen(e.x,e.y)
   if Camera.contains(app,sx,sy) and sx>=x0 and sx<=x1 and sy>=y0 and sy<=y1 then
    if e.owner~=app.player then other[#other+1]=e.id
    elseif e.category=='unit' then own[#own+1]=e.id
    else buildings[#buildings+1]=e.id end
   end
  end
 end
 if #own>0 then return own end
 if #buildings>0 then return buildings end
 if #other>0 then table.sort(other);return {other[1]} end
 return {}
end
-- Ctrl+click and double click both mean "every visible one of these", which is the
-- Warcraft 3 binding. On screen only, deliberately: selecting an army you cannot see
-- is not a Warcraft 3 behaviour and hides units from the player commanding them.
function I.selectSameKind(app,x,y)
 local hit=app:pick(x,y,true)
 if not hit then return false end
 local ids={}
 for _,e in ipairs(app.view.entities) do
  local sx,sy=app:screen(e.x,e.y)
  if e.alive and e.owner==app.player and e.kind==hit.kind and e.category==hit.category and Camera.contains(app,sx,sy) then ids[#ids+1]=e.id end
 end
 table.sort(ids);app.selected=ids;return true
end
function I.mousereleased(app,x,y,button)
 if app.capture=='pan' and button==3 or app.capture=='minimap' and button==1 then app.capture=nil;return end
 if button~=1 or not app.drag then return end
 local drag=app.drag;app.drag=nil;app.capture=nil
 if not shift() then app.selected={} end
 if math.abs(x-drag.x)+math.abs(y-drag.y)<8 then local e=app:pick(x,y,true);if e then if shift() then Selection.toggle(app.selected,e.id) else app.selected={e.id} end end
 else
  local picked=I.boxSelect(app,math.min(x,drag.x),math.min(y,drag.y),math.max(x,drag.x),math.max(y,drag.y))
  for _,id in ipairs(picked) do if shift() then Selection.toggle(app.selected,id) else app.selected[#app.selected+1]=id end end
 end
 table.sort(app.selected);app.audio:play('click')
end
-- Keys the match loop owns and that rebinding must not be able to take away.
local RESERVED={escape=true,tab=true,f2=true,f3=true,f4=true,f5=true,f6=true,f7=true,f8=true,f10=true,q=true,w=true,e=true,r=true}
-- Own combat units: everything alive that is not a worker and not a building.
function I.army(app)
 local ids={}
 for _,e in ipairs(app.view.entities) do
  if e.alive and e.owner==app.player and e.category=='unit' then
   local d=Content.units[e.kind]
   if d and not d.worker then ids[#ids+1]=e.id end
  end
 end
 table.sort(ids);return ids
end
-- A worker counts as idle when it has no order. Workers that are constructing hold a
-- 'build' order, so they are not offered.
function I.idleWorkers(app)
 local ids={}
 for _,e in ipairs(app.view.entities) do
  if e.alive and e.owner==app.player and e.kind=='worker' and e.order and e.order.kind=='stop' then
   ids[#ids+1]=e.id
  end
 end
 table.sort(ids);return ids
end
-- Cycles rather than always selecting the first, so repeated presses walk the whole set.
function I.selectIdleWorker(app)
 local ids=I.idleWorkers(app)
 if #ids==0 then app.message='No idle workers';return false end
 local index=1
 if app.lastIdleWorker then
  for i,id in ipairs(ids) do if id==app.lastIdleWorker then index=i%#ids+1;break end end
 end
 local id=ids[index];app.lastIdleWorker=id;app.selected={id}
 local e=app:entity(id);if e then Camera.glide(app,e.x,e.y) end
 app.audio:play('click');app.message='Idle worker '..index..' / '..#ids
 return true
end
function I.keypressed(app,key)
 if app.rebind then
  if not RESERVED[key] and not tonumber(key) then
   for action,binding in pairs(app.settings.bindings) do if binding==key then app.settings.bindings[action]=app.settings.bindings[app.rebind] end end
   app.settings.bindings[app.rebind]=key;require('src.ui.settings').save(app.settings)
  end;app.rebind=nil;return
 end
 if key=='escape' then
  if app.building or app.targeting then I.disarm(app)
  elseif app.overlay then app.overlay=nil else app.overlay='pause' end;return
 end
 if app.overlay then return end
 local bindings=app.settings.bindings
 if key==bindings.hero then
  if ctrl() then app.followHero=not app.followHero;app.message=app.followHero and 'Following hero' or 'Hero follow off';return end
  app.selected={app.view.player.hero};local e=app:entity(app.view.player.hero);if app.lastHero and app.clock-app.lastHero<.35 and e then Camera.glide(app,e.x,e.y) end;app.lastHero=app.clock
 elseif key==bindings.alert then local a=app.alerts.items[1];if a and a.x then Camera.glide(app,a.x,a.y) end
 elseif key==bindings.idle then I.selectIdleWorker(app)
 elseif key=='f2' then
  local ids=I.army(app)
  if #ids>0 then app.selected=ids;app.audio:play('click');app.message=#ids..' combat units selected' else app.message='No combat units' end
 elseif key=='f4' then app.perfOverlay=not app.perfOverlay
 elseif key=='f10' then app.hotkeyHelp=not app.hotkeyHelp
 elseif key=='f5' or key=='f6' or key=='f7' or key=='f8' then
  local slot=tonumber(key:sub(2))
  if ctrl() then Camera.setBookmark(app,slot);app.message='Camera bookmark '..slot..' set'
  elseif not Camera.recallBookmark(app,slot) then app.message='Camera bookmark '..slot..' is empty' end
 elseif key=='s' and ctrl() then app:save()
 elseif key=='tab' then
  local kind=Selection.cycle(app)
  if kind then
   local label=(Content.units[kind] or Content.buildings[kind] or {}).label or kind
   app.message=label..' commands';app.audio:play('click')
  end
  app.lastTab=app.clock
 elseif tonumber(key) and tonumber(key)>=1 and tonumber(key)<=9 then
  local n=tonumber(key)
  if love.keyboard.isDown('lctrl','rctrl') then app.groups[n]=Codec.copy(app.selected)
  elseif app.groups[n] then app.selected={};for _,id in ipairs(app.groups[n]) do local e=app:entity(id);if e and e.alive then app.selected[#app.selected+1]=id end end
   if app.lastGroup==n and app.clock-(app.lastGroupTime or -100)<.35 then local e=app:entity(app.selected[1]);if e then Camera.glide(app,e.x,e.y) end end
   app.lastGroup=n;app.lastGroupTime=app.clock
  end
 elseif key=='f3' then app.debugOrders=not app.debugOrders
 else for _,a in ipairs(Actions.list(app)) do if a.key==key then if not a.reason then a.run() else app.message=a.reason end;break end end end
end
return I
