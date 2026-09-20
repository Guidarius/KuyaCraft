-- Uses the real shader and App draw path, with view-only aircraft fixtures.
local T={}
function T.run(capture)
 local app=require('src.app').create({map='twin_marches',content=require('src.content'),faction='megacorp',opponent='orders'})
 app.noAutoSave=true
 local sprites=app.sprites
 if not (sprites and sprites.units.command_blimp and sprites.units.battleship) then
  print('SKIP aircraft rendered checks: build -Roster megacorp_aircraft');app:close();return
 end
 local Frames=require('src.asset_frames');local Sim=require('src.sim');local g=love.graphics
 local width,height=g.getDimensions()
 -- Every heading and every sample, drawn with the actual runtime recolor shader.
 for _,clip in ipairs({'idle','move','attack','death'}) do
  local max=6
  for sample=1,max do
   capture('aircraft-'..clip..'-'..sample,function()
    g.clear(.14,.18,.16,1)
    for row,id in ipairs({'command_blimp','battleship','command_blimp','battleship'}) do
     local m=sprites.units[id].metadata
     local team=row<=2 and {.20,.48,.95} or {.95,.22,.16}
     g.setColor(1,1,1);g.print(id..' / '..clip..' / sample '..sample,18,22+(row-1)*145)
     for i,d in ipairs(Frames.directions) do
      local frames=m.clips[clip].frames[d];local f=frames[math.min(sample,#frames)]
      assert(sprites:drawFrame(id,f,80+(i-1)*(width-100)/8,135+(row-1)*145,1,team))
      g.setColor(1,1,1);g.print(d,70+(i-1)*(width-100)/8,52+(row-1)*145)
     end
    end
   end)
  end
 end
 capture('aircraft-scales',function()
  for row,zoom in ipairs({.75,1,1.25}) do
   for column,bg in ipairs({{.12,.16,.12},{.70,.72,.65}}) do
    local x=(column-1)*width/2;local y=(row-1)*height/3
    g.setColor(bg);g.rectangle('fill',x,y,width/2,height/3)
    g.setColor(column==1 and 1 or .1,column==1 and 1 or .1,column==1 and 1 or .1)
    g.print('Scale '..zoom,x+18,y+18)
    for index,id in ipairs({'command_blimp','battleship'}) do
     local m=sprites.units[id].metadata
     for owner,team in ipairs({{.20,.48,.95},{.95,.22,.16}}) do
      local frame=Frames.sample(m,'idle',owner==1 and 'SE' or 'NW',0)
      assert(sprites:drawFrame(id,frame,x+(index-1)*width/4+owner*width/12,y+height/4,zoom,team))
     end
    end
   end
  end
 end)
 -- Mixed army on shipping terrain at the normal gameplay camera/scale.
 app:update(.05)
 local template
 for _,e in ipairs(app.view.entities) do if e.kind=='command_blimp' then template=e;break end end
 assert(template,'Megacorp start must supply a Blimp')
 require('src.ui.camera').center(app,template.x,template.y)
 local before=Sim.serializeCanonical(app.world)
 for index,kind in ipairs({'command_blimp','battleship','crossbow','command_blimp','battleship','crossbow'}) do
  local e={};for k,v in pairs(template) do e[k]=v end
  e.id=800000+index;e.kind=kind;e.owner=index<=3 and 1 or 2
  e.x,e.y=app:position(width*.20+(index-1)%3*width*.20,height*(index<=3 and .42 or .67))
  e.hp=app.content.units[kind].hp;e.maxHp=e.hp;e.order={kind='hold'}
  app.view.entities[#app.view.entities+1]=e;app.view.byId[e.id]=e
 end
 app.selected={800001,800002}
 capture('aircraft-gameplay',function() app:draw() end)
 for _,id in ipairs({800001,800002,800004,800005}) do assert(sprites.states[id],'Aircraft did not use sprite draw path') end
 assert(Sim.serializeCanonical(app.world)==before,'Aircraft presentation changed gameplay')
 assert(#sprites.diagnostics==0,'Aircraft catalog or shader diagnostics')
 app:close()
 print('PASS aircraft: actual shader, all headings and clip samples, two teams, gameplay scale, unchanged sim')
end
return T
