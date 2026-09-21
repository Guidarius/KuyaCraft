-- Explicit compatibility proof for an existing shipping recording; never rewrites it.
local V={}
function V.run(path)
 local Replay=require('src.replay');local Content=require('src.content');local Sim=require('src.sim');local Hash=require('src.hash')
 local r=Replay.read(path,Content);local w=Sim.create(r.header.config,Content,r.header.map);local checked=0
 for _,frame in ipairs(r.frames) do
  Sim.step(w,frame.commands)
  if r.hashes[w.tick] then assert(Hash.bytes(Sim.serializeAuthoritative(w))==r.hashes[w.tick],'Existing recording diverged at '..w.tick);checked=checked+1 end
 end
 assert(checked>0,'Recording has no authoritative checkpoints')
 print('EXISTING_REPLAY_PASS '..w.tick..' ticks; '..checked..' recorded checkpoints; '..require('src.build').fingerprint())
 return 0
end
return V
