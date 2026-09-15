local Camera=require('src.ui.camera')
local Content=require('src.content')
local Selection=require('src.ui.selection')
local M={}
-- Fog is repainted only when the fog actually changed. Detecting that by
-- canonically encoding the two key sets cost roughly fifty thousand
-- string.format calls per tick to produce a value that was then thrown away.
-- Counting and summing the integer keys answers the same question with plain
-- arithmetic. explored only ever grows, so its size alone identifies it; visible
-- is rebuilt each tick, so it also contributes a sum and a sum of squares.
-- A missed change would delay one cosmetic repaint by a tick, never gameplay.
local function fogSignature(player)
 local count,sum,squares=0,0,0
 for key in pairs(player.visible) do count=count+1;sum=sum+key;squares=squares+key%977*key end
 local explored=0
 for _ in pairs(player.explored) do explored=explored+1 end
 return count..':'..sum..':'..squares..':'..explored
end
function M.bounds(map,panel)
 local cell=math.min(panel.w/map.width,panel.h/map.height)
 return {x=panel.x+(panel.w-map.width*cell)/2,y=panel.y+(panel.h-map.height*cell)/2,w=map.width*cell,h=map.height*cell,cell=cell}
end
function M.position(map,r,x,y,clamp)
 if not clamp and (x<r.x or y<r.y or x>=r.x+r.w or y>=r.y+r.h) then return end
 return math.max(0,math.min(map.width*256-1,math.floor((x-r.x)/r.cell*256))),math.max(0,math.min(map.height*256-1,math.floor((y-r.y)/r.cell*256)))
end
function M.cache(app)
 local g=love.graphics;local map=app.view.map
 -- One tiny pixel per world cell; canvases allocated only on map/renderer change.
 local cache=app.miniCache
 if not cache or cache.map~=app.world.map then
  if cache then cache.terrain:release();cache.fog:release() end
  cache={map=app.world.map,terrain=g.newCanvas(map.width,map.height,{dpiscale=1}),fog=g.newCanvas(map.width,map.height,{dpiscale=1})};app.miniCache=cache
  cache.terrain:setFilter('nearest','nearest');cache.fog:setFilter('nearest','nearest')
  g.push('all');g.setCanvas(cache.terrain);g.origin();g.setScissor();g.clear(.22,.32,.25)
  for y=0,map.height-1 do for x=0,map.width-1 do local shade=(x*7+y*11)%5*.008;local key=y*map.width+x+1;if map.blocked[key] then g.setColor(.15,.26,.35) elseif map.unbuildable and map.unbuildable[key] then g.setColor(.38+shade,.32+shade,.22+shade) else g.setColor(.16+shade,.235+shade,.19+shade) end;g.rectangle('fill',x,y,1,1) end end;g.pop()
 end
 local signature=cache.signature
 if cache.tick~=app.view.tick or cache.player~=app.player then signature=fogSignature(app.view.player);cache.tick=app.view.tick;cache.player=app.player end
 if cache.signature~=signature then
  cache.signature=signature;g.push('all');g.setCanvas(cache.fog);g.origin();g.setScissor();g.clear(0,0,0,0)
  for y=0,map.height-1 do for x=0,map.width-1 do local key=y*map.width+x+1
   if not app.view.player.visible[key] then g.setColor(0,0,0,app.view.player.explored[key] and .6 or .96);g.rectangle('fill',x,y,1,1) end
  end end;g.pop()
 end
 return cache
end
function M.draw(app,panel)
 local g=love.graphics;local map=app.view.map;local r=M.bounds(map,panel);app.minimap=r
 g.setColor(.03,.05,.06);g.rectangle('fill',panel.x,panel.y,panel.w,panel.h)
 local cache=M.cache(app)
 g.setColor(1,1,1);g.draw(cache.terrain,r.x,r.y,0,r.cell,r.cell);g.draw(cache.fog,r.x,r.y,0,r.cell,r.cell)
 for _,e in ipairs(app.observation.markers or {}) do
  local x,y=r.x+e.x/256*r.cell,r.y+e.y/256*r.cell
  if e.owner==app.player then g.setColor(.35,.78,1) elseif e.owner==0 then g.setColor(.85,.72,.4) else g.setColor(1,.35,.25) end
  if e.remembered then g.setColor(.5,.48,.4,.6) end
  local unit=Content.units[e.kind];local hero=unit and unit.hero
  if e.category=='building' then g.rectangle(e.remembered and 'line' or 'fill',x-2,y-2,5,5)
  elseif e.category=='node' then if e.resource=='gold' then g.polygon('fill',x,y-3,x+3,y,x,y+3,x-3,y) else g.polygon('fill',x,y-4,x+3,y+2,x-3,y+2) end
  elseif hero then g.polygon('fill',x,y-4,x+4,y,x,y+4,x-4,y)
  else g.circle('fill',x,y,1.8) end
  if Selection.has(app.selected,e.id) then g.setColor(.7,1,.7);g.circle('line',x,y,4) end
 end
 for _,item in ipairs(app.alerts.items) do if item.x then g.setColor(1,.65,.2,.8);g.circle('line',r.x+item.x/256*r.cell,r.y+item.y/256*r.cell,5+(app.alerts.clock-item.time)%1*6) end end
 -- A ping, from either player: it arrives as a simulation event, so both sides see the
 -- same marker at the same tick. Pulses so it catches the eye on a busy minimap.
 if app.localPing and app.clock-app.localPing.time<4 then
  local age=app.clock-app.localPing.time
  local own=app.localPing.player==app.player
  g.setColor(own and .8 or 1,own and 1 or .85,own and .6 or .4,1-age/4)
  g.setLineWidth(2)
  for ring=0,1 do g.circle('line',r.x+app.localPing.x/256*r.cell,r.y+app.localPing.y/256*r.cell,4+ring*4+(age%1)*5) end
  g.setLineWidth(1)
 end
 if app.orderMarker and app.clock-(app.orderMarker.time or 0)<.6 then local o=app.orderMarker;g.setColor(.65,1,.6);g.circle('line',r.x+o.x/256*r.cell,r.y+o.y/256*r.cell,4) end
 local vp=Camera.rect(app);local x1,y1=app:position(vp.x,vp.y);local x2,y2=app:position(vp.x+vp.w,vp.y+vp.h)
 x1=math.max(0,x1);y1=math.max(0,y1);x2=math.min(map.width*256,x2);y2=math.min(map.height*256,y2)
 g.setColor(.95,.94,.79);g.setLineWidth(1);g.rectangle('line',r.x+x1/256*r.cell,r.y+y1/256*r.cell,(x2-x1)/256*r.cell,(y2-y1)/256*r.cell)
end
return M
