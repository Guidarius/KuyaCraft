-- Opt-in art review; uses exactly the shipping catalog, shaders and frame interface.
local Frames=require('src.asset_frames')
local R={}
local units={'worker','worker_loaded','footman','crossbow','gryphon','reliquary'}
local buildings={'keep','depot','barracks','sanctum'}
local compare={'associate','medic','enforcer','command_blimp','battleship'}
local colors={{.38,.75,.96},{.94,.43,.32}}
function R.create(options)
 local self=setmetatable({sprites=require('src.sprites').load(),time=0,playing=true,page=tonumber(options['review-page']) or 1,
  index=tonumber(options['review-unit']) or 1,mode=tonumber(options['review-mode']) or 0,labels=true},{__index=R})
 local camera={settings={scale=100},camera={userZoom=1}};require('src.ui.camera').normalize(camera);self.gameplayZoom=camera.camera.zoom
 self.canvas=love.graphics.newCanvas(love.graphics.getDimensions())
 self.shader=love.graphics.newShader([[extern float mode;
 vec4 effect(vec4 c,Image t,vec2 uv,vec2 p){vec4 b=Texel(t,uv);float v=dot(b.rgb,vec3(.299,.587,.114));
 return vec4(mode>1.5?vec3(0.0):vec3(v),b.a)*c;}]])
 for _,list in ipairs({units,buildings,compare}) do for _,id in ipairs(list) do assert(self.sprites.units[id],'Missing review asset: '..id) end end
 assert(#self.sprites.diagnostics==0,'Catalog diagnostics')
 return self
end
function R:update(dt) if self.playing then self.time=self.time+dt*1000 end end
function R:keypressed(key)
 if key=='escape' then love.event.quit()
 elseif tonumber(key) and tonumber(key)>=1 and tonumber(key)<=4 then self.page=tonumber(key)
 elseif key=='tab' then self.index=self.index%#units+1
 elseif key=='g' then self.mode=(self.mode+1)%3
 elseif key=='l' then self.labels=not self.labels
 elseif key=='space' then self.playing=not self.playing
 elseif key=='home' then self.time=0 end
end
function R:mousepressed() end
function R:sample(id,clip,direction,x,y,zoom,team,sample)
 local m=self.sprites.units[id].metadata
 if self.runtimeScale then
  zoom=zoom*require('src.app').unitVisualScale({content=require('src.content'),sprites=self.sprites},{kind=id=='worker_loaded' and 'worker' or id})
 end
 local f=sample and m.clips[clip].frames[direction][sample] or Frames.sample(m,clip,direction,self.time)
 self.sprites:drawFrame(id,f,x,y,zoom,colors[team or 1])
end
function R:draw()
 local g=love.graphics;local w,h=g.getDimensions()
 if self.canvas:getWidth()~=w or self.canvas:getHeight()~=h then
  self.canvas:release();self.canvas=g.newCanvas(w,h)
  local camera={settings={scale=100},camera={userZoom=1}};require('src.ui.camera').normalize(camera);self.gameplayZoom=camera.camera.zoom
 end
 g.push('all');g.clear(.105,.135,.13)
 -- The light/dark bands remain outside the grayscale/silhouette sprite pass.
 for row=1,4 do g.setColor(row%2==0 and .64 or .13,row%2==0 and .66 or .17,row%2==0 and .57 or .15)
  g.rectangle('fill',12,110+(row-1)*(h-135)/4,w-24,(h-135)/4-3) end
 local previous=g.getCanvas();g.setCanvas(self.canvas);g.clear(0,0,0,0)
 self.runtimeScale=self.page==2 or self.page==4
 if self.page==1 then
  local roster={};for _,id in ipairs(units) do roster[#roster+1]=id end;for _,id in ipairs(compare) do roster[#roster+1]=id end
  for row,zoom in ipairs({1,self.gameplayZoom,2,self.gameplayZoom}) do
   self.runtimeScale=row==2 or row==4
   local y=110+(row-.45)*(h-135)/4
   for i,id in ipairs(roster) do self:sample(id,row==4 and 'move' or 'idle','SW',70+(i-.5)*(w-140)/#roster,y,zoom,row==3 and (i%2+1) or 1) end
  end
 elseif self.page==2 then
  for row,id in ipairs(buildings) do for col=1,4 do
   self:sample(id,col==4 and 'idle' or 'construction','S',(col-.5)*w/4,110+(row-.30)*(h-135)/4,self.gameplayZoom,1,col==4 and 1 or col)
   self:sample('associate','idle','SW',(col-.5)*w/4+100,110+(row-.30)*(h-135)/4,self.gameplayZoom,1)
  end end
 elseif self.page==4 then
  local armies={{'worker','footman','crossbow','gryphon','reliquary'},{'associate','medic','enforcer'},{'footman','associate','crossbow','medic','gryphon','enforcer','reliquary'}}
  for group,army in ipairs(armies) do for row=1,6 do for col=1,12 do
   local id=army[(row*7+col-2)%#army+1]
   self:sample(id,'move',Frames.directions[(row+col-2)%8+1],(group-1)*w/3+45+col*(w/3-80)/12,155+row*68,self.gameplayZoom,1)
  end end end
  for i,pair in ipairs({{'keep','orbital_command'},{'depot','med_bay'},{'barracks','mc_barracks'},{'sanctum','armory'}}) do
   for j,id in ipairs(pair) do self:sample(id,'idle','S',(i-1)*w/4+w/8+(j-1.5)*190,h-105,self.gameplayZoom,1) end
  end
 else
  local id=units[self.index];local m=self.sprites.units[id].metadata;local clips={}
  for _,name in ipairs({'idle','move','attack','death','work'}) do if m.clips[name] then clips[#clips+1]=name end end
  for ci,clip in ipairs(clips) do for di,d in ipairs(Frames.directions) do
   local ids=m.clips[clip].frames[d];local cw=(w-65)/#clips
   for sample=1,#ids do self:sample(id,clip,d,40+(ci-1)*cw+(sample-.5)*cw/#ids,145+di*(h-190)/8,1.15,1,sample) end
  end end
 end
 g.setCanvas(previous);g.setColor(1,1,1)
 if self.mode>0 then self.shader:send('mode',self.mode);g.setShader(self.shader) end
 g.setBlendMode('alpha','premultiplied');g.draw(self.canvas);g.setBlendMode('alpha','alphamultiply');g.setShader();g.setColor(.96,.93,.83)
 g.print('ORDERS / CATHEDRAL ASSET REVIEW     1: shared scale     2: construction     3: every sample     4: crowds / architecture     Tab: unit     G: color / gray / silhouette     L: labels     Space: pause',20,15)
 g.print('Production 60-degree camera / 64 pixels per Blender unit / unchanged gameplay footprints.  '..({'Color','Grayscale','Black silhouette'})[self.mode+1],20,40)
 if self.labels then
  if self.page==1 then
   for row,text in ipairs({'Native 1x / same team',string.format('Normalized gameplay scale %.3fx / same team',self.gameplayZoom),'2x inspection / opposing teams','Movement / same team / light terrain'}) do g.print(text,25,115+(row-1)*(h-135)/4) end
   local roster={};for _,id in ipairs(units) do roster[#roster+1]=id end;for _,id in ipairs(compare) do roster[#roster+1]=id end
   for i,id in ipairs(roster) do g.printf(id,35+(i-1)*(w-70)/#roster,85,(w-70)/#roster,'center') end
  elseif self.page==2 then
   for i,text in ipairs({'Foundation','Walls / partial roof','Near completion','Completed'}) do g.printf(text,(i-1)*w/4,85,w/4,'center') end
   for i,id in ipairs(buildings) do g.print(id,25,115+(i-1)*(h-135)/4) end
  elseif self.page==4 then
   for i,name in ipairs({'Orders / same team','Megacorp / same team','Mixed factions / same team'}) do g.printf(name,(i-1)*w/3,90,w/3,'center') end
   g.print('Shared-scale architecture / matching team color',25,h-275)
  else
   local id=units[self.index];g.print(id..' / all headings and samples, fixed anchors',25,70)
   local clips={};for _,c in ipairs({'idle','move','attack','death','work'}) do if self.sprites.units[id].metadata.clips[c] then clips[#clips+1]=c end end
   for i,c in ipairs(clips) do g.printf(c,40+(i-1)*(w-65)/#clips,105,(w-65)/#clips,'center') end
   for i,d in ipairs(Frames.directions) do g.print(d,5,130+i*(h-190)/8) end
  end
 end
 g.pop()
end
return R
