local Sim=require('src.sim')
local Codec=require('src.sim.codec')
local Content=require('src.content')
local Maps=require('src.maps')
local Replay=require('src.replay')
local Hash=require('src.hash')
local Bot=require('src.bot')
local F=require('src.sim.fixed')
local App={}
local CELL_Y=26*math.sin(math.pi/3)
local colors={{0.38,0.75,0.96},{0.94,0.43,0.32},{0.67,0.47,0.95},{0.92,0.78,0.32}}
local function color(c,a) love.graphics.setColor(c[1],c[2],c[3],a or 1) end
function App.create(options)
    assert(Content.factions[options.faction or 'bastion'],'unknown faction: use bastion or wild')
    local config={seed=12345,players={{faction=options.faction or 'bastion'},{faction=options.opponent or 'wild'}}}
    local map=Maps.create(options.map)
    local self=setmetatable({options=options,player=1,queue={},sequences={0,0},selected={},groups={},accumulator=0,
        camera={x=28,y=115,zoom=1},previous={},message='Select a worker and right-click gold or lumber to begin.',effects={},fonts={}}, {__index=App})
    self.fonts.title=love.graphics.newFont(24);self.fonts.body=love.graphics.newFont(14);self.fonts.small=love.graphics.newFont(12)
    if options.replay then
        self.playback=Replay.read(options.replay,Content);config=self.playback.header.config;map=self.playback.header.map
        self.message='Replay playback | commands are read-only'
    end
    self.world=Sim.create(config,Content,map);self.recording=Replay.create(config,Content,map)
    if options.host or options.join then
        self.network=require('src.net.session').create(options,config,Content,map);self.player=self.network.player
    end
    self.settings=options.settings or require('src.ui.settings').load()
    self.widgets=require('src.ui.widgets').create();self.observation=require('src.ui.observation').create()
    self.alerts=require('src.ui.alerts').create();self.audio=require('src.ui.audio').create(self.settings)
    self.clock=0;self.pending={};self.replaySpeed=1;self.healthTrails={}
    if options['audio-disabled'] then self.audio.templates={} end
    self.view=Sim.view(self.world,self.player);self.observation:update(self.view)
    self.feedback=require('src.feedback').create()
    self.feedback:observe({},self.view,self.world.tick)
    self.selected={self.world.players[self.player].hero}
    local ok,sprites=pcall(require,'src.sprites')
    if ok then self.sprites=sprites.load() end
    require('src.ui.camera').normalize(self)
    require('src.ui.camera').center(self,self.world.entities[self.view.player.hero].x,self.world.entities[self.view.player.hero].y)
    return self
end
function App:screen(x,y)
    return self.camera.x+x/256*26*self.camera.zoom,self.camera.y+y/256*CELL_Y*self.camera.zoom
end
function App:position(x,y)
    return math.floor((x-self.camera.x)/26/self.camera.zoom*256),math.floor((y-self.camera.y)/CELL_Y/self.camera.zoom*256)
end
function App:entity(id)
    for _,e in ipairs(self.view.entities) do if e.id==id then return e end end
