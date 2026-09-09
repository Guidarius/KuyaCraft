local C=require('src.content')
local S={}
function S.settings(app,w,h,back)
 local g=love.graphics;local x=w/2-240;local y=h/2-210
 g.setColor(.065,.09,.11);g.rectangle('fill',x-20,y-40,520,494,8);g.setColor(.95,.88,.65);g.print('Settings',x,y-24)
 for i,key in ipairs({'scale','master','ui','effects','ambience'}) do local yy=y+i*35
  g.setColor(.85,.87,.82);g.print(key..': '..app.settings[key]..'%',x,yy)
  for _,delta in ipairs({-5,5}) do app.widgets:button(key..delta,delta<0 and '-' or '+',x+250+(delta>0 and 55 or 0),yy-5,45,28,function() app.settings[key]=math.max(key=='scale' and 80 or 0,math.min(key=='scale' and 125 or 100,app.settings[key]+delta));require('src.ui.settings').save(app.settings) end) end
 end
 app.widgets:button('edges','Edge scroll: '..(app.settings.edgeScroll and 'On' or 'Off'),x,y+215,200,28,function() app.settings.edgeScroll=not app.settings.edgeScroll;require('src.ui.settings').save(app.settings) end)
 for i,key in ipairs({'attack','stop','hold','hero','alert','build','tower'}) do
  app.widgets:button('bind-'..key,key..': '..app.settings.bindings[key],x+((i-1)%3)*155,y+255+math.floor((i-1)/3)*34,148,28,function() app.rebind=key end,nil,'Click, then press a key. Numbers, Q/W/E/R, F3 and F5 are reserved.')
 end
 if app.rebind then g.setColor(1,.8,.4);g.print('Press a key for '..app.rebind..' (Escape cancels)',x,y+355) end
 app.widgets:button('back','Back',x,y+395,460,30,back)
end
function S.overlay(app,w,h)
 local g=love.graphics;g.setColor(0,0,0,.7);g.rectangle('fill',0,0,w,h)
 -- Discard underlying hit targets while a modal panel owns input.
 app.widgets.items={}
 if app.overlay=='settings' then return S.settings(app,w,h,function() app.overlay='pause' end) end
 local x,y=w/2-220,h/2-170;g.setColor(.07,.1,.12);g.rectangle('fill',x-20,y-25,480,355,6)
 if app.overlay=='upgrade' then
  local hero=app:entity(app.view.player.hero);local milestone=app.upgradeMilestone;local faction=C.factions[app.view.player.faction]
  g.setColor(.94,.85,.6);g.print('Choose a permanent hero upgrade',x,y)
  for i=1,2 do
   local xx=x+(i-1)*225
   app.widgets:button('choice-'..i,faction.upgrades[milestone][i],xx,y+40,215,45,function() app.upgradeChoice=i end)
   g.setColor(.84,.88,.82);g.printf(require('src.ui.actions').upgrades[app.view.player.faction][milestone][i],xx,y+100,210)
   if app.upgradeChoice==i then g.setColor(.85,.75,.35);g.rectangle('line',xx-2,y+38,219,170) end
  end
  app.widgets:button('commit','Choose Upgrade',x,y+235,440,34,function() app:command('upgrade',hero.id,{milestone=milestone,choice=app.upgradeChoice});app.overlay=nil end,not app.upgradeChoice and 'Preview an option first' or nil)
  app.widgets:button('close','Decide later',x,y+279,440,28,function() app.overlay=nil end)
 else
  g.setColor(.95,.86,.6);g.print(app.network and 'Match continues' or 'Match paused',x,y)
  for i,item in ipairs({{'Resume',function() app.overlay=nil end},{'Settings',function() app.overlay='settings' end},{'Save Replay',function() app:save() end},{'Leave Match',function() app.leaveRequested=true end}}) do
   app.widgets:button('pause-'..i,item[1],x,y+35+i*51,440,40,item[2])
  end
 end
end
return S
