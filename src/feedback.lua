-- Cosmetic state only; inputs must already be filtered for the viewing player.
local F={}
-- Hit flash, floating text and screen shake all read the same filtered event stream the
-- rings and tracers already use, so nothing here can observe anything the player cannot.
local FLASH_TICKS=2
-- Long enough to see, short enough that it is gone before the shortest windup in the
-- content (five ticks, the stalker) has landed its hit.
local WINDUP_TICKS=4
-- Settles from full amplitude in about a third of a second. Slower than that reads as
-- the camera being broken rather than as an impact.
local SHAKE_DECAY=24
function F.create()
    return setmetatable({items={},known={},tick=nil,clock=0,texts={},flashes={},shakeX=0,shakeY=0,shake=0,banner=nil},{__index=F})
end
function F:reset()
    self.items={};self.known={};self.tick=nil;self.clock=0
    self.texts={};self.flashes={};self.shakeX=0;self.shakeY=0;self.shake=0;self.banner=nil
end
function F:update(dt)
    self.clock=self.clock+dt
    -- Floating text is aged in wall-clock so it reads the same at any tick rate.
    local texts=self.texts
    for i=#texts,1,-1 do
        local item=texts[i]
        item.age=item.age+dt
        if item.age>=item.life then table.remove(texts,i) end
    end
    if self.shake>0 then
        self.shake=math.max(0,self.shake-dt*SHAKE_DECAY)
        -- Deterministic wobble from the clock: presentation only, never simulation input.
        self.shakeX=math.sin(self.clock*57)*self.shake
        self.shakeY=math.cos(self.clock*73)*self.shake
    else self.shakeX,self.shakeY=0,0 end
    if self.banner then self.banner.age=self.banner.age+dt end
end
-- Cap matches the effects cap: a burst must never grow the frame cost without bound.
local TEXT_CAP=256
function F:text(kind,label,x,y,color,life)
    local texts=self.texts
    if #texts>=TEXT_CAP then return end
    texts[#texts+1]={kind=kind,label=label,x=x,y=y,color=color,age=0,life=life or 1.4,
        drift=(kind=='error' and 0 or 26)}
end
function F:error(label)
    -- One centre-screen error at a time; a repeat restarts it rather than stacking.
    local texts=self.texts
    for i=#texts,1,-1 do if texts[i].kind=='error' then table.remove(texts,i) end end
    self:text('error',label,nil,nil,{1,.45,.38},1.8)
end
function F:flash(id,tick) self.flashes[id]=tick end
function F:shakeBy(amount) self.shake=math.min(8,self.shake+amount) end
function F:flashing(id,tick)
    local at=self.flashes[id]
    return at~=nil and tick-at<=FLASH_TICKS
