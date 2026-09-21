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
 -- Aimed a few cells from the worker, which the camera has just centred, so the click lands in
 -- the field whatever map and layout the fixture put the worker on.
 app:keypressed('a');local x,y=app:screen(worker.x+3*256,worker.y+2*256);app:mousepressed(x,y,1);app:update(.05)
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
 -- The fog texture must agree with the player's visible and explored sets pixel for pixel:
 -- at the start, after ticks of incremental updates while units move, and after a change of
 -- perspective, which rebuilds it. A fog that disagrees shows or hides the wrong ground.
 do
  local Minimap=require('src.ui.minimap')
  local function fogAgrees(label)
   local cache=Minimap.cache(app);local player=app.view.player;local map=app.view.map
   for key=1,map.width*map.height do
    local x,y=(key-1)%map.width,math.floor((key-1)/map.width)
    local _,_,_,alpha=cache.fogData:getPixel(x,y)
    local want=player.visible[key] and 0 or player.explored[key] and .6 or .96
    assert(math.abs(alpha-want)<.01,label..': fog pixel '..x..','..y..' has alpha '..alpha..', expected '..want)
   end
   return cache
  end
  fogAgrees('start')
  local uploads=Minimap.cache(app).uploads
  for _=1,40 do app:update(.05);Minimap.cache(app) end
  local cache=fogAgrees('after 40 ticks')
  assert(cache.uploads-uploads<=40,'fog uploaded more than once per tick')
  -- Ticks alone may leave every cell where it was. Send the hero far out and back, so ground it
  -- revealed must fall back to explored: the incremental path's hardest case.
  local hero=app.world.entities[app.view.player.hero];local homeX,homeY=hero.x,hero.y
  local map=app.view.map
  hero.x=math.min(map.width-2,math.floor(homeX/256)+24)*256+128
  app:update(.05);fogAgrees('hero scouting far out')
  hero.x,hero.y=homeX,homeY
  app:update(.05);fogAgrees('hero back home')
  -- Several simulation ticks can pass between draws (catch-up and accelerated replay).
  -- Reveal a fresh patch and leave it without letting the renderer sample that visibility.
  hero.y=math.min(map.height-2,math.floor(homeY/256)+24)*256+128
  app:update(.05)
  hero.x,hero.y=homeX,homeY
  app:update(.05);fogAgrees('exploration between rendered frames')
  local saved=app.player
  app.player=2;app.view=Sim.view(app.world,2);fogAgrees('player two')
  app.player=saved;app.view=Sim.view(app.world,saved);fogAgrees('back to player one')
 end
 T.gamefeel(app)
 T.feelOrders(app)
 T.feelUnits(app)
 T.feelWorld(app)
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
 require('tests.aircraft_presentation').run(capture)
 require('tests.infantry_presentation').run(capture)
 require('tests.building_presentation').run(capture)
 for _,screen in ipairs({'main','skirmish','multiplayer','settings','replays'}) do shell.screen=screen;if screen=='replays' then shell:replays();local found=false;for _,item in ipairs(shell.replayFiles) do if item.name=='ui-proof.replay' then found=true end end;assert(found,'saved replay absent from browser') end;capture(screen,function() shell:draw() end) end
 shell.screen='multiplayer';shell.focus='address';local old=shell.address;shell:keypressed('a');assert(shell.address==old and not shell.match,'text focus leaked');shell:textinput('1');assert(shell.address==old..'1');shell.focus=nil
 app.overlay='upgrade';app.upgradeMilestone=2;app.upgradeChoice=1;capture('upgrade',function() app:draw() end)
 -- Control points are only drawn on a map that has them, which no fixture above uses. One
 -- point owned with the other half captured by the enemy, then both held: ground rings,
 -- capture fill, minimap rings and the public countdown banner, each actually drawn.
 local marches=require('src.app').create({map='twin_marches'});marches.noAutoSave=true
 local controlState
 if marches.world.control then
  local points=marches.world.control.points
  points[1].owner=1;points[2].capturer=2;points[2].progress=100
  marches.view=Sim.view(marches.world,1);Camera.center(marches,points[1].x,points[1].y)
  capture('control-contest',function() marches:draw() end)
  points[2].owner=1;points[2].capturer=0;points[2].progress=0;Sim.step(marches.world,{})
  marches.view=Sim.view(marches.world,1);assert(marches.view.control.holder==1,'a hold is not visible in the view')
  controlState=Sim.serializeCanonical(marches.world)
  capture('control-hold',function() marches:draw() end)
  assert(Sim.serializeCanonical(marches.world)==controlState,'drawing control points mutated the simulation')
 else controlState=Sim.serializeCanonical(marches.world) end
 -- Terrain: the base, the open field with its forests and roads, and a stretch of coast, each
 -- drawn through the chunked renderer. Drawing bakes chunks but must leave the world untouched.
 -- The view's visible set is replaced by the whole map so the ground can be seen rather than fog.
 -- A view is presentation data, so this reveals nothing in the world, which the check below proves.
 marches.view=Sim.view(marches.world,1)
 local everywhere={};for key=1,marches.world.map.width*marches.world.map.height do everywhere[key]=true end
 marches.view.player.visible=everywhere;marches.view.player.explored=everywhere
 for _,spot in ipairs({{'terrain-home',22,22},{'terrain-field',100,48},{'terrain-coast',30,120}}) do
  Camera.center(marches,spot[2]*256+128,spot[3]*256+128)
  capture(spot[1],function() marches:draw() end)
 end
 assert(marches.terrainRenderer and marches.terrainRenderer.baked>0,'the terrain renderer baked nothing')
 assert(Sim.serializeCanonical(marches.world)==controlState,'drawing terrain mutated the simulation')
 marches:close()
 assert(not marches.terrainRenderer,'closing the app kept the terrain chunks')
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
 -- Target stacks and a channel (simulation version 26), drawn from the view alone: pips
 -- over the enemy hero and the ring where the own hero's channel is falling.
 do
  local overlay=app.overlay;app.overlay=nil
  local own=app.world.entities[app.view.player.hero];local foe=app.world.entities[app.world.players[2].hero]
  local homeX,homeY=foe.x,foe.y;foe.x=own.x+768;foe.y=own.y
  foe.stackFixed=800;foe.stackHit=app.world.tick;own.channel={ability='bulwark',x=own.x,y=own.y,start=app.world.tick,finish=app.world.tick+60}
  app.view=Sim.view(app.world,app.player);Camera.center(app,own.x,own.y)
  assert(app.view.byId[foe.id] and app.view.byId[foe.id].stackFixed==800,'the stacks did not reach the view')
  capture('weapons',function() app:draw() end)
  foe.stackFixed=nil;foe.stackHit=nil;own.channel=nil;foe.x,foe.y=homeX,homeY;app:update(.05);app.overlay=overlay
 end
 -- The shipping factions in their own colours: the Orders' brass and oak, the Megacorp's cyan
 -- and gunmetal, each with its headquarters selected so the command card is showing.
 for _,faction in ipairs({'orders','megacorp'}) do
  local themed=require('src.app').create({map='twin_marches',content=require('src.content'),faction=faction,opponent=faction=='orders' and 'megacorp' or 'orders'});themed.noAutoSave=true
  themed:update(.05);themed.selected={themed:focus()};local hq=themed.world.entities[themed.view.player.hq];Camera.center(themed,hq.x,hq.y)
  local before=Sim.serializeCanonical(themed.world)
  capture('hud-'..faction,function() themed:draw() end)
  -- Moving the pointer with a building armed asks the simulation whether it fits there. This
  -- path named a content table that no longer existed and crashed the first real match.
  local armed=faction=='orders' and 'depot' or 'substrate_rig'
  themed.building=armed;local w,h=love.graphics.getDimensions()
  require('src.ui.input').mousemoved(themed,w/2,h/2,0,0);require('src.ui.input').mousemoved(themed,w/3,h/3,4,4)
  themed.building=nil
  assert(themed.widgets.theme==require('src.ui.theme').of(faction),'the HUD did not take the theme of its faction')
  assert((themed.sidebar==true)==(faction=='megacorp'),'the orbital sidebar is on the wrong faction');if faction=='orders' then assert(Camera.rect(themed).w==love.graphics.getDimensions(),'the Orders lost battlefield to a sidebar they do not have') end
  assert(Sim.serializeCanonical(themed.world)==before,'drawing the themed HUD changed the simulation');themed:close()
 end
 -- The Megacorp's orbital sidebar, driven end to end on the shipping content: order, wait for
 -- READY, click the frame, F9, land, cancel a frame, B and P from anywhere, load, refund a
 -- seat, and a launch that is refused off coverage before it is accepted on it.
 do
  local Orbital=require('src.ui.orbital');local C2=require('src.content')
  local mc=require('src.app').create({map='twin_marches',content=C2,faction='megacorp',opponent='orders'});mc.noAutoSave=true
  local s=mc.settings.scale/100;local ww=love.graphics.getDimensions()
  assert(mc.sidebar and Camera.rect(mc).w==ww-Orbital.WIDTH*s,'the battlefield was not narrowed for the sidebar')
  local function run(n) for _=1,n do mc:update(.05) end end
  local function widget(id) mc:draw();for _,b in ipairs(mc.widgets.items) do if b.id==id then return b end end end
  local function click(id) local b=assert(widget(id),'no widget '..id);mc:mousepressed((b.x+b.w/2)*s,(b.y+b.h/2)*s,1) end
  local hq=mc.view.player.hq;mc.world.players[1].resources={substrate=5000,charge=5000};run(1)
  for _,kind in ipairs({'mc_barracks','orbital_relay','requisition_office'}) do mc:command('requisition',hq,{building=kind});run(1) end
  run(120);local before=Sim.serializeCanonical(mc.world);capture('orbital-queue',function() mc:draw() end);assert(Sim.serializeCanonical(mc.world)==before,'drawing the sidebar changed the simulation')
  assert(mc.orbitalModel.frames[1].state=='producing' and mc.orbitalModel.frames[2].state=='waiting','the sidebar model is not the queue')
  run(C2.buildings.mc_barracks.buildTicks);assert(widget('orbit-frame-1') and mc.orbitalModel.frames[1].state=='ready' and mc.orbitalModel.blocked,'the barracks is not READY and blocking')
  click('orbit-frame-1');assert(mc.landing==1 and mc.building=='mc_barracks','clicking READY did not arm the landing')
  local hqe=mc.world.entities[hq];Camera.center(mc,hqe.x,hqe.y);capture('orbital-landing',function() mc:draw() end)
  local cr=Camera.rect(mc);mc:mousepressed(cr.x+cr.w/2,cr.y+cr.h/2,2);assert(not mc.landing and mc.view.player.callDown[1].remaining==0,'a right-click did not return the building to READY')
  mc:keypressed('f9');assert(mc.landing==1,'F9 did not arm the next ready building')
  local site;for dx=6,14 do for dy=-6,6 do if not site and Sim.placement(mc.view,C2,'mc_barracks',math.floor(hqe.x/256)+dx,math.floor(hqe.y/256)+dy,true) then site={math.floor(hqe.x/256)+dx,math.floor(hqe.y/256)+dy} end end end
  local sx,sy=mc:screen(assert(site,'no landing site near the Command')[1]*256+128,site[2]*256+128);mc:mousepressed(sx,sy,1);run(2)
  assert(#mc.view.player.landings==1 and not mc.landing,'the landing was not ordered');assert(mc.view.player.callDown[1].kind=='orbital_relay','the queue did not move up')
  local cancelled=assert(widget('orbit-frame-2'),'no second frame');cancelled.alt();run(2);assert(#mc.view.player.callDown==1,'right-click on a frame did not cancel it')
  mc.selected={};mc:keypressed('b');assert(mc.cardPage=='requisition' and mc.selected[1]==hq,'B did not open Requisition from anywhere')
  mc.selected={};mc:keypressed('p');assert(mc.cardPage=='pod','P did not open the pod page from anywhere')
  run(C2.rules.descentTicks+5);for _=1,2 do mc:command('pod_load',hq,{unit='associate'});run(1) end
  before=Sim.serializeCanonical(mc.world);capture('orbital-pods',function() mc:draw() end);assert(Sim.serializeCanonical(mc.world)==before)
  assert(mc.orbitalModel.loaded==2 and mc.orbitalModel.launch.state=='ready','the pod is not loaded and ready')
  click('orbit-seat-1');run(2);assert(#mc.view.player.pods.open.kinds==1,'clicking a seat did not refund it')
  click('orbit-launch');assert(mc.targeting and mc.targeting.command=='pod_launch','the dial did not arm a launch')
  require('src.ui.input').resolveTargeting(mc,120*256,120*256,nil);run(2);assert(mc.targeting and #mc.view.player.pods.inFlight==0,'a launch off coverage was not refused at the pointer')
  require('src.ui.input').resolveTargeting(mc,hqe.x+8*256,hqe.y,nil);run(2);assert(#mc.view.player.pods.inFlight==1,'the pod did not launch onto covered ground')
  mc:draw();assert(mc.orbitalModel.launch.state=='away' and mc.orbitalModel.launch.cooldown>0 and mc.orbitalModel.pips[1]=='flight','the dial does not say the only pod is away');mc:close()
 end
 -- Game juice, drawn: an impact ring with its dust, a splash circle, scorch, a burst number and
 -- the owner's descent marker over a landing site, none of it touching the simulation.
 do
  local overlay=app.overlay;app.overlay=nil
  local own=app.world.entities[app.view.player.hero];local tick=app.world.tick
  local before=Sim.serializeCanonical(app.world)
  app.juice:reset();Camera.center(app,own.x,own.y)
  app.juice:observe({{kind='landed',entity=own.id,x=own.x+1024,y=own.y,tick=tick},{kind='stack_burst',entity=own.id,x=own.x-768,y=own.y+256,damage=45,tick=tick},
   {kind='death',entity=0,unitKind='barracks',x=own.x,y=own.y+1280,tick=tick},{kind='cast',source=own.id,ability='thornfall',castX=own.x-1536,castY=own.y-768,tick=tick}},app)
  app.juice:update(.08);app.feedback:update(.08)
  assert(#app.juice.particles>30 and #app.juice.rings>=3 and #app.juice.decals==1,'the juice reactions did not all appear')
  app.view.player.landings={{kind='barracks',x=math.floor(own.x/256)+6,y=math.floor(own.y/256)-5,at=tick+40}}
  capture('juice',function() app:draw() end)
  app.view.player.landings=nil;app.juice:reset()
  assert(Sim.serializeCanonical(app.world)==before,'game juice changed the simulation')
  app.overlay=overlay
 end
 app.overlay=nil;app.selected={app.view.player.hero};Camera.center(app,hero.x,hero.y);capture('match',function() app:draw() end)
 require('tests.command_card').captures(app,capture)
 T.tooltips(app,capture)
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
 -- Pan speed and the alert camera are presentation settings too.
 local scrolls={}
 for _=1,#Settings.SCROLL_SPEEDS+1 do local b=control('scroll');scrolls[#scrolls+1]=app.settings.scrollSpeed;b.action() end
 assert(scrolls[1]==scrolls[#scrolls] and scrolls[1]~=scrolls[2],'scroll speed did not cycle')
 local cameraBefore=app.settings.alertCamera
 control('alertcam').action();assert(app.settings.alertCamera~=cameraBefore,'camera-to-alerts did not toggle')
 control('alertcam').action();assert(app.settings.alertCamera==cameraBefore,'camera-to-alerts did not toggle back')
 -- And every setting has to survive the round trip through storage, not just the button. Smart
 -- cast used to be saved and never read back.
 app.settings.healthBars='always';app.settings.smartCast=true;app.settings.alertCamera=true;app.settings.scrollSpeed=3
 Settings.save(app.settings)
 local loaded=Settings.load()
 assert(loaded.healthBars=='always','health bars did not survive a save and load')
 assert(loaded.smartCast==true,'smart cast did not survive a save and load')
 assert(loaded.alertCamera==true and loaded.scrollSpeed==3,'pan speed or camera-to-alerts did not survive a save and load')
 app.settings.smartCast=false;app.settings.alertCamera=false;app.settings.scrollSpeed=2
end
-- Feel pass, batch A (docs/GAME_FEEL.md): the selection pop, the health trail's hold, order
-- markers coloured by what was ordered, and formation ghosts. All presentation, so every draw
-- here is checked against the world, and every check is one that fails without its feature.
function T.feelOrders(app)
 local Sim=require('src.sim');local Input=require('src.ui.input')
 app.overlay=nil;app.building=nil;app.targeting=nil
 local own,enemy={},nil
 for _,e in ipairs(app.view.entities) do
  if e.alive and e.category=='unit' and e.owner==app.player then own[#own+1]=e end
  if e.alive and e.category=='unit' and e.owner~=app.player and e.owner~=0 and not enemy then enemy=e end
 end
 assert(#own>=2,'the fixture needs two units of our own')
 local function drawClean(what)
  local before=Sim.serializeCanonical(app.world);app:draw()
  assert(Sim.serializeCanonical(app.world)==before,what..' mutated the simulation')
 end
 -- Selection pop: a ring remembers when its unit was selected, and forgets once it is not.
 app.selected={own[1].id};drawClean('the selection pop')
 assert(app.selectedSince and app.selectedSince[own[1].id]==app.clock,'a new selection was not timed')
 app.selected={};drawClean('clearing the selection')
 assert(app.selectedSince[own[1].id]==nil,'a deselected unit kept its selection time')
 -- The health trail holds what was just lost before draining it.
 local victim=app.world.entities[own[1].id]
 victim.hp=victim.hp-60;app.view=Sim.view(app.world,app.player)
 app:update(0)
 local trail=app.healthTrails[victim.id]
 assert(trail and trail.value>victim.hp,'the trail did not keep the health just lost')
 local held=trail.value
 app:update(.1)
 assert(trail.value==held,'the trail drained before its hold was over')
 for _=1,10 do app:update(.05) end
 assert(trail.value<held,'the trail never drained after its hold')
 -- Order markers carry what was actually ordered, not just which key was pressed.
 own[1]=app.view.byId[own[1].id];own[2]=app.view.byId[own[2].id]
 app.selected={own[1].id,own[2].id}
 Input.intent(app,own[1].x+512,own[1].y,nil,nil)
 assert(app.orderMarker.kind=='move','a plain right-click did not mark a move: '..tostring(app.orderMarker.kind))
 Input.intent(app,own[1].x+512,own[1].y,nil,'patrol')
 assert(app.orderMarker.kind=='patrol','a patrol did not mark as a patrol: '..tostring(app.orderMarker.kind))
 -- Right-clicking one of your own units is a follow, whatever key was held: the marker has to
 -- say what the click became. This needs no enemy in sight, unlike the attack check below.
 app.selected={own[1].id}
 Input.intent(app,own[2].x,own[2].y,own[2],nil)
 assert(app.orderMarker.kind=='follow','a right-click on our own unit did not mark a follow: '..tostring(app.orderMarker.kind))
 app.selected={own[1].id,own[2].id}
 if enemy then
  Input.intent(app,enemy.x,enemy.y,enemy,nil)
  assert(app.orderMarker.kind=='attack','a right-click on an enemy did not mark an attack: '..tostring(app.orderMarker.kind))
 end
 drawClean('the order marker')
 -- Formation ghosts: once a group move reaches the world, each unit's cell is marked, and the
 -- marks are gone a second later.
 Input.intent(app,own[1].x+1024,own[1].y,nil,nil)
 for _=1,4 do app:update(.05) end
 drawClean('the formation ghosts')
 assert((app.formationGhosts or 0)>=2,'a group move showed no formation ghosts: '..tostring(app.formationGhosts))
 app.clock=app.clock+1.1;drawClean('expired formation ghosts')
 assert(app.formationGhosts==0,'formation ghosts outlived their second')
 app.selected={}
 print('PASS feel batch A: selection pop, health trail hold, order markers by kind, formation ghosts')
end
-- Feel pass, batch B: a badly hurt unit of ours pulses, and a unit winding up leans into the
-- swing. Both are drawn, not spawned; the counters say whether they were.
function T.feelUnits(app)
 local Sim=require('src.sim');local Camera=require('src.ui.camera')
 app.overlay=nil;app.building=nil;app.targeting=nil
 local unit
 for _,e in ipairs(app.view.entities) do if e.alive and e.category=='unit' and e.owner==app.player then unit=e;break end end
 assert(unit,'the fixture has no unit of ours')
 local body=app.world.entities[unit.id];local full=body.hp
 Camera.center(app,body.x,body.y)
 body.hp=math.floor(body.maxHp*.2);app.view=Sim.view(app.world,app.player)
 local before=Sim.serializeCanonical(app.world);app:draw()
 assert(Sim.serializeCanonical(app.world)==before,'the low-health pulse mutated the simulation')
 local hurt=app.lowHealthDrawn
 body.hp=body.maxHp;app.view=Sim.view(app.world,app.player);app:draw()
 assert(hurt>app.lowHealthDrawn,'a badly hurt unit of ours did not pulse: '..hurt..' against '..app.lowHealthDrawn)
 -- A swing halfway through, as the feedback layer would record it from a windup event.
 app.feedback.windups[unit.id]=app.world.tick-2;app:draw()
 assert((app.windupsDrawn or 0)>=1,'a unit winding up was drawn without leaning into the swing')
 app.feedback.windups[unit.id]=nil;app:draw()
 assert(app.windupsDrawn==0,'a unit leaned into a swing it was not making')
 body.hp=full;app.view=Sim.view(app.world,app.player)
 print('PASS feel batch B: low-health pulse, windup lean')
end
-- Feel pass, batch C: the scroll ramp and speed setting, feathered fog, an alert for attacks out of
-- view, and the camera following alerts only when the player has turned that on.
function T.feelWorld(app)
 local Camera=require('src.ui.camera');local Alerts=require('src.ui.alerts')
 app.overlay=nil
 -- Scrolling starts gentle, reaches full speed while held, starts over on release, and follows
 -- the speed setting.
 local savedX,savedY,savedSpeed=app.camera.x,app.camera.y,app.settings.scrollSpeed
 app.settings.scrollSpeed=2;app.scrollHeld=0
 local x=app.camera.x;Camera.scroll(app,.05,1,0);local first=x-app.camera.x
 for _=1,10 do Camera.scroll(app,.05,1,0) end
 x=app.camera.x;Camera.scroll(app,.05,1,0);local held=x-app.camera.x
 assert(first>0 and held>first*2,'panning did not ramp up: '..first..' then '..held)
 Camera.scroll(app,.05,0,0);assert(app.scrollHeld==0,'letting go did not reset the ramp')
 x=app.camera.x;Camera.scroll(app,.05,1,0)
 assert(math.abs((x-app.camera.x)-first)<1e-6,'the ramp did not start again from rest')
 app.settings.scrollSpeed=3;app.scrollHeld=0
 x=app.camera.x;Camera.scroll(app,.05,1,0)
 assert(x-app.camera.x>first*1.4,'the fast scroll setting did not pan faster')
 app.settings.scrollSpeed=savedSpeed;app.camera.x,app.camera.y=savedX,savedY;app.scrollHeld=0
 -- The fog is sampled linearly, which is what feathers its edge.
 app:draw()
 local _,magnify=app.miniCache.fog:getFilter()
 assert(magnify=='linear','the fog edge is not feathered: '..tostring(magnify))
 -- Attacks out of view: announced once, not for an attack in plain view, and the camera only
 -- goes there when the player asked for that. Twin Marches is large enough to look away from.
 local m=require('src.app').create({map='twin_marches'});m.noAutoSave=true
 local unit
 for _,e in ipairs(m.view.entities) do if e.alive and e.category=='unit' and e.owner==m.player and e.id~=m.view.player.hero then unit=e;break end end
 assert(unit,'Twin Marches has no unit of ours')
 local event={kind='attack',owner=m.player,target=unit.id,source=0,x=unit.x,y=unit.y}
 local function announced()
  for _,item in ipairs(m.alerts.items) do if item.text=='Your forces are under attack' then return item end end
 end
 m.settings.alertCamera=false
 Camera.center(m,unit.x,unit.y);m.alerts=Alerts.create();m.alerts:observe({event},m)
 assert(not announced(),'an attack in plain view was announced')
 Camera.center(m,96*256,96*256);m.cameraGlide=nil;m.alerts=Alerts.create();m.alerts:observe({event},m)
 assert(announced(),'an attack out of view was not announced')
 assert(m.cameraGlide==nil,'the camera moved to an alert nobody asked it to follow')
 m.alerts:observe({event,event},m)
 local notices=0;for _,item in ipairs(m.alerts.items) do if item.text=='Your forces are under attack' then notices=notices+1 end end
 assert(notices==1,'one attack was announced '..notices..' times')
 m.settings.alertCamera=true;m.alerts=Alerts.create();m.alerts:observe({event},m)
 assert(m.cameraGlide,'the camera did not go to an attack with camera-to-alerts on')
 m.settings.alertCamera=false;m:close()
 print('PASS feel batch C: scroll ramp and speed, feathered fog, attacks out of view, opt-in alert camera')
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
  assert(e.category=='unit' and not app.content.units[e.kind].worker,'F2 selected a non-combat unit')
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
  local selectedCue=app.audio.selected;local cueKind
  app.audio.selected=function(self,kind,...) cueKind=kind;return selectedCue(self,kind,...) end
  app:mousepressed(fx,fy,1);app:mousereleased(fx,fy,1)
  app.audio.selected=selectedCue
  assert(cueKind==foe.kind,"a click-select did not ask for the selected unit's own cue")
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
  assert(Selection.rank(primary,app)<=Selection.rank(app:entity(worker),app),'the card preferred a worker over a combat unit')
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
 local Content=app.content
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
-- Tooltips: the card answers at once and above the card; the rest wait, then sit by the pointer
-- and stay on screen; a modal hides what is under it; the world tooltip only says what a view
-- carries. The pointer is stubbed, because a test cannot move the real one.
function T.tooltips(app,capture)
 local Sim=require('src.sim');local Tooltip=require('src.ui.tooltip');local C=app.content
 local g=love.graphics;local s=app.settings.scale/100;local width,height=g.getDimensions();local w,h=width/s,height/s
 local realPosition=love.mouse.getPosition
 local px,py=0,0
 love.mouse.getPosition=function() return px*s,py*s end
 local function at(x,y) px,py=x,y end
 local state=Sim.serializeCanonical(app.world)
 local world=app.world;local player=world.players[1];local gold=player.resources.gold
 local clock=app.clock
 local function frame(dt) app.clock=app.clock+(dt or 0);app:draw();return app.widgets.shownTip end
 local function item(id) for _,b in ipairs(app.widgets.items) do if b.id==id then return b end end end
 local function inside(tip,x,y) return x>=tip.x and x<tip.x+tip.w and y>=tip.y and y<tip.y+tip.h end
 local function onScreen(tip,what) assert(tip.x>=0 and tip.y>=0 and tip.x+tip.w<=w and tip.y+tip.h<=h,what..' tooltip left the screen') end
 app.overlay=nil;app.building=nil;app.targeting=nil;app.drag=nil;app.capture=nil;app.hoverId=nil
 local workers={}
 for _,e in ipairs(app.view.entities) do if e.owner==1 and e.kind=='worker' and e.alive then workers[#workers+1]=e.id end end
 -- A command card button: instant, anchored above the card, hotkey, costs, stats, reason.
 player.resources.gold=100;app.view=Sim.view(world,1)
 app.selected={workers[1]};require('src.ui.actions').context(app);app.cardPage='build'
 at(10,60);frame(1)
 local hall=assert(item('barracks'),'the build card has no War hall')
 at(hall.x+hall.w/2,hall.y+hall.h/2)
 local tip=frame(0)
 assert(tip and tip.id=='w:barracks','a command card tooltip did not show on the first frame')
 assert(tip.spec.key=='q' and tip.spec.reason=='Insufficient gold','the card tooltip lost its hotkey or its reason')
 assert(tip.spec.costs[1].short and tip.spec.stats and table.concat(tip.spec.stats,','):find('HP '..C.buildings.barracks.hp,1,true),'the card tooltip lost its cost or its stats')
 local cardTop=h-180
 assert(tip.y+tip.h<=cardTop and tip.x+tip.w>w-40,'the card tooltip is not anchored above the card')
 assert(not inside(tip,px,py),'the card tooltip covers the pointer')
 local anchoredBottom=tip.y+tip.h
 -- It stays put while the pointer moves along the card.
 local outpost=assert(item('outpost'))
 at(outpost.x+5,outpost.y+5);tip=frame(0)
 assert(tip.id=='w:outpost' and tip.y+tip.h==anchoredBottom and tip.x+tip.w==w-16,'the card tooltip moved with the pointer')
 assert(type(tip.spec.lines[1])=='string' and tip.spec.lines[1]:find('drop%-off') and tip.spec.stats[1]=='Build '..string.format('%g',C.buildings.outpost.buildTicks/20)..'s','the Outpost tooltip does not say what it is for or how long it takes')
 capture('tooltip-card',function() app:draw() end)
 player.resources.gold=gold;app.view=Sim.view(world,1);app.cardPage=nil
 -- A hero spell: its own name as the title, whatever the button shows, with cooldown and aim.
 app.selected={app.view.player.hero};require('src.ui.actions').context(app);at(10,60);frame(1)
 local spell
 for _,b in ipairs(app.widgets.items) do if b.details and b.details.title then
  at(b.x+4,b.y+4);tip=frame(0)
  assert(tip and tip.spec.title==b.details.title and tip.spec.stats[1]:find('^Cooldown') and #tip.spec.lines==2,'a spell tooltip lost its name, cooldown or aim')
  assert(not tip.spec.lines[1]:find('mana'),'a spell tooltip repeats its mana cost')
  spell=b;capture('tooltip-spell',function() app:draw() end)
  break
 end end
 assert(spell,'the hero card has no spell to hover');app.selected={}
 -- A readout waits, then sits beside the pointer; the next one within the grace is immediate.
 at(60,20);frame(0);assert(not frame(1),'a tooltip showed over plain text')
 at(150,20);assert(not frame(0),'the gold tooltip showed with no delay')
 assert(not frame(Tooltip.DELAY*.5),'the gold tooltip showed before its delay')
 tip=frame(Tooltip.DELAY*.6)
 assert(tip and tip.id=='w:gold' and tip.spec.title=='Gold','the gold tooltip did not show after the delay')
 onScreen(tip,'the gold');assert(not inside(tip,px,py),'the gold tooltip covers the pointer')
 capture('tooltip-gold',function() app:draw() end)
 at(440,20);tip=frame(0.05)
 assert(tip and tip.id=='w:food','moving to the next readout did not show its tooltip at once')
 at(60,20);frame(0);assert(not frame(Tooltip.GRACE+.1),'a tooltip lingered')
 at(470,20);assert(not frame(0),'the grace outlived its window')
 -- Near the bottom-right corner the panel flips to stay on screen.
 local big={title='Corner',lines={string.rep('word ',60)},costs={{key='gold',label='gold',amount=999,available=1,short=true}}}
 local layout=Tooltip.layout(big,app.fonts.small,app.fonts.body)
 assert(layout.width<=Tooltip.MAX_WIDTH,'a long tooltip grew past its width')
 local x,y=Tooltip.place(layout,nil,{w=w,h=h,top=44},w-2,h-2)
 assert(x>=4 and y>=44 and x+layout.width<=w-4 and y+layout.height<=h-4,'a corner tooltip left the screen')
 -- On a screen too narrow to flip into, it is pushed back on rather than off the left edge.
 x,y=Tooltip.place(layout,nil,{w=layout.width+40,h=h,top=44},layout.width/2,50)
 assert(x>=4 and x+layout.width<=layout.width+36 and y>=44,'a tooltip on a narrow screen left it')
 -- A modal takes the pointer: the hero button under the pause panel keeps no tooltip.
 local hero=assert(item('hero'),'the hero button is missing')
 at(hero.x+5,hero.y+5);frame(0);frame(1);assert(app.widgets.shownTip and app.widgets.shownTip.id=='w:hero','the hero button had no tooltip')
 app.overlay='pause';tip=frame(1);assert(not tip,'a tooltip from under the pause panel showed through it');app.overlay=nil
 -- The world: after the delay, what the pointer rests on. Nothing while dragging a box.
 at(w/2,h/2-100);frame(1)
 local unit=app:entity(workers[1])
 app.hoverId=unit.id;assert(not frame(0),'the world tooltip showed with no delay')
 tip=frame(Tooltip.DELAY+.05)
 assert(tip and tip.id=='e:'..unit.id and tip.spec.title=='Worker' and tip.spec.subtitle=='Yours','the world tooltip did not describe the unit')
 onScreen(tip,'the world')
 capture('tooltip-world',function() app:draw() end)
 app.drag={x=0,y=0};assert(not frame(0),'the world tooltip showed during a box drag');app.drag=nil
 local mine;for _,e in ipairs(app.view.entities) do if e.category=='node' then mine=e;break end end
 if mine then assert(Tooltip.entity(app,mine).title==Tooltip.RESOURCE_NAMES[mine.resource],'a resource node was not named by its resource') end
 -- Only what a view carries: an enemy hero's experience is private, so no level is shown.
 local ownHero=app:entity(app.view.player.hero)
 assert(Tooltip.entity(app,ownHero).title:find('level'),'your own hero tooltip lost its level')
 local enemy={kind=ownHero.kind,owner=2,category='unit',alive=true,hp=10,maxHp=20}
 local spec=Tooltip.entity(app,enemy)
 assert(not spec.title:find('level') and spec.subtitle=='Enemy','the enemy tooltip claimed private detail')
 app.hoverId=nil;app.selected={};love.mouse.getPosition=realPosition;app.clock=clock
 assert(Sim.serializeCanonical(app.world)==state,'tooltips changed the simulation')
end
return T
