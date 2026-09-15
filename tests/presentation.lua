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
 app:keypressed('b');assert(app.cardPage=='build' and not app.building);app:keypressed('q');assert(app.building=='barracks');app:keypressed('escape');assert(not app.building and not app.overlay);app:keypressed('escape');assert(not app.cardPage)
 app:keypressed('f1');local hero=app.world.entities[app.view.player.hero];local stance=hero.stance;click('hero-stance');app:update(.05);assert(hero.stance~=stance)
 hero.xp=400;app.view=Sim.view(app.world,1);app.observation:update(app.view)
 click('upgrade');assert(app.cardPage=='abilities');click('ability-1-1');click('choice-1');assert(not hero.upgrades[1],'preview committed early');click('commit');app:update(.05);assert(hero.upgrades[1]==1)
 app.selected={app.view.player.hq};click('recruit-worker');app:update(.05);assert(#app.world.entities[app.view.player.hq].queue==1)
 local before=#app.queue;app:keypressed('1');assert(#app.queue==before,'number recruited')
 local state=Sim.serializeCanonical(app.world);for _=1,4 do app:draw() end;assert(Sim.serializeCanonical(app.world)==state,'render mutated sim')
 app.overlay='pause';app.network={poll=function() end,ready=false,status='Lobby'}
 local polls=0;app.network.poll=function() polls=polls+1 end;app:update(.1);assert(polls==1,'multiplayer menu blocked network');app.network=nil;app.overlay=nil
 require('tests.command_card').rendered(app,click)
 T.gamefeel(app)
 require('tests.control_input').run()
 -- Pinned to normal pacing. This compares a live match against a replay seek tick for
 -- tick, and App.create otherwise picks up whatever game speed is saved on this machine.
 local clean=require('src.app').create({map='open_fields'})
 clean.settings.gameSpeed=2
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
 -- Control points are only drawn on a map that has them, which no fixture above uses. One
 -- point owned with the other half captured by the enemy, then both held: ground rings,
 -- capture fill, minimap rings and the public countdown banner, each actually drawn.
 local marches=require('src.app').create({map='twin_marches'});marches.noAutoSave=true
 local points=marches.world.control.points
 points[1].owner=1;points[2].capturer=2;points[2].progress=100
 marches.view=Sim.view(marches.world,1);Camera.center(marches,points[1].x,points[1].y)
 capture('control-contest',function() marches:draw() end)
 points[2].owner=1;points[2].capturer=0;points[2].progress=0;Sim.step(marches.world,{})
 marches.view=Sim.view(marches.world,1);assert(marches.view.control.holder==1,'a hold is not visible in the view')
 local controlState=Sim.serializeCanonical(marches.world)
 capture('control-hold',function() marches:draw() end)
 assert(Sim.serializeCanonical(marches.world)==controlState,'drawing control points mutated the simulation')
 marches:close()
 -- The inspection card, captured so it can be looked at: the enemy hero brought into
 -- sight and selected. Pausing overlays stop ticks, so the overlay is lifted meanwhile.
 do
  local overlay=app.overlay;app.overlay=nil
  local own=app.world.entities[app.view.player.hero];local foe=app.world.entities[app.world.players[2].hero]
  local homeX,homeY=foe.x,foe.y;foe.x=own.x+768;foe.y=own.y;app:update(.05)
  require('src.ui.selection').apply(app,{foe.id});Camera.center(app,foe.x,foe.y)
  assert(require('src.ui.selection').inspecting(app),'the enemy hero could not be inspected for the capture')
  capture('inspect',function() app:draw() end)
  foe.x,foe.y=homeX,homeY;app:update(.05);app.overlay=overlay
 end
 app.overlay=nil;app.selected={app.view.player.hero};Camera.center(app,hero.x,hero.y);capture('match',function() app:draw() end)
 require('tests.command_card').captures(app,capture)
 canvas:release();shell:close();app:draw()
 print('PASS rendered UI: scales, capture, minimap drag, transforms, pause, commands, upgrades, recruitment, replay seek')
end
-- Every gameplay-presentation setting must be reachable from the settings screen and
-- must persist. These four existed and worked before they had any control at all, which
-- meant a player could not change them and the README described options that were not
-- there. Run through T.gamefeel, which restores the stored settings afterwards.
function T.settingsControls(app,Sim,Settings)
 local function control(id)
  app.overlay='settings';app:draw()
  for _,b in ipairs(app.widgets.items) do if b.id==id then return b end end
  error('settings screen has no control '..id)
 end
 local bars={}
 for _=1,4 do local b=control('bars');bars[#bars+1]=app.settings.healthBars;b.action() end
 assert(bars[1]~=bars[2] and bars[2]~=bars[3],'health bar control did not cycle')
 assert(bars[1]==bars[4],'health bar control did not return to its first value')
 local shakeBefore=app.settings.screenShake
 control('shake').action();assert(app.settings.screenShake~=shakeBefore,'screen shake did not toggle')
 control('shake').action();assert(app.settings.screenShake==shakeBefore,'screen shake did not toggle back')
 local nightBefore=app.settings.dayNight
 control('daynight').action();assert(app.settings.dayNight~=nightBefore,'day/night did not toggle')
 -- The tint is cosmetic, so drawing with it on must not disturb the simulation.
 app.overlay=nil
 local guard=Sim.serializeCanonical(app.world);app:draw();app:draw()
 assert(Sim.serializeCanonical(app.world)==guard,'the day/night tint mutated the simulation')
 control('daynight').action();assert(app.settings.dayNight==nightBefore)
 local speeds={}
 for _=1,#Settings.SPEEDS+1 do local b=control('speed');speeds[#speeds+1]=app.settings.gameSpeed;b.action() end
 assert(speeds[1]==speeds[#speeds],'game speed did not cycle back round')
 for _,speed in ipairs(speeds) do assert(Settings.SPEED_SCALE[speed],'game speed reached an invalid value: '..tostring(speed)) end
 -- Every binding the game reads must be rebindable, including the ones added later.
 for _,key in ipairs({'attack','stop','hold','hero','alert','build','tower','idle'}) do
  assert(control('bind-'..key),'binding '..key..' has no control')
 end
 -- And a setting has to survive the round trip through storage, not just the button.
 app.settings.healthBars='always';Settings.save(app.settings)
 assert(Settings.load().healthBars=='always','settings did not survive a save and load')
end
-- WC3-style control and feedback that only exists in the presentation layer. Every check
-- here must be able to fail loudly: these are the features a player notices missing.
function T.gamefeel(app)
 local Camera=require('src.ui.camera');local Input=require('src.ui.input');local Settings=require('src.ui.settings')
 local Selection=require('src.ui.selection')
 app.overlay=nil;app.building=nil;app.targeting=nil

 -- Idle workers: counted, selected, and cycled rather than always returning the first.
 local idle=Input.idleWorkers(app)
 assert(#idle>0,'fixture has no idle workers to exercise the control')
 for _,id in ipairs(idle) do
  local e=app:entity(id)
  assert(e.kind=='worker' and e.order.kind=='stop','a busy worker was reported idle')
 end
 assert(Input.selectIdleWorker(app),'idle worker selection failed')
 local first=app.selected[1]
 assert(#app.selected==1 and first==idle[1],'idle worker selection picked the wrong unit')
 if #idle>1 then
  Input.selectIdleWorker(app)
  assert(app.selected[1]~=first,'repeated idle-worker presses must cycle')
 end
 -- A worker on its way to a build site holds a 'build' order and is not offered.
 local busy=app.world.entities[idle[1]];local restore=busy.order
 busy.order={kind='build',target=app.view.player.hq};app.view=require('src.sim').view(app.world,app.player)
 for _,id in ipairs(Input.idleWorkers(app)) do assert(id~=idle[1],'a building worker was offered as idle') end
 busy.order=restore;app.view=require('src.sim').view(app.world,app.player)

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
 app:keypressed('p');assert(app.targeting and app.targeting.command=='patrol','P did not arm patrol targeting')
 Input.intent(app,14*256+128,9*256+128,nil,'patrol');app.targeting=nil
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
 T.warcraftControls(app)
 T.abilities(app)
 -- Every gameplay-presentation setting must actually be reachable and must persist.
 -- These existed and worked before they had any control, which meant a player could
 -- not change them and the README described options that were not there.
 -- Driving the real controls writes the real settings file, because that is what the
 -- buttons do. Capture the stored bytes first and put them back afterwards even if a
 -- check fails, so the suite can never alter the settings of whoever ran it -- and, more
 -- importantly, can never leak a changed value into a later test that creates an App.
 local Settings=require('src.ui.settings')
 -- Capture the effective settings rather than the stored bytes: on a machine that has
 -- never saved any, there are no bytes to put back and the test would leave behind the
 -- file it created. Writing these back guarantees a later Settings.load() sees exactly
 -- what it would have seen, whether or not a file existed. Restored even on failure.
 local before=Settings.load()
 local ok,err=pcall(T.settingsControls,app,Sim2,Settings)
 Settings.save(before)
 for key,value in pairs(before) do app.settings[key]=value end
 app.overlay=nil
 if not ok then error(err,0) end
 -- Saving a replay must not be able to take the game down. This runs from love.quit, so
 -- in a packaged build sitting somewhere unwritable a hard failure here would turn
 -- "quit the game" into a crash. An unwritable path has to fall back, not throw.
 local unwritable=require('src.app').create({map='open_fields'})
 unwritable.noAutoSave=true
 for _=1,4 do unwritable:update(.05) end
 local saved=unwritable:save('no-such-directory/nested/match.replay')
 assert(saved,'saving to an unwritable path did not fall back: '..tostring(unwritable.message))
 local fallback=unwritable.message:match('^Replay saved: (.+)$')
 assert(fallback,'fallback save reported no path: '..tostring(unwritable.message))
 local handle=io.open(fallback,'rb');assert(handle,'the fallback path does not exist: '..fallback);handle:close()
 unwritable:close()
 app:draw()
 print('PASS gamefeel: idle workers, army select, bookmarks, eased camera, game speed, unit tiles, floating text, overlays, rally, patrol, follow, replay fallback')
end
-- The control rules a Warcraft 3 player has in their hands before they think about it.
-- Each of these was wrong in a way that no existing test could see, because the suite
-- checked that a command was issued and never checked that it was the right one.
function T.warcraftControls(app)
 local Input=require('src.ui.input')
 local Selection=require('src.ui.selection')
 local Camera=require('src.ui.camera')
 local army=Input.army(app)
 local mover=army[1] or Input.idleWorkers(app)[1]
 -- Attack-move dropped on an enemy is a focused attack on that enemy, not a walk to
 -- the ground under it. Previously the picked target was resolved and then discarded.
 local enemy
 for _,e in ipairs(app.view.entities) do
  if e.alive and e.owner~=app.player and e.owner~=0 and e.category=='unit' then enemy=e;break end
 end
 if enemy then
  app.selected={mover}
  Input.intent(app,enemy.x,enemy.y,enemy,'attack_move')
  app:update(.05)
  local order=app.world.entities[mover].order
  assert(order.kind=='attack','A-click on an enemy issued '..order.kind..' instead of a focused attack')
  assert(order.target==enemy.id,'focused attack targeted the wrong entity')
 end
 -- Attack-move on empty ground stays an attack-move.
 app.selected={mover}
 Input.intent(app,9*256+128,9*256+128,nil,'attack_move')
 app:update(.05)
 assert(app.world.entities[mover].order.kind=='attack_move','A-click on open ground stopped being an attack-move')
 -- Inspection. An enemy, a neutral or a mine can be selected to read and never commanded:
 -- a click on one selects it alone, adding your own unit replaces it, an order goes
 -- nowhere, the card offers no commands, and the selection lets go once it is out of sight.
 do
  local own=app.world.entities[app.view.player.hero]
  local foe=app.world.entities[app.world.players[2].hero]
  local homeX,homeY=foe.x,foe.y
  foe.x=own.x+768;foe.y=own.y;app:update(.05)
  local seen=app:entity(foe.id);assert(seen,'an enemy hero moved into sight is not in the view')
  Camera.center(app,seen.x,seen.y);app:draw()
  local fx,fy=app:screen(seen.x,seen.y);fy=fy-12*app.camera.zoom
  app:mousepressed(fx,fy,1);app:mousereleased(fx,fy,1)
  assert(#app.selected==1 and app.selected[1]==foe.id,'a click on an enemy did not select it alone')
  assert(#require('src.ui.actions').list(app)==0,'an inspected enemy offered commands')
  local queued=#app.queue;Input.intent(app,seen.x+256,seen.y,nil)
  assert(#app.queue==queued,'an order was sent for an enemy unit')
  app:draw()
  Selection.apply(app,{own.id},true)
  assert(#app.selected==1 and app.selected[1]==own.id,'an own unit was mixed into an inspected enemy')
  for _,e in ipairs(app.view.entities) do
   if e.category=='node' and e.alive then Selection.apply(app,{e.id});assert(Selection.inspecting(app)==e,'a mine could not be inspected');app:draw();break end
  end
  Selection.apply(app,{foe.id});foe.x,foe.y=homeX,homeY;app:update(.05)
  assert(#app.selected==0,'the selection kept an enemy that left sight')
 end
 -- Tab moves the command card between types and never shrinks the selection. The old
 -- behaviour replaced the selection with one subgroup, so a player who pressed Tab to
 -- look at one unit type lost the rest of their army with no way back.
 local worker=Input.idleWorkers(app)[1]
 if worker and mover and worker~=mover then
  app.selected={mover,worker};table.sort(app.selected)
  local size=#app.selected
  app.subgroupKind=nil
  local first=Selection.cycle(app)
  assert(#app.selected==size,'Tab shrank the selection from '..size..' to '..#app.selected)
  local second=Selection.cycle(app)
  assert(#app.selected==size,'a second Tab shrank the selection')
  assert(first and second and first~=second,'Tab did not move between unit types')
  assert(Selection.cycle(app)==first,'Tab did not wrap back to the first type')
  -- The card follows the active subgroup.
  app.subgroupKind=app:entity(worker).kind
  assert(Selection.primary(app)==worker,'the command card ignored the active subgroup')
  -- And with no subgroup chosen it picks the most interesting member, not the lowest id.
  app.subgroupKind=nil
  local primary=app:entity(Selection.primary(app))
  assert(Selection.rank(primary)<=Selection.rank(app:entity(worker)),'the card preferred a worker over a combat unit')
 end
 -- Box selection takes your own units over anything else in the same rectangle, and
 -- never mixes a building into an army.
 app.selected={}
 local anchorUnit=app:entity(mover)
 Camera.center(app,anchorUnit.x,anchorUnit.y);app:draw()
 local wide=Input.boxSelect(app,-1e6,-1e6,1e6,1e6)
 assert(#wide>0,'a box over the whole visible field selected nothing')
 for _,id in ipairs(wide) do
  local e=app:entity(id)
  assert(e.owner==app.player,'box selection picked up an entity that is not yours')
  assert(e.category=='unit','box selection mixed a '..e.category..' into a unit selection')
 end
 -- The acknowledgement is local and immediate: it must be set before any tick runs.
 app.selected={mover};app.ackFlash=nil;app.ackFlashAt=nil
 local tick=app.world.tick
 Input.intent(app,9*256+128,9*256+128,nil,'move')
 assert(app.world.tick==tick,'issuing an order advanced the simulation')
 assert(app.ackFlash and app.ackFlash[mover],'the ordered unit was not acknowledged locally')
 assert(app.ackFlashAt,'the acknowledgement carries no start time')
 app:update(.05)
 -- The hover state refreshes without the mouse moving, so a unit walking under a still
 -- pointer updates the cursor.
 Input.refreshHover(app)
 -- Effects anchored to a live entity follow it; the recorded position is the fallback.
 local unit=app:entity(mover)
 local ax,ay=app:anchorScreen(mover,0,0)
 local ex,ey=app:screen(app:interpolated(unit))
 assert(math.abs(ax-ex)<1e-6 and math.abs(ay-ey)<1e-6,'an anchored effect did not follow its entity')
 local fx,fy=app:anchorScreen(nil,1234,2345)
 local sx,sy=app:screen(1234,2345)
 assert(fx==sx and fy==sy,'an unanchored effect did not fall back to its recorded position')
 -- A windup event raises an anticipation effect. It was emitted and consumed by nothing.
 app.feedback:reset()
 app.feedback:observe({{kind='windup',tick=app.world.tick,source=mover,target=mover,x=unit.x,y=unit.y}},app.view,app.world.tick)
 local windups=0
 for _,item in ipairs(app.feedback.items) do if item.kind=='windup' then windups=windups+1 end end
 assert(windups==1,'the windup event raised no anticipation effect')
 app.feedback:reset()
 app.selected={mover};app.subgroupKind=nil;Camera.clamp(app)
 print('PASS warcraft controls: focus fire, non-destructive Tab, card priority, box priority, acknowledgement, anchored effects, windup')
end
-- Abilities from the player's side: the card offers them, the hotkey arms them, a click
-- casts them, and every refusal says why. A spell that is unreachable from the command
-- card is a spell that does not exist as far as a player is concerned.
function T.abilities(app)
 local Input=require('src.ui.input')
 local Content=require('src.content')
 local Camera=require('src.ui.camera')
 local hero=app:entity(app.view.player.hero)
 if not hero or not hero.alive then return end
 local names=Content.units[hero.kind].abilities
 assert(names and #names>0,'the hero has no abilities to offer')
 app.selected={hero.id};app.subgroupKind=nil;app.targeting=nil
 app:draw()
 -- Every ability has a button, and the button carries the ability label.
 for _,name in ipairs(names) do
  local spec=Content.abilities[name]
  local button
  for _,b in ipairs(app.widgets.items) do if b.id=='ability-'..name then button=b end end
  assert(button,'no command-card button for '..name)
  assert(button.label:find(spec.label,1,true),'the button for '..name..' does not name it')
 end
 -- A ground-targeted ability arms rather than firing, and the preview record carries
 -- everything the cursor and the range ring need.
 local ground
 for _,name in ipairs(names) do if Content.abilities[name].target~='none' then ground=name end end
 if ground then
  local spec=Content.abilities[ground]
  Input.arm(app,'cast',ground)
  assert(app.targeting and app.targeting.ability==ground,'arming a ground ability did not set the targeting record')
  assert(app.targeting.spec==spec,'the targeting record carries no ability definition')
  app:draw()
  -- Escape gives it up without issuing anything.
  local queued=#app.queue
  app:keypressed('escape')
  assert(not app.targeting,'escape did not cancel ability targeting')
  assert(#app.queue==queued,'cancelling targeting issued a command')
  -- Armed and clicked, it becomes exactly one cast command per selected caster.
  Input.arm(app,'cast',ground)
  local target
  if spec.target=='unit' then
   for _,e in ipairs(app.view.entities) do if e.alive and e.owner~=app.player and e.category=='unit' then target=e end end
  end
  if spec.target~='unit' or target then
   Input.resolveTargeting(app,hero.x+512,hero.y,target)
   assert(not app.targeting,'targeting stayed armed after the click')
   local last=app.queue[#app.queue]
   assert(last and last.kind=='cast','clicking with an ability armed did not issue a cast: '..tostring(last and last.kind))
   eqAbility(last.args.ability,ground)
   for i=#app.queue,1,-1 do if app.queue[i].kind=='cast' then table.remove(app.queue,i) end end
  end
 end
 -- A no-target ability has nothing to click, so pressing it casts on the spot.
 local instant
 for _,name in ipairs(names) do if Content.abilities[name].target=='none' then instant=name end end
 if instant then
  local queued=#app.queue
  Input.arm(app,'cast',instant)
  assert(not app.targeting,'a no-target ability armed a targeting mode instead of casting')
  assert(#app.queue>queued,'a no-target ability issued no command')
  local last=app.queue[#app.queue]
  assert(last.kind=='cast' and last.args.ability==instant,'the instant cast named the wrong ability')
  for i=#app.queue,1,-1 do if app.queue[i].kind=='cast' then table.remove(app.queue,i) end end
 end
 -- A cooldown is reported on the button rather than silently doing nothing.
 local world=app.world.entities[hero.id]
 world.cooldowns=world.cooldowns or {}
 world.cooldowns[names[1]]=app.world.tick+60
 app.view=require('src.sim').view(app.world,app.player)
 app:draw()
 local button
 for _,b in ipairs(app.widgets.items) do if b.id=='ability-'..names[1] then button=b end end
 assert(button and button.reason and button.reason:find('Ready in'),'a cooling ability did not say when it is ready')
 world.cooldowns[names[1]]=nil
 -- And so is a shortage of mana.
 world.mana=0
 app.view=require('src.sim').view(app.world,app.player)
 app:draw()
 for _,b in ipairs(app.widgets.items) do if b.id=='ability-'..names[1] then button=b end end
 assert(button and button.reason and button.reason:find('mana'),'an unaffordable ability did not mention mana')
 world.mana=world.maxMana
 -- Smart cast turns the key into the cast: no armed mode, a command straight away.
 local ground2
 for _,name in ipairs(names) do if Content.abilities[name].target~='none' then ground2=name end end
 if ground2 then
  local was=app.settings.smartCast
  app.settings.smartCast=true
  app.targeting=nil
  local queued=#app.queue
  -- Pointed at the middle of the battlefield, the key is the cast: no armed mode. The
  -- pointer is passed in rather than read from the mouse, so this does not depend on
  -- where the cursor happened to be when the suite ran. A ground-aimed ability issues a
  -- command outright; a unit-aimed one with nothing under the pointer says so instead,
  -- and either way the player is never left holding an armed mode they did not ask for.
  local rect=Camera.rect(app)
  Input.arm(app,'cast',ground2,rect.x+rect.w/2,rect.y+rect.h/2)
  assert(not app.targeting,'smart cast armed a targeting mode instead of casting')
  if Content.abilities[ground2].target~='unit' then
   local fired=app.queue[#app.queue]
   assert(#app.queue>queued and fired.kind=='cast','smart cast issued no command')
  end
  for i=#app.queue,queued+1,-1 do table.remove(app.queue,i) end
  -- Pointed at the dock there is nothing to aim at, so it arms rather than casting at a
  -- panel.
  app.targeting=nil
  Input.arm(app,'cast',ground2,rect.x+rect.w/2,rect.y+rect.h+40)
  assert(app.targeting,'smart cast off the battlefield did not fall back to arming')
  app.targeting=nil
  app.settings.smartCast=was
 end
 -- A ping is a command, so it reaches the other player and the replay rather than being
 -- a dot only this client draws.
 local queued=#app.queue
 app:command('ping',nil,{x=8*256,y=8*256})
 local last=app.queue[#app.queue]
 assert(#app.queue>queued and last.kind=='ping','the minimap ping did not become a command')
 assert(last.args.x==8*256 and last.args.y==8*256,'the ping carried the wrong position')
 for i=#app.queue,queued+1,-1 do table.remove(app.queue,i) end
 app.localPing={x=8*256,y=8*256,time=app.clock,player=app.player}
 app:draw()
 app.localPing=nil
 app.targeting=nil;app.selected={hero.id}
 print('PASS abilities: command card, arming, ground and instant casts, smart cast, ping, cooldown and mana refusals')
end
function eqAbility(a,b) assert(a==b,'wrong ability: '..tostring(a)..' != '..tostring(b)) end
return T
