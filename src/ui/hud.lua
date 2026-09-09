local Sim=require('src.sim')
local Minimap=require('src.ui.minimap')
local Selection=require('src.ui.selection')
local Icons=require('src.ui.icons')
local Actions=require('src.ui.actions')
local Input=require('src.ui.input')
local C=require('src.content')
local Camera=require('src.ui.camera')
local H={}
local function text(value,x,y,w) love.graphics.setColor(.83,.86,.81);love.graphics.printf(value,x,y,w or 180) end
local function bar(x,y,w,value,max)
 local g=love.graphics;g.setColor(.04,.07,.08);g.rectangle('fill',x,y,w,6);g.setColor(.42,.76,.55);g.rectangle('fill',x,y,w*math.max(0,math.min(1,value/math.max(1,max))),6)
end
function H.draw(app)
 local g=love.graphics;local s=app.settings.scale/100;local width,height=g.getDimensions();local w,h=width/s,height/s;local y=h-180
 g.push('all');g.scale(s);g.setFont(app.fonts.small);app.widgets:begin(s);app.widgets.context=app.overlay or 'match'
 g.setColor(.065,.09,.11,.98);g.rectangle('fill',0,0,w,40);g.rectangle('fill',0,y,w,180)
 g.setColor(.48,.4,.25);g.line(0,40,w,40);g.line(0,y,w,y)
 text('LoveRTS',16,13);local p=app.view.player
 text('Gold  '..p.resources.gold,135,13);text('Lumber  '..p.resources.lumber,270,13)
 text('Food  '..Sim.population(app.world,app.player)..' / '..C.rules.population..'   Units '..Sim.unitCount(app.world,app.player),430,13,300)
 text(string.format('%02d:%02d',math.floor(app.world.tick/1200),math.floor(app.world.tick/20)%60),w-220,13,100)
 app.widgets:button('menu','Menu',w-98,6,86,28,function() app.overlay='pause' end)
 Minimap.draw(app,{x=10,y=y+10,w=190,h=160})
 local hero=app:entity(p.hero);local hx=214
 if hero then
  app.widgets:button('hero',C.units[hero.kind].label..' [F1]',hx+42,y+12,103,42,function() app.selected={hero.id};Camera.center(app,hero.x,hero.y) end)
  Icons.portrait(hero.kind,hx,y+12)
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
  app.widgets:button('hero-stance','Stance '..hero.stance..': toggle',hx,y+111,145,24,function() app:command('toggle',hero.id) end,not hero.alive and 'Hero is dead' or nil)
  local milestone
  for i,t in ipairs(C.rules.xpThresholds) do if hero.xp>=t and not hero.upgrades[i] then milestone=i;break end end
  if milestone and hero.alive then app.widgets:button('upgrade','Upgrade available',hx,y+140,145,28,function() app.overlay='upgrade';app.upgradeMilestone=milestone;app.upgradeChoice=nil end)
  elseif not hero.alive then app.widgets:button('revive',hero.reviveRemaining and ('Reviving '..math.ceil(hero.reviveRemaining/20)..'s') or ('Revive: '..Sim.revival(C,hero)..' gold'),hx,y+140,145,28,function() app:command('revive',hero.id) end,hero.reviveRemaining and 'Revival in progress' or p.resources.gold<Sim.revival(C,hero) and 'Insufficient gold' or nil) end
 end
 -- Idle workers are the most common thing a player loses track of, so the count is
 -- always on screen and one click takes you to the next one.
 local idle=Input.idleWorkers(app)
 app.widgets:button('idle-worker','Idle: '..#idle..' ['..(app.settings.bindings.idle or 'f9'):upper()..']',745,6,150,28,
  function() Input.selectIdleWorker(app) end,#idle==0 and 'No idle workers' or nil,
  'Select and centre on the next worker with no order and nothing to deliver.')
 local sx,sw=375,math.max(140,w-375-330);local e=app:entity(app.selected[1])
 text(#app.selected..' selected',sx,y+12,sw)
 local groups=Selection.groups(app)
 for i,group in ipairs(groups) do local col=(i-1)%3;local row=math.floor((i-1)/3)
  app.widgets:button('group-'..group.kind,(C.units[group.kind] or C.buildings[group.kind]).label..' x'..#group.ids,sx+col*(sw/3),y+35+row*30,sw/3-4,26,function() app.selected=group.ids end)
 end
 -- One tile per selected unit with its own health, because a type-count row cannot show
 -- that three of twelve shieldguards are nearly dead. Click selects that one unit;
 -- shift-click drops it from the selection, which is what the tiles are really for.
 if #app.selected>1 then H.unitTiles(app,sx,y+35+math.ceil(#groups/3)*30,sw) end
 if e then
  text(e.hp..'/'..e.maxHp..' HP  |  '..(e.blockedReason or e.order.kind)..'  |  '..#(e.orders or {})..' queued',sx,y+104,sw)
  if e.queue then
   for i,q in ipairs(e.queue) do app.widgets:button('production-'..i,C.units[q.kind].label..' '..math.ceil(q.remaining/20)..'s  x',sx+(i-1)%3*(sw/3),y+127+math.floor((i-1)/3)*24,sw/3-4,22,function() app:command('cancel',e.id,{index=i}) end,nil,'Cancel: unstarted units refund 100%; training units refund 50%.') end
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
 for i,a in ipairs(Actions.list(app)) do
  local col=(i-1)%3;local row=math.floor((i-1)/3)
  app.widgets:button(a.id,a.label..(a.key~='' and (' ['..a.key:upper()..']') or ''),w-320+col*103,y+14+row*49,98,44,a.run,a.reason,a.tip,a.id)
 end
 local pending=0;for _ in pairs(app.pending or {}) do pending=pending+1 end
 text((pending>0 and (pending..' pending | ') or '')..(app.message or ''),16,48,w-32)
 for i,a in ipairs(app.alerts.items) do app.widgets:button('alert-'..i,a.text..(a.count and (' x'..a.count) or ''),16,72+(i-1)*31,285,27,function() if a.x then Camera.center(app,a.x,a.y) end end) end
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
 app.widgets:tooltip(w,h);g.pop()
end
H.TILES_PER_PAGE=12
-- A page of up to twelve per-unit tiles, each with its own health. Paging keeps the
-- dock a fixed size with any selection size; Tab still cycles subgroups as before.
function H.unitTiles(app,x,y,width)
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
    end,nil,(C.units[e.kind] or C.buildings[e.kind] or {}).label..'  '..e.hp..' / '..e.maxHp..' HP\nClick selects only this unit; shift-click removes it.')
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
return H