end
function App:command(kind,id,args)
    if self.playback or self.world.result or (self.network and not self.network.ready) then return end
    args=args or {};args.entity=id
    self.sequences[self.player]=self.sequences[self.player]+1
    self.pending[self.sequences[self.player]]={kind=kind,group=self.commandGroup or 0,issuedTick=self.world.tick,issuedTime=self.clock}
    self.queue[#self.queue+1]={tick=0,player=self.player,sequence=self.sequences[self.player],kind=kind,args=args}
end
function App:update(dt)
    self.clock=self.clock+dt;self.audio:update(dt);self.alerts:update(dt)
    for _,e in ipairs(self.view.entities) do
        local trail=self.healthTrails[e.id] or {value=e.hp};self.healthTrails[e.id]=trail
        if e.hp<trail.value then trail.value=math.max(e.hp,trail.value-dt*e.maxHp*1.5) else trail.value=e.hp end
    end
    if self.feedback.update then self.feedback:update(dt) end
    if self.seeking then
        local target=self.seeking;local limit=math.min(target,self.world.tick+40)
        while self.world.tick<limit do
            local tick=self.world.tick+1;Sim.step(self.world,self.playback.frames[tick].commands)
            if self.playback.hashes[tick] then assert(self.playback.hashes[tick]==Hash.bytes(Sim.serializeCanonical(self.world)),'Replay diverged at tick '..tick) end
            self.observation:update(Sim.view(self.world,self.player))
        end
        self.view=Sim.view(self.world,self.player);self.message='Seeking '..self.world.tick..' / '..target
        if self.world.tick>=target then self.seeking=nil;self.message='Replay ready' end
        return
    end
    if self.overlay and not self.network then self.accumulator=0;return end
    if self.playback then if self.replayPaused then self.accumulator=0;return end;dt=dt*self.replaySpeed end
    if self.settings.edgeScroll and not self.overlay and not self.capture then
        local mx,my=love.mouse.getPosition();local r=require('src.ui.camera').rect(self)
        if require('src.ui.camera').contains(self,mx,my) then
            if mx<8 then self.camera.x=self.camera.x+dt*350 elseif mx>r.w-8 then self.camera.x=self.camera.x-dt*350 end
            if my<r.y+8 then self.camera.y=self.camera.y+dt*350 elseif my>r.y+r.h-8 then self.camera.y=self.camera.y-dt*350 end
        end
    end
    if love.keyboard.isDown('left') then self.camera.x=self.camera.x+dt*350 end
    if love.keyboard.isDown('right') then self.camera.x=self.camera.x-dt*350 end
    if love.keyboard.isDown('up') then self.camera.y=self.camera.y+dt*350 end
    if love.keyboard.isDown('down') then self.camera.y=self.camera.y-dt*350 end
    if not self.overlay then require('src.ui.camera').clamp(self) end
    if self.network then
        self.network:poll()
        self.message=self.network.status
        if self.network.error then
            if self.network.desyncTick and not self.savedDesync then
                self.savedDesync=true
                local file=assert(io.open('artifacts/desync-player-'..self.player..'.state','wb'));file:write(self.network.states[self.network.desyncTick] or Sim.serializeCanonical(self.world));file:close()
                self:save('artifacts/desync-player-'..self.player..'.replay')
            end
            return
        end
        if not self.network.ready then return end
        if not self.started then
            self.started=true;self.world=Sim.create(self.network.config,Content,self.network.map)
            self.recording=Replay.create(self.network.config,Content,self.network.map)
            self.selected={self.world.players[self.player].hero};self.view=Sim.view(self.world,self.player)
            self.observation=require('src.ui.observation').create();self.observation:update(self.view)
            self.alerts=require('src.ui.alerts').create();self.healthTrails={};self.audio:clear()
            if self.sprites then self.sprites:reset() end
            self.previous={}
            self.feedback:reset();self.feedback:observe({},self.view,self.world.tick)
            for tick=1,3 do self.network:submit(tick,{}) end
        end
    end
    self.accumulator=self.accumulator+dt
    local steps=0
    while self.accumulator>=0.05 and steps<8 do
        if self.world.result then self.accumulator=0;break end
        local tick=self.world.tick+1
        local commands
        if self.playback then
            local frame=self.playback.frames[tick]
            if not frame then self.message='Replay complete; verified '..self.world.tick..' ticks';self.accumulator=0;break end
            commands=frame.commands
        elseif self.network then
            local future=tick+3
            if not self.network.submitted[future] then
                for _,c in ipairs(self.queue) do c.tick=future end
                self.network:submit(future,self.queue);self.queue={}
            end
            self.network:poll();commands=self.network:take(tick)
            if not commands then self.message='Waiting for complete tick '..tick;break end
        else
            commands=self.queue;self.queue={}
            for _,c in ipairs(commands) do c.tick=tick end
            local bot=self.world.tick%20==0 and Bot.commands(Sim.view(self.world,2),Content) or {}
            for _,c in ipairs(bot) do
                self.sequences[2]=self.sequences[2]+1;c.player=2;c.sequence=self.sequences[2];c.tick=tick;commands[#commands+1]=c
            end
        end
        self.previous={}
        for _,e in ipairs(self.view.entities) do self.previous[e.id]={x=e.x,y=e.y} end
        local events=Sim.step(self.world,commands)
        self.view=Sim.view(self.world,self.player);self.observation:update(self.view)
        events=Sim.eventsFor(self.world,self.player)
        self.alerts:observe(events,self)
        if self.sprites then self.sprites:observe(events,self.view,self.world.tick) end
        self.feedback:observe(events,self.view,self.world.tick)
        local acceptedCount,rejectedCount,firstReason=0,0,nil
        for _,event in ipairs(events) do
            if (event.kind=='rejected' or event.kind=='accepted') and event.player==self.player then
                local pending=self.pending[event.sequence];self.pending[event.sequence]=nil
                if pending then self.lastCommandTiming={ticks=self.world.tick-pending.issuedTick,milliseconds=math.floor((self.clock-pending.issuedTime)*1000+.5)} end
                if event.kind=='rejected' then rejectedCount=rejectedCount+1;firstReason=firstReason or event.reason;self.audio:play('rejected');if pending and pending.kind=='build' then self.building=self.awaitingPlacement;self.awaitingPlacement=nil end
                elseif pending then acceptedCount=acceptedCount+1;self.audio:play('accepted');if pending.kind=='build' then self.awaitingPlacement=nil end end
            elseif event.kind=='healed' then self.audio:play('heal',self,event.x,event.y)
            elseif event.kind=='attack' or event.kind=='death' then self.audio:play(event.kind,self,event.x,event.y)
            elseif event.kind=='constructed' or event.kind=='recruited' or event.kind=='upgraded' or event.kind=='revived' then self.audio:play('ready',self,event.x,event.y) end
        end
        for _,unit in ipairs(self.view.entities) do if unit.owner==self.player and unit.alive and (unit.harvestRemaining or unit.order.kind=='build' and not unit.goal) then self.audio:play('work',self,unit.x,unit.y);break end end
        self.audio:play('ambience')
        if rejectedCount>0 then self.message=acceptedCount>0 and (acceptedCount..' accepted, '..rejectedCount..' rejected: '..firstReason) or firstReason elseif acceptedCount>0 then self.message=acceptedCount..' order'..(acceptedCount==1 and '' or 's')..' accepted' end
        if not self.playback then Replay.record(self.recording,self.world,commands)
        elseif self.playback.hashes[tick] then
            assert(self.playback.hashes[tick]==Hash.bytes(Sim.serializeCanonical(self.world)),'Replay diverged at tick '..tick)
        end
        if self.network and tick%100==0 then local bytes=Sim.serializeCanonical(self.world);self.network:checksum(tick,Hash.bytes(bytes),bytes) end
        self.accumulator=self.accumulator-0.05;steps=steps+1
    end
end
local function selected(self,id) for _,v in ipairs(self.selected) do if v==id then return true end end return false end
function App:drawEntity(e)
    local g=love.graphics
    local x,y=e.x,e.y;local prev=self.previous[e.id]
    if prev and e.category=='unit' then
        local alpha=math.min(1,self.accumulator/0.05)
        x=prev.x+(x-prev.x)*alpha;y=prev.y+(y-prev.y)*alpha
    end
    x,y=self:screen(x,y)
    local z=self.camera.zoom
    local team=colors[e.owner] or {0.76,0.61,0.39}
    if not e.alive and not (self.sprites and self.sprites.units[require('src.asset_frames').assetId(e)]) then
        color(team,0.5);g.ellipse('fill',x,y,15*z,5*z);return
    end
    g.setColor(0,0,0,0.28);g.ellipse('fill',x,y,12*z,5*z)
    if selected(self,e.id) then g.setColor(0.55,0.93,0.73);g.setLineWidth(2);g.ellipse('line',x,y,15*z,7*z) end
    if e.category=='building' then
        local w,h=e.size*26*z,e.size*CELL_Y*z
        x=x-13*z;y=y-(CELL_Y/2)*z
        if selected(self,e.id) then g.setColor(.55,.93,.73);g.rectangle('line',x,y,w,h) end
        color(team,0.5);g.rectangle('fill',x,y-22*z,w,h+22*z)
        color(team);g.polygon('fill',x,y-22*z,x+w/2,y-38*z,x+w,y-22*z,x+w/2,y-8*z)
        g.setColor(0.07,0.1,0.13);g.rectangle('fill',x+w*0.35,y+h-24*z,w*0.3,24*z)
        if e.remaining>0 then
            g.setColor(.72,.58,.32);g.rectangle('line',x,y-22*z,w,h+22*z);g.line(x,y-22*z,x+w,y+h,x+w,y-22*z,x,y+h)
            g.setColor(.07,.1,.12);g.rectangle('fill',x,y-44*z,w,5*z)
            g.setColor(.95,.77,.36);g.rectangle('fill',x,y-44*z,w*(1-e.remaining/Content.buildings[e.kind].buildTicks),5*z)
        end
        g.setColor(0.92,0.94,0.91);g.setFont(self.fonts.small);g.print(({hq='HQ',tower='T',barracks='WAR',depot='LUMBER',outpost='OUTPOST'})[e.kind] or e.kind,x+4,y+h-18*z)
    elseif e.category=='node' then
        if e.resource=='gold' then x=x+(e.size-1)*13*z;y=y+(e.size-1)*CELL_Y/2*z;z=z*e.size;g.setColor(0.9,0.71,0.27);g.polygon('fill',x-12*z,y,x-5*z,y-20*z,x+8*z,y-17*z,x+14*z,y)
        else g.setColor(0.32,0.24,0.13);g.rectangle('fill',x-3*z,y-22*z,6*z,22*z);g.setColor(0.21,0.48,0.33);g.polygon('fill',x-16*z,y-12*z,x,y-44*z,x+16*z,y-12*z) end
    else
        local d=Content.units[e.kind];z=z*self:unitVisualScale(e);local height=d.hero and 31 or 23
        local drawn=self.sprites and self.sprites:draw(e,x,y,z,team,prev,self.world.tick,self.view)
        if not drawn then
            color(team);g.rectangle('fill',x-8*z,y-height*z,16*z,(height-5)*z,4*z)
            g.setColor(0.9,0.82,0.66);g.circle('fill',x,y-(height+4)*z,6*z)
            g.setColor(0.12,0.18,0.2);g.rectangle('fill',x-8*z,y-5*z,6*z,6*z);g.rectangle('fill',x+2*z,y-5*z,6*z,6*z)
            if d.hero then g.setColor(1,0.85,0.38);g.polygon('fill',x-7*z,y-37*z,x-8*z,y-46*z,x,y-40*z,x+8*z,y-46*z,x+7*z,y-37*z) end
            if e.kind=='worker' then g.setColor(0.74,0.63,0.44);g.setLineWidth(3*z);g.line(x+10*z,y-30*z,x+10*z,y-4*z) end
        end
        local barY=y-(d.hero and 53 or 40)*z
        g.setColor(0.06,0.08,0.1);g.rectangle('fill',x-14*z,barY,28*z,4*z)
        local trail=self.healthTrails[e.id];if trail then g.setColor(.95,.74,.42);g.rectangle('fill',x-14*z,barY,28*z*trail.value/e.maxHp,4*z) end
        color(team);g.rectangle('fill',x-14*z,barY,28*z*e.hp/e.maxHp,4*z)
    end
end
function App:draw()
    if self.options['sprite-proof'] then return require('src.sprite_proof').draw(self.sprites) end
    local g=love.graphics;local width,height=g.getDimensions();local panel=width
    g.clear(0.055,0.078,0.088)
    local cameraModule=require('src.ui.camera');local cameraRect=cameraModule.rect(self);if self.camera.viewportHeight and self.camera.viewportHeight~=cameraRect.h then local cx,cy=self:position(cameraRect.w/2,cameraRect.y+cameraRect.h/2);cameraModule.normalize(self);cameraModule.center(self,cx,cy) end;self.camera.viewportHeight=cameraRect.h
    local viewport=cameraRect;g.setScissor(viewport.x,viewport.y,viewport.w,viewport.h)
    local m=self.world.map;local z=self.camera.zoom
    local terrain=require('src.ui.minimap').cache(self)
    g.setColor(1,1,1);g.draw(terrain.terrain,self.camera.x,self.camera.y,0,26*z,CELL_Y*z)
    g.draw(terrain.fog,self.camera.x,self.camera.y,0,26*z,CELL_Y*z)
    local entities={}
    for _,e in ipairs(self.view.entities) do if e.alive or (e.category=='unit' and e.deathTick and self.world.tick-e.deathTick<40) then entities[#entities+1]=e end end
    table.sort(entities,function(a,b) local ay=a.y+(a.size-1)*256;local by=b.y+(b.size-1)*256;if ay~=by then return ay<by end return a.id<b.id end)
    for _,e in ipairs(entities) do self:drawEntity(e) end
    if not self.options['effects-disabled'] then self.feedback:draw(self) end
    if self.orderMarker and self.clock-(self.orderMarker.time or 0)<.4 then
        local marker=self.orderMarker;local mx,my=self:screen(marker.x,marker.y)
        local age=(self.clock-(marker.time or 0))*20
        g.setColor(0.65,0.95,0.65,1-age/8);g.setLineWidth(2*z)
        g.ellipse('line',mx,my,(7+age)*z,(4+age*0.5)*z)
    end
    if self.drag then
        local mx,my=love.mouse.getPosition();g.setColor(0.52,0.86,0.73,0.18);g.rectangle('fill',self.drag.x,self.drag.y,mx-self.drag.x,my-self.drag.y)
        g.setColor(0.52,0.86,0.73);g.setLineWidth(1);g.rectangle('line',self.drag.x,self.drag.y,mx-self.drag.x,my-self.drag.y)
    end
    if self.building then
        local mx,my=love.mouse.getPosition();local wx,wy=self:position(mx,my);local x,y=self:screen(F.cell(wx)*256,F.cell(wy)*256);local size=Content.buildings[self.building].size
        local valid,reason=Sim.placement(self.view,Content,self.building,F.cell(wx),F.cell(wy))
        g.setColor(valid and .4 or 1,valid and .85 or .3,.3,.4);g.rectangle('fill',x,y,size*26*z,size*CELL_Y*z)
        g.setColor(valid and .65 or 1,valid and 1 or .3,.4);g.rectangle('line',x,y,size*26*z,size*CELL_Y*z)
        if not valid then for offset=0,size*26*z,8 do g.line(x+offset,y,x+offset,y+size*CELL_Y*z) end end
        g.setColor(1,.9,.7);g.print(reason,mx+16,my+12)
    end
    for _,id in ipairs(self.selected) do local e=self:entity(id);if e then
        local px,py=self:screen(e.x,e.y)
        local orders={e.order};for _,order in ipairs(e.orders or {}) do orders[#orders+1]=order end
        for _,order in ipairs(orders) do local wx,wy
            if order.x then wx=order.x*256+128;wy=order.y*256+128 elseif order.target then local t=self:entity(order.target);if t then wx=t.x;wy=t.y end end
            if wx then local x,y=self:screen(wx,wy);g.setColor(.5,.8,.6,.5);g.line(px,py,x,y);g.circle('line',x,y,4);px,py=x,y end
        end
    end end
    g.setScissor();require('src.ui.hud').draw(self)
end

function App:unitVisualScale(e)
    local d=Content.units[e.kind];if not d then return 1 end
    local u=self.sprites and self.sprites.units[require('src.asset_frames').assetId(e)]
    local target=d.hero and 38.4 or d.worker and 26.24 or 32
    return u and target/(u.metadata.bodyHeightPixels*(u.metadata.drawScale or 1)) or d.worker and .82 or 1
end
function App:pick(x,y,ownOnly)
    local best,dist
    for _,e in ipairs(self.view.entities) do
        if e.alive and (not ownOnly or e.owner==self.player) then
            local z=self.camera.zoom;local sx,sy=self:screen(e.x,e.y);local hit,distance
            if e.category~='unit' then
                local left,top=self:screen(F.cell(e.x)*256,F.cell(e.y)*256)
                local width,height=e.size*26*z,e.size*CELL_Y*z
                hit=x>=left and x<=left+width and y>=top-38*z and y<=top+height
                distance=(x-(left+width/2))^2+(y-(top+height/2))^2
            else
                z=z*self:unitVisualScale(e);distance=(x-sx)^2+(y-(sy-12*z))^2;hit=distance<(20*z)^2
            end
            if hit and (not best or distance<dist) then best=e;dist=distance end
        end
    end
    return best
end
function App:mousepressed(...) return require('src.ui.input').mousepressed(self,...) end
function App:mousereleased(...) return require('src.ui.input').mousereleased(self,...) end
function App:mousemoved(...) return require('src.ui.input').mousemoved(self,...) end
function App:keypressed(...) return require('src.ui.input').keypressed(self,...) end
function App:wheelmoved(_,dy)
    if self.overlay then return end
    local x,y=love.mouse.getPosition();if require('src.ui.camera').contains(self,x,y) then require('src.ui.camera').zoom(self,x,y,dy) end
end
function App:requestSeek(tick,player)
    self:seek(0,player);self.seeking=math.max(0,math.min(#self.playback.frames,math.floor(tick)))
end
function App:seek(tick,player)
    if not self.playback then return end
    self.player=player or self.player;self.world=Sim.create(self.playback.header.config,Content,self.playback.header.map)
    self.observation=require('src.ui.observation').create();self.observation:update(Sim.view(self.world,self.player))
    for i=1,math.min(tick,#self.playback.frames) do
        Sim.step(self.world,self.playback.frames[i].commands)
        if self.playback.hashes[i] then assert(self.playback.hashes[i]==Hash.bytes(Sim.serializeCanonical(self.world)),'Replay diverged at tick '..i) end
        self.observation:update(Sim.view(self.world,self.player))
    end
    self.view=Sim.view(self.world,self.player);self.previous={};self.accumulator=0;self.feedback:reset();self.audio:clear()
    self.alerts=require('src.ui.alerts').create();self.selected={self.view.player.hero};if self.sprites then self.sprites:reset() end
end
function App:save(path)
    if not self.playback then
        path=path or ('artifacts/match-'..os.date('%Y%m%d-%H%M%S')..'-player-'..self.player..'.replay')
        Replay.write(path,self.recording);require('src.ui.replay_library').remember(path);self.message='Replay saved: '..path;print(self.message)
    end
end
function App:close() if not self.noAutoSave then self:save() end;self.audio:clear();if self.miniCache then self.miniCache.terrain:release();self.miniCache.fog:release();self.miniCache=nil end;if self.network then self.network:close() end end
return App
