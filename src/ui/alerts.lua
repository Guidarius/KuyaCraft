local A={}
function A.create() return setmetatable({items={},last={},clock=0,pending={}}, {__index=A}) end
function A:update(dt) self.clock=self.clock+dt;for i=#self.items,1,-1 do if self.clock-self.items[i].time>12 then table.remove(self.items,i) end end end
function A:add(key,text,x,y,app)
 for _,item in ipairs(self.items) do if item.text==text and x and item.x and (item.x-x)^2+(item.y-y)^2<(8*256)^2 and self.clock-item.time<5 then item.count=(item.count or 1)+1;return end end
 if self.clock-(self.last[key] or -100)<5 then return end;self.last[key]=self.clock
 local item={text=text,x=x,y=y,time=self.clock,priority=text:find('Hero') and 5 or text:find('Headquarters') and 4 or text:find('upgrade') and 3 or 1};table.insert(self.items,1,item);table.sort(self.items,function(a,b) if a.priority~=b.priority then return a.priority>b.priority end return a.time>b.time end);if #self.items>4 then table.remove(self.items) end
 if app and app.audio then app.audio:play('alert') end
end
function A:observe(events,app)
 for _,v in ipairs(events) do
  local own=v.owner==app.player
  if v.kind=='attack' and own and (v.target==app.view.player.hero or v.target==app.view.player.hq) then self:add('attack'..v.target,v.target==app.view.player.hero and 'Hero under attack' or 'Headquarters under attack',v.x,v.y,app)
  elseif v.kind=='death' and v.entity==app.view.player.hero then self:add('hero-death','Hero lost - revive at headquarters',v.x,v.y,app)
  elseif own and (v.kind=='constructed' or v.kind=='production_blocked' or v.kind=='blocked') then self:add(v.kind..v.entity,({constructed='Construction complete',production_blocked='Production exit blocked',blocked='Order blocked'})[v.kind],v.x,v.y,app) end
 end
 local hero=app:entity(app.view.player.hero)
 if hero then for i,t in ipairs(require('src.content').rules.xpThresholds) do if hero.xp>=t and not hero.upgrades[i] and not self.pending[i] then self.pending[i]=true;self:add('upgrade','Hero upgrade available',hero.x,hero.y,app) end end end
end
return A
