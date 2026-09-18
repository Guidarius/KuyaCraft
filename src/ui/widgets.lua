local Tooltip=require('src.ui.tooltip')
local W={}
function W.create() return setmetatable({items={}}, {__index=W}) end
function W:begin(scale) self.items={};self.scale=scale or 1;self.hover=nil;self.hoverRegion=nil end
function W:button(id,label,x,y,w,h,action,reason,tip,icon,details)
 local g=love.graphics;local mx,my=love.mouse.getPosition();mx=mx/self.scale;my=my/self.scale
 local over=mx>=x and mx<x+w and my>=y and my<y+h
 local item={id=id,x=x,y=y,w=w,h=h,action=action,reason=reason,label=label,tip=tip,details=details,anchor=self.anchor};self.items[#self.items+1]=item
 if over then self.hover=item end
 -- The faction's look (src/ui/theme.lua), set by whoever is drawing; the default otherwise.
 local theme=self.theme or require('src.ui.theme').default;local radius=theme.radius
 local fill=reason and theme.buttonOff or over and theme.buttonHover or theme.button
 g.setColor(fill[1],fill[2],fill[3]);g.rectangle('fill',x,y,w,h,radius)
 g.setColor(theme.buttonLine[1],theme.buttonLine[2],theme.buttonLine[3],reason and .35 or .8);g.rectangle('line',x,y,w,h,radius)
 local costs=details and details.costs or {};local hasCosts=#costs>0
 local flash=self.notice and self.notice.action==id and (self.clock or 0)-self.notice.time<.45
 if flash then g.setColor(self.notice.kind=='rejected' and 1 or .65,self.notice.kind=='rejected' and .3 or .88,.35,.8);g.rectangle('line',x+1,y+1,w-2,h-2,radius) end
 if reason then g.setColor(.46,.49,.49) else g.setColor(theme.buttonText[1],theme.buttonText[2],theme.buttonText[3]) end
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
-- Hover-only areas: a readout that explains itself but does nothing when clicked. Kept apart from
-- buttons so a click on one still reaches whatever it would have reached before.
function W:region(id,x,y,w,h,tip)
 local mx,my=love.mouse.getPosition();mx=mx/self.scale;my=my/self.scale
 if mx>=x and mx<x+w and my>=y and my<y+h then self.hoverRegion={id=id,x=x,y=y,w=w,h=h,tip=tip} end
end
-- A modal panel takes the pointer: nothing drawn under it may keep a tooltip.
function W:clearHover() self.hover=nil;self.hoverRegion=nil end
-- Draws the tooltip for whatever the pointer is over. `opts` may give the command card rectangle,
-- the top edge of the usable area, a world spec to fall back on, and `hidden` to suppress it.
function W:tooltip(width,height,opts)
 opts=opts or {}
 self.tipState=self.tipState or {}
 local clock=self.clock or (love.timer and love.timer.getTime()) or 0
 local item=self.hover or self.hoverRegion
 local spec,id,instant
 if item then
  spec=Tooltip.fromWidget(item);id='w:'..tostring(item.id or item.label)
  -- The card answers at once; so does a widget a test or caller marks as instant.
  instant=item.anchor=='card' or item.instant
 elseif opts.world then spec=opts.world;id=opts.worldId end
 if opts.hidden or not spec or not (spec.lines or spec.reason or spec.status or (spec.costs and #spec.costs>0) or (spec.stats and #spec.stats>0)) then Tooltip.ready(self.tipState,nil,clock);self.shownTip=nil;return end
 if not Tooltip.ready(self.tipState,id,clock,instant) then self.shownTip=nil;return end
 local g=love.graphics
 local font=g.getFont();local titleFont=opts.titleFont or font
 local layout=Tooltip.layout(spec,font,titleFont)
 local mx,my=love.mouse.getPosition();mx=mx/self.scale;my=my/self.scale
 local x,y=Tooltip.place(layout,spec.anchor or item and item.anchor,{w=width,h=height,top=opts.top},mx,my,opts.card)
 Tooltip.draw(spec,x,y,layout,font,titleFont)
 g.setFont(font)
 -- What was drawn, for tests and for anything that needs to avoid it.
 self.shownTip={id=id,spec=spec,x=x,y=y,w=layout.width,h=layout.height}
end
return W
