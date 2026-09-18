-- Game juice: what the world does back when something happens in it. Presentation only. It
-- reads the same filtered event stream and view the rest of the interface reads, so it can
-- show nothing the player could not already see, and it never writes to the simulation.
--
-- Three things are drawn: particles (dust, sparks, debris, a capped pool), rings and decals
-- on the ground (impacts, splash and ability circles, scorch where a building fell), and the
-- owner's descent markers for call-downs and drop pods, read from the view's own queues.
-- Everything a reaction does is listed in one table, REACTIONS, keyed by event kind: a cue
-- name for the sound that will one day be recorded for it, a ring, a burst of particles, a
-- shake, a word. Add a row to react to a new event; art and sound slot in behind the names.
--
-- The randomness here is cosmetic and comes from its own generator, never the simulation's.
local J={}
local PARTICLE_CAP=384
local RING_CAP=96
local DECAL_CAP=48
local DECAL_LIFE=24
local COLOURS={
    dust={.62,.56,.46},spark={1,.86,.5},debris={.42,.4,.38},ember={1,.55,.25},
    chip={.45,.85,1},charge={.5,1,.6},heal={.5,1,.62},flak={1,.75,.4},gold={1,.82,.3},door={.6,1,.75}}
-- ring: {radius in cells, seconds, colour}; burst: {count, colour, speed in cells/s, lift};
-- cue: the audio manifest name; shake: amplitude; text: a word over the spot.
local REACTIONS={
    stack_burst={cue='burst',ring={1.3,.35,'gold'},burst={12,'spark',3.2,70},shake=1.5,text=function(ev) return '-'..tostring(ev.damage or '') end,textColour='gold'},
    pod_landed={cue='pod_land',ring={2.2,.5,'dust'},burst={18,'dust',2.6,40},shake=3,decal=1.2,at='pod'},
    landed={cue='land',ring={3,.6,'dust'},burst={24,'dust',3,45},shake=3.5},
    landing={cue='landing',at='land'},
    pod_launched={cue='pod_launch',at='pod'},
    requisitioned={cue='requisition'},
    call_down_ready={cue='ready_to_land',text=function(ev,app) local d=app.content.buildings[ev.building];return (d and d.label or 'Building')..' ready to land' end,textColour='door',at='hq'},
    landing_blocked={cue='rejected',text=function() return 'Landing site blocked' end,textColour='ember',at='hq'},
    harvest_started={cue='harvest',burst={3,'chip',1.4,50},at='target'},
    delivered={cue='deliver'},
    depleted={cue='depleted',ring={1.2,.5,'dust'},burst={12,'dust',1.8,35},text=function() return 'Exhausted' end,textColour='dust'},
    garrisoned={cue='garrison',ring={1.4,.3,'door'},at='target'},
    unloaded={cue='unload',ring={.7,.25,'door'}},
    garrison_full={text=function() return 'Full' end,textColour='ember',at='target'},
    projectile_hit={burst={6,'spark',2.4,50},at='target'},
    status_applied={ring={.8,.3,'flak'}},
    healed={burst={2,'heal',.5,90}},
    constructed={burst={10,'dust',1.6,30}},
    channel_started={cue='barrage'},
}
function J.create()
    return setmetatable({particles={},rings={},decals={},clock=0,tick=nil,
        rng=love.math and love.math.newRandomGenerator(7) or nil,counts={}},{__index=J})
end
function J:reset() self.particles={};self.rings={};self.decals={};self.tick=nil end
function J:random() if self.rng then return self.rng:random() end;return .5 end
-- A particle lives in world subunits on the ground plane with a height in screen units, so
-- it stays put while the camera moves and falls the same at every zoom.
function J:burst(x,y,count,colour,speed,lift,height)
    local particles=self.particles
    for _=1,count do
        if #particles>=PARTICLE_CAP then return end
        local angle=self:random()*6.2831853;local v=(.35+self:random()*.65)*speed*256
        particles[#particles+1]={x=x,y=y,vx=math.cos(angle)*v,vy=math.sin(angle)*v*.6,
            h=height or 4,vh=(.5+self:random()*.5)*lift,age=0,life=.45+self:random()*.5,colour=COLOURS[colour] or COLOURS.dust,size=2.5+self:random()*2.5}
    end
