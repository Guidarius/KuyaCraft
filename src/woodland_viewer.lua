-- Isolated pixel-art comparison; production asset IDs and gameplay are untouched.
local Base=require('src.asset_viewer')
local Frames=require('src.asset_frames')
local W={}
function W.create(options)
    local sprites=require('src.sprites').load('assets/generated/woodland/catalog.lua')
    local v=Base.create(sprites)
    setmetatable(v,{__index=function(_,k)return W[k] or Base[k] end})
    v.zoom=2;v.options=options or {};v.backgroundIndex=1;v.teamIndex=1
    v.production=require('src.sprites').load()
    v.teamIndex=math.max(1,math.min(3,tonumber(v.options['pilot-team']) or 1))
    v.backgroundIndex=math.max(1,math.min(3,tonumber(v.options['pilot-background']) or 1))
    if options and options['pilot-clip'] then
        for i,name in ipairs(v:clips()) do if name==options['pilot-clip'] then v.clipIndex=i end end
    end
    if options and options['pilot-time'] then v.timeMs=tonumber(options['pilot-time']);v.playing=false end
    return v
end
function W:keypressed(key)
    if key=='escape' then love.event.quit() else Base.keypressed(self,key) end
end
function W:draw()
    local g=love.graphics;local width,height=g.getDimensions();g.push('all');g.setShader()
    local backgrounds={{.18,.23,.18},{.72,.73,.58},{.07,.10,.12}};g.clear(backgrounds[self.backgroundIndex])
    -- Deterministic terrain swatches expose silhouette contrast without simulation state.
    for y=90,height-174,24 do for x=0,width,32 do
        local n=(x*13+y*7)%19
        g.setColor(.37,.40,.22,.16);g.rectangle('fill',x+n,y,3,2)
        g.setColor(.65,.59,.41,.12);g.rectangle('fill',x+11,y+n,5,3)
    end end
    g.setColor(.035,.055,.055);g.rectangle('fill',0,0,width,84)
    g.setColor(.93,.90,.77);g.print('WOODLAND PIXEL PILOT / MOUSE BUILDER / 32, 48, 64 px crown height (ears excluded)',18,12)
    local band=(height-254)/3;local zoom=math.max(1,math.min(self.zoom,math.floor((band-28)/95)))
    local clip=self:clip()
    g.print('Clip '..clip..'   '..(self.playing and 'Playing' or 'Paused')..'   Integer magnifier '..zoom..'x   Team '..self.teamIndex,18,35)
    g.print('[C] clip   [Space] pause   [Left/Right] frame   [Z] magnify   [T] team   [B] terrain   [G] anchors   [Home] rewind   [Esc] exit',18,58)
    if #self.ids~=3 then g.setColor(1,.4,.5);g.print('Run scripts/export-assets.ps1 -Roster woodland. '..table.concat(self.sprites.diagnostics,' | '),18,110);g.pop();return end
    for row,id in ipairs({'mouse_builder_32','mouse_builder_48','mouse_builder_64'}) do
        local u=self.sprites.units[id];local top=84+(row-1)*band
        g.setColor(1,1,1,.035);g.rectangle('fill',0,math.floor(top),width,math.floor(band)-1)
        g.setColor(.95,.91,.76);g.print(u.metadata.bodyHeightPixels..' px / '..u.metadata.buildId:sub(1,10),12,math.floor(top+8))
        for i,d in ipairs(Frames.directions) do
            local x=math.floor((i-.5)*width/8);local y=math.floor(top+band*.78)
            local frame,index=Frames.sample(u.metadata,clip,d,self.timeMs)
            self.sprites:drawFrame(id,frame,x,y,zoom,self.teamIndex)
            if self.guides then g.setColor(.96,.78,.32,.8);g.line(x-8,y,x+8,y);g.line(x,y-3,x,y+3) end
            g.setColor(.95,.91,.76);g.printf(d..' '..index..'/'..#u.metadata.clips[clip].frames[d],x-45,math.floor(top+band-18),90,'center')
        end
    end
    local top=height-170;g.setColor(.035,.055,.055);g.rectangle('fill',0,top,width,170)
    g.setColor(.85,.88,.77);g.print('NATIVE 1x / mixed sizes and teams + shaded production units for context',14,top+7)
    for i=1,math.floor((width-40)/74) do
        local id=self.ids[(i-1)%3+1];local m=self.sprites.units[id].metadata
        local frame=Frames.sample(m,clip,Frames.directions[(i-1)%8+1],self.timeMs+(i%3)*83)
        local context=({'worker','shieldguard','archer'})[(i%3)+1]
        local other=self.production.units[context]
        if i%4==0 and other then
            local f=Frames.sample(other.metadata,clip=='work' and 'idle' or clip,Frames.directions[(i-1)%8+1],self.timeMs)
            self.production:drawFrame(context,f,math.floor(i*74),height-26,1,({{.38,.75,.96},{.94,.43,.32},{.48,.75,.4}})[(i%3)+1])
        else self.sprites:drawFrame(id,frame,math.floor(i*74),height-26,1,(i%3)+1) end
    end
    g.pop()
end
return W
