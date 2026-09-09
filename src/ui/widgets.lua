local W={}
function W.create() return setmetatable({items={}}, {__index=W}) end
function W:begin(scale) self.items={};self.scale=scale or 1;self.hover=nil end
function W:button(id,label,x,y,w,h,action,reason,tip,icon)
 local g=love.graphics;local mx,my=love.mouse.getPosition();mx=mx/self.scale;my=my/self.scale
 local over=mx>=x and mx<x+w and my>=y and my<y+h
 local item={id=id,x=x,y=y,w=w,h=h,action=action,reason=reason,label=label,tip=tip};self.items[#self.items+1]=item
 if over then self.hover=item end
 g.setColor(reason and .1 or over and .22 or .12,reason and .13 or over and .27 or .17,reason and .14 or over and .27 or .19);g.rectangle('fill',x,y,w,h,4)
 g.setColor(.47,.41,.27,reason and .35 or .8);g.rectangle('line',x,y,w,h,4)
 g.setColor(reason and .46 or .91,reason and .49 or .88,reason and .49 or .76);if icon then require('src.ui.icons').draw(icon,x+4,y+(h-17)/2,17) end;g.printf(label,x+(icon and 24 or 5),y+(h-14)/2-(#label>18 and 5 or 0),w-(icon and 29 or 10),'center')
end
function W:click(x,y)
 x=x/self.scale;y=y/self.scale
 for i=#self.items,1,-1 do local b=self.items[i];if x>=b.x and x<b.x+b.w and y>=b.y and y<b.y+b.h then if not b.reason and b.action then b.action() end;return true,b.reason end end
 return false
end
function W:tooltip(width,height)
 local b=self.hover;if not b then return end
 local text=b.reason=='Passive' and b.tip or b.reason or b.tip;if not text then return end
 local g=love.graphics;local mx,my=love.mouse.getPosition();local x=math.min(mx/self.scale+12,width-310);local y=math.min(my/self.scale-65,height-80)
 g.setColor(.04,.06,.08,.98);g.rectangle('fill',x,y,300,62,4);g.setColor(.94,.9,.75);g.printf(text,x+10,y+8,280)
end
return W
