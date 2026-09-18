-- Bounded rendered integration fixture. Instrumentation is deliberately outside sim/draw CPU timers.
local App=require('src.app')
local Sim=require('src.sim')
local Content=require('tests.fixture_content')
local Maps=require('src.maps')
local Codec=require('src.sim.codec')
local Hash=require('src.hash')
local Sprites=require('src.sprites')
local Catalog=require('src.asset_catalog')
local Frames=require('src.asset_frames')
local Viewer=require('src.asset_viewer')
local Feedback=require('src.feedback')
local P={}
local function now() return love.timer.getTime() end
local function percentile(values,p)
    local sorted={};for i,v in ipairs(values) do sorted[i]=v end;table.sort(sorted)
    return sorted[math.max(1,math.ceil(#sorted*p))] or 0
end
local function write(path,data)
    local file=assert(io.open(path,'wb'));file:write(data);file:close()
end
-- The default 48x48 arena keeps the rendered fixture cheap and deterministic.
-- Passing the shipping 128x112 map instead exposes the costs that scale with map
-- area (fog canvas, visibility spans, blocked-cell copies) rather than unit count.
local function fixture(name)
    local map=name=='twin_marches' and Maps.create('twin_marches') or Maps.create('asset_battle',48)
    map.resources={};map.camps={}
    local world=Sim.create({seed=4081,players={{faction='bastion'},{faction='bastion'}}},Content,map)
    for player=1,2 do
        local members,template={},nil
        for _,id in ipairs(world.order) do
            local e=world.entities[id]
            if e.owner==player and e.category=='unit' then members[#members+1]=e;if e.kind=='worker' then template=e end end
        end
        assert(template)
        while #members<60 do
            local e=Codec.copy(template);e.id=world.nextId;world.nextId=world.nextId+1
            e.kind=#members%3==0 and 'crossbow' or 'shield';e.hp=Content.units[e.kind].hp;e.maxHp=e.hp
            world.entities[e.id]=e;world.order[#world.order+1]=e.id;members[#members+1]=e
        end
        assert(#members==60)
        for i,e in ipairs(members) do
            e.x=((player==1 and 15 or 25)+(i-1)%6)*256+128
            e.y=(12+math.floor((i-1)/6))*256+128
            if e.kind=='worker' and i%2==0 then e.category='carrier';e.kind='carrier';e.payload=8 end
        end
    end
    return world
end
local function legacyRenderer(shader)
    local old=assert(love.filesystem.load('assets/generated/shieldguard.lua'))()
    local m=Catalog.adaptV1(old);local p=m.pages[1]
    local image=love.graphics.newImage(p.color);local mask=love.graphics.newImage(p.mask)
    assert(image:getWidth()==p.width and image:getHeight()==p.height and mask:getWidth()==p.width and mask:getHeight()==p.height)
    image:setFilter('nearest','nearest');mask:setFilter('nearest','nearest')
    local unit={metadata=m,pages={{color=image,mask=mask}},quads={}}
    for i,f in ipairs(m.frames) do unit.quads[i]=love.graphics.newQuad(f.x,f.y,f.width,f.height,p.width,p.height) end
    return setmetatable({units={shieldguard=unit},states={},shader=shader,diagnostics={}},{__index=Sprites})
end
function P.create(options)
    options=options or {};local app=App.create({faction='bastion',map='open_fields',content=Content})
    local self=setmetatable({app=app,benchmark=not not options['asset-benchmark'],tickTimes={},drawTimes={},cadence={},frames=0,accumulator=0,
        ticks=math.max(120,math.min(1200,tonumber(options['asset-samples']) or 300)),pendingShots=0,
        attacks=0,movingTicks=0,comparisons=0,started=now(),memoryBefore=collectgarbage('count'),screenshots={},modes={}}, {__index=P})
    for _,id in ipairs({'shieldguard','worker','worker_loaded','crossbow','warden'}) do assert(app.sprites.units[id],'required v2 asset missing: '..id) end
    assert(not app.sprites.catalog.legacy and #app.sprites.diagnostics==0,'v2 assets required without diagnostics')
    self.modes={{name='v2',world=fixture(options.map),sprites=app.sprites,previous={}}}
    if not self.benchmark then
        self.modes[2]={name='v1-adapter',sprites=legacyRenderer(app.sprites.shader),previous={}}
        self.modes[3]={name='diagnostic-fallback-effects-disabled',sprites=setmetatable({units={},states={},diagnostics={}},{__index=Sprites}),previous={}}
        for i=2,3 do self.modes[i].world=Sim.restore(Sim.snapshot(self.modes[1].world)) end
    end
    for _,mode in ipairs(self.modes) do mode.view=Sim.view(mode.world,1);mode.feedback=Feedback.create();mode.feedback:observe({},mode.view,mode.world.tick) end
    app.selected={self.modes[1].world.players[1].hero};app.message='Asset verification: 60 vs 60 / attack-move / filtered fog'
    if not self.benchmark then
        self.canvas=love.graphics.newCanvas(love.graphics.getDimensions())
        self.viewer=Viewer.create(app.sprites)
        self:checkViewer();self:checkCargo()
    else
        self:bind(self.modes[1],1);collectgarbage('collect')
        self.memoryBefore=collectgarbage('count');self.droppedSeconds=0;self.maxBacklog=0
        app.message='V2 benchmark: 60 vs 60 / 1x / real UI, fog and feedback'
    end
    return self
end
function P:checkViewer()
    local v=self.viewer
    for _=1,#v.ids do
        local id,u=v:unit();assert(u and u.metadata.unitId==id)
        for _=1,#v:clips() do
            v:update(0.1);v:keypressed('space');v:keypressed('right');v:keypressed('left');v:keypressed('home')
            local clip=u.metadata.clips[v:clip()]
            for _,direction in ipairs(Frames.directions) do assert(u.metadata.frames[Frames.sample(u.metadata,v:clip(),direction,v.timeMs)]) end
            assert(clip.durationMs>0);v:keypressed('c')
        end
        v:keypressed('tab')
    end
    for _,key in ipairs({'t','b','z','g','r','d','-','+','home'}) do v:keypressed(key) end
    v.playing=true
end
function P:checkCargo()
    local a=self.app.sprites.units.worker.metadata;local b=self.app.sprites.units.worker_loaded.metadata
    for _,name in ipairs({'idle','move','attack','death','work'}) do
        assert(a.clips[name].durationMs==b.clips[name].durationMs,'cargo duration mismatch')
        for _,direction in ipairs(Frames.directions) do
            local fa,ia=Frames.sample(a,name,direction,337);local fb,ib=Frames.sample(b,name,direction,337)
            assert(ia==ib and a.frames[fa].anchorX==b.frames[fb].anchorX and a.frames[fa].anchorY==b.frames[fb].anchorY,'cargo phase/anchor mismatch')
        end
    end
end
function P:commands(tick)
    if tick~=1 then return {} end
    local commands={};local sequences={0,0};local w=self.modes[1].world
    for _,id in ipairs(w.order) do
        local e=w.entities[id]
        if e.category=='unit' and e.alive then
            local p=e.owner;sequences[p]=sequences[p]+1
            commands[#commands+1]={tick=tick,player=p,sequence=sequences[p],kind='attack_move',args={entity=id,x=(p==1 and 29 or 16)*256+128,y=17*256+128}}
        end
    end
    return commands
end
function P:step()
    local tick=self.modes[1].world.tick+1;local commands=self:commands(tick);local canonical
    for index,mode in ipairs(self.modes) do
        mode.previous={};for _,e in ipairs(mode.view.entities) do mode.previous[e.id]={x=e.x,y=e.y} end
        local before=now();local events=Sim.step(mode.world,commands);local elapsed=(now()-before)*1000
        if index==1 then self.tickTimes[#self.tickTimes+1]=elapsed end
        mode.view=Sim.view(mode.world,1);mode.sprites:observe(events,mode.view,tick);mode.feedback:observe(events,mode.view,tick)
        if index==1 then
            for _,event in ipairs(events) do if event.kind=='attack' then self.attacks=self.attacks+1 end end
            local moving=false;for _,e in ipairs(mode.view.entities) do local prev=mode.previous[e.id];if prev and (e.x~=prev.x or e.y~=prev.y) then moving=true;break end end
            if moving then self.movingTicks=self.movingTicks+1 end
        end
        if not self.benchmark then
            local bytes=Sim.serializeCanonical(mode.world)
            if canonical then assert(bytes==canonical,'presentation mode replay divergence at tick '..tick) else canonical=bytes end
        end
    end
    if not self.benchmark then self.comparisons=self.comparisons+1 end
end
function P:update(dt)
    if self.finished then return end
    self.frames=self.frames+1
    if self.benchmark and self.frames==1 then
        -- Exclude asset loading from frame cadence; the first real draw still counts.
        self.started=now();dt=0
    else self.cadence[#self.cadence+1]=dt*1000 end
    if self.modes[1].world.tick>=self.ticks then
        if self.benchmark then self:finishBenchmark();return end
        self.endFrames=(self.endFrames or 0)+1
        if self.endFrames>3 and self.pendingShots==0 then self:finish() end
        return
    end
    self.accumulator=self.accumulator+math.min(dt,0.25)
    if self.benchmark then
        self.droppedSeconds=self.droppedSeconds+math.max(0,dt-0.25)
        self.maxBacklog=math.max(self.maxBacklog,self.accumulator)
    end
    local steps=0
    while self.accumulator>=0.05 and steps<8 and self.modes[1].world.tick<self.ticks do self:step();self.accumulator=self.accumulator-0.05;steps=steps+1 end
end
function P:bind(mode,zoom)
    local app=self.app;app.world=mode.world;app.view=mode.view;app.previous=mode.previous;app.sprites=mode.sprites
    app.accumulator=self.accumulator;app.effects={};app.feedback=mode.feedback;app.options['effects-disabled']=mode.name=='diagnostic-fallback-effects-disabled';app.camera.zoom=zoom
    local width,height=love.graphics.getDimensions()
    app.camera.x=(width-266)/2-23*26*zoom
    app.camera.y=(height-130+84)/2-17*26*math.sin(math.pi/3)*zoom
end
function P:screenshot(name)
    if self.screenshots[name] then return end
    self.screenshots[name]=true;self.pendingShots=self.pendingShots+1
    love.graphics.captureScreenshot(function(data)
        write('artifacts/asset-presentation-'..name..'.png',data:encode('png'):getString())
        self.pendingShots=self.pendingShots-1
    end)
end
function P:draw()
    if self.finished then return end
    if self.benchmark then
        self:bind(self.modes[1],1)
        local before=now();self.app:draw();self.drawTimes[#self.drawTimes+1]=(now()-before)*1000
        self.lastStats=love.graphics.getStats()
        self.maxTextureMemory=math.max(self.maxTextureMemory or 0,self.lastStats.texturememory or 0)
        return
    end
    local tick=self.modes[1].world.tick;local zoom=tick<40 and 0.75 or tick<80 and 1 or 1.25
    if tick>=self.ticks then
        self.viewer:draw();self:screenshot('viewer');return
    end
    local beforeDraw=self.checkedDrawTick~=tick and Sim.serializeCanonical(self.modes[1].world) or nil
    self:bind(self.modes[1],zoom)
    local start=now();self.app:draw();self.drawTimes[#self.drawTimes+1]=(now()-start)*1000
    local stats=love.graphics.getStats();self.lastStats=stats
    self.maxTextureMemory=math.max(self.maxTextureMemory or 0,stats.texturememory or 0)
    if tick>=20 and tick<40 then self:screenshot('zoom075') elseif tick>=60 and tick<80 then self:screenshot('zoom100') elseif tick>=100 then self:screenshot('zoom125') end
    local g=love.graphics;g.push('all');g.setCanvas(self.canvas)
    for i=2,3 do self:bind(self.modes[i],zoom);self.app:draw() end
    g.pop();self:bind(self.modes[1],zoom)
    -- Check after actual draw calls, including legacy/placeholder paths, once per tick.
    if self.checkedDrawTick~=tick then
        for i=1,3 do assert(Sim.serializeCanonical(self.modes[i].world)==beforeDraw,'draw mutated simulation') end
        self.checkedDrawTick=tick
    end
end
function P:finishBenchmark()
    assert(#self.modes==1 and not self.canvas and not self.viewer,'benchmark comparison objects leaked')
    assert(#self.tickTimes==self.ticks and self.comparisons==0,'incomplete benchmark or unexpected comparisons')
    assert(self.attacks>0 and self.movingTicks>0,'benchmark did not move and fight')
    local renderer,version,vendor,device=love.graphics.getRendererInfo()
    local width,height=love.graphics.getDimensions();local _,_,flags=love.window.getMode()
    local stats=self.lastStats or {};local living={0,0}
    for _,e in pairs(self.modes[1].world.entities) do if e.alive and e.category=='unit' and living[e.owner] then living[e.owner]=living[e.owner]+1 end end
    local lines={
        'Standalone v2 asset benchmark: COMPLETED',
        'Scenario: 60 mobile units per player at start; 2 Bastion players; actual attack-move movement/combat; original gameplay stats; no replenishment.',
        string.format('Remaining mobile units: %d vs %d',living[1],living[2]),
        'Workload: one v2 world, 1x zoom, actual App HUD/fog/selection/shadows and visible combat feedback.',
        'Excluded: legacy images, comparison worlds/canvas, snapshots, canonical serialization/hashing, viewer, screenshots, audio, replay recording and bots.',
        'Timing: Sim.step and App.draw CPU elapsed; draw submission time is NOT GPU frame time.',
        'Actual update cadence includes vsync, driver/presentation waits, simulation, visibility, feedback, drawing and normal runtime overhead; it is not a GPU timer.',
        'Startup asset loading excluded from cadence; first draw and normal Lua garbage collection remain included. No warmup frames removed.',
        string.format('Samples: %d ticks; %d drawn frames; %d cadence intervals; %d attack events; %d moving ticks',#self.tickTimes,#self.drawTimes,#self.cadence,self.attacks,self.movingTicks),
        string.format('Sim.step CPU: p95 %.3f ms; max %.3f ms',percentile(self.tickTimes,0.95),percentile(self.tickTimes,1)),
        string.format('App.draw CPU submission: p95 %.3f ms; max %.3f ms',percentile(self.drawTimes,0.95),percentile(self.drawTimes,1)),
        string.format('Actual update cadence: p50 %.3f ms; p95 %.3f ms; max %.3f ms',percentile(self.cadence,0.5),percentile(self.cadence,0.95),percentile(self.cadence,1)),
        string.format('Elapsed: %.3f s; simulated: %.3f s; discarded dt above 250ms: %.3f s; max pre-step accumulator: %.3f s',now()-self.started,self.ticks*0.05,self.droppedSeconds,self.maxBacklog),
        string.format('Lua heap KiB: before %.1f, after %.1f; peak sampled texture memory bytes: %d',self.memoryBefore,collectgarbage('count'),self.maxTextureMemory or 0),
        string.format('Last draw stats: drawcalls %s; images %s; canvases %s',tostring(stats.drawcalls),tostring(stats.images),tostring(stats.canvases)),
        string.format('Display: %dx%d; zoom 1x; vsync %s; LOVE %s; OS %s',width,height,tostring(flags.vsync),tostring(love.getVersion()),love.system.getOS()),
        'Renderer: '..table.concat({renderer,version,vendor,device},' | '),
        'CPU environment: '..tostring(os.getenv('PROCESSOR_IDENTIFIER')),
        'Run with Blender and other heavy workloads stopped. This harness does not detect external CPU/GPU contention.',
        'Completion confirms measured scenario execution, not a claim that performance targets passed. Human playtesting and cross-PC validation remain separate.'}
    local report=table.concat(lines,'\n')..'\n';write('artifacts/asset-benchmark-report.txt',report);print(report)
    self.finished=true;love.event.quit(0)
end
function P:finish()
    assert(self.attacks>0,'fixture never fought');assert(self.movingTicks>0,'fixture never moved')
    assert(self.comparisons==self.ticks,'incomplete playback comparison')
    local renderer,version,vendor,device=love.graphics.getRendererInfo()
    local stats=self.lastStats or {};local width,height=love.graphics.getDimensions()
    local lines={
        'Asset presentation verification: PASS',
        'Scenario: 60 mobile units per player at start; 2 Bastion players; shared attack-move commands; real movement and combat; losses are not replenished.',
        'Scopes: v2 on-screen App.draw with real HUD/fog/selection/shadows; v1 adapter and diagnostic fallback drawn off-screen every frame.',
        'Effects: actual feedback module observed and drawn for v2/v1; effects disabled for diagnostic fallback. Audio is outside this harness.',
        'Timing: CPU elapsed around Sim.step and v2 App.draw submission only. Draw timing is NOT GPU frame time or FPS.',
        'Frame cadence includes three simulations, offscreen comparison draws, serialization, screenshots, and vsync; NOT a release performance benchmark.',
        string.format('Samples: %d ticks, %d rendered frames, %d attack events, %d moving ticks, %d canonical comparisons',#self.tickTimes,#self.drawTimes,self.attacks,self.movingTicks,self.comparisons),
        string.format('Sim.step CPU: p95 %.3f ms; max %.3f ms',percentile(self.tickTimes,0.95),percentile(self.tickTimes,1)),
        string.format('v2 draw submission CPU: p95 %.3f ms; max %.3f ms',percentile(self.drawTimes,0.95),percentile(self.drawTimes,1)),
        string.format('Instrumented update cadence: p95 %.3f ms; elapsed %.2f s',percentile(self.cadence,0.95),now()-self.started),
        string.format('Lua heap KiB: before %.1f, after %.1f; peak sampled texture/canvas bytes: %d',self.memoryBefore,collectgarbage('count'),self.maxTextureMemory or 0),
        'Memory scope includes both asset generations and offscreen comparison canvas; not standalone v2 memory.',
        string.format('Last v2 submitted draw stats: drawcalls %s; images %s; canvases %s',tostring(stats.drawcalls),tostring(stats.images),tostring(stats.canvases)),
        string.format('Display: %dx%d; LOVE %s; OS %s',width,height,tostring(love.getVersion()),love.system.getOS()),
        'Renderer: '..table.concat({renderer,version,vendor,device},' | '),
        'CPU environment: '..tostring(os.getenv('PROCESSOR_IDENTIFIER')),
        'Canonical final SHA256: '..Hash.bytes(Sim.serializeCanonical(self.modes[1].world)),
        'Asset checks: all five loaded; complete cargo clip duration/phase/anchor agreement; viewer unit/clip/direction and controls exercised.',
        'Screenshots: artifacts/asset-presentation-zoom075.png, zoom100.png, zoom125.png, viewer.png (same prefix).',
        'Human motion/silhouette review and cross-PC validation remain separate.'}
    local report=table.concat(lines,'\n')..'\n';write('artifacts/asset-presentation-report.txt',report);print(report)
    self.finished=true;love.event.quit(0)
end
P.fixture=fixture -- read-only test entry point for the fixed initial scenario
function P:keypressed() end
function P:mousepressed() end
function P:mousereleased() end
function P:wheelmoved() end
return P





