-- Actual shader and App draw-path checks; fixture edits are filtered-view-only.
local T={}
function T.run(capture)
 local App=require('src.app');local Sim=require('src.sim');local Frames=require('src.asset_frames')
 local app=App.create({map='twin_marches',content=require('src.content'),faction='megacorp',opponent='orders'})
 app.noAutoSave=true
 local ids={'orbital_command','mc_barracks','requisition_office','med_bay','armory','orbital_relay','substrate_rig','charge_rig','bunker'}
 local sprites=app.sprites;local g=love.graphics;local width,height=g.getDimensions()
 for _,id in ipairs(ids) do
  if not (sprites and sprites.units[id]) then print('SKIP building render checks: build -Roster megacorp_buildings');app:close();return end
  local m=sprites.units[id].metadata
  assert(m.footprintCells==app.content.buildings[id].size,'building art footprint disagrees with gameplay: '..id)
  assert(#m.frames==#m.clips.idle.frames.S,'building stored duplicate direction frames')
 end
 local before=Sim.serializeCanonical(app.world)
 for _,zoom in ipairs({.75,1,1.5}) do
  capture('buildings-scales-'..zoom,function()
   g.clear(.16,.20,.17,1)
   for i,id in ipairs(ids) do
    local x=((i-1)%3)*width/3;local y=math.floor((i-1)/3)*height/3
    local m=sprites.units[id].metadata;local frame=Frames.sample(m,'idle','S',0)
    g.setColor(1,1,1);g.print(id..' / '..m.footprintCells..' cells / '..zoom..'x',x+15,y+10)
    for owner=1,2 do
     local cx=x+width/3*(owner==1 and .28 or .73);local cy=y+height/3*.62
     g.setColor(.7,.75,.6,.4);g.rectangle('line',cx-m.footprintCells*13*zoom,cy-m.footprintCells*26*math.sin(math.pi/3)/2*zoom,
                  m.footprintCells*26*zoom,m.footprintCells*26*math.sin(math.pi/3)*zoom)
     assert(sprites:drawFrame(id,frame,cx,cy,zoom,owner==1 and {.20,.48,.95} or {.95,.22,.16}))
    end
   end
  end)
 end
 -- Every rigid idle sample must be drawable through the real team shader.
 for i,id in ipairs({'orbital_relay','substrate_rig'}) do
  capture('buildings-motion-'..id,function()
   g.clear(.13,.17,.19,1);local m=sprites.units[id].metadata
   for sample,frame in ipairs(m.clips.idle.frames.S) do
    sprites:drawFrame(id,frame,60+(sample-1)*(width-100)/#m.clips.idle.frames.S,190,1.5,{.20,.48,.95})
   end
  end)
 end
 -- Team shaders must change colored shells and preserve the neutral trim.
 local function pixels(team)
  local canvas=g.newCanvas(192,192);g.push('all');g.setCanvas(canvas);g.clear(0,0,0,0)
  sprites:drawFrame('orbital_command',1,96,100,1,team);g.pop()
  local data=canvas:newImageData();canvas:release();return data
 end
 local blue,red=pixels({.20,.48,.95}),pixels({.95,.22,.16});local changed,neutral=0,0
 for y=0,191 do for x=0,191 do
  local r,b,c,a=blue:getPixel(x,y);local rr,bb,cc=red:getPixel(x,y)
  if a>.9 then if math.abs(r-rr)+math.abs(b-bb)+math.abs(c-cc)>.10 then changed=changed+1 else neutral=neutral+1 end end
 end end
 assert(changed>300 and neutral>300,'building team shell or neutral trim was lost');blue:release();red:release()
 app:update(.05);before=Sim.serializeCanonical(app.world)
 local template,infantryTemplate
 for _,e in ipairs(app.view.entities) do
  if e.kind=='orbital_command' then template=e elseif e.kind=='command_blimp' then infantryTemplate=e end
 end
 assert(template);require('src.ui.camera').center(app,template.x,template.y)
 app.view.entities={};app.view.byId={};app.selected={}
 local rect=require('src.ui.camera').rect(app)
 for i,id in ipairs(ids) do
  local e={};for k,v in pairs(template) do e[k]=v end
  e.id=820000+i;e.kind=id;e.owner=(i-1)%2+1;e.size=app.content.buildings[id].size
  local cx=rect.x+rect.w*(.19+(i-1)%3*.30);local cy=rect.y+rect.h*(.15+math.floor((i-1)/3)*.29)
  local wx,wy=app:position(cx,cy);e.x=math.floor(wx/256)*256+128;e.y=math.floor(wy/256)*256+128
  e.hp=app.content.buildings[id].hp;e.maxHp=e.hp;e.remaining=0
  app.view.entities[#app.view.entities+1]=e;app.view.byId[e.id]=e;app.selected[#app.selected+1]=e.id
  local sx,sy=app:screen(e.x+(e.size-1)*128,e.y+(e.size-1)*128)
  assert(app:pick(sx,sy,false,true).id==e.id,'building centre cannot be picked')
 end
 app.selected={820001}
 -- Existing infantry provides an honest size reference beside the 4x4 headquarters.
 if infantryTemplate then for i,kind in ipairs({'associate','enforcer'}) do
  local e={};for k,v in pairs(infantryTemplate) do e[k]=v end
  local command=app.view.byId[820001]
  e.id=820100+i;e.kind=kind;e.owner=1;e.size=1;e.order={kind='hold'}
  e.hp=app.content.units[kind].hp;e.maxHp=e.hp
  e.x=command.x+(i==1 and 4.7 or 7.5)*256;e.y=command.y+3*256
  app.view.entities[#app.view.entities+1]=e;app.view.byId[e.id]=e
 end end
 local drawFrame=sprites.drawFrame;local drawn={}
 sprites.drawFrame=function(self,id,frame,x,y,...)
  drawn[id]={x=x,y=y};return drawFrame(self,id,frame,x,y,...)
 end
 capture('buildings-gameplay',function() app:draw() end)
 sprites.drawFrame=drawFrame
 for _,e in ipairs(app.view.entities) do
  if e.category=='building' then
  local x,y=app:screen(e.x+(e.size-1)*128,e.y+(e.size-1)*128)
  assert(drawn[e.kind] and math.abs(drawn[e.kind].x-x)<.01 and math.abs(drawn[e.kind].y-y)<.01,'building ground anchor shifted: '..e.kind)
  end
 end
 -- Missing optional art still has the existing selectable building fallback.
 local old=sprites.units.bunker;sprites.units.bunker=nil
 capture('buildings-fallback',function() app:draw() end);sprites.units.bunker=old
 assert(Sim.serializeCanonical(app.world)==before,'building render changed simulation')
 assert(#sprites.diagnostics==0,'building asset diagnostics')
 app:close()
 print('PASS buildings: nine footprint anchors, picking, fixed-view packing, all idle samples, two teams, fractional zoom, fallback, unchanged simulation')
end
return T
