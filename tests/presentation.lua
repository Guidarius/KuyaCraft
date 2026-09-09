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
 T.gamefeel(app)
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
-- WC3-style control and feedback that only exists in the presentation layer. Every check
-- here must be able to fail loudly: these are the features a player notices missing.
function T.gamefeel(app)
 local Camera=require('src.ui.camera');local Input=require('src.ui.input');local Settings=require('src.ui.settings')
 local Selection=require('src.ui.selection')
 app.overlay=nil;app.building=nil;app.targetMode=nil

 -- Idle workers: counted, selected, and cycled rather than always returning the first.
 local idle=Input.idleWorkers(app)
 assert(#idle>0,'fixture has no idle workers to exercise the control')
 for _,id in ipairs(idle) do
  local e=app:entity(id)
  assert(e.kind=='worker' and e.order.kind=='stop' and (e.cargo or 0)==0,'a busy worker was reported idle')
 end
 assert(Input.selectIdleWorker(app),'idle worker selection failed')
 local first=app.selected[1]
 assert(#app.selected==1 and first==idle[1],'idle worker selection picked the wrong unit')
 if #idle>1 then
  Input.selectIdleWorker(app)
  assert(app.selected[1]~=first,'repeated idle-worker presses must cycle')
 end
 -- A worker carrying cargo is on a delivery trip and is not offered even while stopped.
 local carrier=app.world.entities[idle[1]];local restore=carrier.cargo
 carrier.cargo=5;app.view=require('src.sim').view(app.world,app.player)
 for _,id in ipairs(Input.idleWorkers(app)) do assert(id~=idle[1],'a loaded worker was offered as idle') end
 carrier.cargo=restore;app.view=require('src.sim').view(app.world,app.player)

 -- Select-all-army takes combat units and excludes workers and buildings.
 app:keypressed('f2')
 assert(#app.selected>0,'F2 selected nothing')
 for _,id in ipairs(app.selected) do
  local e=app:entity(id)
  assert(e.category=='unit' and not require('src.content').units[e.kind].worker,'F2 selected a non-combat unit')
 end

 -- Camera bookmarks store ground, not a camera offset, so they survive a zoom change.
 Camera.center(app,12*256,9*256)
 local markX,markY=app:position(Camera.rect(app).w/2,Camera.rect(app).y+Camera.rect(app).h/2)
 assert(Camera.setBookmark(app,5))
 Camera.center(app,30*256,20*256)
 assert(Camera.recallBookmark(app,5),'bookmark recall failed')
 for _=1,40 do Camera.update(app,1/60) end
 local backX,backY=app:position(Camera.rect(app).w/2,Camera.rect(app).y+Camera.rect(app).h/2)
 assert(math.abs(backX-markX)<=512 and math.abs(backY-markY)<=512,'bookmark did not return to its ground')
 assert(not Camera.recallBookmark(app,7),'an unset bookmark must report failure')
 -- The ease has to actually take time, or it is just a cut with extra steps.
 Camera.center(app,12*256,9*256);Camera.glide(app,60*256,40*256)
 Camera.update(app,1/60)
 assert(app.cameraGlide,'glide finished within a single frame')
 for _=1,40 do Camera.update(app,1/60) end
 assert(not app.cameraGlide,'glide never finished')

 -- Game speed scales wall-clock pacing only; it must never change the tick rate.
 local base=app.settings.gameSpeed
 app.settings.gameSpeed=2;app.accumulator=0
 local from=app.world.tick;app:update(0.2)
 local normal=app.world.tick-from
 app.settings.gameSpeed=3;app.accumulator=0
 from=app.world.tick;app:update(0.2)
 local faster=app.world.tick-from
 assert(faster>normal,'faster speed did not advance more ticks per second: '..faster..' vs '..normal)
 app.settings.gameSpeed=1;app.accumulator=0
 from=app.world.tick;app:update(0.2)
 assert(app.world.tick-from<normal,'slower speed did not advance fewer ticks')
 app.settings.gameSpeed=base;app.accumulator=0
 assert(Settings.SPEED_SCALE[2]==1,'normal speed must be exactly 1x')

 -- Per-unit tiles: click selects one, shift-click removes it.
 local army=Input.army(app)
 if #army>=2 then
  app.selected={army[1],army[2]}
  app:draw()
  local tile
  for _,b in ipairs(app.widgets.items) do if b.id=='tile-'..army[2] then tile=b end end
  assert(tile,'no per-unit tile for a multi-unit selection')
  tile.action()
  assert(#app.selected==1 and app.selected[1]==army[2],'tile click did not isolate that unit')
  app.selected={army[1],army[2]}
  Selection.toggle(app.selected,army[2])
  assert(#app.selected==1 and app.selected[1]==army[1],'shift-click did not drop the unit')
 end

 -- Income text comes from the simulation's delivered event, so it reports the exact
 -- amount at the worker that delivered it.
 app.feedback:reset()
 local hauler=Input.idleWorkers(app)[1] or app.selected[1]
 app:announceDelivery({kind='delivered',entity=hauler,amount=25,resource='gold',owner=app.player})
 assert(#app.feedback.texts==1,'delivery text not raised')
 assert(app.feedback.texts[1].label=='+25 gold','delivery text read '..app.feedback.texts[1].label)
 app.feedback:reset()
 app:announceDelivery({kind='delivered',entity=hauler,owner=app.player})
 assert(#app.feedback.texts==0,'a delivery with no amount raised text')
 -- Match statistics read the simulation's tallies, not observed deaths.
 local built,lost,kills=app:matchStats()
 assert(built>=0 and lost>=0 and kills>=0,'match statistics unavailable')
 assert(lost==(app.view.player.unitsLost or 0),'losses did not come from the simulation')
 assert(kills==(app.view.player.kills or 0),'kills did not come from the simulation')

 -- Health-bar policy is a setting, not a constant.
 for _,mode in ipairs({'always','selected','damaged'}) do
  app.settings.healthBars=mode;app:draw()
 end
 app.settings.healthBars='damaged'
 app.selected={app.view.player.hero};app.perfOverlay=true;app.hotkeyHelp=true;app:draw()
 app.perfOverlay=false;app.hotkeyHelp=false
 app.banner={won=true,age=0.2,detail='test'};app:draw();app.banner=nil
 app:draw()
 -- Version 6 orders reach the simulation through the same clicks a player uses.
 local Sim2=require('src.sim')
 app.selected={app.view.player.hq}
 Input.intent(app,11*256+128,11*256+128,nil)
 app:update(.05)
 local base=app.world.entities[app.view.player.hq]
 assert(base.rally and base.rally.x==11 and base.rally.y==11,'right click with a building selected did not set a rally point')
 -- With a unit in the selection the same click is a move, not a rally.
 local mover=Input.army(app)[1] or Input.idleWorkers(app)[1]
 app.selected={mover}
 Input.intent(app,9*256+128,9*256+128,nil)
 app:update(.05)
 assert(app.world.entities[mover].order.kind=='move','a unit selection turned a right click into a rally')
 -- Patrol arms a target mode and then issues a patrol order.
 app:keypressed('p');assert(app.targetMode=='patrol','P did not arm patrol targeting')
 Input.intent(app,14*256+128,9*256+128,nil,'patrol');app.targetMode=nil
 app:update(.05)
 assert(app.world.entities[mover].order.kind=='patrol','patrol order was not issued')
 assert(app.world.entities[mover].order.originX,'patrol order carries no beat origin')
 -- Right-clicking one of your own units falls in behind it.
 local other=Input.army(app)[2]
 if other and other~=mover then
  app.selected={mover}
  Input.intent(app,0,0,app:entity(other))
  app:update(.05)
  assert(app.world.entities[mover].order.kind=='follow','right click on an own unit did not follow')
  assert(app.world.entities[mover].order.target==other)
 end
 app:draw()
 print('PASS gamefeel: idle workers, army select, bookmarks, eased camera, game speed, unit tiles, floating text, overlays, rally, patrol, follow')
end
return T
