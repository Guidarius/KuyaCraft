-- Bounded, serialized nearest-reachable searches for hauling and forest succession.
local F=require('src.sim.fixed')
local P=require('src.sim.path')
local H={}
local dirs={{0,-1,10},{1,0,10},{0,1,10},{-1,0,10},{1,-1,14},{1,1,14},{-1,1,14},{-1,-1,14}}
local function less(a,b) return a.cost<b.cost or a.cost==b.cost and a.key<b.key end
local function push(heap,n)
 local i=#heap+1;while i>1 do local p=math.floor(i/2);if not less(n,heap[p]) then break end;heap[i]=heap[p];i=p end;heap[i]=n
end
local function pop(heap)
 local first=heap[1];local last=table.remove(heap);if #heap>0 then local i=1;while i*2<=#heap do local c=i*2;if c<#heap and less(heap[c+1],heap[c]) then c=c+1 end;if not less(heap[c],last) then break end;heap[i]=heap[c];i=c end;heap[i]=last end;return first
end
local function near(x,y,t)
 local left,top=F.cell(t.x)*256,F.cell(t.y)*256
 local dx=x-math.max(left,math.min(x,left+(t.size or 1)*256))
 local dy=y-math.max(top,math.min(y,top+(t.size or 1)*256))
 return dx*dx+dy*dy<=256*256
end
function H.select(w,e,mode)
 local s=e.economySearch
 if not s or s.version~=w.navVersion or s.mode~=mode then
  local candidates={}
  if mode=='dropoff' then
   for _,id in ipairs(w.order) do local b=w.entities[id];local d=w.content.buildings[b.kind]
    if b.alive and b.owner==e.owner and b.remaining==0 and d and d.dropoff and d.dropoff[e.cargoType] then candidates[#candidates+1]={id=id,x=b.x,y=b.y,size=b.size} end
   end
  else
   local known=w.players[e.owner].knownResources or {}
   for _,id in ipairs(w.order) do local n=known[id];if n and n.resource=='lumber' then candidates[#candidates+1]={id=id,x=n.x,y=n.y,size=n.size} end end
  end
  if #candidates==0 then e.economySearch=nil;return nil end
  local x,y=F.cell(e.x),F.cell(e.y);local key=P.key(w.map,x,y)
  s={mode=mode,version=w.navVersion,open={{x=x,y=y,key=key,cost=0}},costs={[key]=0},closed={},candidates=candidates};e.economySearch=s
 end
 while #s.open>0 and w.metrics.economyExpansions<w.content.rules.pathBudget do
  local n=pop(s.open)
  if not s.closed[n.key] then
   if s.best and n.cost>s.best.cost then local best=s.best;e.economySearch=nil;return best end
   s.closed[n.key]=true;w.metrics.economyExpansions=w.metrics.economyExpansions+1
   for _,t in ipairs(s.candidates) do if near(F.center(n.x),F.center(n.y),t) and (not s.best or n.cost<s.best.cost or n.cost==s.best.cost and t.id<s.best.id) then s.best={id=t.id,x=n.x,y=n.y,cost=n.cost} end end
   if not s.best then for _,d in ipairs(dirs) do local x,y=n.x+d[1],n.y+d[2];local key=P.key(w.map,x,y);local cost=n.cost+d[3]
    if P.walkable(w,x,y) and (d[1]==0 or d[2]==0 or P.walkable(w,x,n.y) and P.walkable(w,n.x,y)) and not s.closed[key] and (not s.costs[key] or cost<s.costs[key]) then s.costs[key]=cost;push(s.open,{x=x,y=y,key=key,cost=cost}) end
   end end
  end
 end
 if #s.open==0 then local best=s.best;e.economySearch=nil;if not best then e.economyRetry=w.tick+100 end;return best end
end
function H.prepare(w)
 w.metrics.economyExpansions=0
 -- Slots follow accepted assignments (stable worker IDs), including delivery trips.
 for _,id in ipairs(w.order) do local node=w.entities[id];if node.category=='node' and node.resource=='gold' then node.slots={} end end
 for _,id in ipairs(w.order) do local e=w.entities[id];if e.alive and e.kind=='worker' and e.order.kind=='harvest' then
  local n=w.entities[e.order.target];if n and n.alive and n.resource=='gold' and #n.slots<w.content.rules.mineWorkers then n.slots[#n.slots+1]=id end
 end end
end
function H.step(w,e,approach,route,nextOrder,rebuild)
 local node=w.entities[e.order.target]
 if (e.cargo or 0)>0 then
  local home=e.dropoff and w.entities[e.dropoff]
  if not home or not home.alive or home.remaining~=0 or e.dropoffVersion~=w.navVersion then
   e.dropoff=nil
   if w.tick<(e.economyRetry or 0) then return end
   local choice=H.select(w,e,'dropoff')
   if not choice then return end
   e.dropoff=choice.id;e.dropoffVersion=w.navVersion;home=w.entities[choice.id];route(w,e,choice.x,choice.y)
  end
  if approach(w,e,home,256) then local ledger=w.players[e.owner].resources;ledger[e.cargoType]=(ledger[e.cargoType] or 0)+e.cargo;e.cargo=0;e.harvestRemaining=nil;e.dropoff=nil;e.economySearch=nil end
 elseif node and node.alive then
  if node.resource=='gold' then local slotted=false;for _,id in ipairs(node.slots) do if id==e.id then slotted=true end end;if not slotted then e.harvestStatus='Waiting for mine slot';return end end
  e.harvestStatus=nil
  if approach(w,e,node,256) then
   e.harvestRemaining=math.max(0,(e.harvestRemaining or (node.resource=='gold' and w.content.rules.harvestTicks or w.content.rules.lumberTicks))-1)
   if e.harvestRemaining==0 and (node.resource~='gold' or w.tick>=(node.nextExtractTick or 0)) then
    e.cargo=math.min(w.content.rules.carry,node.amount);e.cargoType=node.resource;node.amount=node.amount-e.cargo;e.harvestRemaining=nil
    if node.resource=='gold' then node.nextExtractTick=w.tick+w.content.rules.mineInterval end
    if node.amount==0 then node.alive=false;w.navVersion=w.navVersion+1;rebuild(w) end
   end
  end
 elseif node then
  local seen=false;for cy=F.cell(node.y),F.cell(node.y)+(node.size or 1)-1 do for cx=F.cell(node.x),F.cell(node.x)+(node.size or 1)-1 do if w.players[e.owner].visible[P.key(w.map,cx,cy)] then seen=true end end end
  if not seen then approach(w,e,node,256);return end
  if node.resource~='lumber' then nextOrder(w,e);return end
  if w.tick<(e.economyRetry or 0) then return end
  -- The worker has observed depletion at its previous task; hidden nodes remain remembered.
  w.players[e.owner].knownResources[node.id]=nil
  local choice=H.select(w,e,'tree');if choice then e.order.target=choice.id;e.harvestRemaining=nil;route(w,e,choice.x,choice.y) end
 else nextOrder(w,e) end
end
return H
