local Sim=require('src.sim');local Codec=require('src.sim.codec')
local Replay=require('src.replay');local Minimap=require('src.ui.minimap')
local B={}
local function percentile(a,p) local s={};for i,v in ipairs(a) do s[i]=v end;table.sort(s);return s[math.max(1,math.ceil(#s*p))] or 0 end
-- Sim.step is only part of what a rendered tick costs. Every phase below runs
-- once per tick in a real match, so each is timed separately: a p95 that only
-- covers the simulation hides the view copy, the observation memory and hashing.
local PHASES={'step','view','observation','events','feedback','replay'}
function B.create(options)
 local shippingContent=options['balance-benchmark'] or options.map=='twin_marches'
 -- The fixture battle is built from the mechanics fixture, so the app plays that content too.
 local app=require('src.app').create({map='open_fields',content=not shippingContent and require('tests.fixture_content') or nil})
 -- --map twin_marches selects the shipping 192x192 map. stressWorld already
 -- deploys 240 units on it with the battle clearings widened, so it is the
 -- shipping-map variant of this benchmark rather than a second fixture.
 local shipping=options['balance-benchmark'] or options.map=='twin_marches'
 local w=shipping and require('tests.balance_scenarios').stressWorld(tonumber(options['ui-units'])) or require('tests.asset_presentation').fixture()
 if not shipping then for player=1,2 do
  local units={};local template
  for _,id in ipairs(w.order) do local e=w.entities[id];if e.owner==player and e.category=='unit' then units[#units+1]=e;if e.kind=='shield' then template=e end end end
  while #units<120 do local e=Codec.copy(template);e.id=w.nextId;w.nextId=w.nextId+1;w.entities[e.id]=e;w.order[#w.order+1]=e.id;units[#units+1]=e end
  for i,e in ipairs(units) do e.x=((player==1 and 14 or 25)+(i-1)%10)*256+128;e.y=(10+math.floor((i-1)/10))*256+128 end
 end
 end
 app.balanceBenchmark=shipping;app.world=w;app.view=Sim.view(w,1);app.selected={w.players[1].hero};app.observation=require('src.ui.observation').create();app.observation:update(app.view)
 app.feedback:reset();app.previous={};require('src.ui.camera').center(app,(app.balanceBenchmark and 96 or 24)*256,(app.balanceBenchmark and 96 or 16)*256)
 local self=setmetatable({app=app,times={},drawTimes={},minimapTimes={},tickTimes={},cadence={},steps=0,frames=0,attacks=0,accumulator=0,
  target=tonumber(options['ui-samples']) or 600,start=love.timer.getTime(),initial=collectgarbage('count'),
  maxParticles=0,maxSources=0,maxBacklog=0,maxDrawCalls=0,drawCalls={},heapSamples={},
  recording=Replay.create(w.config,app.content,w.map,Replay.OFFLINE_INTERVAL)},{__index=B})
 self.phase={};for _,name in ipairs(PHASES) do self.phase[name]={} end
 return self
end
function B:update(dt)
 if self.done then return end
 if self.frames==0 then self.start=love.timer.getTime();dt=0 else self.cadence[#self.cadence+1]=dt*1000 end
 self.app.clock=self.app.clock+dt;self.app.audio:update(dt);self.app.alerts:update(dt);self.app.feedback:update(dt)
 self.accumulator=self.accumulator+dt;self.maxBacklog=math.max(self.maxBacklog,self.accumulator)
 local count=0
 while self.accumulator>=.05 and count<8 and self.steps<self.target do
  local app=self.app;local commands={}
  if self.steps==0 then local sequence={0,0};for _,id in ipairs(app.world.order) do local e=app.world.entities[id];if e.category=='unit' and e.owner>0 then
   sequence[e.owner]=sequence[e.owner]+1;commands[#commands+1]={tick=1,player=e.owner,sequence=sequence[e.owner],kind='attack_move',args={entity=id,x=(app.balanceBenchmark and (e.owner==1 and 98 or 94) or (e.owner==1 and 30 or 18))*256+128,y=(app.balanceBenchmark and 96 or 17)*256+128}}
  end end end
  app.previous={};for _,e in ipairs(app.view.entities) do app.previous[e.id]={x=e.x,y=e.y} end
  local tickStart=love.timer.getTime();local mark=tickStart
  local function lap(name) local now=love.timer.getTime();local list=self.phase[name];list[#list+1]=(now-mark)*1000;mark=now end
  Sim.step(app.world,commands);lap('step')
  self.times[#self.times+1]=self.phase.step[#self.phase.step]
  app.view=Sim.view(app.world,1);lap('view')
  app.observation:update(app.view);lap('observation')
  local events=Sim.eventsFor(app.world,1);lap('events')
  app.feedback:observe(events,app.view,app.world.tick);app.alerts:observe(events,app);if app.sprites then app.sprites:observe(events,app.view,app.world.tick) end;lap('feedback')
  -- Offline matches always record; the periodic canonical hash inside is part of
  -- the tick cost a player actually pays, so it belongs in this measurement.
  Replay.record(self.recording,app.world,commands);lap('replay')
  self.tickTimes[#self.tickTimes+1]=(love.timer.getTime()-tickStart)*1000
  for _,v in ipairs(events) do if v.kind=='attack' then self.attacks=self.attacks+1;app.audio:play('attack',app,v.x,v.y) elseif v.kind=='death' then app.audio:play('death',app,v.x,v.y) end end
  self.steps=self.steps+1;self.accumulator=self.accumulator-.05;count=count+1
  self.heapSamples[#self.heapSamples+1]=collectgarbage('count')
 end
 self.app.accumulator=self.accumulator;self.maxParticles=math.max(self.maxParticles,#self.app.feedback.items);self.maxSources=math.max(self.maxSources,#self.app.audio.pool)
 assert(self.maxParticles<=256 and self.maxSources<=32)
 if self.steps>=self.target then
  local elapsed=love.timer.getTime()-self.start
  local heapGrowth=(self.heapSamples[#self.heapSamples]-self.heapSamples[1])/1024
  local live=0;for _,id in ipairs(self.app.world.order) do local e=self.app.world.entities[id];if e.alive and e.category=='unit' then live=live+1 end end
  local lines={string.format('UI active battle (see invocation for profile/map): %d units now; 2 players; 1080p; minimap, sprites, fog, effects and audio enabled\nTicks %d; frames %d; attacks observed %d; elapsed %.3fs',live,self.steps,self.frames,self.attacks,elapsed)}
  lines[#lines+1]=string.format('Whole tick path p95 %.3f ms; max %.3f ms',percentile(self.tickTimes,.95),percentile(self.tickTimes,1))
  for _,name in ipairs(PHASES) do
   lines[#lines+1]=string.format('  %-12s p95 %7.3f ms; max %7.3f ms',name,percentile(self.phase[name],.95),percentile(self.phase[name],1))
  end
  lines[#lines+1]=string.format('Draw submission p95 %.3f ms; cadence p95 %.3f ms; minimap cache p95 %.3f ms',percentile(self.drawTimes,.95),percentile(self.cadence,.95),percentile(self.minimapTimes,.95))
  lines[#lines+1]=string.format('Draw calls p95 %d; max %d',percentile(self.drawCalls,.95),self.maxDrawCalls)
  lines[#lines+1]=string.format('Maximum pre-step backlog %.3fs; no discarded dt',self.maxBacklog)
  lines[#lines+1]=string.format('Peak effects %d / 256; allocated source slots %d / 32; minimap canvases 2',self.maxParticles,self.maxSources)
  lines[#lines+1]=string.format('Lua heap initial %.0f KiB; final %.0f KiB; growth %.2f MiB over %.1fs (%.2f MiB / 30s)',self.initial,collectgarbage('count'),heapGrowth,elapsed,heapGrowth*30/math.max(elapsed,.001))
  lines[#lines+1]='Includes replay recording (with its periodic canonical hash). Excludes bots and network; losses are not replenished. CPU draw submission is not GPU time.'
  local report=table.concat(lines,'\n')..'\n'
  local f=assert(io.open(self.app.balanceBenchmark and 'artifacts/balance-ui-benchmark.txt' or 'artifacts/ui-benchmark.txt','wb'));f:write(report);f:close();print(report);self.done=true;love.event.quit(0)
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
