local P={}
function P.run(app)
 local Sim=require('src.sim');local Codec=require('src.sim.codec');local Frames=require('src.asset_frames')
 local before=Sim.serializeCanonical(app.world);local calls={};local sprites=app.sprites;local original=sprites.drawFrame
 sprites.drawFrame=function(self,id,frame,...) calls[#calls+1]={id=id,frame=frame};return original(self,id,frame,...) end
 local canvas=love.graphics.newCanvas(love.graphics.getDimensions());local old=love.graphics.getCanvas()
 love.graphics.push('all');love.graphics.setCanvas(canvas);love.graphics.clear()
 for _,kind in ipairs({'keep','depot','barracks','sanctum'}) do
  local source;for _,e in ipairs(app.view.entities) do if e.kind==kind then source=e;break end end
  assert(source,'Missing building in art fixture: '..kind)
  local e=Codec.copy(source);local ticks=app.content.buildings[kind].buildTicks
  for _,remaining in ipairs({ticks,math.floor(ticks*2/3),math.floor(ticks/3),1,0}) do
   e.remaining=remaining;local expected=Frames.construction(sprites.units[kind].metadata,remaining,ticks)
   app:drawEntity(e);local call=calls[#calls];assert(call.id==kind)
   assert(call.frame==(expected or sprites.units[kind].metadata.clips.idle.frames.S[1]),'Incorrect building stage')
  end
 end
 local worker;for _,e in ipairs(app.view.entities) do if e.kind=='worker' then worker=Codec.copy(e);break end end
 assert(worker);local previous={x=worker.x-32,y=worker.y};worker.carrying=0
 sprites:draw(worker,100,100,1,nil,previous,app.world.tick,app.view)
 local a=calls[#calls];local elapsed=sprites.states[worker.id].moveMs
 worker.carrying=8;sprites:draw(worker,100,100,1,nil,previous,app.world.tick,app.view)
 local b=calls[#calls];assert(a.id=='worker' and b.id=='worker_loaded' and a.frame==b.frame)
 assert(sprites.states[worker.id].moveMs==elapsed,'Cargo swap advanced phase')
 for _,kind in ipairs({'gryphon','reliquary'}) do
  local source;for _,e in ipairs(app.view.entities) do if e.kind==kind then source=e;break end end
  assert(source);local e=Codec.copy(source)
  for _,d in ipairs({{1,0},{0,1},{-1,0},{0,-1}}) do
   sprites:draw(e,150,150,1,nil,{x=e.x-d[1]*32,y=e.y-d[2]*32},app.world.tick,app.view)
   assert(calls[#calls].id==kind)
  end
  e.alive=false;e.deathTick=app.world.tick-3;sprites:draw(e,150,150,1,nil,nil,app.world.tick,app.view)
 end
 sprites.drawFrame=original;love.graphics.setCanvas(old);love.graphics.pop();canvas:release();sprites:reset()
 assert(Sim.serializeCanonical(app.world)==before,'Presentation checks mutated canonical state')
 print('ORDERS_PRESENTATION_PASS: 20 building stages, cargo continuity, mounted/shrine playback, canonical read-only')
end
function P.captureRoof(app)
 local keep;for _,e in ipairs(app.view.entities) do if e.kind=='keep' and e.remaining==0 and e.owner==app.player then keep=e;break end end
 assert(keep,'Roof regression requires the complete fixture Keep')
 local z=app.camera.zoom;local x,y=app:screen(keep.x,keep.y)
 x=x+(keep.size-1)*13*z+18*z
 y=y+(keep.size-1)*require('src.ui.camera').cellY/2*z-62*z
 love.graphics.captureScreenshot(function(data)
  local r,g,b=data:getPixel(math.floor(x),math.floor(y))
  assert(b>g+.05 and g>r+.05,'Terrain canvas restore clipped the Keep roof')
  print('ORDERS_ROOF_PIXEL_PASS: visible team roof after terrain-cache warmup')
 end)
end
return P
