local T={}
function T.run(app)
 app.noAutoSave=true -- This rendered fixture deliberately injects XP to exercise upgrades.
 local Camera=require('src.ui.camera');local Sim=require('src.sim')
 local function click(id)
  app:draw()
  for _,b in ipairs(app.widgets.items) do if b.id==id then local s=app.widgets.scale;app:mousepressed((b.x+b.w/2)*s,(b.y+b.h/2)*s,1);return end end
  error('missing button '..id)
 end
 for _,scale in ipairs({80,100,125}) do
  app.settings.scale=scale;Camera.clamp(app);app:draw();local field=Camera.rect(app);assert(math.abs(field.h/(Camera.cellY*app.camera.zoom)-24/app.camera.userZoom)<.01,'camera field changed with UI scale')
  local count=#app.queue;click('menu');assert(app.overlay=='pause' and #app.queue==count and not app.drag,'HUD input leak')
  local tick=app.world.tick;app:update(3);assert(app.world.tick==tick and app.accumulator==0,'paused catchup')
  app:keypressed('escape');assert(not app.overlay)
  app:draw();local r=app.minimap;local s=scale/100
  app:mousepressed((r.x+r.w/2)*s,(r.y+r.h/2)*s,1);assert(app.capture=='minimap' and not app.drag)
  app:mousemoved(-100,-100,-10,-10);app:mousereleased(-100,-100,1);assert(not app.capture)
  for _,p in ipairs({{0,0},{1234,2345},{10000,10000}}) do local sx,sy=app:screen(p[1],p[2]);local x,y=app:position(sx,sy);assert(math.abs(x-p[1])<=1 and math.abs(y-p[2])<=1) end
 end
 app.settings.scale=100;app:keypressed('f1');assert(app.selected[1]==app.view.player.hero)
 local worker;for _,e in ipairs(app.view.entities) do if e.kind=='worker' and e.owner==1 then worker=e;break end end
 app.selected={worker.id};Camera.center(app,worker.x,worker.y);app:draw()
 app:keypressed('a');local x,y=app:screen(10*256+128,8*256+128);app:mousepressed(x,y,1);app:update(.05)
 assert(app.world.entities[worker.id].order.kind=='attack_move','A left click')
 app:keypressed('h');app:update(.05);assert(app.world.entities[worker.id].order.kind=='hold')
 app:keypressed('f3');app:draw();assert(app.debugOrders);app:keypressed('f3')
 app:keypressed('b');assert(app.building=='barracks');app:keypressed('escape');assert(not app.building and not app.overlay)
 app:keypressed('f1');local hero=app.world.entities[app.view.player.hero];local stance=hero.stance;click('hero-stance');app:update(.05);assert(hero.stance~=stance)
 hero.xp=400;app.view=Sim.view(app.world,1);app.observation:update(app.view)
 click('upgrade');click('choice-1');assert(not hero.upgrades[1],'preview committed early');click('commit');app:update(.05);assert(hero.upgrades[1]==1)
 app.selected={app.view.player.hq};click('recruit-worker');app:update(.05);assert(#app.world.entities[app.view.player.hq].queue==1)
 local before=#app.queue;app:keypressed('1');assert(#app.queue==before,'number recruited')
 local state=Sim.serializeCanonical(app.world);for _=1,4 do app:draw() end;assert(Sim.serializeCanonical(app.world)==state,'render mutated sim')
 app.overlay='pause';app.network={poll=function() end,ready=false,status='Lobby'}
 local polls=0;app.network.poll=function() polls=polls+1 end;app:update(.1);assert(polls==1,'multiplayer menu blocked network');app.network=nil;app.overlay=nil
 require('tests.control_input').run()
 local clean=require('src.app').create({map='open_fields'})
 for _=1,120 do clean:update(.05) end
 clean:save('artifacts/ui-proof.replay')
 local replay=require('src.app').create({replay='artifacts/ui-proof.replay'});replay:seek(120)
 assert(Sim.serializeCanonical(replay.world)==Sim.serializeCanonical(clean.world),'seek continuation differs')
 assert(#replay.feedback.items==0 and #replay.alerts.items==0,'seek leaked transient feedback')
 replay:seek(60,2);assert(replay.player==2);replay:close();clean:close()
 local netApp=require('src.app').create({map='open_fields'});netApp.player=2
 netApp.network={ready=true,config=netApp.world.config,map=netApp.world.map,submitted={},poll=function() end,submit=function() end,close=function() end}
 netApp:update(0);assert(not netApp.observation.memory[netApp.world.players[1].hq],'network start leaked player 1 observations');netApp.network=nil;netApp:close()
 local shell=require('src.ui.shell').create({});local g=love.graphics;local width,height=g.getDimensions()
 local canvas=g.newCanvas(width,height)
 local function capture(name,draw)
  g.push('all');g.setCanvas(canvas);g.origin();g.clear();draw();g.pop()
  local data=canvas:newImageData();local f=assert(io.open('artifacts/ui-'..name..'-'..width..'.png','wb'));f:write(data:encode('png'):getString());f:close()
 end
 for _,screen in ipairs({'main','skirmish','multiplayer','settings','replays'}) do shell.screen=screen;if screen=='replays' then shell:replays();local found=false;for _,item in ipairs(shell.replayFiles) do if item.name=='ui-proof.replay' then found=true end end;assert(found,'saved replay absent from browser') end;capture(screen,function() shell:draw() end) end
 shell.screen='multiplayer';shell.focus='address';local old=shell.address;shell:keypressed('a');assert(shell.address==old and not shell.match,'text focus leaked');shell:textinput('1');assert(shell.address==old..'1');shell.focus=nil
 app.overlay='upgrade';app.upgradeMilestone=2;app.upgradeChoice=1;capture('upgrade',function() app:draw() end)
 app.overlay=nil;app.selected={app.view.player.hero};Camera.center(app,hero.x,hero.y);capture('match',function() app:draw() end)
 canvas:release();shell:close();app:draw()
 print('PASS rendered UI: scales, capture, minimap drag, transforms, pause, commands, upgrades, recruitment, replay seek')
end
return T
