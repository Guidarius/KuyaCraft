local Catalog=require('src.asset_catalog')
local Frames=require('src.asset_frames')
local S={}
local shaderSource=[[
extern Image teamMask;
extern vec3 teamColor;
vec4 effect(vec4 color, Image tex, vec2 uv, vec2 pixel) {
    vec4 base=Texel(tex,uv);
    float mask=Texel(teamMask,uv).r;
    float shade=dot(base.rgb,vec3(0.299,0.587,0.114));
    base.rgb=mix(base.rgb,teamColor*shade*1.4,mask);
    return base*color;
}
]]
local pixelShaderSource=[[
extern Image teamMask;
extern Image teamPalette;
extern float teamRow;
vec4 effect(vec4 color, Image tex, vec2 uv, vec2 pixel) {
    vec4 base=Texel(tex,uv);
    float index=floor(Texel(teamMask,uv).r*5.0+0.5);
    if(index>0.0) base.rgb=Texel(teamPalette,vec2((index-0.5)/5.0,teamRow)).rgb;
    return base*color;
}
]]
function S.load(catalogPath)
    local self=setmetatable({catalog=Catalog.load(nil,nil,catalogPath),units={},states={},lastTick=nil},{__index=S})
    self.diagnostics=self.catalog.diagnostics
    local ok,shader=pcall(love.graphics.newShader,shaderSource)
    if ok then self.shader=shader else self.diagnostics[#self.diagnostics+1]='shader: '..tostring(shader) end
    local ids={};for id in pairs(self.catalog.units) do ids[#ids+1]=id end;table.sort(ids)
    for _,id in ipairs(ids) do
        local m=self.catalog.units[id]
        local valid,unit=pcall(function()
            assert(self.shader,'team shader unavailable')
            local u={metadata=m,pages={},quads={}}
            for i,p in ipairs(m.pages) do
                local color=love.graphics.newImage(p.color,{mipmaps=false})
                local mask=love.graphics.newImage(p.mask,{mipmaps=false})
                local w,h=color:getDimensions();local mw,mh=mask:getDimensions()
                assert(w==p.width and h==p.height and mw==w and mh==h,'atlas/mask dimensions mismatch')
                local filter=(m.profileId=='legacy_v1' or m.pixelStyle) and 'nearest' or 'linear'
                color:setFilter(filter,filter);mask:setFilter(filter,filter)
                u.pages[i]={color=color,mask=mask}
            end
            for i,f in ipairs(m.frames) do local p=m.pages[f.page];u.quads[i]=love.graphics.newQuad(f.x,f.y,f.width,f.height,p.width,p.height) end
            if m.pixelStyle then
                u.pixelShader=love.graphics.newShader(pixelShaderSource)
                local ramps=m.pixelStyle.teamRamps;local data=love.image.newImageData(5,#ramps)
                for row,ramp in ipairs(ramps) do for i,hex in ipairs(ramp) do
                    data:setPixel(i-1,row-1,tonumber(hex:sub(2,3),16)/255,tonumber(hex:sub(4,5),16)/255,tonumber(hex:sub(6,7),16)/255,1)
                end end
                u.teamPalette=love.graphics.newImage(data);u.teamPalette:setFilter('nearest','nearest')
            end
            return u
        end)
        if valid then self.units[id]=unit else self.diagnostics[#self.diagnostics+1]=id..': '..tostring(unit) end
    end
    for _,message in ipairs(self.diagnostics) do print('ASSET ERROR '..message) end
    return self
end
function S:reset() self.states={};self.lastTick=nil;self.prunedTick=nil;self.observedTick=nil end
-- Called once after each authoritative step, using only the player's filtered view.
-- Dead visible targets are valid: an attack may kill its target on this same tick.
function S:observe(events,view,tick)
    if (self.lastTick and tick<self.lastTick) or (self.observedTick and tick<self.observedTick) then self:reset() end
    if self.observedTick==tick then return end
    self.observedTick=tick
    local visible={}
    for _,e in ipairs(view and view.entities or {}) do visible[e.id]=e end
    for _,event in ipairs(events or {}) do
        if event.kind=='attack' and (event.tick==nil or event.tick==tick) then
            local source,target=visible[event.source],visible[event.target]
            if source and target then
                local state=self.states[source.id] or {};self.states[source.id]=state
                state.attackFacingTick=tick
                state.attackHeading=Frames.direction(target.x-source.x,target.y-source.y,state.direction)
            end
        end
    end
end
function S:drawFrame(unitId,frameId,x,y,zoom,team)
    local u=self.units[unitId]
    if not u then return false end
    local f=u.metadata.frames[frameId];if not f then return false end
    local page=u.pages[f.page];local g=love.graphics
    g.push('all')
    local scale=(zoom or 1)*(u.metadata.drawScale or 1)
    if u.pixelShader then
        local row=type(team)=='number' and team or 1
        assert(row>=1 and row<=#u.metadata.pixelStyle.teamRamps,'invalid pixel team')
        u.pixelShader:send('teamMask',page.mask);u.pixelShader:send('teamPalette',u.teamPalette)
        u.pixelShader:send('teamRow',(row-.5)/#u.metadata.pixelStyle.teamRamps)
        g.setShader(u.pixelShader);scale=math.max(1,math.floor(scale+.5));x=math.floor(x+.5);y=math.floor(y+.5)
    else
        self.shader:send('teamMask',page.mask);self.shader:send('teamColor',team or {0.38,0.75,0.96});g.setShader(self.shader)
    end
    g.setColor(1,1,1,1)
    g.draw(page.color,u.quads[frameId],x,y,0,scale,scale,f.anchorX,f.anchorY)
    g.pop();return true
end
function S:placeholder(id,x,y,zoom)
    self.missingWarned=self.missingWarned or {}
    if not self.missingWarned[id] then
        self.missingWarned[id]=true
        local message='Missing usable asset: '..id
        self.diagnostics[#self.diagnostics+1]=message;print('ASSET ERROR '..message)
    end
    local g=love.graphics;zoom=zoom or 1;g.push('all');g.setShader();g.setColor(1,0,0.8,1)
    g.rectangle('line',x-12*zoom,y-32*zoom,24*zoom,32*zoom);g.line(x-12*zoom,y-32*zoom,x+12*zoom,y)
    g.setColor(1,1,1);g.print('?'..id,x-15*zoom,y-46*zoom,0,0.65,0.65);g.pop()
end
function S:draw(e,x,y,zoom,team,previous,tick,view)
    local id=Frames.assetId(e);if not id then return false end
    if self.lastTick and tick<self.lastTick then self:reset() end;self.lastTick=tick
    if view and self.prunedTick~=tick then
        local visible={};for _,entity in ipairs(view.entities or {}) do visible[entity.id]=true end
        for key in pairs(self.states) do if not visible[key] then self.states[key]=nil end end
        self.prunedTick=tick
    end
    local u=self.units[id]
    if not u then self:placeholder(id,x,y,zoom);return true end
    local state=self.states[e.id] or {};self.states[e.id]=state
    local frame=Frames.select(u.metadata,e,previous,tick,state,view)
    return self:drawFrame(id,frame,x,y,zoom,team)
end
return S
