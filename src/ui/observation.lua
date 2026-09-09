local Codec=require('src.sim.codec')
local O={}
function O.create() return setmetatable({memory={}}, {__index=O}) end
function O:update(view)
 local seen={}
 for _,e in ipairs(view.entities) do
  if e.alive then seen[e.id]=true end
  if e.category=='node' or e.category=='building' or e.home then
   if e.alive then self.memory[e.id]=Codec.copy(e) else self.memory[e.id]=nil end
  end
 end
 for id,e in pairs(self.memory) do
  local visible=false
  for y=math.floor(e.y/256),math.floor(e.y/256)+e.size-1 do for x=math.floor(e.x/256),math.floor(e.x/256)+e.size-1 do
   if view.player.visible[y*view.map.width+x+1] then visible=true end
  end end
  if visible and not seen[id] then self.memory[id]=nil end
 end
 self.markers={}
 for _,e in ipairs(view.entities) do if e.alive then self.markers[#self.markers+1]=e end end
 for _,id in ipairs(Codec.keys(self.memory)) do if not seen[id] then local ghost=Codec.copy(self.memory[id]);ghost.remembered=true;self.markers[#self.markers+1]=ghost end end
 table.sort(self.markers,function(a,b) return a.id<b.id end)
end
return O