end
function F:observe(events,view,tick)
    if self.tick and tick<self.tick then self:reset() end
    if self.tick==tick then return end
    local visible={};for _,e in ipairs(view.entities) do visible[e.id]=e end
    local kept={}
    for _,item in ipairs(self.items) do
        if tick-item.tick<item.duration and visible[item.target] and (not item.source or visible[item.source]) then kept[#kept+1]=item end
    end
    self.items=kept
    for id,at in pairs(self.flashes) do if tick-at>FLASH_TICKS or not visible[id] then self.flashes[id]=nil end end
    local function add(item)
        item.tick=tick;item.time=self.clock
        if #self.items<256 then self.items[#self.items+1]=item end
    end
    for _,event in ipairs(events or {}) do
        if event.tick==nil or event.tick==tick then
            if event.kind=='attack' then
                local source,target=visible[event.source],visible[event.target]
                if source and target then
                    add({kind=source.kind=='crossbow' and 'tracer' or 'hit',source=source.id,target=target.id,x=target.x,y=target.y,sx=source.x,sy=source.y,duration=3})
                    self:flash(target.id,tick)
                end
            -- The simulation has committed to a swing that has not landed yet. Drawing
            -- the anticipation is what makes an attack read as thrown rather than as
            -- damage appearing, and it is what makes a cancelled swing legible: the
            -- arc simply stops. The event was emitted and consumed by nothing until now.
            elseif event.kind=='windup' then
                local source=visible[event.source]
                if source then add({kind='windup',source=source.id,target=source.id,x=source.x,y=source.y,duration=WINDUP_TICKS}) end
            elseif event.kind=='death' or event.kind=='revived' or event.kind=='healed' or event.kind=='constructed' or event.kind=='upgraded' then
                local e=visible[event.entity]
                if e then add({kind=event.kind,target=e.id,x=e.x,y=e.y,duration=6}) end
                if event.kind=='death' and e and e.category=='building' then self:shakeBy(4) end
            end
        end
    end
    for _,e in ipairs(view.entities) do
        if self.tick and not self.known[e.id] and visible[view.player.hq] and e.owner==visible[view.player.hq].owner and e.category=='unit' and e.alive then
            add({kind='ready',target=e.id,x=e.x,y=e.y,duration=10})
        end
        self.known[e.id]=true
    end
    self.tick=tick
end
function F:draw(app)
    local g=love.graphics;g.push('all');g.setShader();local z=app.camera.zoom
    for _,item in ipairs(self.items) do
        local age=math.max((self.clock-(item.time or self.clock))*20,app.world.tick-item.tick)
        local alpha=math.max(0,1-age/item.duration)
        -- Anchored to the entity rather than to the coordinates the event carried, so an
        -- effect over a moving unit glides with it instead of stuttering at 20 Hz. The
        -- recorded coordinates remain the fallback for anything that has since died.
        local x,y=app:anchorScreen(item.target,item.x,item.y)
        if item.kind=='hit' or item.kind=='tracer' then
            y=y-18*z;g.setColor(1,0.86,0.56,alpha);g.setLineWidth(1.5*z)
            if item.kind=='tracer' then local sx,sy=app:anchorScreen(item.source,item.sx,item.sy);g.line(sx,sy-18*z,x,y) end
            g.line(x-4*z,y,x+4*z,y);g.line(x,y-4*z,x,y+4*z)
        elseif item.kind=='windup' then
            -- A tightening arc on the attacker's weapon side, drawn shrinking so the
            -- eye reads it as gathering rather than as an impact that already happened.
            local grow=1-math.min(1,age/item.duration)
            g.setColor(1,0.92,0.72,alpha*0.55);g.setLineWidth(1.5*z)
            g.ellipse('line',x,y-14*z,(9+7*grow)*z,(5+4*grow)*z)
        else
            g.setColor(item.kind=='death' and 0.8 or 0.55,item.kind=='death' and 0.58 or 0.95,0.6,alpha)
            g.setLineWidth(1.5*z);g.ellipse('line',x,y,(12+age*2)*z,(5+age)*z)
        end
    end
    g.pop()
end
-- Drawn after the HUD panels so world text is never hidden behind them, and so the
-- centre-screen rejection notice sits above everything.
function F:drawText(app,width,height)
    local g=love.graphics;g.push('all');g.setShader();g.setFont(app.fonts.body)
    for _,item in ipairs(self.texts) do
        local fade=1-item.age/item.life
        local alpha=math.min(1,fade*2.2)
        local c=item.color or {1,1,1}
        if item.kind=='error' then
            local y=height*0.34-item.age*10
            g.setColor(0,0,0,alpha*.55);g.printf(item.label,1,y+1,width,'center')
            g.setColor(c[1],c[2],c[3],alpha);g.printf(item.label,0,y,width,'center')
        else
            local x,y=app:screen(item.x,item.y)
            y=y-30*app.camera.zoom-item.age*item.drift
            g.setColor(0,0,0,alpha*.5);g.printf(item.label,x-59,y+1,120,'center')
            g.setColor(c[1],c[2],c[3],alpha);g.printf(item.label,x-60,y,120,'center')
        end
    end
    g.pop()
end
return F
