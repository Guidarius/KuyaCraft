local enet=require('enet')
local Codec=require('src.sim.codec')
local Lock=require('src.net.lockstep')
local Hash=require('src.hash')
local Replay=require('src.replay')
local N={}
local function send(peer,message) peer:send(Codec.encode(message),0,'reliable') end
function N.create(options,config,content,map)
    local self={role=options.host and 'host' or 'client',manualLobby=options.manualLobby==true,lobbyReady={false,false},ready=false,status='Connecting',frames={},submitted={},hashes={},remoteHashes={},states={},content=content,map=map,config=config,lastPacket=love.timer.getTime()}
    if options.host then
        self.host=assert(enet.host_create(options.host,1,1),'cannot bind ENet host'); self.player=1;self.lock=Lock.create(2);self.status='Waiting for player 2'
    else
        self.host=assert(enet.host_create(nil,1,1),'cannot create ENet client');self.player=2;self.peer=self.host:connect(options.join,1)
    end
    return setmetatable(self,{__index=N})
end
function N:fail(reason) self.error=reason;self.ready=false;self.status=reason end
function N:poll()
    while true do
        local event=self.host:service(0)
        if not event then break end
        self.lastPacket=love.timer.getTime()
        if event.type=='connect' then
            self.peer=event.peer
            if self.role=='host' then send(self.peer,{kind='hello',manualLobby=self.manualLobby,header=Replay.header(self.config,self.content,self.map)}) end
        elseif event.type=='disconnect' then self:fail('Peer disconnected; match ended')
        elseif event.type=='receive' then
            if #event.data>1024*1024 then self:fail('Oversized network message');return end
            local ok,message=pcall(Codec.decode,event.data)
            if not ok or type(message)~='table' then self:fail('Malformed network message');return end
            local valid,err=pcall(function() self:receive(message) end)
            if not valid then self:fail('Protocol error: '..tostring(err)) end
        end
    end
    if (self.ready or not self.compatible) and love.timer.getTime()-self.lastPacket>30 then self:fail('Connection timed out; match ended') end
    if self.role=='host' and self.ready then
        while true do
            local frame=Lock.take(self.lock)
            if not frame then break end
            self.frames[frame.tick]=frame.commands
            send(self.peer,{kind='frame',tick=frame.tick,commands=frame.commands})
        end
    end
    self.host:flush()
end
function N:receive(m)
    if m.kind=='hello' and self.role=='client' and not self.ready then
        local expected=Replay.header(m.header.config,self.content,m.header.map)
        assert(m.header.game==expected.game and m.header.runtime==expected.runtime and m.header.simulation==expected.simulation and m.header.format==expected.format,'version mismatch')
        assert(m.header.buildHash==expected.buildHash,'authoritative source mismatch'); assert(m.header.contentHash==expected.contentHash and m.header.mapHash==expected.mapHash,'content/map mismatch')
        assert(#m.header.config.players==2,'expected two players')
        assert(m.manualLobby==self.manualLobby,'lobby mode mismatch')
        self.config=m.header.config;self.map=m.header.map
        send(self.peer,{kind='ready',signature=Hash.value(m.header)})
        self.compatible=true;self.ready=not self.manualLobby;self.status=self.manualLobby and 'Connected - waiting for players to ready' or 'Connected'
    elseif m.kind=='ready' and self.role=='host' and not self.ready then
        assert(m.signature==Hash.value(Replay.header(self.config,self.content,self.map)),'handshake mismatch')
        self.compatible=true;self.ready=not self.manualLobby;self.status=self.manualLobby and 'Connected - waiting for players to ready' or 'Connected'
    elseif m.kind=='lobby-choice' and self.role=='host' and self.compatible and not self.ready then
        assert(self.content.factions[m.faction] and type(m.ready)=='boolean','invalid lobby choice')
        if self.config.players[2].faction~=m.faction then self.lobbyReady[1]=false end
        self.config.players[2].faction=m.faction;self.lobbyReady[2]=m.ready
        send(self.peer,{kind='lobby-state',config=self.config,players=self.lobbyReady})
    elseif m.kind=='lobby-state' and self.role=='client' and self.compatible and not self.ready then
        assert(#m.config.players==2 and self.content.factions[m.config.players[1].faction] and self.content.factions[m.config.players[2].faction],'invalid lobby config')
        self.config=m.config;self.lobbyReady=m.players
    elseif m.kind=='start' and self.role=='client' and self.compatible and not self.ready then
        assert(self.lobbyReady[1] and self.lobbyReady[2],'players not ready')
        assert(m.signature==Hash.value(Replay.header(self.config,self.content,self.map)),'start config mismatch')
        self.ready=true;self.status='Match started'
    elseif m.kind=='submit' and self.role=='host' and self.ready then
        local ok,reason=Lock.submit(self.lock,2,m.tick,m.commands);assert(ok,reason)
    elseif m.kind=='frame' and self.role=='client' and self.ready then
        assert(type(m.tick)=='number' and m.tick==math.floor(m.tick) and type(m.commands)=='table','invalid frame')
        if self.frames[m.tick] then assert(Codec.encode(self.frames[m.tick])==Codec.encode(m.commands),'conflicting frame') end
        self.frames[m.tick]=m.commands
    elseif m.kind=='hash' and self.ready then
        assert(type(m.tick)=='number' and type(m.hash)=='string' and #m.hash==64,'invalid checksum')
        self.remoteHashes[m.tick]=m.hash
        if self.hashes[m.tick] and self.hashes[m.tick]~=m.hash then self:fail('Desync at tick '..m.tick);self.desyncTick=m.tick end
    else error('unexpected message '..tostring(m.kind)) end
end
function N:setLobby(faction,ready)
    if not self.compatible or self.ready or self.error then return end
    assert(self.content.factions[faction])
    if self.role=='host' then
        if self.config.players[1].faction~=faction then self.lobbyReady[2]=false end
        self.config.players[1].faction=faction;self.lobbyReady[1]=ready
        send(self.peer,{kind='lobby-state',config=self.config,players=self.lobbyReady})
    else send(self.peer,{kind='lobby-choice',faction=faction,ready=ready}) end
end
function N:startMatch()
    if self.role~='host' or not self.compatible or not self.lobbyReady[1] or not self.lobbyReady[2] or self.error then return false end
    send(self.peer,{kind='start',signature=Hash.value(Replay.header(self.config,self.content,self.map))});self.ready=true;self.status='Match started';return true
end
function N:submit(tick,commands)
    if self.submitted[tick] then return end
    self.submitted[tick]=true
    if self.role=='host' then local ok,reason=Lock.submit(self.lock,1,tick,commands);assert(ok,reason)
    else send(self.peer,{kind='submit',tick=tick,commands=commands}) end
end
function N:take(tick)
    local commands=self.frames[tick];self.frames[tick]=nil
    self.submitted[tick-10]=nil
    return commands
end
function N:checksum(tick,hash,bytes)
    self.hashes[tick]=hash; self.states[tick]=bytes
    send(self.peer,{kind='hash',tick=tick,hash=hash})
    if self.remoteHashes[tick] and self.remoteHashes[tick]~=hash then self:fail('Desync at tick '..tick);self.desyncTick=tick end
    self.states[tick-200]=nil;self.hashes[tick-200]=nil;self.remoteHashes[tick-200]=nil
end
function N:close() if self.peer then self.peer:disconnect();self.host:flush() end end
return N
