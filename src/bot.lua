-- Decisions use filtered observations, public map anchors and content costs only.
local F=require('src.sim.fixed')
local Sim=require('src.sim')
local B={}
function B.commands(view,C)
 local out={};if view.tick%20~=0 or view.result then return out end
 local owner,hq,hero;local workers,army,halls,nodes,outposts={},{},{},{},{}
 for _,e in ipairs(view.entities) do if e.id==view.player.hq then hq=e;owner=e.owner end end
 if not hq or not hq.alive then return out end
 local ledger={gold=view.player.resources.gold,lumber=view.player.resources.lumber};local food=0;local queuedWorkers=0
 for _,e in ipairs(view.entities) do
  if e.owner==owner then
   local d=C.units[e.kind]
   if d and (e.alive or d.hero) then food=food+d.food end
   if e.id==view.player.hero then hero=e end
   if e.alive then
    if e.kind=='worker' then workers[#workers+1]=e elseif e.category=='unit' and not d.hero then army[#army+1]=e end
    if e.kind=='barracks' then halls[#halls+1]=e end
    if e.kind=='outpost' then outposts[#outposts+1]=e end
    for _,q in ipairs(e.queue or {}) do food=food+C.units[q.kind].food;if q.kind=='worker' then queuedWorkers=queuedWorkers+1 end end
   end
  elseif e.alive and e.category=='node' then nodes[#nodes+1]=e end
 end
 local function afford(cost) return ledger.gold>=(cost.gold or 0) and ledger.lumber>=(cost.lumber or 0) end
 local function spend(cost) ledger.gold=ledger.gold-(cost.gold or 0);ledger.lumber=ledger.lumber-(cost.lumber or 0) end
 local function add(kind,e,args) args=args or {};args.entity=e.id;out[#out+1]={kind=kind,args=args} end
 local function recruit(b,kind) local d=C.units[kind];if b.remaining==0 and #b.queue<2 and food+d.food<=C.rules.population and afford(d.cost) and (not d.tech or view.player.tech) then spend(d.cost);food=food+d.food;add('recruit',b,{unit=kind});return true end end
 local used={};local function build(kind,cx,cy)
  local d=C.buildings[kind];if not afford(d.cost) then return false end
  local builder;for _,e in ipairs(workers) do if e.order.kind~='build' and not used[e.id] then builder=e;break end end
  if not builder then return false end
  -- Walk each ring's perimeter directly. Scanning the whole square and discarding
  -- everything but its edge made this cubic in the radius for a quadratic result,
  -- and each rejected cell still paid a full footprint scan.
  local footprints={}
  for _,e in ipairs(view.entities) do if e.alive and e.category~='unit' and e.resource~='lumber' then
   footprints[#footprints+1]={x=math.floor(e.x/256),y=math.floor(e.y/256),size=e.size}
  end end
  local maxX,maxY=view.map.width-d.size,view.map.height-d.size
  local function try(x,y)
   if x<0 or y<0 or x>maxX or y>maxY then return false end
   -- Preserve a two-cell working apron around existing footprints/mines.
   for _,f in ipairs(footprints) do
    if x<f.x+f.size+2 and x+d.size>f.x-2 and y<f.y+f.size+2 and y+d.size>f.y-2 then return false end
   end
   if not Sim.placement(view,C,kind,x,y) then return false end
   spend(d.cost);used[builder.id]=true;add('build',builder,{building=kind,x=x,y=y});return true
  end
  -- Row-major ascending, exactly as the discarded square scan visited the ring:
  -- the bot's choice of cell is gameplay, so the order must not change.
  for r=3,10 do
   for y=math.max(0,cy-r),math.min(maxY,cy+r) do
    if math.abs(y-cy)==r then
     for x=math.max(0,cx-r),math.min(maxX,cx+r) do if try(x,y) then return true end end
    elseif try(cx-r,y) or try(cx+r,y) then return true end
   end
  end
  return false
 end
 local hx,hy=math.floor(hq.x/256),math.floor(hq.y/256)
 local wantTech=view.tick>=4800 and not view.player.tech and not hq.researchRemaining
 local wantExpansion=view.tick>=7200 and #outposts==0
 if #halls==0 then build('barracks',hx,hy)
 elseif wantTech and afford(C.rules.tech.cost) then spend(C.rules.tech.cost);add('research',hq)
 elseif wantExpansion and afford(C.buildings.outpost.cost) then
  local anchor=view.map.anchors and view.map.anchors.naturals[owner]
  if anchor then
   if not build('outpost',anchor.x,anchor.y) and hero and hero.alive and view.tick%200==0 then add('attack_move',hero,{x=anchor.x*256,y=anchor.y*256}) end
  end
 elseif view.tick>=3600 and #halls<(view.tick>=8400 and 3 or 2) and view.tick%100==0 and not wantTech and not wantExpansion then build('barracks',hx,hy) end
 local depot=false;for _,e in ipairs(view.entities) do if e.alive and e.owner==owner and e.kind=='depot' then depot=true end end
 if not depot and #workers>=8 and view.tick%100==0 then build('depot',hx-6,hy) end
 if #workers+queuedWorkers<(view.tick<3600 and 12 or 16) then recruit(hq,'worker') end
 -- Five workers per operating mine; remaining workers chop the nearest observed forest.
 local mines={};for _,n in ipairs(nodes) do if n.resource=='gold' then
  local close=F.sq(n.x-hq.x)+F.sq(n.y-hq.y)<F.sq(16*256)
  for _,b in ipairs(outposts) do if b.remaining==0 and F.sq(n.x-b.x)+F.sq(n.y-b.y)<F.sq(16*256) then close=true end end
  if close then mines[#mines+1]=n end
 end end
 table.sort(mines,function(a,b) local da=F.sq(a.x-hq.x)+F.sq(a.y-hq.y);local db=F.sq(b.x-hq.x)+F.sq(b.y-hq.y);return da<db or da==db and a.id<b.id end)
 local assigned=0
 for _,e in ipairs(workers) do if not used[e.id] and e.order.kind~='build' then
  assigned=assigned+1;local mine=mines[math.floor((assigned-1)/5)+1];local target=mine
  if not target then local best;for _,n in ipairs(nodes) do if n.resource=='lumber' then local dist=F.sq(n.x-e.x)+F.sq(n.y-e.y);if not best or dist<best then best=dist;target=n end end end end
  if target and (e.order.kind~='harvest' or e.order.target~=target.id and mine) then add('harvest',e,{target=target.id}) end
 end end
 if not wantTech and not wantExpansion then
  local roster=C.factions[view.player.faction].roster
  for _,b in ipairs(halls) do local pattern=view.player.tech and {1,2,1,3,2,4} or {1,2,1};local index=pattern[1+(b.produced or 0)%#pattern];recruit(b,roster[index]) end
 end
 if hero then
  if not hero.alive and not hero.reviveRemaining then local cost=Sim.revival(C,hero);if ledger.gold>=cost then add('revive',hero) end
  elseif hero.alive then for i,t in ipairs(C.rules.xpThresholds) do if hero.xp>=t and not hero.upgrades[i] then add('upgrade',hero,{milestone=i,choice=1+(owner+i)%2}) end end end
 end
 if hero and hero.alive then army[#army+1]=hero end
 local target,best
 if #army>=3 and view.tick<6000 then
  for _,e in ipairs(view.entities) do if e.alive and e.home and (e.campTier=='easy' or #army>=6) then local dist=F.sq(e.x-hq.x)+F.sq(e.y-hq.y);if not best or dist<best then target=e;best=dist end end end
 end
 local tx,ty;local threat,threatDistance
 for _,e in ipairs(view.entities) do
  if e.alive and e.owner>0 and e.owner~=owner then local distance=F.sq(e.x-hq.x)+F.sq(e.y-hq.y)
   if distance<=F.sq(22*256) and (not threatDistance or distance<threatDistance) then threat=e;threatDistance=distance end
  end
 end
 if threat then tx,ty=threat.x,threat.y
 elseif wantExpansion and view.map.anchors and #army>=3 then local anchor=view.map.anchors.naturals[owner];tx,ty=anchor.x*256,anchor.y*256
 elseif target then tx,ty=target.x,target.y
 elseif #army>=3 and view.tick<3600 then tx,ty=(owner==1 and 28 or 100)*256,(owner==1 and 30 or 82)*256
 elseif #army>=6 or view.tick>=6000 then local start=view.map.starts and view.map.starts[owner==1 and 2 or 1];tx,ty=(start and start.x or (owner==1 and view.map.width-8 or 8))*256,(start and start.y or (owner==1 and view.map.height-8 or 8))*256 end
 for _,e in ipairs(army) do
  local retreat=e.hp*100<e.maxHp*30 or e.order.kind=='move' and e.hp*100<e.maxHp*75
  if retreat then if e.order.kind~='move' and view.tick%100==0 then add('move',e,{x=hq.x+(hq.size+1)*256,y=hq.y}) end
  elseif tx and (e.order.kind=='stop' or view.tick%200==0) then add('attack_move',e,{x=tx,y=ty}) end
 end
 return out
end
return B
