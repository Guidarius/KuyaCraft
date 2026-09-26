-- Real sprite shader, game-camera scale board, and owner-filtered cosmetic descent.
local T={}
function T.run(capture)
 local App=require('src.app');local Sim=require('src.sim');local Frames=require('src.asset_frames')
 local app=App.create({map='twin_marches',content=require('src.content'),faction='megacorp',opponent='orders'})
 app.noAutoSave=true;app:update(.05)
 local sprites=app.sprites;local asset=sprites and sprites.units.drop_pod
 if not asset then print('SKIP drop pod render checks: build -Unit drop_pod');app:close();return end
 local g=love.graphics;local width,height=g.getDimensions();local before=Sim.serializeCanonical(app.world)
 local roster={'associate','medic','enforcer','drop_pod','bunker','mc_barracks','orbital_command'}
 for _,zoom in ipairs({1,2}) do
  capture('megacorp-scale-board-'..zoom,function()
   g.clear(.14,.18,.17,1)
   g.setColor(1,1,1);g.print('MEGACORP / shared game camera / '..zoom..'x / buildings retain gameplay footprints',24,20)
   for owner=1,2 do
    local ground=height*(owner==1 and .38 or .78)
    for index,id in ipairs(roster) do
     local x=width*(.055+(index-1)*.143);local m=sprites.units[id].metadata
     local frame=Frames.sample(m,'idle',id=='drop_pod' and 'S' or 'SE',0)
     g.setColor(.5,.6,.55,.5);g.line(x-30,ground,x+30,ground)
     sprites:drawFrame(id,frame,x,ground,zoom,owner==1 and {.20,.48,.95} or {.95,.22,.16})
     g.setColor(1,1,1);g.printf(id,x-75,ground+44*zoom,150,'center')
    end
   end
  end)
 end
 capture('drop-pod-doors',function()
  g.clear(.14,.18,.17,1)
  for sample,frame in ipairs(asset.metadata.clips.deploy.frames.S) do
   local x=width*(sample-.5)/6
   g.setColor(1,1,1);g.printf('Door pose '..sample,x-70,70,140,'center')
   sprites:drawFrame('drop_pod',frame,x,height*.45,2,{.20,.48,.95})
   sprites:drawFrame('drop_pod',frame,x,height*.78,1,{.95,.22,.16})
  end
 end)
 local x,y=app:position(width*.55,height*.52);local cellX,cellY=math.floor(x/256),math.floor(y/256)
 local cx,cy=app:screen(cellX*256+128,cellY*256+128)
 app.view.player.pods=app.view.player.pods or {open={kinds={}},inFlight={},cooldownUntil=0}
 app.view.player.pods.inFlight={{x=cellX,y=cellY,at=app.world.tick+20,kinds={'associate','medic','enforcer'}}}
 local original=sprites.drawFrame;local drawn={}
 sprites.drawFrame=function(self,id,frame,px,py,z,team,alpha)
  if id=='drop_pod' then drawn[#drawn+1]={frame=frame,x=px,y=py,alpha=alpha or 1} end
  return original(self,id,frame,px,py,z,team,alpha)
 end
 capture('drop-pod-descent',function() app:draw() end)
 assert(#drawn==1 and drawn[1].y<cy and math.abs(drawn[1].x-cx)<.01,'pod did not descend above its marked landing site')
 app.view.player.pods.inFlight={};app.juice:reset()
 app.juice:observe({{kind='pod_landed',player=app.player,podX=cellX,podY=cellY}},app)
 app.juice:update(.5);drawn={}
 capture('drop-pod-landed',function() app:draw() end)
 assert(#drawn==1 and drawn[1].frame==asset.metadata.clips.deploy.frames.S[6],'landed pod did not finish opening')
 assert(math.abs(drawn[1].y-cy)<.01,'landed pod anchor shifted')
 app.juice:update(1.7);drawn={};app.juice:drawGround(app)
 assert(#drawn==1 and drawn[1].alpha<1 and drawn[1].alpha>0,'spent hull did not fade')
 local owner=app.player;app.player=owner+1;drawn={};app.juice:drawGround(app)
 assert(#drawn==0,'another perspective saw the cosmetic landed hull');app.player=owner
 app.juice:update(.31);drawn={};app.juice:drawGround(app);assert(#drawn==0,'spent hull remained')
 -- Optional art missing: the original descent marker remains drawable.
 sprites.units.drop_pod=nil;app.view.player.pods.inFlight={{x=cellX,y=cellY,at=app.world.tick+20,kinds={'associate'}}}
 capture('drop-pod-fallback',function() app:draw() end);sprites.units.drop_pod=asset
 sprites.drawFrame=original
 assert(Sim.serializeCanonical(app.world)==before,'cosmetic pod changed simulation')
 assert(#sprites.diagnostics==0,'drop pod asset diagnostics');app:close()
 print('PASS drop pod: shared scale, six door poses, descent anchor, landed opening, fading, owner privacy, expiry, fallback, unchanged simulation')
end
return T
