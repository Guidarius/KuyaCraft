local Camera=require('src.ui.camera')
local A={}
-- An attack on your forces is announced once per area this size, in cells, however many of your
-- units are being hit there. The per-key cooldown below then keeps a long fight to one notice
-- every few seconds.
local FORCES_AREA=12
local function onScreen(app,x,y)
 local r=Camera.rect(app);local sx,sy=app:screen(x,y)
 return sx>=r.x and sx<r.x+r.w and sy>=r.y and sy<r.y+r.h
end
function A.create() return setmetatable({items={},last={},clock=0,pending={}}, {__index=A}) end
function A:update(dt) self.clock=self.clock+dt;for i=#self.items,1,-1 do if self.clock-self.items[i].time>12 then table.remove(self.items,i) end end end
function A:add(key,text,x,y,app)
 for _,item in ipairs(self.items) do if item.text==text and x and item.x and (item.x-x)^2+(item.y-y)^2<(8*256)^2 and self.clock-item.time<5 then item.count=(item.count or 1)+1;return end end
 if self.clock-(self.last[key] or -100)<5 then return end;self.last[key]=self.clock
 local item={text=text,x=x,y=y,time=self.clock,priority=text:find('Hero') and 5 or (text:find('Headquarters') or text:find('both control points')) and 4 or (text:find('under attack') or text:find('upgrade')) and 3 or 1};table.insert(self.items,1,item);table.sort(self.items,function(a,b) if a.priority~=b.priority then return a.priority>b.priority end return a.time>b.time end);if #self.items>4 then table.remove(self.items) end
 if app and app.audio then app.audio:play('alert') end
 -- Opt-in only: the camera never moves unasked, but a player who turned this on has asked. Only
 -- fights take it there; a finished building does not deserve to pull the view away.
 if app and app.settings and app.settings.alertCamera and x and text:find('under attack') then Camera.glide(app,x,y) end
end
function A:observe(events,app)
 for _,v in ipairs(events) do
  local own=v.owner==app.player
  if v.kind=='attack' and own and (v.target==app.view.player.hero or v.target==app.view.player.hq) then self:add('attack'..v.target,v.target==app.view.player.hero and 'Hero under attack' or 'Headquarters under attack',v.x,v.y,app)
  -- Anything else of yours being hit where you are not looking. The minimap rings the spot.
  elseif v.kind=='attack' and own and v.x and not onScreen(app,v.x,v.y) then
   self:add('forces'..math.floor(v.x/(FORCES_AREA*256))..':'..math.floor(v.y/(FORCES_AREA*256)),'Your forces are under attack',v.x,v.y,app)
  elseif v.kind=='death' and v.entity==app.view.player.hero then self:add('hero-death','Hero lost - revive at headquarters',v.x,v.y,app)
  elseif v.kind=='captured' then self:add('captured'..v.point..':'..v.capturedBy,v.capturedBy==app.player and 'Control point captured' or 'Control point taken by the enemy',v.x,v.y,app)
  elseif v.kind=='control_started' then self:add('control'..v.holder,v.holder==app.player and 'You hold both control points' or 'Enemy holds both control points - retake one',nil,nil,app)
  elseif own and (v.kind=='constructed' or v.kind=='build_stalled' or v.kind=='production_blocked' or v.kind=='blocked') then self:add(v.kind..v.entity,({constructed='Construction complete',build_stalled='Construction stopped - send a worker back',production_blocked='Production exit blocked',blocked='Order blocked'})[v.kind],v.x,v.y,app) end
 end
 local hero=app:entity(app.view.player.hero)
 if hero then for i,t in ipairs(require('src.content').rules.xpThresholds) do if hero.xp>=t and not hero.upgrades[i] and not self.pending[i] then self.pending[i]=true;self:add('upgrade','Hero upgrade available',hero.x,hero.y,app) end end end
end
return A
