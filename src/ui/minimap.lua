local Camera=require('src.ui.camera')
local Content=require('src.content')
local Selection=require('src.ui.selection')
local M={}
-- Fog is one pixel per cell in an ImageData, uploaded to one Image with replacePixels and
-- drawn scaled for both the world and the minimap. Each tick only the cells visible now or
-- visible last tick are looked at, so the work follows how much a player can see rather
-- than the size of the map. The previous version walked every visible and every explored
-- key to build a change signature, then cleared a canvas and drew one rectangle for every
-- unseen cell -- 36,864 on Twin Marches -- on almost every tick anything moved.
--
-- Levels: 0 visible, 1 explored, 2 never seen. A cell only becomes explored by being
-- visible, so the incremental pass is exact; a map change or a change of perspective
-- (replays switch player) rebuilds every pixel once.
local FOG_ALPHA={[0]=0,[1]=.6,[2]=.96}
local function fogPixel(cache,key,level)
 local width=cache.width
 cache.fogData:setPixel((key-1)%width,math.floor((key-1)/width),0,0,0,FOG_ALPHA[level])
end
local function rebuildFog(cache,player)
 local visible,explored,levels=player.visible,player.explored,cache.levels
 local count,list=0,cache.list
 for key=1,cache.width*cache.height do
  local level=visible[key] and 0 or explored[key] and 1 or 2
  levels[key]=level;fogPixel(cache,key,level)
  if level==0 then count=count+1;list[count]=key end
 end
 cache.count=count
 cache.fog:replacePixels(cache.fogData)
end
local function updateFog(cache,player)
 local visible,explored,levels=player.visible,player.explored,cache.levels
 local previous,previousCount=cache.list,cache.count
 local current,count=cache.spare,0
 local changed=false
 -- Presentation only, so the unordered walk over the visible set cannot affect gameplay.
 for key in pairs(visible) do
  count=count+1;current[count]=key
  if levels[key]~=0 then levels[key]=0;fogPixel(cache,key,0);changed=true end
 end
 for i=1,previousCount do
  local key=previous[i]
  if not visible[key] then
   local level=explored[key] and 1 or 2
   if levels[key]~=level then levels[key]=level;fogPixel(cache,key,level);changed=true end
  end
 end
 -- The lists swap roles; entries past `count` are stale and never read.
 cache.list,cache.spare,cache.count=current,previous,count
 if changed then cache.fog:replacePixels(cache.fogData);cache.uploads=cache.uploads+1 end
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
  local fogData=love.image.newImageData(map.width,map.height)
  cache={map=app.world.map,width=map.width,height=map.height,terrain=g.newCanvas(map.width,map.height,{dpiscale=1}),
   fogData=fogData,fog=g.newImage(fogData),levels={},list={},spare={},count=0,uploads=0}
  app.miniCache=cache
  cache.terrain:setFilter('nearest','nearest');cache.fog:setFilter('nearest','nearest')
  g.push('all');g.setCanvas(cache.terrain);g.origin();g.setScissor();g.clear(.22,.32,.25)
  for y=0,map.height-1 do for x=0,map.width-1 do local shade=(x*7+y*11)%5*.008;local key=y*map.width+x+1;if map.blocked[key] then g.setColor(.15,.26,.35) elseif map.unbuildable and map.unbuildable[key] then g.setColor(.38+shade,.32+shade,.22+shade) else g.setColor(.16+shade,.235+shade,.19+shade) end;g.rectangle('fill',x,y,1,1) end end;g.pop()
 end
 -- A view is rebuilt every tick, but each player's visible set is one table the simulation
 -- reuses for the whole match, so its identity marks a change of perspective or of world.
 if cache.player~=app.player or cache.fogVisible~=app.view.player.visible then
  cache.player=app.player;cache.fogVisible=app.view.player.visible;cache.tick=app.view.tick
  rebuildFog(cache,app.view.player)
 elseif cache.tick~=app.view.tick then
  cache.tick=app.view.tick
  updateFog(cache,app.view.player)
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
 -- Control points, ringed in their owner's colour so a hold reads from anywhere on the map.
 local control=app.view.control
 if control then for _,point in ipairs(control.points) do
  if point.owner==app.player then g.setColor(.35,.78,1) elseif point.owner==0 then g.setColor(.9,.82,.45) else g.setColor(1,.35,.25) end
  g.setLineWidth(2);g.circle('line',r.x+point.x/256*r.cell,r.y+point.y/256*r.cell,math.max(4,4*r.cell));g.setLineWidth(1)
 end end
 local vp=Camera.rect(app);local x1,y1=app:position(vp.x,vp.y);local x2,y2=app:position(vp.x+vp.w,vp.y+vp.h)
 x1=math.max(0,x1);y1=math.max(0,y1);x2=math.min(map.width*256,x2);y2=math.min(map.height*256,y2)
 g.setColor(.95,.94,.79);g.setLineWidth(1);g.rectangle('line',r.x+x1/256*r.cell,r.y+y1/256*r.cell,(x2-x1)/256*r.cell,(y2-y1)/256*r.cell)
end
return M
