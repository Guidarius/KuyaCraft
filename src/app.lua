local Sim=require('src.sim')
local Codec=require('src.sim.codec')
local Content=require('src.content')
local Maps=require('src.maps')
local Replay=require('src.replay')
local Hash=require('src.hash')
local Bot=require('src.bot')
local F=require('src.sim.fixed')
-- Hoisted because these sit on the per-frame and per-entity draw paths, where an
-- inline require() is a package.loaded hash lookup on every single call.
local Camera=require('src.ui.camera')
local Minimap=require('src.ui.minimap')
local Terrain=require('src.ui.terrain')
local Hud=require('src.ui.hud')
local Input=require('src.ui.input')
local Frames=require('src.asset_frames')
local Settings=require('src.ui.settings')
local App={}
local CELL_Y=26*math.sin(math.pi/3)
-- Ticks for a full day/night cycle: eight minutes at 20 Hz, long enough that the
-- change is never distracting during a fight.
local DAY_LENGTH=9600
-- How long an ordered unit's selection circle brightens for. Long enough to register
-- as a reply, short enough that it has faded before the order visibly starts.
local ACK_FLASH=0.2
-- Health trail: hold the lost chunk this long, never longer than the cap, then drain it with
-- this time constant.
local TRAIL_HOLD,TRAIL_HOLD_CAP,TRAIL_DRAIN=0.3,1.0,0.2
-- After a group order, how long the cells its units were given stay marked.
local FORMATION_GHOST=1.0
-- Own units below this percentage of their health pulse; a winding-up body swells this much.
local LOW_HEALTH,WINDUP_SWELL=30,0.07
-- The order marker and formation ghosts are coloured by what was ordered, so the player can
-- see what they told the army to do: move, attack-move, a focused attack, a patrol beat.
local ORDER_COLORS={
    move={.55,.95,.6},follow={.55,.9,.85},build={.95,.8,.4},patrol={.45,.8,.95},
    attack={1,.38,.32},attack_move={1,.5,.34},rejected={1,.38,.32},cast={.75,.6,1}}
local colors={{0.38,0.75,0.96},{0.94,0.43,0.32},{0.67,0.47,0.95},{0.92,0.78,0.32}}
local function color(c,a) love.graphics.setColor(c[1],c[2],c[3],a or 1) end
-- Warcraft 3 colours a health bar by relation, not by player colour: green is yours,
-- red is hostile, amber is neutral. The bar used to carry the owner's player colour,
-- which meant that in a fight the only question a four-pixel bar needs to answer --
-- can I shoot this -- was the one it did not answer. Player colour is still on the
-- body, the minimap dot and the selection tile.
-- One swatch per status, so the strip over a unit is readable at a glance without any
-- art: red is harm you are taking, blue holds you still, green protects. The user's own
-- icons drop in over these later; the slot and the position are what the code owes them.
local STATUS_COLOURS={stun={.55,.6,1},root={.4,.5,.9},slow={.55,.75,.95},burn={1,.5,.25},
    guard={.5,.95,.6},other={.85,.85,.85}}
local BAR_OWN={0.42,0.87,0.46}
local BAR_ENEMY={0.9,0.33,0.28}
local BAR_NEUTRAL={0.88,0.74,0.32}
local function barColor(app,e)
    if e.owner==app.player then return BAR_OWN end
    if e.owner==0 then return BAR_NEUTRAL end
    return BAR_ENEMY
end
function App.create(options)
    assert(Content.factions[options.faction or 'bastion'],'unknown faction: use bastion or wild')
    local config={seed=12345,players={{faction=options.faction or 'bastion'},{faction=options.opponent or 'wild'}}}
    local map=Maps.create(options.map)
    local self=setmetatable({options=options,player=1,queue={},sequences={0,0},selected={},groups={},accumulator=0,
        camera={x=28,y=115,zoom=1},previous={},message='Select a worker and build an extractor on a gold mine to begin.',effects={},fonts={}}, {__index=App})
    self.fonts.title=love.graphics.newFont(24);self.fonts.body=love.graphics.newFont(14);self.fonts.small=love.graphics.newFont(12);self.fonts.card=love.graphics.newFont(10)
    if options.replay then
        self.playback=Replay.read(options.replay,Content);config=self.playback.header.config;map=self.playback.header.map
        self.message='Replay playback | commands are read-only'
    end
    self.world=Sim.create(config,Content,map);self.recording=Replay.create(config,Content,map,Replay.OFFLINE_INTERVAL)
    if options.host or options.join then
        self.network=require('src.net.session').create(options,config,Content,map);self.player=self.network.player
    end
    self.settings=options.settings or Settings.load()
    self.widgets=require('src.ui.widgets').create();self.observation=require('src.ui.observation').create()
    self.alerts=require('src.ui.alerts').create();self.audio=require('src.ui.audio').create(self.settings)
    self.clock=0;self.pending={};self.replaySpeed=1;self.healthTrails={}
    self.stats={built=0,buildings=0}
    if options['audio-disabled'] then self.audio.templates={} end
    self.view=Sim.view(self.world,self.player);self.observation:update(self.view)
    self.feedback=require('src.feedback').create()
    self.feedback:observe({},self.view,self.world.tick)
    self.selected={self.world.players[self.player].hero}
    local ok,sprites=pcall(require,'src.sprites')
    if ok then self.sprites=sprites.load() end
    Camera.normalize(self)
    Camera.center(self,self.world.entities[self.view.player.hero].x,self.world.entities[self.view.player.hero].y)
    return self
end
function App:screen(x,y)
    return self.camera.x+x/256*26*self.camera.zoom,self.camera.y+y/256*CELL_Y*self.camera.zoom
end
function App:position(x,y)
    return math.floor((x-self.camera.x)/26/self.camera.zoom*256),math.floor((y-self.camera.y)/CELL_Y/self.camera.zoom*256)
