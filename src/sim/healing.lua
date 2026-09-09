local F=require('src.sim.fixed')
local H={}
function H.step(w,emit)
 if w.tick%20~=0 then return end
 local recipients={}
 for _,id in ipairs(w.order) do local e=w.entities[id];if e.alive and e.category=='unit' and e.hp<e.maxHp then recipients[#recipients+1]=e end end
 table.sort(recipients,function(a,b) local left,right=a.hp*b.maxHp,b.hp*a.maxHp;if left~=right then return left<right end;return a.id<b.id end)
 local healed={}
 -- Supports act first. Each target receives at most one support/base pulse per second.
 for pass=1,2 do for _,id in ipairs(w.order) do local e=w.entities[id];local d=w.content.units[e.kind] or w.content.buildings[e.kind]
  if e.alive and d and ((pass==1 and d.heal) or (pass==2 and d.baseHeal and e.remaining==0)) then
   local count=0;local limit=d.baseHeal and 3 or 1;local range=d.healRange or 1536
   local ex,ey=e.x,e.y;if e.category=='building' then ex=ex+(e.size-1)*128;ey=ey+(e.size-1)*128 end
   for _,ally in ipairs(recipients) do
    if count<limit and not healed[ally.id] and ally.owner==e.owner and (not d.baseHeal or w.tick-ally.lastCombat>=w.content.rules.outOfCombatTicks) and F.sq(ex-ally.x)+F.sq(ey-ally.y)<=F.sq(range) then
     ally.hp=math.min(ally.maxHp,ally.hp+(d.heal or d.baseHeal));healed[ally.id]=true;count=count+1;emit(w,'healed',{entity=ally.id})
    end
   end
  end
 end end
end
return H
