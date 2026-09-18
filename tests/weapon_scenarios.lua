-- The Megacorp's weapons (simulation version 26), on the shipping content: the Associate's
-- target stacks with their burst and decay, and the Battleship's channelled barrage.
local C=require('src.content')
local Sim=require('src.sim')
local F=require('src.sim.fixed')
local M={}
local function eq(a,b,message) assert(a==b,(message or 'values differ')..': '..tostring(a)..' != '..tostring(b)) end
local function world()
 return Sim.create({seed=7,players={{faction='megacorp'},{faction='orders'}}},C,{id='weapon_fixture',width=64,height=64,starts={{x=6,y=6},{x=56,y=56}},blocked={},resources={},camps={}})
end
local function step(w,n,cs) for i=1,n do Sim.step(w,i==1 and cs or {}) end end
local function command(w,p,kind,e,args,offset) args=args or {};args.entity=e;return {tick=w.tick+1,player=p,sequence=w.players[p].sequence+1+(offset or 0),kind=kind,args=args} end
local function building(w,kind,owner,x,y)
 local id=w.nextId;w.nextId=id+1;local d=C.buildings[kind]
 local e={id=id,kind=kind,category='building',owner=owner,alive=true,x=F.center(x),y=F.center(y),size=d.size,hp=d.hp,maxHp=d.hp,remaining=0,queue={},order={kind='stop'},orders={},path={},pathIndex=1,cooldown=0,lastCombat=-1000}
 w.entities[id]=e;w.order[#w.order+1]=id;w.navVersion=w.navVersion+1;w.blocked=Sim.recomputeBlocked(w);return e
end
local function unit(w,kind,owner,x,y)
 local d=C.units[kind];local id=w.nextId;w.nextId=id+1
 local e={id=id,kind=kind,owner=owner,x=F.center(x),y=F.center(y),category='unit',alive=true,hp=d.hp,maxHp=d.hp,size=1,cooldown=0,path={},pathIndex=1,order={kind='stop'},orders={},lastCombat=-1000}
 w.entities[id]=e;w.order[#w.order+1]=id;return e
end
local function rejected(events) for _,ev in ipairs(events) do if ev.kind=='rejected' then return ev.reason end end end
local function count(events,kind,source) local n=0;for _,ev in ipairs(events) do if ev.kind==kind and (not source or ev.source==source) then n=n+1 end end;return n end

function M.stacks()
 local w=world();step(w,1)
 -- The threshold: a base, half again per armour point, two per hundred hit points.
 eq(Sim.stackThreshold(w,{kind='associate',maxHp=55,owner=2}),6,'associate threshold')
 eq(Sim.stackThreshold(w,{kind='enforcer',maxHp=250,owner=2}),13,'enforcer threshold')
 eq(Sim.stackThreshold(w,{kind='keep',maxHp=1500,owner=2}),38,'keep threshold')
 -- Two Associates on an empty Bunker (400 hp, 2 armour, threshold 16): each hit lands 4
 -- and one stack. The Associate's 18-tick period is longer than the 15-tick grace, so a
 -- few points fade between hits; the oracle below applies the rule tick by tick and the
 -- sixteenth stack bursts for 45 through the armour, on the same tick as the hit.
 local bunker=building(w,'bunker',2,24,19);local a1=unit(w,'associate',1,20,20);local a2=unit(w,'associate',1,20,21);step(w,1)
 assert(not rejected(Sim.step(w,{command(w,1,'attack',a1.id,{target=bunker.id}),command(w,1,'attack',a2.id,{target=bunker.id},1)})),'attack refused')
 local rules=C.rules.stacks;local hits,burstTick,expected,lastHit=0,nil,0,-1000
 for _=1,600 do
  local events=Sim.step(w,{})
  if expected>0 and w.tick-lastHit>rules.grace then expected=math.max(0,expected-(rules.decay+rules.decayPerArmor*2)) end
  local n=count(events,'attack');hits=hits+n
  -- Hits land one at a time: the one that crosses the threshold bursts and resets, and
  -- any hit after it on the same tick starts the next stack.
  local burst=false
  for _=1,n do expected=expected+rules.perHit;lastHit=w.tick;if expected>=16*rules.perHit then burst=true;expected=0 end end
  eq(count(events,'stack_burst'),burst and 1 or 0,'burst on the wrong tick')
  eq(bunker.stackFixed or 0,expected,'stacks do not follow the rule')
  if burst then burstTick=w.tick;break end
 end
 assert(burstTick,'the stacks never burst');assert(hits>=16,'burst on too few hits');eq(bunker.hp,400-hits*4-45,'burst damage not armour-piercing')
 -- Stacks build again, then the Associates walk away and the stacks fade: nothing for the
 -- grace, then 30 plus 6 per armour point a tick until none are left.
 while not (bunker.stackFixed and bunker.stackFixed>=800) do step(w,1) end
 local left,lastHit=bunker.stackFixed,bunker.stackHit
 step(w,1,{command(w,1,'move',a1.id,{x=F.center(4),y=F.center(20)}),command(w,1,'move',a2.id,{x=F.center(4),y=F.center(21)},1)})
 while w.tick<lastHit+C.rules.stacks.grace do step(w,1) end
 eq(bunker.stackFixed,left,'stacks decayed inside the grace')
 step(w,1);eq(bunker.stackFixed,left-(30+6*2),'wrong decay step')
 while bunker.stackFixed do step(w,1) end
 eq(bunker.stackHit,nil,'the last-hit tick outlived the stacks')
 assert(Sim.view(w,2).byId[bunker.id].stackFixed==nil and Sim.view(w,1).byId[a1.id].stackFixed==nil,'stack field leaked')
end

function M.barrage()
 local w=world();step(w,1)
 -- A Battleship, two enemy Blimps (the Orders' Gryphon walks; only the Reliquary flies, and
 -- it would heal) and a Footman under them, and an allied Blimp in the circle. Only the
 -- enemy Blimps are hit: six pulses of 14, no armour.
 local ship=unit(w,'battleship',1,20,20);local g1=unit(w,'command_blimp',2,28,20);local g2=unit(w,'command_blimp',2,29,21)
 local foot=unit(w,'footman',2,28,22);local blimp=unit(w,'command_blimp',1,27,20);step(w,1)
 local ok=not rejected(Sim.step(w,{command(w,1,'cast',ship.id,{ability='barrage',x=F.center(28),y=F.center(21)})}));assert(ok,'barrage refused')
 local spec=C.abilities.barrage;local castTick=w.tick+spec.castPoint
 local pulses=count(w.events,'cast',ship.id)
 local clone
 while w.tick<castTick+spec.channel.ticks+2 do
  local events=Sim.step(w,{});pulses=pulses+count(events,'cast',ship.id)
  if w.tick==castTick then assert(ship.channel,'no channel at the cast point');eq(ship.cooldowns.barrage,castTick+spec.cooldown,'cooldown not charged at the cast point') end
  if w.tick==castTick+spec.channel.period+3 then
   local view=Sim.view(w,2).byId[ship.id];assert(view.channel and view.channel.finish==ship.channel.finish and view.channel.ability==nil,'enemy view of the channel')
   clone=Sim.restore(Sim.snapshot(w))
  end
 end
 eq(pulses,spec.channel.ticks/spec.channel.period,'wrong pulse count');eq(ship.channel,nil,'channel did not end')
 eq(g1.hp,200-6*14,'blimp 1');eq(g2.hp,200-6*14,'blimp 2');eq(foot.hp,140,'the footman was hit');eq(blimp.hp,200,'the blimp was hit')
 eq(ship.order.kind,'stop','the cast order outlived the channel');eq(ship.attackTick,nil,'the gun fired during the channel')
 while clone.tick<w.tick do Sim.step(clone,{}) end
 eq(Sim.serializeCanonical(clone),Sim.serializeCanonical(w),'a channel does not survive a snapshot')
 -- A second ship: a move order mid-channel breaks it after two pulses, the cooldown stays
 -- spent, and the gun stayed silent throughout.
 -- The first ship is taken off the board so its gun cannot touch the numbers below.
 ship.alive=false;ship.hp=0
 local ship2=unit(w,'battleship',1,20,26);step(w,1)
 assert(not rejected(Sim.step(w,{command(w,1,'cast',ship2.id,{ability='barrage',x=F.center(28),y=F.center(21)})})),'second barrage refused')
 local cast2=w.tick+spec.castPoint;local hp1=g1.hp
 while w.tick<cast2+spec.channel.period do step(w,1) end
 eq(count(w.events,'cast',ship2.id),1,'second pulse missing');eq(ship2.channel and true,true)
 step(w,1,{command(w,1,'move',ship2.id,{x=F.center(20),y=F.center(30)})})
 eq(ship2.channel,nil,'a move did not break the channel');eq(ship2.cooldowns.barrage,cast2+spec.cooldown,'cooldown refunded');eq(ship2.attackTick,nil,'the gun fired during the channel')
 step(w,spec.channel.ticks);eq(g1.hp,hp1-2*14,'pulses continued after the break')
 eq(rejected(Sim.step(w,{command(w,1,'cast',ship2.id,{ability='barrage',x=F.center(28),y=F.center(21)})})),'ability on cooldown')
end
return M
