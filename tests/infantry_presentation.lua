-- Read-only render fixtures for the Megacorp pressure suits and their team masks.
local T={}
function T.run(capture)
 local App=require('src.app');local Sim=require('src.sim');local Frames=require('src.asset_frames')
 local app=App.create({map='twin_marches',content=require('src.content'),faction='megacorp',opponent='orders'})
 app.noAutoSave=true
 local ids={'associate','medic','enforcer'};local sprites=app.sprites
 for _,id in ipairs(ids) do
  if not (sprites and sprites.units[id]) then print('SKIP infantry render checks: build -Roster megacorp_infantry');app:close();return end
 end
 local g=love.graphics;local width,height=g.getDimensions()
 local grounds={92,190,326,424,522,658}
 local labels={8,106,212,340,438,544}
 for _,clip in ipairs({'idle','move','attack','death','work'}) do
  local count=0
  for _,id in ipairs(ids) do local c=sprites.units[id].metadata.clips[clip];if c then count=math.max(count,#c.frames.S) end end
  for sample=1,count do
   capture('infantry-'..clip..'-'..sample,function()
    g.clear(.14,.18,.16,1)
    for row=1,6 do
     local id=ids[(row-1)%3+1];local m=sprites.units[id].metadata;local c=m.clips[clip]
     g.setColor(1,1,1);g.print(id..' / '..clip..' / '..sample,12,labels[row])
     if c then for i,d in ipairs(Frames.directions) do
      local frames=c.frames[d]
      assert(sprites:drawFrame(id,frames[math.min(sample,#frames)],80+(i-1)*(width-100)/8,grounds[row],1,
                             row<=3 and {.20,.48,.95} or {.95,.22,.16}))
     end end
    end
   end)
  end
 end
 capture('infantry-scales',function()
  local positions={{.0625,.164},{.289,.391},{.609,.859}}
  for row,zoom in ipairs({.75,1,1.5}) do for col,bg in ipairs({{.12,.16,.12},{.70,.72,.65}}) do
   local x=(col-1)*width/2;local y=(row-1)*height/3
   g.setColor(bg);g.rectangle('fill',x,y,width/2,height/3)
   g.setColor(col==1 and 1 or .1,col==1 and 1 or .1,col==1 and 1 or .1);g.print('Scale '..zoom,x+15,y+15)
   for index,id in ipairs(ids) do for owner=1,2 do
    local m=sprites.units[id].metadata;local frame=Frames.sample(m,'idle',owner==1 and 'SE' or 'NW',0)
    sprites:drawFrame(id,frame,x+positions[index][owner]*width/2,y+height/4,zoom,owner==1 and {.20,.48,.95} or {.95,.22,.16})
   end end
  end end
 end)
 app:update(.05)
 local template;for _,e in ipairs(app.view.entities) do if e.kind=='command_blimp' then template=e;break end end
 assert(template);require('src.ui.camera').center(app,template.x,template.y)
 local before=Sim.serializeCanonical(app.world)
 -- Keep the comparison unobscured by the starting headquarters and Blimp.
 app.view.entities={};app.view.byId={}
 local roster={'associate','medic','enforcer','crossbow','associate','medic','enforcer','crossbow'}
 for index,kind in ipairs(roster) do
  local e={};for k,v in pairs(template) do e[k]=v end
  e.id=810000+index;e.kind=kind;e.owner=index<=4 and 1 or 2
  e.x,e.y=app:position(width*.14+(index-1)%4*width*.10,height*(index<=4 and .43 or .68))
  e.hp=app.content.units[kind].hp;e.maxHp=e.hp;e.order={kind='hold'}
  app.view.entities[#app.view.entities+1]=e;app.view.byId[e.id]=e
 end
 app.selected={810001,810002,810003}
 capture('infantry-gameplay',function() app:draw() end)
 for i=1,8 do assert(sprites.states[810000+i],'Infantry did not use sprite renderer') end
 assert(Sim.serializeCanonical(app.world)==before,'Infantry render changed simulation')
 assert(#sprites.diagnostics==0,'Infantry asset diagnostics')
 app:close()
 print('PASS infantry: all clips/headings, two teams, fractional scales, same-team Orders comparison, unchanged simulation')
end
return T
