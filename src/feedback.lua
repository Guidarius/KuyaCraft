-- Cosmetic state only; inputs must already be filtered for the viewing player.
local F={}
function F.create() return setmetatable({items={},known={},tick=nil,clock=0},{__index=F}) end
function F:reset() self.items={};self.known={};self.tick=nil;self.clock=0 end
function F:update(dt) self.clock=self.clock+dt end
function F:observe(events,view,tick)
    if self.tick and tick<self.tick then self:reset() end
    if self.tick==tick then return end
    local visible={};for _,e in ipairs(view.entities) do visible[e.id]=e end
    local kept={}
    for _,item in ipairs(self.items) do
        if tick-item.tick<item.duration and visible[item.target] and (not item.source or visible[item.source]) then kept[#kept+1]=item end
    end
    self.items=kept
    local function add(item)
        item.tick=tick;item.time=self.clock
        if #self.items<256 then self.items[#self.items+1]=item end
    end
    for _,event in ipairs(events or {}) do
        if event.tick==nil or event.tick==tick then
            if event.kind=='attack' then
                local source,target=visible[event.source],visible[event.target]
                if source and target then add({kind=source.kind=='crossbow' and 'tracer' or 'hit',source=source.id,target=target.id,x=target.x,y=target.y,sx=source.x,sy=source.y,duration=3}) end
            elseif event.kind=='death' or event.kind=='revived' or event.kind=='healed' or event.kind=='constructed' or event.kind=='upgraded' then
                local e=visible[event.entity]
                if e then add({kind=event.kind,target=e.id,x=e.x,y=e.y,duration=6}) end
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
        local alpha=math.max(0,1-age/item.duration);local x,y=app:screen(item.x,item.y)
        if item.kind=='hit' or item.kind=='tracer' then
            y=y-18*z;g.setColor(1,0.86,0.56,alpha);g.setLineWidth(1.5*z)
            if item.kind=='tracer' then local sx,sy=app:screen(item.sx,item.sy);g.line(sx,sy-18*z,x,y) end
            g.line(x-4*z,y,x+4*z,y);g.line(x,y-4*z,x,y+4*z)
        else
            g.setColor(item.kind=='death' and 0.8 or 0.55,item.kind=='death' and 0.58 or 0.95,0.6,alpha)
            g.setLineWidth(1.5*z);g.ellipse('line',x,y,(12+age*2)*z,(5+age)*z)
        end
    end
    g.pop()
end
return F
