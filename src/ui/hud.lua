local Sim=require('src.sim')
local Minimap=require('src.ui.minimap')
local Selection=require('src.ui.selection')
local Icons=require('src.ui.icons')
local Actions=require('src.ui.actions')
local Input=require('src.ui.input')
local Camera=require('src.ui.camera')
local H={}
-- The faction's look for this frame (src/ui/theme.lua), set at the top of H.draw.
local theme=require('src.ui.theme').default
local function text(value,x,y,w) love.graphics.setColor(theme.text[1],theme.text[2],theme.text[3]);love.graphics.printf(value,x,y,w or 180) end
local function bar(x,y,w,value,max)
 local g=love.graphics;g.setColor(.04,.07,.08);g.rectangle('fill',x,y,w,6);g.setColor(theme.meter[1],theme.meter[2],theme.meter[3]);g.rectangle('fill',x,y,w*math.max(0,math.min(1,value/math.max(1,max))),6)
end
function H.draw(app)
 local C=app.content
 local g=love.graphics;local s=app.settings.scale/100;local width,height=g.getDimensions();local w,h=width/s,height/s;local y=h-180
 local actions=Actions.list(app)
 g.push('all');g.scale(s);g.setFont(app.fonts.small);app.widgets:begin(s);app.widgets.context=app.overlay or 'match';app.widgets.notice=app.uiNotice;app.widgets.clock=app.clock
 theme=require('src.ui.theme').of(app.view.player.faction);app.widgets.theme=theme
 g.setColor(theme.panel[1],theme.panel[2],theme.panel[3],.98);g.rectangle('fill',0,0,w,40);g.rectangle('fill',0,y,w,180)
 g.setColor(theme.line[1],theme.line[2],theme.line[3]);g.line(0,40,w,40);g.line(0,y,w,y)
 g.setColor(theme.accent[1],theme.accent[2],theme.accent[3]);g.print(theme.name,16,13);local p=app.view.player
 local font=g.getFont()
 -- One readout per ledger key, in content order, each explaining itself on hover the way
 -- Warcraft 3's resource bar does.
 local rx=135
 for _,key in ipairs(C.rules.resources or {'gold'}) do
  local label=key:sub(1,1):upper()..key:sub(2);local readout=label..'  '..(p.resources[key] or 0)
  local flash=app.costFlash and app.clock-app.costFlash.time<.9 and app.costFlash.keys[key]
  g.setColor(flash and 1 or .83,flash and .38 or .86,flash and .32 or .81);g.print(readout,rx,13)
  app.widgets:region(key,rx-4,6,font:getWidth(readout)+8,28,{title=label,
   lines=key=='gold' and {'Pays for units, buildings, hero revival and HQ advancement.','Carriers bring it from Extractors built on gold mines.'} or {'Pays for units and buildings.'}})
  rx=rx+font:getWidth(readout)+28
 end
 local cap=p.supplyCap or C.rules.population
 local food,units=require('src.sim').population(app.world,app.player),require('src.sim').unitCount(app.world,app.player)
 local foodText,unitText=theme.supply..'  '..food..' / '..cap,'   Units '..units
 text(foodText..unitText,430,13,300)
 local clockText=string.format('%02d:%02d',math.floor(app.world.tick/1200),math.floor(app.world.tick/20)%60)
 text(clockText,w-220,13,100)
 app.widgets:region('food',426,6,font:getWidth(foodText)+8,28,{title=theme.supply,stats={food..' used','cap '..cap},
  lines={'Every living unit and every unit in training takes '..theme.supply:lower()..'. Nothing more can be trained past the cap'..(C.rules.supplyFromBuildings and ', which your buildings raise.' or '.')},reason=food>=cap and theme.supply..' cap reached' or nil})
 app.widgets:region('units',430+font:getWidth(foodText),6,font:getWidth(unitText)+4,28,{title='Units',lines={'You have '..units..' living units.'}})
 app.widgets:region('clock',w-224,6,font:getWidth(clockText)+8,28,{title='Match time',lines={'Game time. It runs at the fixed simulation rate, whatever the game speed setting.'}})
 app.widgets:button('menu','Menu',w-98,6,86,28,function() app.overlay='pause' end)
 -- Orbital logistics are always on screen for a faction that has them.
 local Orbital=require('src.ui.orbital');app.sidebar=Orbital.active(app.view,C)
 if app.sidebar then Orbital.draw(app,w,h) end
 Minimap.draw(app,{x=10,y=y+10,w=190,h=160})
 app.widgets:region('minimap',10,y+10,190,160,{title='Minimap',lines={'Click or drag to move the camera. Right-click to send the selection there.',{'Alt-click pings the spot for everyone.',{.62,.66,.62}}}})
 local hero=app:entity(p.hero);local hx=214
 if hero then
  app.widgets:button('hero',C.units[hero.kind].label..' [F1]',hx+42,y+12,103,42,function() app.selected={hero.id};Actions.context(app);app.audio:selected(hero.kind);Camera.center(app,hero.x,hero.y) end,nil,{title=C.units[hero.kind].label,key=app.settings.bindings.hero or 'f1',subtitle='Your hero',subtitleColor={.45,.8,1},lines={'Select your hero and centre the camera on it.',{'Ctrl+'..(app.settings.bindings.hero or 'f1'):upper()..' keeps the camera following it.',{.62,.66,.62}}}})
  require('src.ui.icons').portrait(hero.kind,hx,y+12)
  text(hero.hp..' / '..hero.maxHp..' HP',hx,y+59,145);bar(hx,y+77,145,hero.hp,hero.maxHp)
  -- Experience toward the next milestone, with the level number, so progression is
  -- readable without opening the upgrade panel.
  local level,floor,ceiling=0,0,nil
  for i,threshold in ipairs(C.rules.xpThresholds) do
   if hero.xp>=threshold then level=i;floor=threshold else ceiling=ceiling or threshold end
  end
  local xpLabel
  if ceiling then
   bar(hx,y+101,145,hero.xp-floor,math.max(1,ceiling-floor))
   xpLabel='XP '..hero.xp..' / '..ceiling
  else xpLabel='XP '..hero.xp..' (max)' end
  -- Stance moved onto its own button label: the level/XP line has to stay one line,
  -- and printf wraps rather than clips, which pushed text under the button below.
  text('Level '..level..'    '..xpLabel,hx,y+87,160)
  app.widgets:region('hero-hp',hx,y+57,145,28,{title='Hero health',stats={hero.hp..' / '..hero.maxHp},lines={hero.alive and 'Heals near your headquarters when out of combat.' or 'Dead. Revive it from the button below.'}})
  app.widgets:region('hero-xp',hx,y+85,145,24,{title='Level '..level,stats={'XP '..hero.xp},lines={ceiling and ('Next upgrade at '..ceiling..' XP.') or 'Every upgrade tier is unlocked.','Heroes gain experience when enemies die nearby.'}})
  app.widgets:button('hero-stance','Stance '..hero.stance..': toggle',hx,y+111,145,24,function() Actions.order(app,{hero},'toggle') end,not hero.alive and 'Hero is dead' or nil,
   {title='Stance '..hero.stance,key='z',lines={'Switch between the defensive, recovering stance and the offensive, pursuing one.'}})
  local milestone
  for i,t in ipairs(C.rules.xpThresholds) do if hero.xp>=t and not hero.upgrades[i] then milestone=i;break end end
  if milestone and hero.alive then app.widgets:button('upgrade','Upgrade available',hx,y+140,145,28,function() Actions.openAbilities(app);app.audio:play('menu') end,nil,
   {title='Hero upgrade',subtitle='Tier '..milestone,subtitleColor={.56,.9,.6},lines={'Your hero has enough experience for a permanent upgrade. Open the choices.'}})
  elseif not hero.alive then app.widgets:button('revive',hero.reviveRemaining and ('Reviving '..math.ceil(hero.reviveRemaining/20)..'s') or ('Revive: '..require('src.sim').revival(C,hero)..' gold'),hx,y+140,145,28,function() app:command('revive',hero.id) end,hero.reviveRemaining and 'Revival in progress' or p.resources.gold<require('src.sim').revival(C,hero) and 'Insufficient gold' or nil,
   (function() local cost,ticks=require('src.sim').revival(C,hero)
    return {title='Revive hero',lines={'Your hero returns at your headquarters after '..math.ceil(ticks/20)..' seconds. Cost and time grow with each experience milestone reached.'},
     costs=not hero.reviveRemaining and Actions.costs(app,{gold=cost}) or nil} end)()) end
 end
 -- Idle workers are the most common thing a player loses track of, so the count is
 -- always on screen and one click takes you to the next one.
 -- A faction with no workers (the Megacorp) has nothing to lose track of here.
 local idle=Input.idleWorkers(app)
 if (C.factions[p.faction] or {}).worker~=false then app.widgets:button('idle-worker','Idle: '..#idle..' ['..(app.settings.bindings.idle or 'f9'):upper()..']',745,6,150,28,
  function() Input.selectIdleWorker(app) end,#idle==0 and 'No idle workers' or nil,
  {title='Idle workers',key=app.settings.bindings.idle or 'f9',stats={#idle..' idle'},lines={'Select and centre on the next worker with no order and nothing to deliver.'}}) end
 local sx,sw=375,math.max(140,w-375-330);local e=app:entity(Selection.primary(app))
 local inspected=Selection.inspecting(app)
 text(inspected and 'Inspecting' or (#app.selected..' selected'),sx,y+12,sw)
 local groups=Selection.groups(app)
 for i,group in ipairs(inspected and {} or groups) do local col=(i-1)%3;local row=math.floor((i-1)/3)
  -- Clicking a type makes it the active subgroup, the same as Tab, and leaves the rest
  -- of the army selected. Shift-click is the narrowing move, for when you actually want
  -- to split the crossbows out. The active type is marked so the card has an owner.
  local active=app.subgroupKind==group.kind
  app.widgets:button('group-'..group.kind,(active and '> ' or '')..(C.units[group.kind] or C.buildings[group.kind]).label..' x'..#group.ids,
   sx+col*(sw/3),y+35+row*30,sw/3-4,26,function()
    if love.keyboard.isDown('lshift','rshift') then app.selected=group.ids;app.subgroupKind=nil
    else app.subgroupKind=group.kind end
   end,nil,'Click shows this type\'s commands and keeps the whole selection. Shift-click keeps only this type.')
 end
 -- One tile per selected unit with its own health, because a type-count row cannot show
 -- that three of twelve shieldguards are nearly dead. Click selects that one unit;
 -- shift-click drops it from the selection, which is what the tiles are really for.
 if #app.selected>1 then H.unitTiles(app,sx,y+35+math.ceil(#groups/3)*30,sw) end
 if inspected then H.inspect(app,inspected,sx,y,sw)
 elseif e then
  text(e.hp..'/'..e.maxHp..' HP  |  '..(e.blockedReason or e.order.kind)..'  |  '..#(e.orders or {})..' queued',sx,y+104,sw)
  if e.queue then
   for i,q in ipairs(e.queue) do app.widgets:button('production-'..i,C.units[q.kind].label..' '..math.ceil(q.remaining/20)..'s  x',sx+(i-1)%3*(sw/3),y+127+math.floor((i-1)/3)*24,sw/3-4,22,function() app:command('cancel',e.id,{index=i}) end,nil,{title=C.units[q.kind].label,subtitle=i==1 and 'Training, '..math.ceil(q.remaining/20)..'s left' or 'Waiting in queue',lines={'Click to cancel. A unit still waiting refunds in full; the one training refunds half.'}}) end
   -- Progress of whatever is actually training, under the queue tiles.
   local head=e.queue[1]
   if head then
    local total=C.units[head.kind].buildTicks
    bar(sx,y+127+math.ceil(#e.queue/3)*24,sw-8,total-head.remaining,total)
   end
  elseif #app.selected==1 then
   local d=C.units[e.kind]
   if d then
    -- Full stat card for a single selection: what the unit does, not just its health.
    text('Damage '..(d.damage or 0)..'   Range '..string.format('%.1f',d.range/256)..' cells   Speed '..(d.speed or 0),sx,y+124,sw)
    text('Attack every '..string.format('%.2f',(d.cooldown or 0)/20)..'s   Sight '..(d.sight or 0)..' cells   Food '..(d.food or 1),sx,y+140,sw)
   end
  end
 end
 local title=app.cardPage=='build' and 'BUILD STRUCTURES' or app.cardPage=='abilities' and 'HERO ABILITIES' or 'COMMANDS'
 text(title,w-320,y+6,310)
 g.setFont(app.fonts.card)
 app.widgets.anchor='card'
 for i,a in ipairs(actions) do
  local slot=a.slot or i;local col=(slot-1)%3;local row=math.floor((slot-1)/3)
  app.widgets:button(a.id,a.label,w-320+col*103,y+24+row*49,98,46,function() Actions.activate(app,a) end,a.reason,a.tip,a.id,a)
 end
 app.widgets.anchor=nil
 g.setFont(app.fonts.small)
 if #actions==0 then text(inspected and ('You cannot command '..(inspected.owner==0 and 'neutral' or 'enemy')..' '..(inspected.category=='node' and 'resources.' or inspected.category=='building' and 'buildings.' or 'units.'))
  or #app.selected>1 and 'Select a unit group or one building.' or 'Select units to see commands.',w-315,y+38,290) end
 local pending=0;for _ in pairs(app.pending or {}) do pending=pending+1 end
 if app.uiNotice and app.uiNotice.kind=='rejected' and app.clock-app.uiNotice.time<2 then g.setColor(1,.4,.32);g.rectangle('fill',8,46,3,19) end
 text((pending>0 and (pending..' pending | ') or '')..(app.message or ''),16,48,w-32)
 for i,a in ipairs(app.alerts.items) do app.widgets:button('alert-'..i,a.text..(a.count and (' x'..a.count) or ''),16,72+(i-1)*31,285,27,function() if a.action then a.action(app) elseif a.x then Camera.center(app,a.x,a.y) end end,nil,a.action and {title=a.text,lines={a.hint or 'Click to act on it.'}} or a.x and {title=a.text,lines={'Click to centre the camera here.'}} or nil) end
 if app.playback then
  local ry=42
  app.widgets:button('replay-pause',app.replayPaused and 'Play' or 'Pause',w-410,ry,70,26,function() app.replayPaused=not app.replayPaused end)
  app.widgets:button('replay-speed',app.replaySpeed..'x',w-334,ry,65,26,function() app.replaySpeed=app.replaySpeed==4 and .5 or app.replaySpeed*2 end)
  app.widgets:button('perspective','Player '..app.player,w-263,ry,90,26,function() app:requestSeek(app.world.tick,app.player==1 and 2 or 1) end)
  app.widgets:button('replay-back','-10s',w-167,ry,65,26,function() app:requestSeek(math.max(0,app.world.tick-200)) end)
  app.widgets:button('replay-next','+10s',w-96,ry,65,26,function() app:requestSeek(math.min(#app.playback.frames,app.world.tick+200)) end)
  local ty=73;bar(w-410,ty,380,app.world.tick,#app.playback.frames);app.timeline={x=(w-410)*s,y=(ty-2)*s,w=380*s,h=14*s}
 end
 if app.perfOverlay then H.performance(app,w,h) end
 if app.hotkeyHelp then H.hotkeys(app,w,h) end
 if app.debugOrders then require('src.ui.order_debug').draw(app,w,h) end
 if app.overlay then require('src.ui.screens').overlay(app,w,h) end
 if app.banner then H.banner(app,w,h) end
 H.tooltip(app,w,h,y);g.pop()
end
-- The one tooltip for the frame, drawn last so nothing covers it. A widget under the pointer wins;
-- otherwise whatever the pointer rests on in the world. Nothing shows while the pointer is doing
-- something else with the world: dragging a box, panning, or placing a building.
function H.tooltip(app,w,h,cardTop)
 local world,worldId
 local busy=app.capture or app.drag or app.building
 if not app.overlay and app.hoverId then
  local e=app:entity(app.hoverId)
  if e and e.kind~='projectile' then
   world=require('src.ui.tooltip').entity(app,e);worldId='e:'..e.id
  end
 end
 app.widgets:tooltip(w,h,{card={x=w-322,y=cardTop,w=306,h=180},top=44,world=world,worldId=worldId,
  titleFont=app.fonts.body,hidden=busy and not app.widgets.hover})
end
-- The card for an inspected enemy, neutral or gold mine, drawn where your own unit's card
-- goes: what it is, its health, and the statistics anyone could look up. Nothing about its
-- orders, queue or experience, which a view does not carry for someone else's entity.
function H.inspect(app,e,x,y,width)
 local C=app.content
 local g=love.graphics
 local d=C.units[e.kind] or C.buildings[e.kind]
 local name=e.category=='node' and (require('src.ui.tooltip').RESOURCE_NAMES[e.resource] or 'Resource') or (d and d.label) or e.kind
 if e.owner==0 then g.setColor(.95,.78,.38) else g.setColor(1,.45,.38) end
 g.printf((e.owner==0 and 'Neutral  ' or 'Enemy  ')..name,x,y+35,width)
 if e.category=='node' then text((e.amount or 0)..' gold remaining',x,y+60,width);return end
 text(e.hp..' / '..e.maxHp..' HP'..((e.remaining or 0)>0 and (e.stalled and '   construction stopped' or '   under construction') or ''),x,y+60,width)
 bar(x,y+80,math.min(width-8,240),e.hp,e.maxHp)
 if e.maxMana then text('Mana '..(e.mana or 0)..' / '..e.maxMana,x,y+104,width) end
 if not d then return end
 local first,second={},{}
 if d.damage then first[#first+1]='Damage '..d.damage;first[#first+1]='Range '..string.format('%.1f',(d.range or 0)/256)..' cells' end
 if e.category=='unit' then first[#first+1]='Speed '..(d.speed or 0) end
 if d.damage and d.cooldown then second[#second+1]='Attack every '..string.format('%.2f',d.cooldown/20)..'s' end
 second[#second+1]='Sight '..(d.sight or 0)..' cells'
 if e.category=='unit' and d.food then second[#second+1]='Food '..d.food end
 text(table.concat(first,'   '),x,y+124,width);text(table.concat(second,'   '),x,y+140,width)
end
H.TILES_PER_PAGE=12
-- A page of up to twelve per-unit tiles, each with its own health. Paging keeps the
-- dock a fixed size with any selection size; Tab still cycles subgroups as before.
function H.unitTiles(app,x,y,width)
 local C=app.content
 local g=love.graphics
 local ids=app.selected
 local pages=math.ceil(#ids/H.TILES_PER_PAGE)
 app.tilePage=math.max(1,math.min(pages,app.tilePage or 1))
 local first=(app.tilePage-1)*H.TILES_PER_PAGE
 local tile=math.min(34,(width-8)/H.TILES_PER_PAGE)
 for slot=1,H.TILES_PER_PAGE do
  local id=ids[first+slot]
  if id then
   local e=app:entity(id)
   if e then
    local tx=x+(slot-1)*(tile+2)
    g.setColor(.11,.15,.17);g.rectangle('fill',tx,y,tile,tile,3)
    g.setColor(.4,.44,.36);g.rectangle('line',tx,y,tile,tile,3)
    Icons.draw(e.kind,tx+3,y+2,tile-10)
    local ratio=math.max(0,math.min(1,e.hp/math.max(1,e.maxHp)))
    g.setColor(.05,.07,.08);g.rectangle('fill',tx+2,y+tile-6,tile-4,4)
    g.setColor(1-ratio,.35+ratio*.5,.35);g.rectangle('fill',tx+2,y+tile-6,(tile-4)*ratio,4)
    -- Registered after drawing so the click region matches exactly what is shown.
    app.widgets:button('tile-'..id,'',tx,y,tile,tile,function()
     if love.keyboard.isDown('lshift','rshift') then Selection.toggle(app.selected,id)
     else app.selected={id};local unit=app:entity(id);if unit then Camera.glide(app,unit.x,unit.y) end end
    end,nil,{title=(C.units[e.kind] or C.buildings[e.kind] or {}).label or e.kind,stats={'HP '..e.hp..' / '..e.maxHp},
     lines={'Click selects only this unit. Shift-click removes it from the selection.'}})
   end
  end
 end
 if pages>1 then
  app.widgets:button('tile-prev','<',x+width-58,y,26,tile,function() app.tilePage=math.max(1,app.tilePage-1) end,app.tilePage<=1 and 'First page' or nil)
  app.widgets:button('tile-next','>',x+width-28,y,26,tile,function() app.tilePage=math.min(pages,app.tilePage+1) end,app.tilePage>=pages and 'Last page' or nil)
 end
end
-- F4. Reports what the benchmark reports, so a player can see the same numbers the
-- perf work is measured against without running the harness.
function H.performance(app,w,h)
 local g=love.graphics
 local p=app.perf or {}
 local lines={
  string.format('FPS %d  (frame %.1f ms)',love.timer.getFPS(),1000*love.timer.getAverageDelta()),
  string.format('sim %.2f ms   view %.2f ms   draw %.2f ms',p.step or 0,p.view or 0,p.draw or 0),
  string.format('draw calls %d   entities drawn %d',p.drawcalls or 0,p.drawn or 0),
  string.format('Lua heap %.1f MiB   effects %d',collectgarbage('count')/1024,#app.feedback.items),
  string.format('tick %d   backlog %.0f ms   dropped %d',app.world.tick,app.accumulator*1000,app.discardedTicks or 0),
 }
 local width=280
 g.setColor(.02,.04,.05,.86);g.rectangle('fill',w-width-12,92,width,#lines*17+12,4)
 g.setColor(.72,.94,.86)
 for i,line in ipairs(lines) do g.print(line,w-width-4,96+(i-1)*17) end
end
-- F10. Generated from the live action list and the current bindings, so it cannot drift
-- out of date the way a hand-written list would.
function H.hotkeys(app,w,h)
 local g=love.graphics
 local rows={}
 local b=app.settings.bindings
 for _,pair in ipairs({{'Select hero',b.hero},{'Select all combat units','f2'},{'Next idle worker',b.idle},
  {'Jump to newest alert',b.alert},{'Cycle subgroup','tab'},{'Control group','1-9 (ctrl sets)'},
  {'Camera bookmark','f5-f8 (ctrl sets)'},{'Follow hero','ctrl+'..(b.hero or 'f1')},{'Save replay','ctrl+s'},
  {'All health bars','hold alt'},{'Order inspector','f3'},{'Performance overlay','f4'},{'This help','f10'}}) do
  rows[#rows+1]=pair
 end
 for _,a in ipairs(Actions.list(app)) do if a.key and a.key~='' then rows[#rows+1]={a.label,a.key} end end
 local width,lineHeight=380,18
 local x,y=w/2-width/2,h/2-(#rows*lineHeight+40)/2
 g.setColor(.02,.04,.05,.93);g.rectangle('fill',x-16,y-30,width+32,#rows*lineHeight+52,6)
 g.setColor(.95,.88,.65);g.print('Hotkeys  [F10 closes]',x,y-22)
 for i,row in ipairs(rows) do
  g.setColor(.84,.88,.82);g.print(row[1],x,y+(i-1)*lineHeight)
  g.setColor(.95,.82,.45);g.printf(tostring(row[2]):upper(),x,y+(i-1)*lineHeight,width,'right')
 end
end
-- Shown before the results screen so the outcome registers as an event rather than as
-- a panel that simply appears.
function H.banner(app,w,h)
 local g=love.graphics;local banner=app.banner
 local fade=math.min(1,banner.age*1.6)
 local won=banner.won
 g.setColor(0,0,0,.45*fade);g.rectangle('fill',0,h/2-70,w,140)
 g.setFont(app.fonts.title)
 g.setColor(won and .55 or 1,won and .95 or .45,won and .6 or .4,fade)
 g.printf(won and 'VICTORY' or 'DEFEAT',0,h/2-34,w,'center')
 g.setFont(app.fonts.body);g.setColor(.86,.88,.84,fade)
 g.printf(banner.detail or '',0,h/2+6,w,'center')
end
-- The control-point countdown is public, so both sides read the same clock: the holder to
-- defend it, the other player to know how long they have to break the hold.
function H.control(app)
 local C=app.content
 local control=app.view and app.view.control
 if not control or control.holder==0 or app.world.result then return end
 local g=love.graphics;local w=g.getDimensions()
 local rules=C.rules.control or require('src.sim.control').DEFAULT
 local seconds=math.ceil(math.max(0,rules.holdTicks-(app.view.tick-control.since))/20)
 local own=control.holder==app.player
 local text=string.format('%s both control points   %d:%02d',own and 'You hold' or 'The enemy holds',math.floor(seconds/60),seconds%60)
 g.setFont(app.fonts.body);local width=app.fonts.body:getWidth(text)+28
 g.setColor(0,0,0,.6);g.rectangle('fill',(w-width)/2,44,width,26,4)
 if own then g.setColor(.55,.95,.6) else g.setColor(1,.5,.4) end
 g.printf(text,0,49,w,'center')
end
return H
