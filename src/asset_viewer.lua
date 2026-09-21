local Frames=require('src.asset_frames')
local V={}
local teams={{0.38,0.75,0.96},{0.94,0.43,0.32},{0.7,0.48,0.95}}
local backgrounds={{0.08,0.11,0.13},{0.65,0.7,0.58},{0.18,0.27,0.2}}
local clipOrder={'idle','move','attack','death','work','hit','deploy','construction'}
function V.create(sprites)
    local ids={};for id in pairs(sprites and sprites.units or {}) do ids[#ids+1]=id end;table.sort(ids)
    return setmetatable({sprites=sprites,ids=ids,unitIndex=1,clipIndex=1,directionIndex=1,playing=true,timeMs=0,speed=1,zoom=3,teamIndex=1,backgroundIndex=1,guides=true,rectangles=false,buttons={}}, {__index=V})
end
function V:unit() local id=self.ids[self.unitIndex];return id,self.sprites and self.sprites.units[id] end
function V:clips()
    local _,u=self:unit();local result={}
    if u then for _,name in ipairs(clipOrder) do if u.metadata.clips[name] then result[#result+1]=name end end end
    return result
end
function V:clip() local names=self:clips();self.clipIndex=math.min(self.clipIndex,math.max(1,#names));return names[self.clipIndex] or 'idle' end
function V:update(dt) if self.playing then self.timeMs=self.timeMs+math.min(dt,0.25)*1000*self.speed end end
function V:keypressed(key)
    if key=='space' then self.playing=not self.playing
    elseif key=='tab' or key=='u' then self.unitIndex=self.unitIndex%math.max(1,#self.ids)+1;self.clipIndex=1;self.timeMs=0
    elseif key=='c' then self.clipIndex=self.clipIndex%math.max(1,#self:clips())+1;self.timeMs=0
    elseif key=='d' then self.directionIndex=self.directionIndex%8+1
    elseif key=='t' then self.teamIndex=self.teamIndex%#teams+1
    elseif key=='b' then self.backgroundIndex=self.backgroundIndex%#backgrounds+1
    elseif key=='g' then self.guides=not self.guides
    elseif key=='r' then self.rectangles=not self.rectangles
    elseif key=='home' then self.timeMs=0
    elseif key=='=' or key=='+' then self.speed=math.min(4,self.speed*2)
    elseif key=='-' then self.speed=math.max(0.125,self.speed/2)
    elseif key=='z' then self.zoom=self.zoom==1 and 2 or self.zoom==2 and 3 or self.zoom==3 and 4 or 1
    elseif key=='left' or key=='right' then
        local _,u=self:unit();if u then
            self.playing=false;local c=u.metadata.clips[self:clip()];local count=#c.frames.N
            local index=math.floor(self.timeMs/c.durationMs*count+0.00001)
            if c.loop then index=index%count end
            index=math.max(0,math.min(count-1,index+(key=='right' and 1 or -1)))
            self.timeMs=index*c.durationMs/count+0.00001
        end
    end
end
function V:mousepressed(x,y,button)
    if button~=1 then return end
    for _,b in ipairs(self.buttons) do if x>=b.x and x<=b.x+b.w and y>=b.y and y<=b.y+b.h then self:keypressed(b.key);return end end
end
function V:drawSample(id,clip,direction,x,y,scale,team,elapsed)
    local g=love.graphics;local u=self.sprites.units[id];if not u then return end
    local frame,index=Frames.sample(u.metadata,clip,direction,elapsed or self.timeMs)
    local f=u.metadata.frames[frame];self.sprites:drawFrame(id,frame,x,y,scale,team)
    if self.guides then g.setColor(0.95,0.79,0.3,0.6);g.line(x-12,y,x+12,y);g.line(x,y-5,x,y+5);g.circle('line',x,y,2) end
    if self.rectangles then local s=scale*(u.metadata.drawScale or 1);g.setColor(0.9,0.4,0.8,0.6);g.rectangle('line',x-f.anchorX*s,y-f.anchorY*s,f.width*s,f.height*s) end
    return index,#u.metadata.clips[clip].frames[direction]
end
function V:draw()
    local g=love.graphics;local w,h=g.getDimensions();local bg=backgrounds[self.backgroundIndex]
    g.push('all');g.setShader();g.clear(bg);g.setColor(0.04,0.06,0.08,0.94);g.rectangle('fill',0,0,w,132)
    g.setColor(0.95,0.94,0.88);g.print('FACTION / ASSET REVIEW',20,12)
    local id,u=self:unit();local clip=self:clip()
    g.print('Unit: '..(id or 'none')..'   Clip: '..clip..'   '..(self.playing and 'Playing' or 'Paused')..'   Speed: '..self.speed..'x   Zoom: '..self.zoom..'x',20,36)
    self.buttons={};local x,y=20,62
    for _,item in ipairs({{'Unit [Tab]','tab'},{'Clip [C]','c'},{'Play [Space]','space'},{'Step <','left'},{'Step >','right'},{'Team [T]','t'},{'Ground [B]','b'},{'Zoom [Z]','z'},{'Guides [G]','g'},{'Bounds [R]','r'}}) do
        local bw=g.getFont():getWidth(item[1])+16;if x+bw>w-20 then x=20;y=y+29 end
        g.setColor(0.17,0.23,0.28);g.rectangle('fill',x,y,bw,24,3);g.setColor(0.88,0.92,0.94);g.print(item[1],x+8,y+4)
        self.buttons[#self.buttons+1]={x=x,y=y,w=bw,h=24,key=item[2]};x=x+bw+6
    end
    if not u then
        g.setColor(1,0.7,0.8);g.printf('No usable assets. Run scripts/export-assets.ps1 -Mode Build -Roster bastion',20,155,w-40)
        for i,message in ipairs(self.sprites and self.sprites.diagnostics or {}) do g.printf(message,20,190+i*30,w-40) end
        g.pop();return
    end
    local top=145;local crowdTop=math.max(top+280,h-185);local rowH=(crowdTop-top)/2;local columnW=w/4
    for i,d in ipairs(Frames.directions) do
        local col=(i-1)%4;local row=math.floor((i-1)/4);local sx=(col+0.5)*columnW;local sy=top+(row+0.7)*rowH
        if i==self.directionIndex then g.setColor(1,1,1,0.08);g.rectangle('fill',col*columnW+8,top+row*rowH,columnW-16,rowH-4) end
        local index,count=self:drawSample(id,clip,d,sx,sy,self.zoom,teams[self.teamIndex])
        g.setColor(0.94,0.94,0.9);g.printf(d..'   '..index..'/'..count,col*columnW,sy+18,columnW,'center')
    end
    g.setColor(0.04,0.06,0.08,0.85);g.rectangle('fill',0,crowdTop,w,h-crowdTop)
    g.setColor(0.93,0.94,0.9);g.print('ACTUAL SIZE / MIXED ROSTER / TWO TEAMS     [D] direction   [-/+] speed   [Home] restart',20,crowdTop+8)
    for i=1,math.min(20,math.floor((w-40)/52)) do
        local uid=self.ids[(i-1)%#self.ids+1];local cm=self.sprites.units[uid].metadata
        local cn=cm.clips[clip] and clip or 'idle'
        self:drawSample(uid,cn,Frames.directions[(i-1)%8+1],25+i*52,crowdTop+80,1,teams[(i-1)%2+1],self.timeMs+(i%3)*75)
    end
    g.setColor(0.72,0.78,0.8);g.printf('Build: '..u.metadata.buildId..'   Profile: '..u.metadata.profileId..'   Body: '..u.metadata.bodyHeightPixels..' px\nColor + team mask | ground anchor cross | full attack preview (gameplay starts at contact)',20,h-72,w-40)
    if #(self.sprites.diagnostics or {})>0 then g.setColor(1,0.35,0.6);g.print('Asset errors: '..#self.sprites.diagnostics..' (see log)',20,h-25) end
    g.pop()
end
return V
