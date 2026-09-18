-- The Megacorp's bot: rigs on every patch its relays cover, a barracks, a charge rig, a
-- Requisition Office, a relay pushed toward the natural, a Command Blimp scouting ahead of
-- it, and Battleships once the charge is there. Nothing is built on the ground: it
-- requisitions from orbit and lands what is ready. Decisions use the filtered view, public
-- anchors and content costs only, in a fixed order over the view's entities.
local F=require('src.sim.fixed')
local Sim=require('src.sim')
local B={}
function B.commands(view,C)
 local out={};if view.tick%20~=0 or view.result then return out end
 local player=view.player;local owner=player.id
 local faction=C.factions[player.faction];local hqKind=faction.hq
 local cap=player.supplyCap or 200
 local hq;local relays,halls,offices,blimps,ships,nodes,byNode={},{},{},{},{},{},{}
 local rigged={};local rigsOn={substrate=0,charge=0};local food=0
 for _,e in ipairs(view.entities) do
  if e.alive and e.category=='node' then nodes[#nodes+1]=e;byNode[e.id]=e end
 end
 for _,e in ipairs(view.entities) do
  if e.alive and e.owner==owner then
   local d=C.units[e.kind]
   if e.category=='unit' and d then
    food=food+(d.food or 1)
    if d.coverage then blimps[#blimps+1]=e elseif d.damage then ships[#ships+1]=e end
   elseif e.category=='building' then
    if e.kind==hqKind then hq=e
    elseif e.kind=='orbital_relay' then relays[#relays+1]=e
    elseif e.kind=='mc_barracks' then halls[#halls+1]=e
    elseif e.kind=='requisition_office' then offices[#offices+1]=e end
    if e.mine then rigged[e.mine]=true;local n=byNode[e.mine];if n then rigsOn[n.resource]=(rigsOn[n.resource] or 0)+1 end end
    for _,q in ipairs(e.queue or {}) do food=food+(C.units[q.kind].food or 1) end
   end
  elseif e.alive and e.mine then rigged[e.mine]=true end
 end
 if not hq or not hq.alive then return out end
 local queue=player.callDown or {};local landings=player.landings or {}
 local ledger={};for key,amount in pairs(player.resources) do ledger[key]=amount end
 local function afford(cost) for key,amount in pairs(cost) do if (ledger[key] or 0)<amount then return false end end;return true end
 local function spend(cost) for key,amount in pairs(cost) do ledger[key]=(ledger[key] or 0)-amount end end
 local function add(kind,e,args) args=args or {};args.entity=e.id;out[#out+1]={kind=kind,args=args} end
 local function inOrbit(kind) local n=0;for _,i in ipairs(queue) do if i.kind==kind then n=n+1 end end;for _,l in ipairs(landings) do if l.kind==kind then n=n+1 end end;return n end
 -- A landing site for a ground building: ring by ring around a centre, with an apron.
 local function ring(kind,cx,cy)
  local d=C.buildings[kind];local maxX,maxY=view.map.width-d.size,view.map.height-d.size
  local footprints={}
  for _,e in ipairs(view.entities) do if e.alive and e.category~='unit' then footprints[#footprints+1]={x=math.floor(e.x/256),y=math.floor(e.y/256),size=e.size} end end
  local function ok(x,y)
   if x<0 or y<0 or x>maxX or y>maxY then return false end
   for _,f in ipairs(footprints) do if x<f.x+f.size+1 and x+d.size>f.x-1 and y<f.y+f.size+1 and y+d.size>f.y-1 then return false end end
   return Sim.placement(view,C,kind,x,y,true)
  end
  for r=2,12 do
   for y=math.max(0,cy-r),math.min(maxY,cy+r) do
    if math.abs(y-cy)==r then for x=math.max(0,cx-r),math.min(maxX,cx+r) do if ok(x,y) then return x,y end end
    elseif ok(cx-r,y) then return cx-r,y elseif ok(cx+r,y) then return cx+r,y end
   end
  end
 end
 local anchor=view.map.anchors and view.map.anchors.naturals and view.map.anchors.naturals[owner]
 -- Land what is ready: one landing a tick, the first ready item first.
 for i,item in ipairs(queue) do
  if item.remaining==0 then
   local d=C.buildings[item.kind];local x,y
   if d.onNode then
    local best,bestDistance
    for _,n in ipairs(nodes) do
     if n.resource==d.onNode and not rigged[n.id] and (n.amount or 1)>0 then
      local cx,cy=F.cell(n.x),F.cell(n.y)
      if Sim.placement(view,C,item.kind,cx,cy,true) then local distance=F.sq(n.x-hq.x)+F.sq(n.y-hq.y);if not bestDistance or distance<bestDistance then best=n;bestDistance=distance end end
     end
    end
    if best then x,y=F.cell(best.x),F.cell(best.y) end
   else
    local cx,cy=F.cell(hq.x),F.cell(hq.y)
    if item.kind=='orbital_relay' and anchor then cx,cy=anchor.x,anchor.y end
    x,y=ring(item.kind,cx,cy)
   end
   if x then add('land',hq,{index=i,x=x,y=y}) end
   break
  end
 end
 -- Requisition, in priority order, keeping the queue short so a rig is never stuck behind three offices.
 local function requisition(kind)
  local d=C.buildings[kind]
  if #queue>=3 or not afford(d.cost) or Sim.missingRequirement(view,owner,d.requires) then return false end
  spend(d.cost);add('requisition',hq,{building=kind});return true
 end
 local substrateRigs=rigsOn.substrate+inOrbit('substrate_rig');local chargeRigs=rigsOn.charge+inOrbit('charge_rig')
 local officeCount=#offices+inOrbit('requisition_office');local relayCount=#relays+inOrbit('orbital_relay')
 if substrateRigs<4 then requisition('substrate_rig')
 elseif #halls+inOrbit('mc_barracks')<1 then requisition('mc_barracks')
 elseif chargeRigs<1 then requisition('charge_rig')
 elseif view.tick>=3600 and officeCount<1 then requisition('requisition_office')
 elseif view.tick>=4800 and relayCount<1 then requisition('orbital_relay')
 elseif substrateRigs<8 then requisition('substrate_rig')
 elseif view.tick>=7200 and officeCount<2 then requisition('requisition_office')
 elseif chargeRigs<2 then requisition('charge_rig') end
 -- The Command trains a Blimp when it has none, then Battleships.
 local function recruit(kind) local d=C.units[kind];if hq.remaining==0 and #hq.queue<2 and food+(d.food or 1)<=cap and afford(d.cost) then spend(d.cost);food=food+(d.food or 1);add('recruit',hq,{unit=kind}) end end
 if #blimps==0 then recruit('command_blimp') else recruit('battleship') end
 -- The Blimp carries coverage toward the natural until a relay stands there.
 for _,b in ipairs(blimps) do
  if anchor and view.tick>=2400 and #relays==0 and b.order.kind=='stop' then add('move',b,{x=anchor.x*256,y=anchor.y*256}) end
 end
 -- Battleships: defend the Command, then sortie in pairs.
 local threat,threatDistance;local tuned=2*math.max(128,view.map.width)
 for _,e in ipairs(view.entities) do
  if e.alive and e.owner>0 and e.owner~=owner then local distance=F.sq(e.x-hq.x)+F.sq(e.y-hq.y)
   if distance<=F.sq(22*tuned) and (not threatDistance or distance<threatDistance) then threat=e;threatDistance=distance end
  end
 end
 local tx,ty
 if threat then tx,ty=threat.x,threat.y
 elseif #ships>=2 or view.tick>=12000 then local start=view.map.starts and view.map.starts[owner==1 and 2 or 1];if start then tx,ty=start.x*256,start.y*256 end end
 for _,e in ipairs(ships) do
  if e.hp*100<e.maxHp*30 then if e.order.kind~='move' and view.tick%100==0 then add('move',e,{x=hq.x,y=hq.y}) end
  elseif tx and (e.order.kind=='stop' or view.tick%200==0) then add('attack_move',e,{x=tx,y=ty,group=view.tick+1}) end
 end
 return out
end
return B
