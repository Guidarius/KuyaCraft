-- The Megacorp's bot. It spends by a plan: a rig on every covered patch first (a rig pays
-- itself back in under a minute), then a barracks, a charge rig, a Requisition Office for
-- a second pod, a relay pushed to the natural under the Blimp's coverage, rigs there,
-- Battleships once the charge is there, and the support buildings after. The first want it
-- cannot afford is saved for: pods are loaded only from what is left over, so the army
-- never starves the economy. Troops land at a rally by the Command and go out as one wave
-- with the ships, or at once against anything that comes near. Decisions use the filtered
-- view, public anchors and content costs only, in a fixed order over the view's entities.
local F=require('src.sim.fixed')
local Sim=require('src.sim')
local B={}
function B.commands(view,C)
 local out={};if view.tick%20~=0 or view.result then return out end
 local player=view.player;local owner=player.id
 local faction=C.factions[player.faction];local hqKind=faction.hq
 local cap=player.supplyCap or 200;local width=view.map.width
 local coverage=player.coverage or {}
 local function covered(cx,cy) return coverage[cy*width+cx+1]==true end
 local hq;local relays,halls,offices,blimps,ships,troops,medbays,armories,bunkers,nodes={},{},{},{},{},{},{},{},{},{}
 local rigged={};local rigsOn={substrate=0,charge=0};local food=0
 for _,e in ipairs(view.entities) do
  if e.alive and e.category=='node' then nodes[#nodes+1]=e end
 end
 for _,e in ipairs(view.entities) do
  if e.alive and e.owner==owner then
   local d=C.units[e.kind]
   if e.category=='unit' and d then
    food=food+(d.food or 1)
    if d.coverage then blimps[#blimps+1]=e elseif d.flying then ships[#ships+1]=e elseif not e.garrisoned then troops[#troops+1]=e end
   elseif e.category=='building' then
    if e.kind==hqKind then hq=e
    elseif e.kind=='orbital_relay' then relays[#relays+1]=e
    elseif e.kind=='mc_barracks' then halls[#halls+1]=e
    elseif e.kind=='requisition_office' then offices[#offices+1]=e
    elseif e.kind=='med_bay' then medbays[#medbays+1]=e
    elseif e.kind=='armory' then armories[#armories+1]=e
    elseif e.kind=='bunker' then bunkers[#bunkers+1]=e end
    if e.mine then rigged[e.mine]=true;local d2=C.buildings[e.kind];if d2 and d2.onNode then rigsOn[d2.onNode]=(rigsOn[d2.onNode] or 0)+1 end end
    for _,q in ipairs(e.queue or {}) do food=food+(C.units[q.kind].food or 1) end
   end
  elseif e.alive and e.mine then rigged[e.mine]=true end
 end
 if not hq or not hq.alive then return out end
 local queue=player.callDown or {};local landings=player.landings or {}
 local pods=player.pods or {open={kinds={}},inFlight={},cooldownUntil=0}
 for _,kind in ipairs(pods.open.kinds) do food=food+(C.units[kind].food or 1) end
 for _,pod in ipairs(pods.inFlight) do for _,kind in ipairs(pod.kinds) do food=food+(C.units[kind].food or 1) end end
 local ledger={};for key,amount in pairs(player.resources) do ledger[key]=amount end
 local function afford(cost) for key,amount in pairs(cost) do if (ledger[key] or 0)<amount then return false end end;return true end
 local function spend(cost) for key,amount in pairs(cost) do ledger[key]=(ledger[key] or 0)-amount end end
 local function add(kind,e,args) args=args or {};args.entity=e.id;out[#out+1]={kind=kind,args=args} end
 local function inOrbit(kind) local n=0;for _,i in ipairs(queue) do if i.kind==kind then n=n+1 end end;for _,l in ipairs(landings) do if l.kind==kind then n=n+1 end end;return n end
 -- Patches the bot could rig now: covered, unrigged, not empty, and placeable.
 local function riggable(resource)
  local kind=resource=='charge' and 'charge_rig' or 'substrate_rig';local n=0
  for _,node in ipairs(nodes) do
   if node.resource==resource and not rigged[node.id] and (node.amount or 1)>0 and covered(F.cell(node.x),F.cell(node.y)) and Sim.placement(view,C,kind,F.cell(node.x),F.cell(node.y),true) then n=n+1 end
  end
  return n
 end
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
 local hqX,hqY=F.cell(hq.x),F.cell(hq.y)
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
    local cx,cy=hqX,hqY
    if (item.kind=='orbital_relay' or item.kind=='bunker') and anchor then cx,cy=anchor.x,anchor.y end
    x,y=ring(item.kind,cx,cy)
   end
   if x then add('land',hq,{index=i,x=x,y=y}) end
   break
  end
 end
 -- The plan, in priority order. The first want that cannot be paid for is what the bot
 -- saves for; everything below it waits, and pods get only what is left over.
 local substrateRigs=rigsOn.substrate+inOrbit('substrate_rig');local chargeRigs=rigsOn.charge+inOrbit('charge_rig')
 local officeCount=#offices+inOrbit('requisition_office');local relayCount=#relays+inOrbit('orbital_relay')
 local hallCount=#halls+inOrbit('mc_barracks')
 local wants={}
 local function want(kind,unit) wants[#wants+1]={kind=kind,unit=unit} end
 local canRigSubstrate=riggable('substrate')-inOrbit('substrate_rig')
 local canRigCharge=riggable('charge')-inOrbit('charge_rig')
 if canRigSubstrate>0 and substrateRigs<4 then want('substrate_rig') end
 if hallCount<1 then want('mc_barracks') end
 if canRigSubstrate>0 then want('substrate_rig') end
 if canRigCharge>0 and chargeRigs<1 then want('charge_rig') end
 if officeCount<1 and substrateRigs>=4 then want('requisition_office') end
 if relayCount<1 and officeCount>=1 then want('orbital_relay') end
 if canRigCharge>0 then want('charge_rig') end
 if #halls>0 and #ships<2 then want(nil,'battleship') end
 if #medbays+inOrbit('med_bay')<1 and #halls>0 then want('med_bay') end
 if #armories+inOrbit('armory')<1 and #halls>0 then want('armory') end
 if #relays>0 and #bunkers+inOrbit('bunker')<1 and #halls>0 then want('bunker') end
 if officeCount<2 and #relays>0 then want('requisition_office') end
 if #halls>0 then want(nil,'battleship') end
 local saving=false
 for _,w in ipairs(wants) do
  if w.unit then
   local d=C.units[w.unit]
   if hq.remaining==0 and #hq.queue<1 and food+(d.food or 1)<=cap then
    if afford(d.cost) then spend(d.cost);food=food+(d.food or 1);add('recruit',hq,{unit=w.unit}) else saving=true;break end
   end
  else
   local d=C.buildings[w.kind]
   if not Sim.missingRequirement(view,owner,d.requires) then
    if #queue>=3 then break end
    if afford(d.cost) then spend(d.cost);add('requisition',hq,{building=w.kind}) else saving=true;break end
   end
  end
 end
 -- Where troops gather: the natural once a relay covers it, else beside the Command.
 local rallyX,rallyY=hqX+8,hqY
 if anchor and #relays>0 and covered(anchor.x,anchor.y) then rallyX,rallyY=anchor.x,anchor.y end
 -- A threat near home is answered with everything, at once.
 local threat,threatDistance;local tuned=2*math.max(128,view.map.width)
 for _,e in ipairs(view.entities) do
  if e.alive and e.owner>0 and e.owner~=owner and e.category~='node' and e.category~='projectile' then local distance=F.sq(e.x-hq.x)+F.sq(e.y-hq.y)
   if distance<=F.sq(22*tuned) and (not threatDistance or distance<threatDistance) then threat=e;threatDistance=distance end
  end
 end
 -- Drop pods: filled from what the plan leaves over (always when the base is under attack),
 -- an Enforcer or a Medic in the mix as their buildings allow, launched full at the rally.
 local open=#pods.open.kinds
 if #halls>0 and (not saving or threat) then
  for _=open+1,(C.rules.podCapacity or 4) do
   local kind='associate'
   if #armories>0 and open%4==3 then kind='enforcer' elseif #medbays>0 and open%3==2 then kind='medic' end
   local d=C.units[kind]
   if not Sim.missingRequirement(view,owner,d.requires) and food+(d.food or 1)<=cap and afford(d.cost) then spend(d.cost);food=food+(d.food or 1);add('pod_load',hq,{unit=kind});open=open+1 else break end
  end
 end
 local unlocked=math.min(C.rules.podsMax or 3,(C.rules.podsBase or 1)+#offices)
 if #pods.open.kinds>=(C.rules.podCapacity or 4) and view.tick>=(pods.cooldownUntil or 0) and #pods.inFlight<unlocked then
  local px,py=rallyX,rallyY
  if not covered(px,py) then px,py=hqX+8,hqY end
  if covered(px,py) then add('pod_launch',hq,{x=px,y=py}) end
 end
 -- The Blimp carries coverage to the natural as soon as a relay is wanted there, and comes
 -- home once the relay stands so it is not the first thing the enemy kills.
 for _,b in ipairs(blimps) do
  if anchor and #relays==0 and officeCount>=1 and b.order.kind=='stop' and (F.cell(b.x)~=anchor.x or F.cell(b.y)~=anchor.y) then add('move',b,{x=anchor.x*256+128,y=anchor.y*256+128})
  elseif #relays>0 and b.order.kind=='stop' and (F.sq(b.x-hq.x)+F.sq(b.y-hq.y))>F.sq(6*256) then add('move',b,{x=hq.x,y=hq.y-6*256}) end
 end
 local troopFood=0;for _,e in ipairs(troops) do troopFood=troopFood+(C.units[e.kind].food or 1) end
 -- The wave: ships and troops together, once the army is worth sending; late in a match it
 -- goes regardless, so a stalemate still ends.
 local tx,ty
 if threat then tx,ty=threat.x,threat.y
 elseif (troopFood>=24 and #ships>=2) or view.tick>=18000 then local start=view.map.starts and view.map.starts[owner==1 and 2 or 1];if start then tx,ty=start.x*256,start.y*256 end end
 -- A Battleship with its barrage ready bombards enemy flyers in reach rather than
 -- plinking at them with the gun. The view carries its own cooldowns, cast and channel.
 for _,e in ipairs(ships) do
  local d=C.units[e.kind]
  if d.abilities and not e.cast and not e.channel and e.order.kind~='cast' then
   for _,name in ipairs(d.abilities) do
    local spec=C.abilities[name]
    if spec and spec.filter and spec.filter.air and (not e.cooldowns or (e.cooldowns[name] or 0)<=view.tick) then
     local target,best
     for _,f in ipairs(view.entities) do
      if f.alive and f.owner>0 and f.owner~=owner and C.units[f.kind] and C.units[f.kind].flying then
       local distance=F.sq(f.x-e.x)+F.sq(f.y-e.y)
       if distance<=F.sq(spec.range) and (not best or distance<best) then target=f;best=distance end
      end
     end
     if target then add('cast',e,{ability=name,x=target.x,y=target.y}) end
    end
   end
  end
 end
 local army={};for _,e in ipairs(ships) do army[#army+1]=e end;for _,e in ipairs(troops) do army[#army+1]=e end
 for _,e in ipairs(army) do
  local hurt=e.hp*100<e.maxHp*30
  if hurt and not threat then if e.order.kind~='move' and view.tick%100==0 then add('move',e,{x=hq.x,y=hq.y}) end
  elseif tx then if e.order.kind=='stop' or view.tick%200==0 then add('attack_move',e,{x=tx,y=ty,group=view.tick+1}) end
  elseif e.order.kind=='stop' and (F.sq(e.x-(rallyX*256+128))+F.sq(e.y-(rallyY*256+128)))>F.sq(5*256) then add('attack_move',e,{x=rallyX*256+128,y=rallyY*256+128,group=view.tick+1}) end
 end
 return out
end
return B
