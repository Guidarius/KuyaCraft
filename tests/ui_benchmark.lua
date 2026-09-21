local Sim=require('src.sim');local Codec=require('src.sim.codec')
local Replay=require('src.replay');local Minimap=require('src.ui.minimap')
local B={}
local function percentile(a,p) local s={};for i,v in ipairs(a) do s[i]=v end;table.sort(s);return s[math.max(1,math.ceil(#s*p))] or 0 end
-- Sim.step is only part of what a rendered tick costs. Every phase below runs
-- once per tick in a real match, so each is timed separately: a p95 that only
-- covers the simulation hides the view copy, the observation memory and hashing.
local PHASES={'step','view','events','feedback','replay'}
local function distribution(name,values)
 return string.format('DIST %s p50 %.6f p95 %.6f p99 %.6f max %.6f',name,percentile(values,.5),percentile(values,.95),percentile(values,.99),percentile(values,1))
end
function B.create(options)
 if options['benchmark-vsync'] then
  local vsync=assert(tonumber(options['benchmark-vsync']));assert(vsync==0 or vsync==1)
  love.window.setVSync(vsync) -- Diagnostic only; acceptance runs leave the default untouched.
 end
 local shippingContent=options['balance-benchmark'] or options.map=='twin_marches'
 -- The fixture battle is built from the mechanics fixture, so the app plays that content too.
 local app=require('src.app').create({map='open_fields',settings=Codec.copy(require('src.ui.settings').defaults),content=not shippingContent and require('tests.fixture_content') or nil})
 -- --map twin_marches selects the shipping 192x192 map. stressWorld already
 -- deploys 240 units on it with the battle clearings widened, so it is the
 -- shipping-map variant of this benchmark rather than a second fixture.
 local shipping=options['balance-benchmark'] or options.map=='twin_marches'
 local w=shipping and require('tests.balance_scenarios').stressWorld(tonumber(options['ui-units']),options['benchmark-faction']) or require('tests.asset_presentation').fixture()
 if options['require-assets'] then
  for _,id in ipairs({'associate','medic','enforcer','command_blimp','battleship','drop_pod','orbital_command','mc_barracks','bunker','crossbow'}) do
   assert(app.sprites and app.sprites.units[id],'benchmark requires active asset '..id)
  end
  assert(#app.sprites.diagnostics==0,'benchmark asset diagnostics')
 end
 if not shipping then for player=1,2 do
  local units={};local template
  for _,id in ipairs(w.order) do local e=w.entities[id];if e.owner==player and e.category=='unit' then units[#units+1]=e;if e.kind=='shield' then template=e end end end
  while #units<120 do local e=Codec.copy(template);e.id=w.nextId;w.nextId=w.nextId+1;w.entities[e.id]=e;w.order[#w.order+1]=e.id;units[#units+1]=e end
  for i,e in ipairs(units) do e.x=((player==1 and 14 or 25)+(i-1)%10)*256+128;e.y=(10+math.floor((i-1)/10))*256+128 end
 end
 end
 app.balanceBenchmark=shipping;app.world=w;app.player=options['benchmark-faction']=='megacorp' and 2 or 1;app.view=Sim.view(w,app.player);app.selected={};app.observation=require('src.ui.observation').create();app.observation:update(app.view)
 app.feedback:reset();app.juice:reset();app.previous={};app.settings.gameSpeed=2;app.settings.edgeScroll=false;app.settings.dayNight=false;app.noAutoSave=true;app.recording=Replay.create(w.config,app.content,w.map,Replay.OFFLINE_INTERVAL);app.sidebar=require('src.ui.orbital').active(app.view,app.content);require('src.ui.camera').center(app,(app.balanceBenchmark and 96 or 24)*256,(app.balanceBenchmark and 96 or 16)*256)
 local self=setmetatable({app=app,times={},drawTimes={},minimapTimes={},tickTimes={},cadence={},steps=0,frames=0,attacks=0,accumulator=0,
  target=tonumber(options['ui-samples']) or 600,start=love.timer.getTime(),initial=collectgarbage('count'),
  maxParticles=0,maxJuice=0,maxSources=0,clampedTime=0,frameBudget=tonumber(options['frame-budget']) or (1000/60),simBudget=tonumber(options['perf-budget']) or 10,maxBacklog=0,maxDrawCalls=0,drawCalls={},heapSamples={}},{__index=B})
 self.phase={};for _,name in ipairs(PHASES) do self.phase[name]={} end
 app.tickCommands=function(a,tick)
  local commands={};local phase=(tick-1)%400
  if phase==0 or phase==300 then
   for _,id in ipairs(a.world.order) do local e=a.world.entities[id]
    if e.alive and e.category=='unit' and e.owner>0 then
     local attack=phase==0
     local x=a.balanceBenchmark and (attack and (e.owner==1 and 98 or 94) or (e.owner==1 and 87 or 104)) or (e.owner==1 and 30 or 18)
     commands[#commands+1]={player=e.owner,kind=attack and 'attack_move' or 'move',args={entity=id,x=x*256+128,y=(a.balanceBenchmark and 96 or 17)*256+128,group=tick}}
    end
   end
  end
  return commands
 end
 -- Keep a representative army selected, so selection/card costs are measured too.
 for _,e in ipairs(app.view.entities) do if e.alive and e.owner==app.player and e.category=='unit' and #app.selected<24 then app.selected[#app.selected+1]=e.id end end
 app.onStep=function(a,perf,events)
  for _,name in ipairs(PHASES) do local list=self.phase[name];list[#list+1]=perf[name] end
  self.times[#self.times+1]=perf.step;self.tickTimes[#self.tickTimes+1]=perf.total
  for _,ev in ipairs(events) do if ev.kind=='attack' then self.attacks=self.attacks+1 end end
  self.steps=self.steps+1;self.heapSamples[#self.heapSamples+1]=collectgarbage('count')
  assert(a.juice.tick==a.world.tick,'benchmark bypassed live effects observation')
  assert(#a.recording.frames==a.world.tick,'benchmark bypassed live recording')
  if self.steps>=self.target then a.accumulator=0 end
 end
 self.stopProfile=options['profile-sim'] and require('tests.sim_profile').start(options['profile-sim'])
 return self
end
function B:update(dt)
 if self.done then return end
 if self.frames==0 then self.start=love.timer.getTime();dt=0 else self.cadence[#self.cadence+1]=dt*1000 end
 self.maxBacklog=math.max(self.maxBacklog,self.app.accumulator+dt)
 self.clampedTime=self.clampedTime+math.max(0,dt-.25)
 self.app:update(dt)
 self.maxParticles=math.max(self.maxParticles,#self.app.feedback.items)
 self.maxJuice=math.max(self.maxJuice,#self.app.juice.particles)
 self.maxSources=math.max(self.maxSources,#self.app.audio.pool)
 assert(self.maxParticles<=256 and self.maxJuice<=384 and self.maxSources<=32)
 if self.steps>=self.target then
  if self.stopProfile then self.stopProfile();self.stopProfile=nil end
  local elapsed=love.timer.getTime()-self.start
  local heapGrowth=(self.heapSamples[#self.heapSamples]-self.heapSamples[1])/1024
  local live=0;for _,id in ipairs(self.app.world.order) do local e=self.app.world.entities[id];if e.alive and e.category=='unit' then live=live+1 end end
  local width,height=love.graphics.getDimensions()
  local lines={string.format('UI active battle: %d units now; 2 players; %dx%d; minimap, sprites, fog, effects and audio enabled\nTicks %d; frames %d; attacks observed %d; elapsed %.3fs',live,width,height,self.steps,self.frames,self.attacks,elapsed)}
  lines[#lines+1]=distribution('whole_tick_ms',self.tickTimes)
  lines[#lines+1]=distribution('frame_ms',self.cadence)
  lines[#lines+1]=distribution('draw_ms',self.drawTimes)
  lines[#lines+1]=distribution('draw_calls',self.drawCalls)
  lines[#lines+1]=distribution('sampled_heap_kib',self.heapSamples)
  for _,name in ipairs(PHASES) do lines[#lines+1]=distribution(name..'_ms',self.phase[name]) end
  local renderer,version,vendor,device=love.graphics.getRendererInfo()
  local stats=love.graphics.getStats()
  lines[#lines+1]='VSYNC '..love.window.getVSync()
  lines[#lines+1]=string.format('RENDERER %s | %s | %s | %s',renderer,version,vendor,device)
  lines[#lines+1]=string.format('TEXTURE_BYTES %d; IMAGES %d; CANVASES %d',stats.texturememory,stats.images,stats.canvases)
  lines[#lines+1]='AUTHORITATIVE_BUILD '..require('src.build').fingerprint()
  lines[#lines+1]='ASSET_CATALOG '..require('src.hash').bytes(love.filesystem.read('assets/generated/catalog.lua') or '')
  for tick=1,self.app.world.tick do
   local hash=self.app.recording.hashes[tick]
   if hash then lines[#lines+1]='CHECKPOINT '..tick..' '..hash end
  end
  lines[#lines+1]='CHECKPOINT '..self.app.world.tick..' '..require('src.hash').bytes(Sim.serializeAuthoritative(self.app.world))
  lines[#lines+1]=string.format('Whole tick path p95 %.3f ms; max %.3f ms',percentile(self.tickTimes,.95),percentile(self.tickTimes,1))
  for _,name in ipairs(PHASES) do
   lines[#lines+1]=string.format('  %-12s p95 %7.3f ms; max %7.3f ms',name,percentile(self.phase[name],.95),percentile(self.phase[name],1))
  end
  lines[#lines+1]=string.format('Draw submission p95 %.3f ms; cadence p95 %.3f ms; minimap cache p95 %.3f ms',percentile(self.drawTimes,.95),percentile(self.cadence,.95),percentile(self.minimapTimes,.95))
  lines[#lines+1]=string.format('Draw calls p95 %d; max %d',percentile(self.drawCalls,.95),self.maxDrawCalls)
  lines[#lines+1]=string.format('Maximum pre-step backlog %.3fs; frame time clamped %.3fs; discarded backlog ticks %d',self.maxBacklog,self.clampedTime,self.app.discardedTicks or 0)
  lines[#lines+1]=string.format('Peak feedback %d / 256; juice particles %d / 384; allocated source slots %d / 32; minimap canvases 2',self.maxParticles,self.maxJuice,self.maxSources)
  lines[#lines+1]=string.format('Lua heap initial %.0f KiB; final %.0f KiB; growth %.2f MiB over %.1fs (%.2f MiB / 30s)',self.initial,collectgarbage('count'),heapGrowth,elapsed,heapGrowth*30/math.max(elapsed,.001))
  lines[#lines+1]='Runs App:update and App:draw, including selection, hover, juice, audio and replay recording. Scripted commands replace the bot; network excluded. CPU draw submission is not GPU time.'
  local passed=percentile(self.times,.95)<self.simBudget and percentile(self.cadence,.95)<=self.frameBudget;lines[#lines+1]=string.format('GATE %s: simulation p95 < %.3fms; frame p95 <= %.3fms',passed and 'PASS' or 'FAIL',self.simBudget,self.frameBudget);local report=table.concat(lines,'\n')..'\n'
  local f=assert(io.open(self.app.balanceBenchmark and 'artifacts/balance-ui-benchmark.txt' or 'artifacts/ui-benchmark.txt','wb'));f:write(report);f:close();print(report);self.done=true;love.event.quit(passed and 0 or 1)
 end
end
function B:draw()
 -- Priming the minimap cache here times fog rebuilds on their own; the call
 -- inside App:draw then finds the same signature and returns immediately.
 local mini=love.timer.getTime();Minimap.cache(self.app);self.minimapTimes[#self.minimapTimes+1]=(love.timer.getTime()-mini)*1000
 local begin=love.timer.getTime();self.app:draw();self.drawTimes[#self.drawTimes+1]=(love.timer.getTime()-begin)*1000;self.frames=self.frames+1
 local calls=love.graphics.getStats().drawcalls
 self.drawCalls[#self.drawCalls+1]=calls;self.maxDrawCalls=math.max(self.maxDrawCalls,calls)
 if self.steps>=120 and not self.shot then self.shot=true;love.graphics.captureScreenshot(function(data) local f=assert(io.open(self.app.balanceBenchmark and 'artifacts/balance-ui-battle.png' or 'artifacts/ui-battle.png','wb'));f:write(data:encode('png'):getString());f:close() end) end
end
function B:keypressed() end
function B:mousepressed() end
return B