end
function J:ring(x,y,radius,life,colour,filled)
    if #self.rings>=RING_CAP then table.remove(self.rings,1) end
    self.rings[#self.rings+1]={x=x,y=y,radius=radius,life=life,age=0,colour=COLOURS[colour] or COLOURS.dust,filled=filled}
end
function J:decal(x,y,radius)
    if #self.decals>=DECAL_CAP then table.remove(self.decals,1) end
    self.decals[#self.decals+1]={x=x,y=y,radius=radius,age=0}
end
function J:update(dt)
    self.clock=self.clock+dt
    local particles=self.particles
    for i=#particles,1,-1 do
        local p=particles[i];p.age=p.age+dt
        if p.age>=p.life then particles[i]=particles[#particles];particles[#particles]=nil
        else
            p.x=p.x+p.vx*dt;p.y=p.y+p.vy*dt;p.vx=p.vx*(1-2.5*dt);p.vy=p.vy*(1-2.5*dt)
            p.h=p.h+p.vh*dt;p.vh=p.vh-260*dt
            if p.h<0 then p.h=0;p.vh=-p.vh*.3 end
        end
    end
    for i=#self.rings,1,-1 do local r=self.rings[i];r.age=r.age+dt;if r.age>=r.life then table.remove(self.rings,i) end end
    for i=#self.decals,1,-1 do local d=self.decals[i];d.age=d.age+dt;if d.age>=DECAL_LIFE then table.remove(self.decals,i) end end
end
local function onScreen(app,x,y)
    if not (love.graphics and love.graphics.getDimensions) then return true end
    local sx,sy=app:screen(x,y);local w,h=love.graphics.getDimensions()
    return sx>=0 and sy>=0 and sx<=w and sy<=h
end
-- Where an event happened, for the reaction's `at`: the event's own entity by default.
local function place(ev,app,at)
    if at=='pod' then return ev.podX and ev.podX*256+128,ev.podY and ev.podY*256+128 end
    if at=='land' then
        local d=app.content.buildings[ev.building];local half=(d and d.size or 1)*128
        return ev.landX and ev.landX*256+half,ev.landY and ev.landY*256+half
    end
    if at=='hq' then local hq=app.view.byId and app.view.byId[app.view.player.hq];if hq then return hq.x,hq.y end;return nil end
    -- A target out of sight gets no effect at all, rather than one in the wrong place.
    if at=='target' then local t=app.view.byId and app.view.byId[ev.target];if t then return t.x,t.y end;return nil end
    return ev.x,ev.y
end
function J:observe(events,app)
    local tick=app.world.tick
    if self.tick and tick<self.tick then self:reset() end
    if self.tick==tick then return end
    self.tick=tick
    local content=app.content;local byId=app.view.byId or {}
    for _,ev in ipairs(events or {}) do
        local reaction=REACTIONS[ev.kind]
        if reaction then
            self.counts[ev.kind]=(self.counts[ev.kind] or 0)+1
            local x,y=place(ev,app,reaction.at)
            if reaction.cue then app.audio:play(reaction.cue,app,x,y) end
            if x then
                if reaction.ring then self:ring(x,y,reaction.ring[1]*256,reaction.ring[2],reaction.ring[3]) end
                if reaction.burst then self:burst(x,y,reaction.burst[1],reaction.burst[2],reaction.burst[3],reaction.burst[4]) end
                if reaction.decal then self:decal(x,y,reaction.decal*256) end
                if reaction.text then app.feedback:text('juice',reaction.text(ev,app),x,y,COLOURS[reaction.textColour or 'gold'],1.6) end
            end
            if reaction.shake and x and onScreen(app,x,y) then app.feedback:shakeBy(reaction.shake) end
        elseif ev.kind=='attack' then
            -- A blow throws a couple of sparks; a splash weapon shows the ground it covers, and
            -- a heavy one is felt.
            local source=ev.source and byId[ev.source];local d=source and (content.units[source.kind] or content.buildings[source.kind])
            if ev.x then self:burst(ev.x,ev.y,2,'spark',1.6,60,14) end
            if d and d.splash and ev.x then
                self:ring(ev.x,ev.y,d.splash,.3,'ember',true);self:burst(ev.x,ev.y,8,'dust',2.2,40)
                app.audio:play('splash',app,ev.x,ev.y)
                if onScreen(app,ev.x,ev.y) then app.feedback:shakeBy(1.2) end
            end
        elseif ev.kind=='death' then
            -- The dead may already be gone from the view; the event names what it was.
            local building=ev.unitKind and content.buildings[ev.unitKind]
            if ev.x and building then
                self:burst(ev.x,ev.y,26,'debris',3.2,80);self:burst(ev.x,ev.y,10,'ember',2,110)
                self:decal(ev.x,ev.y,(building.size or 2)*150)
            elseif ev.x and ev.unitKind and content.units[ev.unitKind] and not content.units[ev.unitKind].projectile then self:burst(ev.x,ev.y,7,'debris',1.8,60) end
        elseif ev.kind=='cast' and ev.castX then
            -- Every pulse of an area ability marks the ground it hit; a barrage throws flak
            -- about the sky inside its circle.
            local spec=ev.ability and content.abilities and content.abilities[ev.ability]
            local radius=spec and spec.radius or 512
            self:ring(ev.castX,ev.castY,radius,.4,'flak',true)
            if spec and spec.channel then
                for _=1,8 do
                    local angle=self:random()*6.2831853;local r=math.sqrt(self:random())*radius
                    self:burst(ev.castX+math.cos(angle)*r,ev.castY+math.sin(angle)*r,2,'flak',.8,30,60+self:random()*30)
                end
                if onScreen(app,ev.castX,ev.castY) then app.feedback:shakeBy(.8) end
            else app.audio:play('cast',app,ev.castX,ev.castY) end
        end
    end
end
local function cellSize(app)
    local x0,y0=app:screen(0,0);local x1,y1=app:screen(256,256)
    return (x1-x0)/256,(y1-y0)/256
end
-- Under the units: scorch, rings, and the owner's descent markers.
function J:drawGround(app)
    local g=love.graphics;g.push('all');g.setShader()
    local sx,sy=cellSize(app);local z=app.camera.zoom
    for _,d in ipairs(self.decals) do
        local x,y=app:screen(d.x,d.y);local fade=1-d.age/DECAL_LIFE
        g.setColor(.05,.04,.03,.45*fade);g.ellipse('fill',x,y,d.radius*sx,d.radius*sy)
    end
    for _,r in ipairs(self.rings) do
        local x,y=app:screen(r.x,r.y);local t=r.age/r.life;local c=r.colour
        local grow=r.filled and 1 or (.35+.65*t)
        if r.filled then g.setColor(c[1],c[2],c[3],.16*(1-t));g.ellipse('fill',x,y,r.radius*sx,r.radius*sy) end
        g.setColor(c[1],c[2],c[3],.75*(1-t));g.setLineWidth(math.max(1,2*z*(1-t)))
        g.ellipse('line',x,y,r.radius*grow*sx,r.radius*grow*sy)
    end
    -- Descents. A call-down or a pod is yours alone until it lands, so only you see the mark:
    -- a reticle that tightens onto the site, and in the last stretch the thing itself coming down.
    local player=app.view.player;local descent=app.content.rules.descentTicks or 200
    local now=app.world.tick+math.min(1,(app.accumulator or 0)/0.05)
    local function marker(cx,cy,half,at,colour)
        local t=math.max(0,math.min(1,1-(at-now)/descent))
        local x,y=app:screen(cx,cy);local radius=(half+(1-t)*640)
        g.setColor(colour[1],colour[2],colour[3],.35+.4*t);g.setLineWidth(math.max(1,1.5*z))
        g.ellipse('line',x,y,radius*sx,radius*sy)
        g.ellipse('line',x,y,half*sx,half*sy)
        if t>.55 then
            local fall=((1-t)/.45)^2*520*z
            g.setColor(1,.9,.7,.9);g.setLineWidth(math.max(2,3*z));g.line(x,y-fall-26*z,x,y-fall)
            g.setColor(1,.75,.4,.5);g.setLineWidth(math.max(1,1.5*z));g.line(x,y-fall-70*z,x,y-fall-26*z)
        end
    end
    for _,landing in ipairs(player.landings or {}) do
        local d=app.content.buildings[landing.kind];local half=(d and d.size or 1)*128
        marker(landing.x*256+half,landing.y*256+half,half,landing.at,COLOURS.door)
    end
    for _,pod in ipairs(player.pods and player.pods.inFlight or {}) do marker(pod.x*256+128,pod.y*256+128,200,pod.at,COLOURS.flak) end
    g.pop()
end
-- Over the units: the particles.
function J:draw(app)
    local g=love.graphics;g.push('all');g.setShader();local z=app.camera.zoom
    for _,p in ipairs(self.particles) do
        local x,y=app:screen(p.x,p.y);local fade=1-p.age/p.life;local c=p.colour
        g.setColor(c[1],c[2],c[3],math.min(1,fade*1.6));local size=p.size*z
        g.rectangle('fill',x-size/2,y-p.h*z-size/2,size,size)
    end
    g.pop()
end
J.REACTIONS=REACTIONS
-- Every event the simulation emits is accounted for: it has a row above, it is reacted to in
-- J:observe or by another part of the interface, or it is silent on purpose and says why.
-- tests/juice.lua reads the simulation's sources and fails when a new event is none of these,
-- so nothing the game does can go unanswered by accident.
J.ELSEWHERE={attack='juice and feedback',death='juice and feedback',cast='juice',
    accepted='command feedback',rejected='command feedback',windup='feedback',revived='feedback',upgraded='feedback',
    recruited='the ready cue',researched='the research cue',ping='the minimap ping',victory='the result banner',
    blocked='alerts',build_stalled='alerts',production_blocked='alerts',captured='alerts',control_started='alerts'}
J.SILENT={casting='the cast state of the caster is drawn from the view',channel_ended='the ring ends with the channel in the view',
    harvest_ended='the idle-worker count is the signal',pod_loaded='the pod page shows the seat filling',
    projectile_launched='the projectile entity is drawn',projectile_gone='the projectile entity is drawn',
    status_expired='the status pip disappears',control_broken='the control banner clears'}
return J
