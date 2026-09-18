local S={}
local Settings=require('src.ui.settings')
local HEALTH_BAR_LABELS={always='Always',selected='Selected',damaged='Damaged too'}
function S.settings(app,w,h,back)
 local g=love.graphics;local x=w/2-240;local y=h/2-210
 g.setColor(.065,.09,.11);g.rectangle('fill',x-20,y-40,520,580,8);g.setColor(.95,.88,.65);g.print('Settings',x,y-24)
 local function store() Settings.save(app.settings) end
 for i,key in ipairs({'scale','master','ui','effects','ambience'}) do local yy=y+i*35
  g.setColor(.85,.87,.82);g.print(key..': '..app.settings[key]..'%',x,yy)
  for _,delta in ipairs({-5,5}) do app.widgets:button(key..delta,delta<0 and '-' or '+',x+250+(delta>0 and 55 or 0),yy-5,45,28,function() app.settings[key]=math.max(key=='scale' and 80 or 0,math.min(key=='scale' and 125 or 100,app.settings[key]+delta));store() end) end
 end
 -- Two columns of gameplay-presentation options. None of these reach the simulation:
 -- game speed only scales how fast wall-clock time is fed to the fixed 20 Hz tick.
 app.widgets:button('edges','Edge scroll: '..(app.settings.edgeScroll and 'On' or 'Off'),x,y+212,215,28,
  function() app.settings.edgeScroll=not app.settings.edgeScroll;store() end,nil,'Pan the camera when the pointer touches the edge of the world view.')
 app.widgets:button('shake','Screen shake: '..(app.settings.screenShake~=false and 'On' or 'Off'),x+245,y+212,215,28,
  function() app.settings.screenShake=not (app.settings.screenShake~=false);store() end,nil,'A short camera kick when a building is destroyed.')
 app.widgets:button('bars','Health bars: '..(HEALTH_BAR_LABELS[app.settings.healthBars] or 'Damaged too'),x,y+246,215,28,function()
  local order={'damaged','selected','always'}
  local current=app.settings.healthBars or 'damaged'
  for i,mode in ipairs(order) do if mode==current then app.settings.healthBars=order[i%#order+1];break end end
  store()
 end,nil,'Which units carry a health bar. Holding Alt always shows every bar.')
 app.widgets:button('daynight','Day/night tint: '..(app.settings.dayNight and 'On' or 'Off'),x+245,y+246,215,28,
  function() app.settings.dayNight=not app.settings.dayNight;store() end,nil,'A slow cosmetic colour cycle over the world. Purely visual; sight is unaffected.')
 app.widgets:button('smartcast','Smart cast: '..(app.settings.smartCast and 'On' or 'Off'),x+245,y+280,215,28,
  function() app.settings.smartCast=not app.settings.smartCast;store() end,nil,
  'On: an ability key casts at the cursor straight away, and Alt casts it on yourself. Off: the key arms the ability and the next click aims it.')
 local speed=app.settings.gameSpeed or 2
 app.widgets:button('speed','Game speed: '..(Settings.SPEED_LABELS[speed] or 'Normal'),x,y+280,215,28,function()
  app.settings.gameSpeed=speed%#Settings.SPEEDS+1;store()
 end,app.network and 'Network matches always run at 1x' or nil,'Offline pacing only. The tick rate never changes, so replays and checkpoints are identical at every speed.')
 local scroll=app.settings.scrollSpeed or 2
 app.widgets:button('scroll','Scroll speed: '..(Settings.SCROLL_LABELS[scroll] or 'Normal'),x,y+314,215,28,function()
  app.settings.scrollSpeed=scroll%#Settings.SCROLL_SPEEDS+1;store()
 end,nil,'How fast the camera pans with the arrow keys and the screen edge. Panning starts gentle and speeds up while held.')
 app.widgets:button('alertcam','Camera to alerts: '..(app.settings.alertCamera and 'On' or 'Off'),x+245,y+314,215,28,
  function() app.settings.alertCamera=not app.settings.alertCamera;store() end,nil,
  'On: the camera glides to an attack on your hero, headquarters or forces when it is announced. Off: only the alert key moves it.')
 for i,key in ipairs({'attack','stop','hold','hero','alert','build','tower','idle'}) do
  app.widgets:button('bind-'..key,key..': '..app.settings.bindings[key],x+((i-1)%3)*155,y+356+math.floor((i-1)/3)*34,148,28,function() app.rebind=key end,nil,'Click, then press a key. Numbers, Q/W/E/R/U/Y, Tab, Escape and F2-F8/F10 are reserved.')
 end
 if app.rebind then g.setColor(1,.8,.4);g.print('Press a key for '..app.rebind..' (Escape cancels)',x,y+462) end
 app.widgets:button('back','Back',x,y+494,460,30,back)
end
function S.overlay(app,w,h)
 local g=love.graphics;g.setColor(0,0,0,.7);g.rectangle('fill',0,0,w,h)
 -- Discard underlying hit targets while a modal panel owns input.
 app.widgets.items={};app.widgets:clearHover()
 if app.overlay=='settings' then return S.settings(app,w,h,function() app.overlay='pause' end) end
 local x,y=w/2-220,h/2-170;g.setColor(.07,.1,.12);g.rectangle('fill',x-20,y-25,480,355,6)
 if app.overlay=='upgrade' then
  local hero=app:entity(app.view.player.hero);local milestone=app.upgradeMilestone;local faction=app.content.factions[app.view.player.faction]
  local Actions=require('src.ui.actions');local reason=app.playback and 'Replay is read-only' or Actions.upgradeReason(app,hero,milestone)
  g.setColor(.94,.85,.6);g.print('Choose a permanent hero upgrade',x,y)
  for i=1,2 do
   local xx=x+(i-1)*225
   app.widgets:button('choice-'..i,faction.upgrades[milestone][i],xx,y+40,215,45,function() app.upgradeChoice=i;app.audio:play('menu') end,reason)
   g.setColor(.84,.88,.82);g.printf(((require('src.ui.actions').upgrades[app.view.player.faction] or {})[milestone] or {})[i] or '',xx,y+100,210)
   if app.upgradeChoice==i then g.setColor(.85,.75,.35);g.rectangle('line',xx-2,y+38,219,170) end
  end
  app.widgets:button('commit','Choose Upgrade',x,y+235,440,34,function()
   local current=Actions.upgradeReason(app,app:entity(hero.id),milestone)
   if current then require('src.ui.command_feedback').notify(app,'rejected',current,'commit');return end
   app.activeAction='ability-'..milestone..'-'..app.upgradeChoice;app:command('upgrade',hero.id,{milestone=milestone,choice=app.upgradeChoice});app.activeAction=nil;app.overlay=nil
  end,reason or not app.upgradeChoice and 'Preview an option first' or nil)
  app.widgets:button('close','Decide later',x,y+279,440,28,function() app.overlay=nil end)
 else
  g.setColor(.95,.86,.6);g.print(app.network and 'Match continues' or 'Match paused',x,y)
  for i,item in ipairs({{'Resume',function() app.overlay=nil end},{'Settings',function() app.overlay='settings' end},{'Save Replay',function() app:save() end},{'Leave Match',function() app.leaveRequested=true end}}) do
   app.widgets:button('pause-'..i,item[1],x,y+35+i*51,440,40,item[2])
  end
 end
end
return S