end
-- The view carries its own id index. This used to be a linear scan called once
-- per selected entity per frame, which is quadratic with an army selected.
function App:entity(id)
    return self.view.byId[id]
end
function App:command(kind,id,args)
    if self.playback or self.world.result or (self.network and not self.network.ready) then require('src.ui.command_feedback').notify(self,'rejected',self.playback and 'Replay is read-only' or self.world.result and 'Match has ended' or 'Waiting for match to start',self.activeAction);return false end
    args=args or {};args.entity=id
    self.sequences[self.player]=self.sequences[self.player]+1
    self.pending[self.sequences[self.player]]={kind=kind,group=self.commandGroup or 0,issuedTick=self.world.tick,issuedTime=self.clock,action=self.activeAction,building=args.building,selection=self.cardSelection,x=kind=='build' and args.x and (args.x*256+128) or args.x,y=kind=='build' and args.y and (args.y*256+128) or args.y}
    self.queue[#self.queue+1]={tick=0,player=self.player,sequence=self.sequences[self.player],kind=kind,args=args}
    return true
end
function App:update(dt)
    self.clock=self.clock+dt;self.audio:update(dt);self.alerts:update(dt)
    Camera.update(self,dt)
    if self.banner then self.banner.age=self.banner.age+dt end
    self.showAllBars=love.keyboard.isDown('lalt','ralt')
    if self.followHero then
        local hero=self.view.byId[self.view.player.hero]
        if hero and hero.alive then Camera.center(self,hero.x,hero.y) end
    end
    -- The health trail holds the chunk just lost for a moment before draining it, so a big hit
    -- reads as big instead of melting away with the bar. Under sustained damage the hold keeps
    -- restarting, so it is capped: the trail always starts draining within a second.
    for _,e in ipairs(self.view.entities) do
        local trail=self.healthTrails[e.id] or {value=e.hp};self.healthTrails[e.id]=trail
        if e.hp<trail.value then
            if trail.seen~=e.hp then trail.seen=e.hp;trail.since=self.clock;trail.first=trail.first or self.clock end
            if self.clock-trail.since>=TRAIL_HOLD or self.clock-trail.first>=TRAIL_HOLD_CAP then
                trail.value=math.max(e.hp,trail.value-math.max(dt*e.maxHp*.5,(trail.value-e.hp)*dt/TRAIL_DRAIN))
            end
        else trail.value=e.hp;trail.seen=e.hp;trail.first=nil end
    end
    if self.feedback.update then self.feedback:update(dt) end
    if self.seeking then
        local target=self.seeking;local limit=math.min(target,self.world.tick+40)
        while self.world.tick<limit do
            local tick=self.world.tick+1;Sim.step(self.world,self.playback.frames[tick].commands)
            if self.playback.hashes[tick] then assert(self.playback.hashes[tick]==Hash.bytes(Sim.serializeAuthoritative(self.world)),'Replay diverged at tick '..tick) end
            self.observation:update(Sim.view(self.world,self.player))
        end
        self.view=Sim.view(self.world,self.player);self.message='Seeking '..self.world.tick..' / '..target
        if self.world.tick>=target then self.seeking=nil;self.message='Replay ready' end
        return
    end
    if self.overlay and not self.network then self.accumulator=0;return end
    if self.playback then if self.replayPaused then self.accumulator=0;return end;dt=dt*self.replaySpeed end
    -- Which way the player is panning: -1, 0 or 1 on each axis, from the screen edge and the
    -- arrow keys. Camera.scroll turns that into movement with the speed setting and the ramp.
    local panX,panY=0,0
    if self.settings.edgeScroll and not self.overlay and not self.capture then
        local mx,my=love.mouse.getPosition();local r=Camera.rect(self)
        if Camera.contains(self,mx,my) then
            if mx<8 then panX=-1 elseif mx>r.w-8 then panX=1 end
            if my<r.y+8 then panY=-1 elseif my>r.y+r.h-8 then panY=1 end
        end
    end
    if love.keyboard.isDown('left') then panX=-1 elseif love.keyboard.isDown('right') then panX=1 end
    if love.keyboard.isDown('up') then panY=-1 elseif love.keyboard.isDown('down') then panY=1 end
    Camera.scroll(self,dt,panX,panY)
    if not self.overlay then Camera.clamp(self) end
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
            self.recording=Replay.create(self.network.config,Content,self.network.map,Replay.OFFLINE_INTERVAL)
            self.selected={self.world.players[self.player].hero};self.view=Sim.view(self.world,self.player)
            self.observation=require('src.ui.observation').create();self.observation:update(self.view)
            self.alerts=require('src.ui.alerts').create();self.healthTrails={};self.audio:clear()
            if self.sprites then self.sprites:reset() end
            self.previous={}
            self.feedback:reset();self.feedback:observe({},self.view,self.world.tick)
            for tick=1,3 do self.network:submit(tick,{}) end
        end
    end
    -- A load stall (asset page upload, window drag, GC pause) must not become a
    -- catch-up spiral. Clamp the frame delta, then, offline only, discard backlog
    -- beyond half a second: dropping cosmetic catch-up is preferable to a freeze.
    -- Network play keeps every tick because lockstep peers must agree tick for tick.
    -- Offline pacing scales the wall-clock time handed to the fixed-rate accumulator.
    -- The tick rate, the simulation and its hashes are untouched, so a replay recorded
    -- at any speed replays identically. Network play is pinned to 1x: peers must agree
    -- on how fast ticks are consumed.
    if not self.network and not self.playback then
        dt=dt*(Settings.SPEED_SCALE[self.settings.gameSpeed or 2] or 1)
    end
    self.accumulator=self.accumulator+math.min(dt,0.25)
    if not self.network and self.accumulator>0.5 then
        self.discardedTicks=(self.discardedTicks or 0)+math.floor((self.accumulator-0.5)/0.05)
        self.accumulator=0.5
    end
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
        -- Interpolation needs one previous position per drawn entity. Rebuilding
        -- the table allocated a record per unit per tick; the records are reused
        -- and stamped instead. The stamp matters: an entity that was fogged and
        -- has reappeared must not be interpolated from wherever it was last seen.
        self.previousStamp=(self.previousStamp or 0)+1
        local previous,stamp=self.previous,self.previousStamp
        for _,e in ipairs(self.view.entities) do
            local record=previous[e.id]
            if record then record.x=e.x;record.y=e.y;record.stamp=stamp
            else previous[e.id]={x=e.x,y=e.y,stamp=stamp} end
        end
        if stamp%150==0 then for id,record in pairs(previous) do if record.stamp~=stamp then previous[id]=nil end end end
        local perf=self.perf;if not perf then perf={};self.perf=perf end
        local mark=love.timer.getTime()
        local events=Sim.step(self.world,commands)
        local afterStep=love.timer.getTime();perf.step=(afterStep-mark)*1000
        self.view=Sim.view(self.world,self.player);self.observation:update(self.view)
        require('src.ui.selection').prune(self)
        perf.view=(love.timer.getTime()-afterStep)*1000
        events=Sim.eventsFor(self.world,self.player)
        -- Once a tick as well as on motion: with the pointer held still, units walking
        -- under it must still update the cursor and the hover ring.
        Input.refreshHover(self)
        self.alerts:observe(events,self)
        if self.sprites then self.sprites:observe(events,self.view,self.world.tick) end
        self.feedback:observe(events,self.view,self.world.tick)
        local acceptedCount,rejectedCount,firstReason=0,0,nil
        for _,event in ipairs(events) do
            if (event.kind=='rejected' or event.kind=='accepted') and event.player==self.player then
                local pending=self.pending[event.sequence];self.pending[event.sequence]=nil
                require('src.ui.command_feedback').resolve(self,event,pending)
                if pending then self.lastCommandTiming={ticks=self.world.tick-pending.issuedTick,milliseconds=math.floor((self.clock-pending.issuedTime)*1000+.5)} end
                if event.kind=='rejected' then rejectedCount=rejectedCount+1;firstReason=firstReason or (self.uiNotice and self.uiNotice.kind=='rejected' and self.uiNotice.text) or event.reason;if pending and pending.kind=='build' then if pending.selection==self.cardSelection and require('src.ui.actions').context(self).canBuild then self.building=pending.building end;self.awaitingPlacement=nil end
                elseif pending then acceptedCount=acceptedCount+1;if pending.kind=='build' then self.awaitingPlacement=nil end end
            elseif event.kind=='researched' then self.audio:play('research',self,event.x,event.y)
            elseif event.kind=='ping' then self.localPing={x=event.pingX,y=event.pingY,time=self.clock,player=event.player};self.audio:play('alert')
            elseif event.kind=='windup' then self.audio:play('windup',self,event.x,event.y)
            elseif event.kind=='healed' then self.audio:play('heal',self,event.x,event.y)
            elseif event.kind=='attack' or event.kind=='death' then self.audio:play(event.kind,self,event.x,event.y)
            elseif event.kind=='constructed' or event.kind=='recruited' or event.kind=='revived' then self.audio:play('ready',self,event.x,event.y) end
            if event.kind=='delivered' and event.owner==self.player then self:announceDelivery(event) end
            self:recordStat(event)
        end
        for _,unit in ipairs(self.view.entities) do if unit.owner==self.player and unit.alive and (unit.order.kind=='build' and not unit.goal) then self.audio:play('work',self,unit.x,unit.y);break end end
        self.audio:play('ambience')
        if rejectedCount>0 then self.message=acceptedCount>0 and (acceptedCount..' accepted, '..rejectedCount..' rejected: '..firstReason) or firstReason elseif acceptedCount>0 then self.message=acceptedCount..' order'..(acceptedCount==1 and '' or 's')..' accepted' end
        if not self.playback then Replay.record(self.recording,self.world,commands)
        elseif self.playback.hashes[tick] then
            assert(self.playback.hashes[tick]==Hash.bytes(Sim.serializeAuthoritative(self.world)),'Replay diverged at tick '..tick)
        end
        if self.network and tick%100==0 then local bytes=Sim.serializeAuthoritative(self.world);self.network:checksum(tick,Hash.bytes(bytes),bytes) end
        self.accumulator=self.accumulator-0.05;steps=steps+1
        if self.world.result and not self.banner then
            local won=self.world.result.winner==self.player
            local built,lost,kills=self:matchStats()
            local reason=self.world.result.reason=='control' and (won and 'Held both control points   ' or 'The enemy held both control points   ') or ''
            self.banner={won=won,age=0,
                detail=reason..string.format('%02d:%02d   %d units built   %d lost   %d kills',
                    math.floor(self.world.tick/1200),math.floor(self.world.tick/20)%60,
                    built,lost,kills)}
            self.feedback.banner=self.banner
        end
    end
end
-- Painter's order: feet first, entity id to break ties. Defined once instead of as a
-- fresh closure every frame.
local function byDepth(a,b)
    local ay=a.y+(a.size-1)*256;local by=b.y+(b.size-1)*256
    if ay~=by then return ay<by end
    return a.id<b.id
end
-- Rebuilt once per frame rather than scanned per drawn entity.
-- Also remembers when each unit joined the selection, which is what the selection pop reads.
local function selectionSet(self)
    local set=self.selectedSet
    if not set then set={};self.selectedSet=set else for key in pairs(set) do set[key]=nil end end
    local since=self.selectedSince;if not since then since={};self.selectedSince=since end
    for _,v in ipairs(self.selected) do set[v]=true;if not since[v] then since[v]=self.clock end end
    for id in pairs(since) do if not set[id] then since[id]=nil end end
    return set
end
local function selected(self,id) return self.selectedSet and self.selectedSet[id] or false end
-- A newly selected unit's ring settles into place over a short beat instead of blinking on, so
-- a box selection reads as the units answering. Scale, not a new effect: nothing is allocated.
local SELECT_POP=0.08
local function selectPop(self,id)
    local at=self.selectedSince and self.selectedSince[id]
    if not at then return 1 end
    local t=(self.clock-at)/SELECT_POP
    if t>=1 then return 1 end
    return 1+0.15*(1-t)
end
-- Resource gains are announced from the observed ledger delta rather than from a
-- delivery event, because the simulation does not currently emit one. That means a
-- refund or a bounty is announced the same way a drop-off is; the amount is always
-- correct, only the attribution is approximate. Phase 6's `delivered` event replaces it.
-- Units and buildings produced are counted from the player's own events, which is exact
-- because you always observe your own production. Kills and losses are read from the
-- simulation's tallies instead: counting deaths from observed events silently
-- under-reports a kill made outside your sight.
function App:recordStat(event)
    local stats=self.stats
    if event.kind=='recruited' and event.owner==self.player then stats.built=stats.built+1
    elseif event.kind=='constructed' and event.owner==self.player then stats.buildings=stats.buildings+1 end
end
function App:matchStats()
    local player=self.view.player
    local stats=self.stats
    return stats.built,player.unitsLost or 0,player.kills or 0,stats.buildings,player.buildingsLost or 0
end
-- Income is announced from the simulation's `delivered` event, so the figure and the
-- place it appears are both exact: the text rises over the worker that actually made the
-- delivery, and a refund or a kill bounty is never mistaken for one.
local RESOURCE_COLOURS={gold={.96,.82,.36}}
function App:announceDelivery(event)
    local worker=self.view.byId[event.entity]
    local x,y=event.x,event.y
    if worker then x,y=worker.x,worker.y end
    if not x or not event.amount then return end
    self.feedback:text('income','+'..event.amount..' '..tostring(event.resource),x,y,RESOURCE_COLOURS[event.resource])
end
-- Where an entity is drawn: the authoritative position eased from where it stood at the
-- previous tick, so the 20 Hz simulation reads as continuous motion. Returns the raw
-- position for anything that does not move.
function App:interpolated(e)
    local x,y=e.x,e.y;local prev=self.previous[e.id]
    if prev and prev.stamp~=self.previousStamp then prev=nil end
    if prev and (e.category=='unit' or e.category=='carrier') then
        local alpha=math.min(1,self.accumulator/0.05)
        x=prev.x+(x-prev.x)*alpha;y=prev.y+(y-prev.y)*alpha
    end
    return x,y
end
-- Screen position for anything pinned to an entity: an effect, an order line, a tracer
-- endpoint. These used to draw at the raw tick position, so a spark stuttered at 20 Hz
-- over a unit gliding at the frame rate. Falls back to the supplied coordinates when
-- the entity is gone, which is what keeps a death effect where the body fell.
function App:anchorScreen(id,x,y)
    local e=id and self.view.byId[id]
    if e then x,y=self:interpolated(e) end
    return self:screen(x,y)
end
function App:drawEntity(e)
    local g=love.graphics
    local x,y=self:interpolated(e)
    -- The sprite layer reads the previous tick's position to pick a facing and to time
    -- the walk cycle by distance travelled, so it needs the record, not the eased point.
    local prev=self.previous[e.id]
    if prev and prev.stamp~=self.previousStamp then prev=nil end
    x,y=self:screen(x,y)
    local z=self.camera.zoom
    local team=colors[e.owner] or {0.76,0.61,0.39}
    if not e.alive and not (self.sprites and self.sprites.units[Frames.assetId(e)]) then
        color(team,0.5);g.ellipse('fill',x,y,15*z,5*z);return
    end
    g.setColor(0,0,0,0.28);g.ellipse('fill',x,y,12*z,5*z)
    -- Ring colour states what the unit is to the viewer, which is the fastest read in
    -- a fight: own selection, hovered, ally, or enemy.
    local isSelected=selected(self,e.id)
    -- The order acknowledgement: for a fifth of a second after a command the ordered
    -- units' circles brighten and swell. Warcraft 3 answers a click before the
    -- simulation has run, and this is the half of that answer you can see.
    local ack=self.ackFlash and self.ackFlash[e.id] and self.ackFlashAt and (self.clock-self.ackFlashAt)<ACK_FLASH
    if isSelected or ack then
        if ack then
            local swell=1+(1-(self.clock-self.ackFlashAt)/ACK_FLASH)*0.35
            g.setColor(0.85,1,0.9);g.setLineWidth(2.5)
            g.ellipse('line',x,y,15*z*swell,7*z*swell)
        else
            -- A selected enemy or neutral, being inspected, keeps its relation colour.
            if e.owner==self.player then g.setColor(0.55,0.93,0.73) elseif e.owner==0 then g.setColor(.95,.78,.38) else g.setColor(1,.38,.3) end
            local pop=selectPop(self,e.id)
            g.setLineWidth(2);g.ellipse('line',x,y,15*z*pop,7*z*pop)
        end
    elseif self.hoverId==e.id then
        if e.owner==self.player then g.setColor(.55,.93,.73,.7)
        elseif e.owner==0 then g.setColor(.85,.72,.4,.7)
        else g.setColor(1,.4,.32,.8) end
        g.setLineWidth(2);g.ellipse('line',x,y,15*z,7*z)
    end
    if e.category=='building' then
        local w,h=e.size*26*z,e.size*CELL_Y*z
        x=x-13*z;y=y-(CELL_Y/2)*z
        if isSelected then
            if e.owner==self.player then g.setColor(.55,.93,.73) elseif e.owner==0 then g.setColor(.95,.78,.38) else g.setColor(1,.38,.3) end
            g.rectangle('line',x,y,w,h)
        end
        color(team,0.5);g.rectangle('fill',x,y-22*z,w,h+22*z)
        color(team);g.polygon('fill',x,y-22*z,x+w/2,y-38*z,x+w,y-22*z,x+w/2,y-8*z)
        g.setColor(0.07,0.1,0.13);g.rectangle('fill',x+w*0.35,y+h-24*z,w*0.3,24*z)
        if e.remaining>0 then
            g.setColor(.72,.58,.32);g.rectangle('line',x,y-22*z,w,h+22*z);g.line(x,y-22*z,x+w,y+h,x+w,y-22*z,x,y+h)
            g.setColor(.07,.1,.12);g.rectangle('fill',x,y-44*z,w,5*z)
            g.setColor(.95,.77,.36);g.rectangle('fill',x,y-44*z,w*(1-e.remaining/Content.buildings[e.kind].buildTicks),5*z)
        end
        g.setColor(0.92,0.94,0.91);g.setFont(self.fonts.small);g.print(({hq='HQ',tower='T',barracks='WAR',extractor='MINE',outpost='OUTPOST'})[e.kind] or e.kind,x+4,y+h-18*z)
    elseif e.category=='node' then
        if e.resource=='gold' then x=x+(e.size-1)*13*z;y=y+(e.size-1)*CELL_Y/2*z;z=z*e.size;g.setColor(0.9,0.71,0.27);g.polygon('fill',x-12*z,y,x-5*z,y-20*z,x+8*z,y-17*z,x+14*z,y)
        else g.setColor(0.32,0.24,0.13);g.rectangle('fill',x-3*z,y-22*z,6*z,22*z);g.setColor(0.21,0.48,0.33);g.polygon('fill',x-16*z,y-12*z,x,y-44*z,x+16*z,y-12*z) end
    -- Carriers are drawn small and stooped, with the gold they are holding above them, so
    -- a stream of them reads at a glance as income crossing the map -- and so an enemy
    -- can see what it is worth cutting.
    -- A shot in flight: a short streak along its own heading, so which way it is going
    -- reads without any art. Interpolated like a unit, because at 20 Hz a fast shot
    -- would otherwise jump a third of a cell per frame.
    elseif e.category=='projectile' then
        local len=6*z
        local dx,dy=e.dx or 0,e.dy or 0
        local mag=math.sqrt(dx*dx+dy*dy)
        if mag>0 then dx,dy=dx/mag*len,dy/mag*len*(CELL_Y/26) else dx,dy=len,0 end
        g.setColor(1,.92,.6,.95);g.setLineWidth(math.max(1.5,2*z))
        g.line(x-dx,y-dy-14*z,x+dx,y+dy-14*z)
        g.setColor(1,.75,.35,.5);g.circle('fill',x+dx,y+dy-14*z,2*z)
        g.setLineWidth(1)
    elseif e.category=='carrier' then
        z=z*0.66
        color(team);g.rectangle('fill',x-6*z,y-16*z,12*z,12*z,3*z)
        g.setColor(0.9,0.82,0.66);g.circle('fill',x,y-19*z,4*z)
        if (e.payload or 0)>0 then g.setColor(0.96,0.82,0.36);g.polygon('fill',x-6*z,y-24*z,x,y-30*z,x+6*z,y-24*z,x,y-21*z) end
        if self.feedback:flashing(e.id,self.world.tick) then g.setColor(1,1,1,.55);g.ellipse('fill',x,y-10*z,8*z,10*z) end
    else
        local d=Content.units[e.kind];z=z*self:unitVisualScale(e);local height=d.hero and 31 or 23
        -- Your own badly hurt units pulse on the ground, so the one about to die is found without
        -- reading every bar. Drawn rather than spawned, so the effect budget is untouched.
        if e.owner==self.player and e.alive and e.hp*100<e.maxHp*LOW_HEALTH then
            g.setColor(1,.3,.25,.25+.2*math.sin(self.clock*8));g.setLineWidth(2)
            g.ellipse('line',x,y,13*z,6*z);g.setLineWidth(1)
            self.lowHealthDrawn=(self.lowHealthDrawn or 0)+1
        end
        -- Anticipation: the body swells a little as a swing gathers and settles as it lands, so a
        -- blow reads as thrown before the hit appears.
        local swing=self.feedback.windup and self.feedback:windup(e.id,self.world.tick)
        if swing then z=z*(1+WINDUP_SWELL*math.sin(swing*math.pi));self.windupsDrawn=(self.windupsDrawn or 0)+1 end
        local drawn=self.sprites and self.sprites:draw(e,x,y,z,team,prev,self.world.tick,self.view)
        if not drawn then
            color(team);g.rectangle('fill',x-8*z,y-height*z,16*z,(height-5)*z,4*z)
            g.setColor(0.9,0.82,0.66);g.circle('fill',x,y-(height+4)*z,6*z)
            g.setColor(0.12,0.18,0.2);g.rectangle('fill',x-8*z,y-5*z,6*z,6*z);g.rectangle('fill',x+2*z,y-5*z,6*z,6*z)
            if d.hero then g.setColor(1,0.85,0.38);g.polygon('fill',x-7*z,y-37*z,x-8*z,y-46*z,x,y-40*z,x+8*z,y-46*z,x+7*z,y-37*z) end
            if e.kind=='worker' then g.setColor(0.74,0.63,0.44);g.setLineWidth(3*z);g.line(x+10*z,y-30*z,x+10*z,y-4*z) end
        end
        -- A white wash for two ticks after an impact. It reads at a glance in a mass
        -- fight where individual health bars are too small to follow.
        if self.feedback:flashing(e.id,self.world.tick) then
            g.setColor(1,1,1,.55);g.ellipse('fill',x,y-(height/2)*z,11*z,(height/2+3)*z)
        end
        -- Bars for the selected, the damaged, and everything while Alt is held. Drawing
        -- one over every unit at all times turns a battle into a wall of bars.
        local damaged=e.hp<e.maxHp
        local bars=self.settings.healthBars or 'damaged'
        if bars=='always' or self.showAllBars or isSelected or (bars~='selected' and damaged) then
            local barY=y-(d.hero and 53 or 40)*z
            g.setColor(0.06,0.08,0.1);g.rectangle('fill',x-14*z,barY,28*z,4*z)
            local trail=self.healthTrails[e.id];if trail then g.setColor(.95,.74,.42);g.rectangle('fill',x-14*z,barY,28*z*trail.value/e.maxHp,4*z) end
            color(barColor(self,e));g.rectangle('fill',x-14*z,barY,28*z*e.hp/e.maxHp,4*z)
        end
        -- Mana under the health bar, and a status strip above it. A stunned enemy has to
        -- read as stunned or the player cannot tell why their focus target stopped, and
        -- a caster with no mana left has to read that way before they press the key.
        if e.maxMana and e.maxMana>0 then
            local manaY=y-(d.hero and 48 or 35)*z
            g.setColor(0.06,0.08,0.1);g.rectangle('fill',x-14*z,manaY,28*z,3*z)
            g.setColor(.42,.6,.95);g.rectangle('fill',x-14*z,manaY,28*z*(e.mana or 0)/e.maxMana,3*z)
        end
        if e.statuses and #e.statuses>0 then
            local sy=y-(d.hero and 60 or 47)*z
            for index,status in ipairs(e.statuses) do
                local c=STATUS_COLOURS[status.id] or STATUS_COLOURS.other
                g.setColor(c[1],c[2],c[3])
                g.rectangle('fill',x-14*z+(index-1)*6*z,sy,5*z,5*z,1)
            end
        end
        -- Control-group number above a selected member, as a place to look after Tab.
        local badge=isSelected and self.groupBadges and self.groupBadges[e.id]
        if badge then
            g.setFont(self.fonts.small);g.setColor(.08,.1,.12,.8)
            g.rectangle('fill',x-6*z,y-(d.hero and 66 or 53)*z,12*z,11*z,2)
            g.setColor(.92,.94,.7);g.printf(badge,x-6*z,y-(d.hero and 65 or 52)*z,12*z,'center')
        end
    end
end
function App:draw()
    if self.options['sprite-proof'] then return require('src.sprite_proof').draw(self.sprites) end
    local g=love.graphics;local width,height=g.getDimensions();local panel=width
    g.clear(0.055,0.078,0.088)
    self.lowHealthDrawn=0;self.windupsDrawn=0
    local cameraRect=Camera.rect(self);if self.camera.viewportHeight and self.camera.viewportHeight~=cameraRect.h then local cx,cy=self:position(cameraRect.w/2,cameraRect.y+cameraRect.h/2);Camera.normalize(self);Camera.center(self,cx,cy) end;self.camera.viewportHeight=cameraRect.h
    local viewport=cameraRect;g.setScissor(viewport.x,viewport.y,viewport.w,viewport.h)
    local m=self.world.map;local z=self.camera.zoom
    -- Screen shake is applied as a draw-time translate on the world pass only, so it
    -- never moves the HUD, never feeds back into camera clamping, and never reaches
    -- the coordinate transforms that turn clicks into orders.
    local shakeX,shakeY=0,0
    if self.settings.screenShake~=false then shakeX,shakeY=self.feedback.shakeX or 0,self.feedback.shakeY or 0 end
    if shakeX~=0 or shakeY~=0 then g.push();g.translate(shakeX,shakeY) end
    self.groupBadges=self:controlGroupBadges()
    local terrain=Minimap.cache(self)
    -- The ground, baked per chunk from the map's terrain types (src/ui/terrain.lua). It used to
    -- be the minimap's one-pixel-per-cell canvas stretched over the world.
    if not self.terrainRenderer or self.terrainRenderer.map~=m then
        if self.terrainRenderer then Terrain.release(self.terrainRenderer) end
        self.terrainRenderer=Terrain.create(m)
    end
    Terrain.draw(self.terrainRenderer,self.camera.x,self.camera.y,26*z,CELL_Y*z,viewport)
    g.setColor(1,1,1);g.draw(terrain.fog,self.camera.x,self.camera.y,0,26*z,CELL_Y*z)
    -- Control points lie on the ground, under everything standing on them. The ring is the
    -- owner's colour; the fill grows with a capture in progress, in the capturer's colour.
    local control=self.view.control
    if control then
        local rules=Content.rules.control or require('src.sim.control').DEFAULT
        local rx,ry=rules.radius/256*26*z,rules.radius/256*CELL_Y*z
        for _,point in ipairs(control.points) do
            local px,py=self:screen(point.x,point.y)
            if point.progress>0 then
                local t=point.progress/rules.captureTicks
                if point.capturer==self.player then g.setColor(.35,.78,1,.3) else g.setColor(1,.35,.25,.3) end
                g.ellipse('fill',px,py,rx*t,ry*t)
            end
            if point.owner==self.player then g.setColor(.35,.78,1,.9) elseif point.owner==0 then g.setColor(.9,.82,.45,.9) else g.setColor(1,.35,.25,.9) end
            g.setLineWidth(2*z);g.ellipse('line',px,py,rx,ry);g.setLineWidth(1)
            g.ellipse('fill',px,py,5*z,3*z)
        end
    end
    selectionSet(self)
    -- Cull to the viewport before sorting. On the shipping 128x112 map most of the
    -- army is off-screen at normal zoom, and every off-screen entity previously paid a
    -- depth-sort comparison and a full drawEntity of shadow, body, rings and health bar
    -- that the scissor then threw away. The pad covers sprites drawn well above their
    -- feet and multi-cell building footprints.
    local entities=self.drawList
    if entities then for i=#entities,1,-1 do entities[i]=nil end else entities={};self.drawList=entities end
    local left,top=self:position(cameraRect.x,cameraRect.y)
    local right,bottom=self:position(cameraRect.x+cameraRect.w,cameraRect.y+cameraRect.h)
    local pad=6*256
    left=left-pad;top=top-pad;right=right+pad;bottom=bottom+pad
    local tick=self.world.tick
    local count=0
    for _,e in ipairs(self.view.entities) do
        if (e.alive or (e.category=='unit' and e.deathTick and tick-e.deathTick<40))
            and e.x>=left and e.x<=right and e.y>=top and e.y<=bottom then
            count=count+1;entities[count]=e
        end
    end
    table.sort(entities,byDepth)
    for i=1,count do self:drawEntity(entities[i]) end
    if not self.options['effects-disabled'] then self.feedback:draw(self);require('src.ui.command_feedback').draw(self) end
    -- Target marker: green for a move, red for an attack, contracting rather than
    -- expanding so the eye is pulled to the destination instead of away from it.
    local marker=self.orderMarker
    if marker and self.clock-(marker.time or 0)<.45 then
        local mx,my=self:screen(marker.x,marker.y)
        local t=(self.clock-(marker.time or 0))/.45
        local c=ORDER_COLORS[marker.kind] or ORDER_COLORS.move
        g.setColor(c[1],c[2],c[3],1-t)
        g.setLineWidth(2*z)
        for ring=0,1 do
            local scale=(1-t)*(1+ring*0.55)
            g.ellipse('line',mx,my,(4+14*scale)*z,(2+8*scale)*z)
        end
        -- A focused attack is aimed at something, not somewhere: a cross says so.
        if marker.kind=='attack' then
            local s=(4+6*(1-t))*z
            g.line(mx-s,my-s*.6,mx+s,my+s*.6);g.line(mx-s,my+s*.6,mx+s,my-s*.6)
        end
        g.setLineWidth(1)
    end
    -- Formation ghosts: the cell each unit of the last group order was actually given. They come
    -- from the orders the simulation accepted, so they appear once the order has been applied
    -- and show exactly what the formation did, rather than a prediction of it.
    self.formationGhosts=0
    if marker and marker.group and (marker.count or 0)>1 and self.ackFlash and self.clock-(self.ackFlashAt or -10)<FORMATION_GHOST then
        local fade=1-(self.clock-self.ackFlashAt)/FORMATION_GHOST
        local c=ORDER_COLORS[marker.kind] or ORDER_COLORS.move
        g.setColor(c[1],c[2],c[3],.45*fade)
        for id in pairs(self.ackFlash) do
            local e=self.view.byId[id]
            local o=e and e.order
            if o and o.x and o.group==marker.group then
                local gx,gy=self:screen(o.x*256+128,o.y*256+128)
                g.circle('fill',gx,gy,2.5*z)
                self.formationGhosts=self.formationGhosts+1
            end
        end
    end
    -- Ability targeting preview. A spell you cannot see the shape of is a spell you
    -- learn by wasting it: the ring is how far the caster may cast without walking, the
    -- circle is what an area will actually cover, and the line is where a skill shot
    -- goes. Drawn from the same record the click handler reads, so what is shown and
    -- what happens cannot drift apart.
    local targeting=self.targeting
    if targeting and targeting.spec then
        local spec=targeting.spec
        local caster=self:entity(require('src.ui.selection').primary(self))
        local mx,my=love.mouse.getPosition()
        local wx,wy=self:position(mx,my)
        if caster then
            local cx,cy=self:screen(self:interpolated(caster))
            if (spec.range or 0)>0 then
                g.setColor(.55,.85,1,.28);g.setLineWidth(1)
                g.ellipse('line',cx,cy,spec.range/256*26*z,spec.range/256*CELL_Y*z)
            end
            if spec.target=='direction' then
                local dx,dy=wx-caster.x,wy-caster.y
                local length=math.sqrt(dx*dx+dy*dy)
                if length>0 then
                    local ex,ey=self:screen(caster.x+dx/length*spec.range,caster.y+dy/length*spec.range)
                    g.setColor(1,.55,.4,.6);g.setLineWidth(math.max(2,spec.width/256*26*z*.5))
                    g.line(cx,cy,ex,ey);g.setLineWidth(1)
                end
            end
        end
        if spec.target=='area' then
            local ax,ay=self:screen(wx,wy)
            g.setColor(1,.55,.4,.5);g.setLineWidth(2)
            g.ellipse('line',ax,ay,spec.radius/256*26*z,spec.radius/256*CELL_Y*z)
            g.setColor(1,.55,.4,.12)
            g.ellipse('fill',ax,ay,spec.radius/256*26*z,spec.radius/256*CELL_Y*z)
            g.setLineWidth(1)
        elseif spec.target=='none' and caster then
            local cx,cy=self:screen(self:interpolated(caster))
            g.setColor(.6,1,.75,.45);g.setLineWidth(2)
            g.ellipse('line',cx,cy,spec.radius/256*26*z,spec.radius/256*CELL_Y*z);g.setLineWidth(1)
        end
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
        local px,py=self:anchorScreen(e.id,e.x,e.y)
        -- A selected building shows where its production is being sent.
        if e.rally then
            local rx,ry,rallyAnchor
            if e.rally.target then local t=self:entity(e.rally.target);if t then rx,ry=t.x,t.y;rallyAnchor=t.id end
            else rx,ry=e.rally.x*256+128,e.rally.y*256+128 end
            if rx then
                local x,y=self:anchorScreen(rallyAnchor,rx,ry)
                g.setColor(.95,.85,.4,.5);g.setLineWidth(1);g.line(px,py,x,y)
                g.setColor(.95,.85,.4)
                g.line(x,y,x,y-16*z);g.polygon('fill',x,y-16*z,x+11*z,y-12*z,x,y-8*z)
            end
        end
        local orders={e.order};for _,order in ipairs(e.orders or {}) do orders[#orders+1]=order end
        for _,order in ipairs(orders) do local wx,wy
            local anchor;if order.x then wx=order.x*256+128;wy=order.y*256+128 elseif order.target then local t=self:entity(order.target);if t then wx,wy=t.x,t.y;anchor=t.id end end
            if wx then
                local x,y=self:anchorScreen(anchor,wx,wy)
                -- A patrol is a beat, not a destination: draw the whole run.
                if order.kind=='patrol' and order.originX then
                    local ox,oy=self:screen(order.originX*256+128,order.originY*256+128)
                    g.setColor(.45,.8,.95,.6);g.setLineWidth(2*z);g.line(ox,oy,x,y)
                    g.circle('line',ox,oy,5*z);g.circle('line',x,y,5*z)
                    g.setLineWidth(1)
                end
                g.setColor(.5,.8,.6,.5);g.line(px,py,x,y);g.circle('line',x,y,4);px,py=x,y
            end
        end
    end end
    -- Cosmetic day/night wash over the world only, never the HUD, and never anything
    -- the simulation can observe: sight radius and combat are unchanged by the hour.
    -- Driven by the tick so it is identical in a replay and for every observer.
    if self.settings.dayNight then
        local phase=(self.world.tick%DAY_LENGTH)/DAY_LENGTH
        local night=(1-math.cos(phase*2*math.pi))/2
        g.setColor(0.10,0.13,0.32,night*0.34)
        g.rectangle('fill',viewport.x,viewport.y,viewport.w,viewport.h)
    end
    if shakeX~=0 or shakeY~=0 then g.pop() end
    g.setScissor();Hud.draw(self);Hud.control(self)
    self.feedback:drawText(self,width,height)
end
-- Which control group each selected unit belongs to, for the badge above it. Built once
-- per frame; a unit in several groups shows the lowest, matching what the number keys do.
function App:controlGroupBadges()
    local badges=self.badgeScratch
    if badges then for key in pairs(badges) do badges[key]=nil end else badges={};self.badgeScratch=badges end
    for number=1,9 do
        local group=self.groups[number]
        if group then for _,id in ipairs(group) do if badges[id]==nil then badges[id]=number end end end
    end
    return badges
end

function App:unitVisualScale(e)
    local d=Content.units[e.kind];if not d then return 1 end
    local u=self.sprites and self.sprites.units[Frames.assetId(e)]
    local target=d.hero and 38.4 or d.worker and 26.24 or 32
    return u and target/(u.metadata.bodyHeightPixels*(u.metadata.drawScale or 1)) or d.worker and .82 or 1
end
-- `selectable` leaves out what can be shot but never selected: carriers and shots in flight.
function App:pick(x,y,ownOnly,selectable)
    local best,dist
    for _,e in ipairs(self.view.entities) do
        if e.alive and (not ownOnly or e.owner==self.player) and not (selectable and (e.category=='carrier' or e.category=='projectile')) then
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
function App:mousepressed(...) return Input.mousepressed(self,...) end
function App:mousereleased(...) return Input.mousereleased(self,...) end
function App:mousemoved(...) return Input.mousemoved(self,...) end
function App:keypressed(...) return Input.keypressed(self,...) end
function App:wheelmoved(_,dy)
    if self.overlay then return end
    local x,y=love.mouse.getPosition();if Camera.contains(self,x,y) then Camera.zoom(self,x,y,dy) end
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
        if self.playback.hashes[i] then assert(self.playback.hashes[i]==Hash.bytes(Sim.serializeAuthoritative(self.world)),'Replay diverged at tick '..i) end
        self.observation:update(Sim.view(self.world,self.player))
    end
    self.view=Sim.view(self.world,self.player);self.previous={};self.accumulator=0;self.feedback:reset();self.audio:clear()
    self.alerts=require('src.ui.alerts').create();self.selected={self.view.player.hero};self.cardPage=nil;self.cardSelection=nil;self.uiNotice=nil;self.costFlash=nil;self.commandMarks={};self.orderMarker=nil;if self.sprites then self.sprites:reset() end
end
-- Saving a replay must never be able to take the game down with it. A packaged build
-- can easily be sitting somewhere the player cannot write -- Program Files, a read-only
-- share, a different working directory than the one it was launched from -- and this
-- runs from love.quit, so a failure here would turn "quit the game" into a crash.
-- The save directory always exists and is always writable, so it is the fallback.
function App:save(path)
    if self.playback then return false end
    local name=os.date('%Y%m%d-%H%M%S')..'-player-'..self.player..'.replay'
    path=path or ('artifacts/match-'..name)
    local bytes=Replay.encode(self.recording)
    local ok,err=pcall(function()
        local file=assert(io.open(path,'wb'));file:write(bytes);file:close()
    end)
    if not ok then
        local relative='match-'..name
        if love.filesystem.write(relative,bytes) then
            path=love.filesystem.getSaveDirectory()..'/'..relative;ok=true
        end
    end
    if not ok then
        self.message='Could not save replay: '..tostring(err);print(self.message);return false
    end
    pcall(require('src.ui.replay_library').remember,path)
    self.message='Replay saved: '..path;print(self.message)
    return true
end
function App:close() if not self.noAutoSave then self:save() end;self.audio:clear();if self.miniCache then self.miniCache.terrain:release();self.miniCache.fog:release();self.miniCache=nil end;if self.terrainRenderer then Terrain.release(self.terrainRenderer);self.terrainRenderer=nil end;if self.network then self.network:close() end end
return App
