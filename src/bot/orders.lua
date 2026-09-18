-- The Orders' bot: saturate the patches, raise depots ahead of the cap, a barracks then a
-- second, an expansion keep at the natural, footmen and crossbows with a gryphon when the
-- charge is there, and an attack once the army is worth sending. Decisions use the filtered
-- view, public map anchors and content costs only, and every choice is made in a fixed
-- order over the view's entities so two peers running it agree.
local F=require('src.sim.fixed')
local Sim=require('src.sim')
local B={}
local PATCH_WORKERS={substrate=2,charge=3}
function B.commands(view,C)
 local out={};if view.tick%20~=0 or view.result then return out end
 local player=view.player;local owner=player.id
 local faction=C.factions[player.faction];local hqKind=faction.hq or 'hq'
 local cap=player.supplyCap or C.rules.population or 200
 -- Census, in view order.
 local keeps,sites,workers,army,halls,sanctums,nodes={},{},{},{},{},{},{}
 local assigned={};local queuedWorkers,food,armyFood,healers=0,0,0,0
 for _,e in ipairs(view.entities) do
  if e.owner==owner and e.alive then
   local d=C.units[e.kind]
   if e.category=='unit' and d then
    food=food+(d.food or 1)
    if d.worker then
     workers[#workers+1]=e
     if e.order.kind=='harvest' and e.order.target then assigned[e.order.target]=(assigned[e.order.target] or 0)+1 end
    else army[#army+1]=e;armyFood=armyFood+(d.food or 1);if d.heal then healers=healers+1 end end
   elseif e.category=='building' then
    if e.remaining>0 then sites[#sites+1]=e
    elseif e.kind==hqKind then keeps[#keeps+1]=e
    elseif e.kind=='barracks' then halls[#halls+1]=e
    elseif e.kind=='sanctum' then sanctums[#sanctums+1]=e end
    for _,q in ipairs(e.queue or {}) do local qd=C.units[q.kind];food=food+(qd.food or 1);if qd.worker then queuedWorkers=queuedWorkers+1 end;if qd.heal then healers=healers+1 end end
   end
  elseif e.alive and e.category=='node' then nodes[#nodes+1]=e end
 end
 if #keeps==0 then return out end
 local hq=keeps[1];for _,k in ipairs(keeps) do if k.id==player.hq then hq=k end end
 local hx,hy=math.floor(hq.x/256),math.floor(hq.y/256)
 local ledger={};for key,amount in pairs(player.resources) do ledger[key]=amount end
 local function afford(cost) for key,amount in pairs(cost) do if (ledger[key] or 0)<amount then return false end end;return true end
 local function spend(cost) for key,amount in pairs(cost) do ledger[key]=(ledger[key] or 0)-amount end end
 local function add(kind,e,args) args=args or {};args.entity=e.id;out[#out+1]={kind=kind,args=args} end
 local function recruit(b,kind) local d=C.units[kind];if b.remaining==0 and #b.queue<2 and food+(d.food or 1)<=cap and afford(d.cost) then spend(d.cost);food=food+(d.food or 1);add('recruit',b,{unit=kind});return true end end
 local function siteOf(kind) for _,s in ipairs(sites) do if s.kind==kind then return s end end end
 local used={}
 -- A worker to send: idle first, then one that is only harvesting. Never one already ordered this tick.
 local function freeWorker()
  for _,e in ipairs(workers) do if e.order.kind=='stop' and not used[e.id] then return e end end
  for _,e in ipairs(workers) do if e.order.kind~='build' and not used[e.id] then return e end end
 end
 local function build(kind,cx,cy)
  local d=C.buildings[kind];if not afford(d.cost) then return false end
  local builder=freeWorker();if not builder then return false end
  local footprints={}
  for _,e in ipairs(view.entities) do if e.alive and e.category~='unit' then footprints[#footprints+1]={x=math.floor(e.x/256),y=math.floor(e.y/256),size=e.size} end end
  local maxX,maxY=view.map.width-d.size,view.map.height-d.size
  local function try(x,y)
   if x<0 or y<0 or x>maxX or y>maxY then return false end
   -- A two-cell working apron around every footprint and patch, so nothing is walled in.
   for _,f in ipairs(footprints) do
    if x<f.x+f.size+2 and x+d.size>f.x-2 and y<f.y+f.size+2 and y+d.size>f.y-2 then return false end
   end
   if not Sim.placement(view,C,kind,x,y) then return false end
   spend(d.cost);used[builder.id]=true;add('build',builder,{building=kind,x=x,y=y});return true
  end
  -- Row-major ascending around the centre, ring by ring: a fixed order is gameplay.
  for r=3,10 do
   for y=math.max(0,cy-r),math.min(maxY,cy+r) do
    if math.abs(y-cy)==r then
     for x=math.max(0,cx-r),math.min(maxX,cx+r) do if try(x,y) then return true end end
    elseif try(cx-r,y) or try(cx+r,y) then return true end
   end
  end
  return false
 end
 local tuned=2*math.max(128,view.map.width)
 -- A stopped site gets the nearest free worker back before anything new is started.
 local stalled,stalledDistance
 for _,s in ipairs(sites) do
  if s.stalled then local distance=F.sq(s.x-hq.x)+F.sq(s.y-hq.y);if not stalledDistance or distance<stalledDistance then stalled=s;stalledDistance=distance end end
 end
 if stalled then local builder=freeWorker();if builder then used[builder.id]=true;add('build',builder,{building=stalled.kind,target=stalled.id}) end end
 -- Patches worth working: near a standing keep, with room for another worker.
 local function nearKeep(n) for _,k in ipairs(keeps) do if F.sq(n.x-k.x)+F.sq(n.y-k.y)<=F.sq(14*256) then return true end end;return false end
 local reachable={substrate=0,charge=0};local chargeWorkers=0
 for _,n in ipairs(nodes) do
  if (n.amount or 1)>0 and nearKeep(n) and PATCH_WORKERS[n.resource] then
   reachable[n.resource]=reachable[n.resource]+1
   if n.resource=='charge' then chargeWorkers=chargeWorkers+(assigned[n.id] or 0) end
  end
 end
 local function pick(resource)
  local best,bestScore
  for _,n in ipairs(nodes) do
   if n.resource==resource and (n.amount or 1)>0 and nearKeep(n) then
    local load=assigned[n.id] or 0
    if load<PATCH_WORKERS[resource] then
     local score=load*4294967296+F.sq(n.x-hq.x)+F.sq(n.y-hq.y)
     if not bestScore or score<bestScore then best=n;bestScore=score end
    end
   end
  end
  return best
 end
 -- Macro, in priority order: the cap before it binds, then production, then the expansion.
 local depotSoon=food+6>=cap and cap<(faction.supplyCap or 200) and not siteOf('depot')
 local wantHall=#halls+(siteOf('barracks') and 1 or 0)<(view.tick>=4800 and 2 or 1)
 local anchor=view.map.anchors and view.map.anchors.naturals and view.map.anchors.naturals[owner]
 local wantKeep=view.tick>=6000 and anchor and #keeps+(siteOf(hqKind) and 1 or 0)<2
 local wantSanctum=#halls>=2 and #sanctums+(siteOf('sanctum') and 1 or 0)<1 and C.buildings.sanctum
 if depotSoon then build('depot',hx,hy)
 elseif wantHall then build('barracks',hx,hy)
 elseif wantKeep then build(hqKind,anchor.x,anchor.y)
 elseif wantSanctum then build('sanctum',hx,hy) end
 -- Workers: enough to fill the patches in reach, and no more.
 local target=math.min(2*reachable.substrate+3*reachable.charge,24)
 if #workers+queuedWorkers<target then for _,k in ipairs(keeps) do if recruit(k,faction.worker or 'worker') then break end end end
 -- Idle workers go to the patch with the fewest workers; charge once the barracks stands.
 for _,e in ipairs(workers) do
  if e.order.kind=='stop' and not used[e.id] then
   local resource=(#halls>0 and chargeWorkers<3 and reachable.charge>0) and 'charge' or 'substrate'
   local n=pick(resource) or pick(resource=='charge' and 'substrate' or 'charge')
   if n then used[e.id]=true;assigned[n.id]=(assigned[n.id] or 0)+1;if n.resource=='charge' then chargeWorkers=chargeWorkers+1 end;add('harvest',e,{target=n.id}) end
  end
 end
 -- Production: two footmen to a crossbow, and a gryphon every fourth when the charge is there.
 for _,b in ipairs(halls) do
  local produced=b.produced or 0
  local kind=(produced%4==3 and (ledger.charge or 0)>=50) and 'gryphon' or (produced%3==2 and 'crossbow' or 'footman')
  if not recruit(b,kind) and kind=='gryphon' then recruit(b,'footman') end
 end
 -- Two reliquaries follow the army once the sanctum stands and the charge is there.
 for _,sanctum in ipairs(sanctums) do if healers<2 then recruit(sanctum,'reliquary') end end
 -- The army: defend home first, then attack once it is worth sending.
 local threat,threatDistance
 for _,e in ipairs(view.entities) do
  if e.alive and e.owner>0 and e.owner~=owner then local distance=F.sq(e.x-hq.x)+F.sq(e.y-hq.y)
   if distance<=F.sq(22*tuned) and (not threatDistance or distance<threatDistance) then threat=e;threatDistance=distance end
  end
 end
 local tx,ty
 if threat then tx,ty=threat.x,threat.y
 elseif armyFood>=12 or view.tick>=12000 then local start=view.map.starts and view.map.starts[owner==1 and 2 or 1];if start then tx,ty=start.x*256,start.y*256 end end
 local wave=view.tick+1
 for _,e in ipairs(army) do
  local retreat=e.hp*100<e.maxHp*30 or e.order.kind=='move' and e.hp*100<e.maxHp*75
  if retreat then if e.order.kind~='move' and view.tick%100==0 then add('move',e,{x=hq.x+(hq.size+1)*256,y=hq.y}) end
  elseif tx and (e.order.kind=='stop' or view.tick%200==0) then add('attack_move',e,{x=tx,y=ty,group=wave}) end
 end
 return out
end
return B
