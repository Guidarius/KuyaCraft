local Codec=require('src.sim.codec')
local Sim=require('src.sim')
local Hash=require('src.hash')
local M={}
-- How often a recording stores an authoritative checkpoint. Hashing costs tens of
-- milliseconds in a large battle -- in-flight A* searches and 240 entity records are
-- real future-affecting state and cannot be left out -- so the interval is a
-- property of the recording rather than a constant. A sparser interval detects a
-- divergence later, which is the right trade for a local recording: the frames
-- themselves are the replay, the hashes only say where playback stopped matching.
-- Live network play does not use this; it checksums on its own schedule.
M.DEFAULT_INTERVAL=100
M.OFFLINE_INTERVAL=500
function M.header(config,content,map,interval)
    return {format=1,game='LoveRTS-0.1',simulation=Sim.VERSION,runtime='11.5',buildHash=require('src.build').fingerprint(),contentHash=Hash.value(content),mapHash=Hash.value(map),config=config,map=map,checkpointInterval=interval or M.DEFAULT_INTERVAL}
end
function M.create(config,content,map,interval) return {header=M.header(config,content,map,interval),frames={},hashes={}} end
function M.record(replay,w,commands)
    replay.frames[#replay.frames+1]={tick=w.tick,commands=Codec.copy(commands)}
    local interval=replay.header.checkpointInterval or M.DEFAULT_INTERVAL
    if w.tick%interval==0 or w.result then replay.hashes[w.tick]=Hash.bytes(Sim.serializeAuthoritative(w)) end
end
function M.encode(replay) return Codec.encode(replay) end
function M.write(path,replay)
    local file=assert(io.open(path,'wb'));file:write(Codec.encode(replay));file:close()
end
function M.read(path,content)
    local file=assert(io.open(path,'rb'));local bytes=file:read(32*1024*1024+1);file:close()
    local replay=Codec.decode(bytes);local h=assert(replay.header,'missing replay header')
    assert(h.format==1 and h.game=='LoveRTS-0.1' and h.simulation==Sim.VERSION and h.runtime=='11.5','incompatible replay version')
    assert(h.checkpointInterval==nil or (type(h.checkpointInterval)=='number' and h.checkpointInterval>=1 and h.checkpointInterval==math.floor(h.checkpointInterval)),'invalid checkpoint interval')
    assert(h.buildHash==require('src.build').fingerprint(),'replay authoritative source mismatch'); assert(h.contentHash==Hash.value(content) and h.mapHash==Hash.value(h.map),'replay content/map mismatch')
    assert(type(replay.frames)=='table' and type(replay.hashes)=='table','invalid replay body')
    for i=1,#replay.frames do assert(replay.frames[i].tick==i and type(replay.frames[i].commands)=='table','noncontiguous replay frames') end
    return replay
end
return M
