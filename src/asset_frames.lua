-- Pure presentation frame selection; simulation state is never modified.
local F={directions={'N','NE','E','SE','S','SW','W','NW'}}
local assetIds={shield='shieldguard',crossbow='crossbow',warden='warden'}
function F.assetId(e)
    -- A worker with a load on its back is the loaded recipe: same body, same clips, a
    -- bundle on its back. Empty, it is the plain one.
    if e.kind=='worker' then return (e.carrying or 0)>0 and 'worker_loaded' or 'worker' end
    return assetIds[e.kind]
end
-- A unit moving close to the line between two of its eight headings used to flip between them
-- every tick, which reads as flicker, most of all in a shuffling crowd. The current heading is
-- kept until the motion is clearly past the boundary: 15 degrees beyond it.
local HYSTERESIS=math.pi/12
local centres={}
for i,name in ipairs(F.directions) do centres[name]=(i-1)*math.pi/4-math.pi/2 end
function F.direction(dx,dy,last)
    if dx==0 and dy==0 then return last or 'S' end
    local angle=math.atan2 and math.atan2(dy,dx) or math.atan(dy,dx)
    local centre=last and centres[last]
    if centre then
        local off=(angle-centre+math.pi)%(2*math.pi)-math.pi
        if math.abs(off)<=math.pi/8+HYSTERESIS then return last end
    end
    return F.directions[(math.floor((angle+math.pi/2)/(math.pi/4)+0.5)%8)+1]
end
function F.sample(m,name,direction,elapsedMs,contactFirst)
    local c=m.clips[name] or m.clips.idle
    local ids=c.frames[direction] or c.frames.S;local n=#ids
    local elapsed=math.max(0,elapsedMs or 0)
    local frame
    if contactFirst then
        local first=c.contactFrame or 1
        frame=math.min(n,first+math.floor(elapsed/c.durationMs*n))
    elseif c.loop then frame=math.floor(elapsed%c.durationMs/c.durationMs*n)+1
    else frame=math.min(n,math.floor(elapsed/c.durationMs*n)+1) end
    return ids[frame],frame,c
end
function F.select(m,e,previous,tick,state,view)
    state=state or {};local ms=tick*50
    local dx,dy=0,0;if previous then dx=e.x-previous.x;dy=e.y-previous.y end
    local moving=dx~=0 or dy~=0
    local direction=F.direction(dx,dy,state.direction)
    local clip=moving and 'move' or 'idle';local elapsed=ms
    if not moving and e.harvestUntil then clip='work' end
    if moving and state.tick~=tick then
        local distance=math.sqrt(dx*dx+dy*dy)/256
        local stride=m.referenceStride and m.referenceStride.distance
        state.moveMs=(state.moveMs or 0)+(stride and distance/stride*m.clips.move.durationMs or 50)
    end
    if moving then elapsed=state.moveMs or 0 end
    local contact=false
    local attack=m.clips.attack
    local attackElapsed=e.attackTick and (tick-e.attackTick)*50
    local recoverMs=attack.durationMs*(#attack.frames.S-(attack.contactFrame or 1)+1)/#attack.frames.S
    if not e.attack and not moving and attackElapsed and attackElapsed>=0 and attackElapsed<recoverMs then
        clip='attack';elapsed=attackElapsed;contact=true
        local target=e.order and e.order.target
        if state.attackFacingTick==e.attackTick and state.attackHeading then direction=state.attackHeading
        elseif target and view then for _,candidate in ipairs(view.entities or {}) do if candidate.id==target then direction=F.direction(candidate.x-e.x,candidate.y-e.y,direction);break end end end
    end
    if e.attack and not moving then
        local phase=e.attack;clip='attack';contact=false
        direction=F.direction(phase.dx,phase.dy,direction)
        local count=#attack.frames.S;local contactIndex=attack.contactFrame or math.max(1,math.floor(count/2))
        local index
        if tick<phase.impact then index=1+(contactIndex-1)*math.max(0,tick-phase.start)/math.max(1,phase.impact-phase.start)
        else index=contactIndex+(count-contactIndex)*math.max(0,tick-phase.impact)/math.max(1,phase.finish-phase.impact) end
        elapsed=(math.min(count,index)-1)/count*attack.durationMs
    end
    if e.alive==false then clip='death';elapsed=math.max(0,(tick-(e.deathTick or tick))*50);contact=false end
    state.direction=direction;state.tick=tick
    local id,index=F.sample(m,clip,direction,elapsed,contact)
    return id,state,clip,direction,index
end
return F
