local O={}
-- Remembered fog contents. View entities are freshly built each tick and nobody
-- mutates them, so remembering one is a reference assignment rather than a deep
-- copy: copying every resource node and building on every tick was pure waste.
-- The "remembered" ghost is a shallow copy made once per entry, because the flag
-- must not appear on the live entity, and reused until that entry is replaced.
local function byId(a,b) return a.id<b.id end
function O.create() return setmetatable({memory={},ghosts={},markers={}}, {__index=O}) end
function O:update(view)
 local seen={}
 local memory,ghosts=self.memory,self.ghosts
 for _,e in ipairs(view.entities) do
  if e.alive then seen[e.id]=true end
  if e.category=='node' or e.category=='building' or e.home then
   if e.alive then
    if memory[e.id]~=e then memory[e.id]=e;ghosts[e.id]=nil end
   else memory[e.id]=nil;ghosts[e.id]=nil end
  end
 end
 -- An entry inside current sight that is no longer reported has been destroyed.
 local visibleCells,width=view.player.visible,view.map.width
 for id,e in pairs(memory) do
  if not seen[id] then
   local visible=false
   for y=math.floor(e.y/256),math.floor(e.y/256)+e.size-1 do for x=math.floor(e.x/256),math.floor(e.x/256)+e.size-1 do
    if visibleCells[y*width+x+1] then visible=true end
   end end
   if visible then memory[id]=nil;ghosts[id]=nil end
  end
 end
 local markers=self.markers
 local count=0
 for _,e in ipairs(view.entities) do if e.alive then count=count+1;markers[count]=e end end
 for id,e in pairs(memory) do
  if not seen[id] then
   local ghost=ghosts[id]
   if not ghost then ghost={};for k,v in pairs(e) do ghost[k]=v end;ghost.remembered=true;ghosts[id]=ghost end
   count=count+1;markers[count]=ghost
  end
 end
 for i=#markers,count+1,-1 do markers[i]=nil end
 -- Entity ids are unique, so sorting by id is a total order: the pairs traversal
 -- above cannot leak its arbitrary order into the result.
 table.sort(markers,byId)
end
return O
