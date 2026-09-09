local W={}
function W.create() return setmetatable({items={}}, {__index=W}) end
function W:begin(scale) self.items={};self.scale=scale or 1;self.hover=nil end
function W:button(id,label,x,y,w,h,action,reason,tip,icon,details)
 local g=love.graphics;local mx,my=love.mouse.getPosition();mx=mx/self.scale;my=my/self.scale
 local over=mx>=x and mx<x+w and my>=y and my<y+h
 local item={id=id,x=x,y=y,w=w,h=h,action=action,reason=reason,label=label,tip=tip,details=details};self.items[#self.items+1]=item
 if over then self.hover=item end
 g.setColor(reason and .1 or over and .22 or .12,reason and .13 or over and .27 or .17,reason and .14 or over and .27 or .19);g.rectangle('fill',x,y,w,h,4)
 g.setColor(.47,.41,.27,reason and .35 or .8);g.rectangle('line',x,y,w,h,4)
 local costs=details and details.costs or {};local hasCosts=#costs>0
 local flash=self.notice and self.notice.action==id and (self.clock or 0)-self.notice.time<.45
 if flash then g.setColor(self.notice.kind=='rejected' and 1 or .65,self.notice.kind=='rejected' and .3 or .88,.35,.8);g.rectangle('line',x+1,y+1,w-2,h-2,4) end
 g.setColor(reason and .46 or .91,reason and .49 or .88,reason and .49 or .76)
 if icon then require('src.ui.icons').draw(icon,x+3,y+2,10,reason~=nil) end
 if details and details.badge then g.print(details.badge,x+15,y+1) end
 if details and details.key~='' then g.printf(details.key:upper(),x+15,y+1,w-19,'right') end
 local labelX=x+5;local labelW=w-10
 local _,lines=g.getFont():getWrap(label,labelW);local lineHeight=g.getFont():getHeight()
 local labelHeight=h-(hasCosts and 15 or 0)
 g.printf(label,labelX,y+math.max(details and 11 or 2,(labelHeight-#lines*lineHeight)/2),labelW,'center')
 if details and details.status then g.setColor(details.status=='Learned' and .56 or .48,.65,.55);g.printf(details.status,x+3,y+h-14,w-6,'center')
 elseif hasCosts then
  local gap=(w-6)/#costs
  for i,c in ipairs(costs) do
   if c.short then g.setColor(1,.38,.32) else g.setColor(.79,.76,.55) end
   local short=({gold='g',lumber='w',food='f',mana='m',xp='xp'})[c.key] or c.label:sub(1,1)
   g.printf(c.amount..short,x+3+(i-1)*gap,y+h-14,gap,'center')
  end
 end
end
function W:click(x,y)
 x=x/self.scale;y=y/self.scale
 for i=#self.items,1,-1 do local b=self.items[i];if x>=b.x and x<b.x+b.w and y>=b.y and y<b.y+b.h then if not b.reason and b.action then b.action() end;return true,b.reason,b end end
 return false
end
function W:tooltip(width,height)
 local b=self.hover;if not b then return end
 local g=love.graphics;local costs=b.details and b.details.costs or {}
 local body=b.tip or '';if b.reason then body=b.reason..(body~='' and ('\n'..body) or '') end
 if body=='' and #costs==0 then return end
 local _,lines=g.getFont():getWrap(body,280);local heightNeeded=40+#lines*g.getFont():getHeight()+#costs*18
 local mx,my=love.mouse.getPosition();local x=math.max(4,math.min(mx/self.scale+12,width-310));local y=math.max(42,math.min(my/self.scale-heightNeeded-10,height-heightNeeded-4))
 g.setColor(.04,.06,.08,.98);g.rectangle('fill',x,y,300,heightNeeded,4)
 g.setColor(.94,.9,.75);g.print(b.label,x+10,y+8)
 g.setColor(b.reason and 1 or .84,b.reason and .53 or .86,b.reason and .42 or .8);g.printf(body,x+10,y+28,280)
 local cy=y+32+#lines*g.getFont():getHeight()
 for _,c in ipairs(costs) do
  if c.short then g.setColor(1,.38,.32) else g.setColor(.8,.83,.7) end
  g.print(c.amount..' '..c.label..'  (available '..math.max(0,c.available)..')',x+10,cy);cy=cy+18
 end
end
return W
