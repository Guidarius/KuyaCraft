local Codec=require('src.sim.codec')
local F=require('src.sim.fixed')
local L={}
function L.create(players) return {players=players,frames={},nextTick=1} end
function L.submit(state,player,tick,commands)
    if not F.integer(player,1,state.players) or not F.integer(tick,state.nextTick,state.nextTick+120) or type(commands)~='table' or #commands>128 then return nil,'invalid submission' end
    local keys=Codec.keys(commands)
    if #keys~=#commands then return nil,'sparse command batch' end
    for i=1,#commands do
        local c=commands[i]
        if keys[i]~=i or type(c)~='table' or c.player~=player or c.tick~=tick or not F.integer(c.sequence,1,2147483646) or type(c.kind)~='string' or type(c.args)~='table' then return nil,'invalid command envelope' end
    end
    local frame=state.frames[tick] or {};state.frames[tick]=frame
    if frame[player] then
        if Codec.encode(frame[player])==Codec.encode(commands) then return true end
        return nil,'conflicting completed frame'
    end
    frame[player]=Codec.copy(commands)
    return true
end
function L.take(state)
    local tick=state.nextTick;local frame=state.frames[tick]
    if not frame then return nil end
    for p=1,state.players do if not frame[p] then return nil end end
    local commands={}
    for p=1,state.players do for _,c in ipairs(frame[p]) do commands[#commands+1]=c end end
    table.sort(commands,function(a,b) if a.player~=b.player then return a.player<b.player end return a.sequence<b.sequence end)
    state.frames[tick]=nil;state.nextTick=tick+1
    return {tick=tick,commands=commands}
end
return L
