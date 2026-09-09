local N=require('src.net.session')
local Sim=require('src.sim')
local Maps=require('src.maps')
local Content=require('src.content')
local Hash=require('src.hash')
local T={}
function T.run(options)
    local config={seed=12345,players={{faction='bastion'},{faction='wild'}}}
    local map=Maps.create('network',24);map.resources={};map.camps={}
    local net=N.create({host=options.host,join=options.join},config,Content,map)
    local world,sequence=nil,0
    local deadline=love.timer.getTime()+25
    local file=assert(io.open(options.output,'wb'))
    local complete=false
    while love.timer.getTime()<deadline do
        net:poll();assert(not net.error,net.error)
        if net.ready then
            if not world then
                world=Sim.create(net.config,Content,net.map)
                for tick=1,3 do net:submit(tick,{}) end
            end
            if world.tick<600 then
                local future=world.tick+4
                if not net.submitted[future] then
                    local commands={}
                    if future%37==0 then
                        sequence=sequence+1
                        commands[1]={tick=future,player=net.player,sequence=sequence,kind='toggle',args={entity=world.players[net.player].hero}}
                    end
                    if future%71==0 then
                        sequence=sequence+1;commands[#commands+1]={tick=future,player=net.player,sequence=sequence,kind='hold',args={entity=world.players[net.player].hero}}
                    elseif future%71==8 then
                        sequence=sequence+1;commands[#commands+1]={tick=future,player=net.player,sequence=sequence,kind='move',args={entity=world.players[net.player].hero,x=(net.player==1 and 9 or 16)*256+128,y=10*256+128,group=future}}
                    end
                    net:submit(future,commands)
                end
                net:poll()
                local commands=net:take(world.tick+1)
                if commands then
                    Sim.step(world,commands)
                    if world.tick%100==0 then
                        local hash=Hash.bytes(Sim.serializeCanonical(world));file:write(world.tick..' '..hash..'\n');net:checksum(world.tick,hash)
                    end
                end
            elseif net.remoteHashes[600] and net.remoteHashes[600]==net.hashes[600] then
                complete=true;break
            end
        end
        love.timer.sleep(0.001)
    end
    file:close()
    assert(complete,'two-process network proof timed out')
    net.host:flush();print('PASS ENet process '..net.player..': 600 matching ticks')
    return 0
end
return T
