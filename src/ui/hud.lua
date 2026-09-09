local C=require('src.content')
local Camera=require('src.ui.camera')
local Actions=require('src.ui.actions')
local H={}
local function text(value,x,y,w) love.graphics.setColor(.83,.86,.81);love.graphics.printf(value,x,y,w or 180) end
local function bar(x,y,w,value,max)
 local g=love.graphics;g.setColor(.04,.07,.08);g.rectangle('fill',x,y,w,6);g.setColor(.42,.76,.55);g.rectangle('fill',x,y,w*math.max(0,math.min(1,value/math.max(1,max))),6)
end
function H.draw(app)
 local g=love.graphics;local s=app.settings.scale/100;local width,height=g.getDimensions();local w,h=width/s,height/s;local y=h-180
 local actions=Actions.list(app)
 g.push('all');g.scale(s);g.setFont(app.fonts.small);app.widgets:begin(s);app.widgets.context=app.overlay or 'match';app.widgets.notice=app.uiNotice;app.widgets.clock=app.clock
 g.setColor(.065,.09,.11,.98);g.rectangle('fill',0,0,w,40);g.rectangle('fill',0,y,w,180)
 g.setColor(.48,.4,.25);g.line(0,40,w,40);g.line(0,y,w,y)
 text('LoveRTS',16,13);local p=app.view.player
 for _,r in ipairs({{key='gold',label='Gold',x=135},{key='lumber',label='Lumber',x=270}}) do
  local flash=app.costFlash and app.clock-app.costFlash.time<.9 and app.costFlash.keys[r.key]
  g.setColor(flash and 1 or .83,flash and .38 or .86,flash and .32 or .81);g.print(r.label..'  '..p.resources[r.key],r.x,13)
 end
 text('Food  '..require('src.sim').population(app.world,app.player)..' / '..C.rules.population..'   Units '..require('src.sim').unitCount(app.world,app.player),430,13,300)
 text(string.format('%02d:%02d',math.floor(app.world.tick/1200),math.floor(app.world.tick/20)%60),w-220,13,100)
 app.widgets:button('menu','Menu',w-98,6,86,28,function() app.overlay='pause' end)
 require('src.ui.minimap').draw(app,{x=10,y=y+10,w=190,h=160})
 local hero=app:entity(p.hero);local hx=214
 if hero then
  app.widgets:button('hero',C.units[hero.kind].label..' [F1]',hx+42,y+12,103,42,function() app.selected={hero.id};Actions.context(app);app.audio:play('select');Camera.center(app,hero.x,hero.y) end)
  require('src.ui.icons').portrait(hero.kind,hx,y+12)
  text(hero.hp..' / '..hero.maxHp..' HP',hx,y+59,145);bar(hx,y+77,145,hero.hp,hero.maxHp)
  text('XP '..hero.xp..'  |  Stance '..hero.stance,hx,y+87,150)
  app.widgets:button('hero-stance','Toggle stance',hx,y+108,145,25,function() app:command('toggle',hero.id) end,not hero.alive and 'Hero is dead' or nil)
  local milestone
  for i,t in ipairs(C.rules.xpThresholds) do if hero.xp>=t and not hero.upgrades[i] then milestone=i;break end end
  if milestone and hero.alive then app.widgets:button('upgrade','Upgrade available',hx,y+140,145,28,function() Actions.openAbilities(app);app.audio:play('menu') end)
  elseif not hero.alive then app.widgets:button('revive',hero.reviveRemaining and ('Reviving '..math.ceil(hero.reviveRemaining/20)..'s') or ('Revive: '..require('src.sim').revival(C,hero)..' gold'),hx,y+140,145,28,function() app:command('revive',hero.id) end,hero.reviveRemaining and 'Revival in progress' or p.resources.gold<require('src.sim').revival(C,hero) and 'Insufficient gold' or nil) end
 end
 local sx,sw=375,math.max(140,w-375-330);local e=app:entity(app.selected[1])
 text(#app.selected..' selected',sx,y+12,sw)
 local groups=require('src.ui.selection').groups(app)
 for i,group in ipairs(groups) do local col=(i-1)%3;local row=math.floor((i-1)/3)
  app.widgets:button('group-'..group.kind,(C.units[group.kind] or C.buildings[group.kind]).label..' x'..#group.ids,sx+col*(sw/3),y+35+row*30,sw/3-4,26,function() app.selected=group.ids end)
 end
 if e then
  text(e.hp..'/'..e.maxHp..' HP  |  '..(e.blockedReason or e.order.kind)..'  |  '..#(e.orders or {})..' queued',sx,y+104,sw)
  if e.queue then
   for i,q in ipairs(e.queue) do app.widgets:button('production-'..i,C.units[q.kind].label..' '..math.ceil(q.remaining/20)..'s  x',sx+(i-1)%3*(sw/3),y+127+math.floor((i-1)/3)*24,sw/3-4,22,function() app:command('cancel',e.id,{index=i}) end,nil,'Cancel: unstarted units refund 100%; training units refund 50%.') end
  elseif #app.selected==1 then local d=C.units[e.kind];if d then text('Damage '..(d.damage or 0)..'  Range '..string.format('%.1f',d.range/256)..' cells',sx,y+132,sw) end end
 end
 local title=app.cardPage=='build' and 'BUILD STRUCTURES' or app.cardPage=='abilities' and 'HERO ABILITIES' or 'COMMANDS'
 text(title,w-320,y+6,310)
 g.setFont(app.fonts.card)
 for i,a in ipairs(actions) do
  local slot=a.slot or i;local col=(slot-1)%3;local row=math.floor((slot-1)/3)
  app.widgets:button(a.id,a.label,w-320+col*103,y+24+row*49,98,46,function() Actions.activate(app,a) end,a.reason,a.tip,a.id,a)
 end
 g.setFont(app.fonts.small)
 if #actions==0 then text(#app.selected>1 and 'Select a unit group or one building.' or 'Select units to see commands.',w-315,y+38,290) end
 local pending=0;for _ in pairs(app.pending or {}) do pending=pending+1 end
 if app.uiNotice and app.uiNotice.kind=='rejected' and app.clock-app.uiNotice.time<2 then g.setColor(1,.4,.32);g.rectangle('fill',8,46,3,19) end
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
 if app.debugOrders then require('src.ui.order_debug').draw(app,w,h) end
 if app.overlay then require('src.ui.screens').overlay(app,w,h) end
 app.widgets:tooltip(w,h);g.pop()
end
return H
