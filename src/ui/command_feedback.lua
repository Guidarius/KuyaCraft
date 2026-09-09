-- Cosmetic UI cues only. No command outcome is inferred before simulation acknowledgement.
local F={}
function F.notify(app,kind,message,action,costs,x,y)
 if message then app.message=message end
 app.uiNotice={kind=kind,text=message,time=app.clock,action=action,costs=costs}
 if kind=='rejected' then
  app.costFlash={time=app.clock,keys={}};for _,cost in ipairs(costs or {}) do if cost.short then app.costFlash.keys[cost.key]=true end end
 end
 if x and y then
  app.commandMarks=app.commandMarks or {};if #app.commandMarks>=16 then table.remove(app.commandMarks,1) end
  app.commandMarks[#app.commandMarks+1]={x=x,y=y,kind=kind,time=app.clock}
 end
 app.audio:play(kind)
end
function F.resolve(app,event,pending)
 if not pending then return end
 local kind=event.kind;local marker=app.orderMarker
 if marker and marker.group==pending.group and kind=='rejected' then marker.kind='rejected';marker.time=app.clock end
 if kind=='rejected' then
  local costs,reason;for _,a in ipairs(require('src.ui.actions').list(app)) do if a.id==pending.action then costs=a.costs;reason=a.reason end end
  F.notify(app,kind,reason or event.reason,pending.action,costs,pending.x,pending.y)
 elseif pending.kind=='upgrade' then F.notify(app,'levelup','Hero ability learned',pending.action,nil,pending.x,pending.y)
 elseif pending.kind=='toggle' then F.notify(app,'stance',nil,pending.action)
 else app.audio:play('accepted') end
end
function F.draw(app)
 local g=love.graphics;g.push('all');g.setLineWidth(1.5)
 for i=#(app.commandMarks or {}),1,-1 do local mark=app.commandMarks[i];local age=app.clock-mark.time
  if age>.65 then table.remove(app.commandMarks,i) else
   local x,y=app:screen(mark.x,mark.y);local a=1-age/.65
   if mark.kind=='rejected' then g.setColor(1,.34,.27,a);g.line(x-6,y-6,x+6,y+6);g.line(x-6,y+6,x+6,y-6)
   else g.setColor(.64,.87,.7,a);g.ellipse('line',x,y,10+age*15,5+age*7) end
  end
 end
 g.pop()
end
return F
