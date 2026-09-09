local Sim=require('src.sim')
local Content=require('tests.fixture_content')
local Maps=require('src.maps')
local Bot=require('tests.fixture_bot')
local Codec=require('src.sim.codec')
local Replay=require('src.replay')
local Hash=require('src.hash')
local M={}
function M.match(mirror)
    local config={seed=725,players={{faction='bastion'},{faction=mirror and 'bastion' or 'wild'}}}
    local map=Maps.create('river_pass');local w=Sim.create(config,Content,map);local seq={0,0};local recording=Replay.create(config,Content,map)
    for tick=1,30000 do
        local commands={}
        if w.tick%20==0 then
            for p=1,2 do for _,c in ipairs(Bot.commands(Sim.view(w,p),Content)) do
                seq[p]=seq[p]+1;c.tick=tick;c.player=p;c.sequence=seq[p];commands[#commands+1]=c
            end end
        end
        Sim.step(w,commands);Replay.record(recording,w,commands)
        if w.result then break end
    end
    local label=mirror and 'mirror' or 'asymmetric'
    Replay.write('artifacts/'..label..'-match.replay',recording)
    print(label..' match: tick='..w.tick..' result='..Codec.encode(w.result)..' population='..Sim.population(w,1)..'/'..Sim.population(w,2))
    for p=1,2 do
        local home=w.entities[w.players[p].hq]
        print('P'..p..' HQ '..home.hp..' resources '..Codec.encode(w.players[p].resources))
    end
    assert(w.result,'bot match did not finish within 25 simulated minutes')
    local restored=Sim.create(config,Content,map)
    for _,frame in ipairs(recording.frames) do
        Sim.step(restored,frame.commands)
        if recording.hashes[frame.tick] then assert(Hash.bytes(Sim.serializeAuthoritative(restored))==recording.hashes[frame.tick],'full match replay diverged') end
    end
    return w
end
function M.performance()
    local map=Maps.create('stress',64);map.resources={};map.camps={}
    local config={seed=1,players={{faction='bastion'},{faction='wild'},{faction='bastion'},{faction='wild'}}}
    local w=Sim.create(config,Content,map)
    for p=1,4 do
        local template
        for _,id in ipairs(w.order) do local e=w.entities[id];if e.owner==p and e.kind=='worker' then template=e;break end end
        local baseX=(p%2==1) and 8 or 42;local baseY=p<=2 and 8 or 42
        for i=1,55 do
            local e=Codec.copy(template);e.id=w.nextId;w.nextId=w.nextId+1
            e.x=(baseX+(i-1)%8)*256+128;e.y=(baseY+math.floor((i-1)/8))*256+128
            e.kind='shield';e.hp=180;e.maxHp=180
            w.entities[e.id]=e;w.order[#w.order+1]=e.id
        end
    end
    local times={};local initial=collectgarbage('count')
    for i=1,300 do
        local start=love.timer.getTime();Sim.step(w,{})
        times[i]=(love.timer.getTime()-start)*1000
        assert(w.metrics.pathExpansions<=Content.rules.pathBudget)
    end
    table.sort(times)
    local file=assert(io.open('artifacts/performance.txt','wb'))
    local report=string.format('240 mobile units, 4 players, idle vision/combat-acquisition workload\n300 ticks; p95 %.3f ms; max %.3f ms; Lua memory before %.0f KiB, after %.0f KiB\n',times[285],times[300],initial,collectgarbage('count'))
    file:write(report);file:close();print(report)
    assert(times[285]<50,'cannot sustain 20 Hz in stress fixture')
    return times[285]
end
return M
