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
function C.center(app,x,y)
 local r=C.rect(app);app.camera.x=r.x+r.w/2-x/256*C.cellX*app.camera.zoom;app.camera.y=r.y+r.h/2-y/256*C.cellY*app.camera.zoom;C.clamp(app)
end
function C.contains(app,x,y) local r=C.rect(app);return x>=r.x and x<r.x+r.w and y>=r.y and y<r.y+r.h end
function C.zoom(app,x,y,delta)
 local wx,wy=app:position(x,y);app.camera.userZoom=math.max(.8,math.min(1.35,(app.camera.userZoom or 1)+delta*.1));C.normalize(app)
 app.camera.x=x-wx/256*C.cellX*app.camera.zoom;app.camera.y=y-wy/256*C.cellY*app.camera.zoom;C.clamp(app)
end
return C
