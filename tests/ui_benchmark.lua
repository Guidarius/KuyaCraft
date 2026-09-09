local Sim=require('src.sim');local Codec=require('src.sim.codec');local C=require('src.content')
local B={}
local function percentile(a,p) local s={};for i,v in ipairs(a) do s[i]=v end;table.sort(s);return s[math.max(1,math.ceil(#s*p))] or 0 end
function B.create(options)
 local app=require('src.app').create({map='open_fields'})
 local w=options['balance-benchmark'] and require('tests.balance_scenarios').stressWorld() or require('tests.asset_presentation').fixture()
 if not options['balance-benchmark'] then for player=1,2 do
  local units={};local template
  for _,id in ipairs(w.order) do local e=w.entities[id];if e.owner==player and e.category=='unit' then units[#units+1]=e;if e.kind=='shield' then template=e end end end
  while #units<120 do local e=Codec.copy(template);e.id=w.nextId;w.nextId=w.nextId+1;w.entities[e.id]=e;w.order[#w.order+1]=e.id;units[#units+1]=e end
  for i,e in ipairs(units) do e.x=((player==1 and 14 or 25)+(i-1)%10)*256+128;e.y=(10+math.floor((i-1)/10))*256+128 end
 end
 end
 app.balanceBenchmark=options['balance-benchmark'];app.world=w;app.view=Sim.view(w,1);app.selected={w.players[1].hero};app.observation=require('src.ui.observation').create();app.observation:update(app.view)
 app.feedback:reset();app.previous={};require('src.ui.camera').center(app,(app.balanceBenchmark and 64 or 24)*256,(app.balanceBenchmark and 53 or 16)*256)
 return setmetatable({app=app,times={},drawTimes={},cadence={},steps=0,frames=0,attacks=0,accumulator=0,target=tonumber(options['ui-samples']) or 600,start=love.timer.getTime(),initial=collectgarbage('count'),maxParticles=0,maxSources=0,maxBacklog=0},{__index=B})
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
   sequence[e.owner]=sequence[e.owner]+1;commands[#commands+1]={tick=1,player=e.owner,sequence=sequence[e.owner],kind='attack_move',args={entity=id,x=(app.balanceBenchmark and (e.owner==1 and 66 or 62) or (e.owner==1 and 30 or 18))*256+128,y=(app.balanceBenchmark and 53 or 17)*256+128}}
  end end end
  app.previous={};for _,e in ipairs(app.view.entities) do app.previous[e.id]={x=e.x,y=e.y} end
  local begin=love.timer.getTime();Sim.step(app.world,commands);self.times[#self.times+1]=(love.timer.getTime()-begin)*1000
  app.view=Sim.view(app.world,1);app.observation:update(app.view)
  local events=Sim.eventsFor(app.world,1);app.feedback:observe(events,app.view,app.world.tick);app.alerts:observe(events,app);if app.sprites then app.sprites:observe(events,app.view,app.world.tick) end
  for _,v in ipairs(events) do if v.kind=='attack' then self.attacks=self.attacks+1;app.audio:play('attack',app,v.x,v.y) elseif v.kind=='death' then app.audio:play('death',app,v.x,v.y) end end
  self.steps=self.steps+1;self.accumulator=self.accumulator-.05;count=count+1
 end
 self.app.accumulator=self.accumulator;self.maxParticles=math.max(self.maxParticles,#self.app.feedback.items);self.maxSources=math.max(self.maxSources,#self.app.audio.pool)
 assert(self.maxParticles<=256 and self.maxSources<=32)
 if self.steps>=self.target then
  local report=string.format('UI active battle (see invocation for profile/map): 240 units initially; 2 players; 1080p; minimap, sprites, fog, effects and audio enabled\nTicks %d; frames %d; attacks observed %d; elapsed %.3fs\nSimulation p95 %.3f ms; max %.3f ms\nDraw submission p95 %.3f ms; cadence p95 %.3f ms\nMaximum pre-step backlog %.3fs; no discarded dt\nPeak effects %d / 256; allocated source slots %d / 32; minimap canvases 2\nLua heap initial %.0f KiB; final %.0f KiB\nExcludes bots, replay recording and network; losses are not replenished. CPU draw submission is not GPU time.\n',self.steps,self.frames,self.attacks,love.timer.getTime()-self.start,percentile(self.times,.95),percentile(self.times,1),percentile(self.drawTimes,.95),percentile(self.cadence,.95),self.maxBacklog,self.maxParticles,self.maxSources,self.initial,collectgarbage('count'))
  local f=assert(io.open(self.app.balanceBenchmark and 'artifacts/balance-ui-benchmark.txt' or 'artifacts/ui-benchmark.txt','wb'));f:write(report);f:close();print(report);self.done=true;love.event.quit(0)
 end
end
function B:draw()
 local begin=love.timer.getTime();self.app:draw();self.drawTimes[#self.drawTimes+1]=(love.timer.getTime()-begin)*1000;self.frames=self.frames+1
 if self.steps>=120 and not self.shot then self.shot=true;love.graphics.captureScreenshot(function(data) local f=assert(io.open(self.app.balanceBenchmark and 'artifacts/balance-ui-battle.png' or 'artifacts/ui-battle.png','wb'));f:write(data:encode('png'):getString());f:close() end) end
end
function B:keypressed() end
function B:mousepressed() end
return B
