local Codec=require('src.sim.codec')
local Sim=require('src.sim')
local Hash=require('src.hash')
local M={}
function M.header(config,content,map)
    return {format=1,game='LoveRTS-0.1',simulation=Sim.VERSION,runtime='11.5',buildHash=require('src.build').fingerprint(),contentHash=Hash.value(content),mapHash=Hash.value(map),config=config,map=map}
end
function M.create(config,content,map) return {header=M.header(config,content,map),frames={},hashes={}} end
function M.record(replay,w,commands)
    replay.frames[#replay.frames+1]={tick=w.tick,commands=Codec.copy(commands)}
    if w.tick%100==0 or w.result then replay.hashes[w.tick]=Hash.bytes(Sim.serializeCanonical(w)) end
end
function M.write(path,replay)
    local file=assert(io.open(path,'wb'));file:write(Codec.encode(replay));file:close()
end
function M.read(path,content)
    local file=assert(io.open(path,'rb'));local bytes=file:read(32*1024*1024+1);file:close()
    local replay=Codec.decode(bytes);local h=assert(replay.header,'missing replay header')
    assert(h.format==1 and h.game=='LoveRTS-0.1' and h.simulation==Sim.VERSION and h.runtime=='11.5','incompatible replay version')
    assert(h.buildHash==require('src.build').fingerprint(),'replay authoritative source mismatch'); assert(h.contentHash==Hash.value(content) and h.mapHash==Hash.value(h.map),'replay content/map mismatch')
    assert(type(replay.frames)=='table' and type(replay.hashes)=='table','invalid replay body')
    for i=1,#replay.frames do assert(replay.frames[i].tick==i and type(replay.frames[i].commands)=='table','noncontiguous replay frames') end
    return replay
end
return M
