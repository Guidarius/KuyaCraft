-- Long production/combat run using normal bot commands, with explicit evidence
-- of replacements, restore equivalence, and fresh replay equivalence.
local Sim=require('src.sim')
local Content=require('src.content')
local Maps=require('src.maps')
local Bot=require('src.bot')
local Replay=require('src.replay')
local Hash=require('src.hash')
local T={}
function T.run()
 local config={seed=725,players={{faction='orders'},{faction='megacorp'}}}
 local map=Maps.create();local w=Sim.create(config,Content,map)
 local replay=Replay.create(config,Content,map,500)
 local deaths,recruits,replacements,constructed,attacks={0,0},{0,0},{0,0},{0,0},0
 local checkpoints={};local lines={};local function log(s) lines[#lines+1]=s;print(s) end
 collectgarbage('collect');local initial=collectgarbage('count');local retained={}
 for tick=1,12000 do
  assert(not w.result,'soak match ended early at '..w.tick)
  local commands={}
  if w.tick%20==0 then for p=1,2 do
   local sequence=w.players[p].sequence
   for _,c in ipairs(Bot.commands(Sim.view(w,p),Content)) do
    sequence=sequence+1;c.tick=tick;c.player=p;c.sequence=sequence;commands[#commands+1]=c
   end
  end end
  local oldCount=#w.order
  Sim.step(w,commands);Replay.record(replay,w,commands)
  -- Megacorp pod arrivals spawn units without the barracks recruited event.
  -- Count actual newly created unit bodies for both production paths.
  for index=oldCount+1,#w.order do local e=w.entities[w.order[index]]
   if e.category=='unit' and e.owner>0 then
    local p=e.owner;recruits[p]=recruits[p]+1
    if deaths[p]>0 then replacements[p]=replacements[p]+1 end
   end
  end
  assert(w.metrics.pathExpansions<=Content.rules.pathBudget and w.metrics.directChecks<=Content.rules.directPathBudget,'search budget exceeded')
  for _,ev in ipairs(w.events) do
   if ev.kind=='attack' then attacks=attacks+1
   elseif ev.entity then local e=w.entities[ev.entity];local p=e and e.owner
    if p and p>0 then
     if ev.kind=='death' and e.category=='unit' then deaths[p]=deaths[p]+1
     elseif ev.kind=='constructed' then constructed[p]=constructed[p]+1 end
    end
   end
  end
  if tick==4000 or tick==8000 then
   local before=Sim.serializeCanonical(w);w=Sim.restore(Sim.snapshot(w))
   assert(Sim.serializeCanonical(w)==before,'snapshot restore changed canonical state')
   log('RESTORE '..tick..' exact canonical match')
  end
  if tick%500==0 then checkpoints[tick]=Hash.bytes(Sim.serializeCanonical(w)) end
  if tick%1200==0 then
   local before=collectgarbage('count');collectgarbage('collect');local after=collectgarbage('count');retained[#retained+1]=after
   log(string.format('MEMORY tick %d retained_kib %.1f temporary_reclaimed_kib %.1f entities %d replay_frames %d',tick,after,before-after,#w.order,#replay.frames))
  end
 end
 for p=1,2 do
  log(string.format('P%d constructed %d units_produced %d unit_deaths %d units_produced_after_first_death %d',p,constructed[p],recruits[p],deaths[p],replacements[p]))
  assert(deaths[p]>0 and recruits[p]>0 and replacements[p]>0 and constructed[p]>0,'soak did not exercise P'..p..' production/death/replacement')
 end
 assert(attacks>100,'soak did not exercise sustained combat')
 Replay.write('artifacts/overnight-soak.replay',replay)
 local decoded=Replay.read('artifacts/overnight-soak.replay',Content)
 local playback=Sim.create(decoded.header.config,Content,decoded.header.map)
 for _,frame in ipairs(decoded.frames) do
  Sim.step(playback,frame.commands)
  if checkpoints[playback.tick] then
   assert(Hash.bytes(Sim.serializeCanonical(playback))==checkpoints[playback.tick],'fresh replay canonical mismatch at '..playback.tick)
   assert(Hash.bytes(Sim.serializeAuthoritative(playback))==decoded.hashes[playback.tick],'recorded replay hash mismatch at '..playback.tick)
  end
 end
 assert(Sim.serializeCanonical(playback)==Sim.serializeCanonical(w),'final replay mismatch')
 log('SOAK PASS 12000 ticks; 24 fresh replay checkpoints; restores at 4000 and 8000; attacks '..attacks)
 log(string.format('Retained Lua heap initial %.1f KiB; live world + recording at tick12000 %.1f KiB. Includes intentional entity history and replay frames; temporary reclamation reported separately.',initial,retained[#retained]))
 w=nil;playback=nil;replay=nil;decoded=nil;collectgarbage('collect');collectgarbage('collect')
 log(string.format('After releasing worlds and recordings %.1f KiB; delta from initial %.1f KiB (module/JIT caches remain).',collectgarbage('count'),collectgarbage('count')-initial))
 local f=assert(io.open('artifacts/overnight-soak.txt','wb'));f:write(table.concat(lines,'\n')..'\n');f:close()
end
return T
