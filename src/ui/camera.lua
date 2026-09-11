local C={cellX=26,cellY=26*math.sin(math.pi/3)}
function C.rect(app)
 local w,h=love.graphics.getDimensions();local s=(app.settings and app.settings.scale or 100)/100
 return {x=0,y=40*s,w=w,h=h-220*s}
end
function C.normalize(app)
 local r=C.rect(app);local c=app.camera;c.userZoom=c.userZoom or 1;c.zoom=r.h/(24*C.cellY)*c.userZoom;c.viewportHeight=r.h
end
function C.clamp(app)
 local r=C.rect(app);local c=app.camera
 local mw,mh=app.world.map.width*C.cellX*c.zoom,app.world.map.height*C.cellY*c.zoom
 local function axis(v,start,size,mapSize) if mapSize<=size then return start+(size-mapSize)/2 end return math.max(start+size-mapSize-24,math.min(start+24,v)) end
 c.x=axis(c.x,r.x,r.w,mw);c.y=axis(c.y,r.y,r.h,mh)
end
-- Where the camera would have to sit to put a world point in the middle of the viewport.
local function target(app,x,y)
 local r=C.rect(app)
 return r.x+r.w/2-x/256*C.cellX*app.camera.zoom,r.y+r.h/2-y/256*C.cellY*app.camera.zoom
end
function C.center(app,x,y)
 app.camera.x,app.camera.y=target(app,x,y);app.cameraGlide=nil;C.clamp(app)
end
-- Jumping to a group, the hero or an alert is a navigation aid, and an instant cut
-- loses the player's sense of where they went. A short ease keeps the relationship
-- between the old and new position readable. Drag, edge scroll and the minimap stay
-- instant, because those are direct manipulation and any smoothing reads as lag.
C.GLIDE=0.18
function C.glide(app,x,y)
 local toX,toY=target(app,x,y)
 app.cameraGlide={fromX=app.camera.x,fromY=app.camera.y,toX=toX,toY=toY,age=0}
end
function C.update(app,dt)
 local glide=app.cameraGlide
 if not glide then return end
 glide.age=glide.age+dt
 local t=math.min(1,glide.age/C.GLIDE)
 -- Ease-out cubic: fastest at the start, settling into the destination.
 local eased=1-(1-t)^3
 app.camera.x=glide.fromX+(glide.toX-glide.fromX)*eased
 app.camera.y=glide.fromY+(glide.toY-glide.fromY)*eased
 if t>=1 then app.cameraGlide=nil end
 C.clamp(app)
end
function C.contains(app,x,y) local r=C.rect(app);return x>=r.x and x<r.x+r.w and y>=r.y and y<r.y+r.h end
function C.zoom(app,x,y,delta)
 local wx,wy=app:position(x,y);app.camera.userZoom=math.max(.8,math.min(1.35,(app.camera.userZoom or 1)+delta*.1));C.normalize(app)
 app.camera.x=x-wx/256*C.cellX*app.camera.zoom;app.camera.y=y-wy/256*C.cellY*app.camera.zoom;app.cameraGlide=nil;C.clamp(app)
end
-- Bookmarks store a world point, not a camera offset, so they survive a resize or a
-- zoom change and still frame the same ground.
function C.setBookmark(app,slot)
 local r=C.rect(app)
 local x,y=app:position(r.x+r.w/2,r.y+r.h/2)
 app.bookmarks=app.bookmarks or {}
 app.bookmarks[slot]={x=x,y=y}
 return true
end
function C.recallBookmark(app,slot)
 local mark=app.bookmarks and app.bookmarks[slot]
 if not mark then return false end
 C.glide(app,mark.x,mark.y);return true
end
return C
