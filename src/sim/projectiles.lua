local F=require('src.sim.fixed')
local G=require('src.sim.geometry')
local Abilities=require('src.sim.abilities')
-- Things in flight.
--
-- A projectile is built the way a carrier is: its own entity category, in `w.order` and
-- therefore in every snapshot and hash, but out of the collision bins, out of movement,
-- out of the pathfinder and out of visibility. It is not an obstruction and it grants no
-- sight. Dead ones are recycled rather than allowed to grow the entity list without
-- bound, which is the same bargain carriers make.
--
-- Two flight modes, and the difference is the whole reason the file is short. A homing
-- shot knows its target, so hit detection is one distance test. A linear shot -- a skill
-- shot -- has to ask what it passed through, so it walks the segment it covered this
-- tick against the candidates. Only the second kind is ever more than O(1), and there is
-- one of those per cast rather than one per attack.
local P={}
function P.definition(w,e) return w.content.abilities and w.content.abilities[e.ability] end
-- The effect list a projectile carries is looked up from content at impact rather than
-- stored on the entity, so a shot in flight is a handful of integers and a string.
local function onHit(w,e)
    local ability=P.definition(w,e)
    if not ability then return nil end
    local effect=ability.effects and ability.effects[e.effectIndex]
    return effect and effect.onHit or nil
end
local function land(w,e,target,pending)
    local list=onHit(w,e)
    if not list then return end
    for _,effect in ipairs(list) do
        if effect.kind=='damage' then
            pending[#pending+1]={kind='damage',source=e.source,target=target.id,
                damage=math.max(1,effect.amount-require('src.sim.stats').armor(w,target))}
        elseif effect.kind=='heal' then
            pending[#pending+1]={kind='heal',source=e.source,target=target.id,amount=effect.amount}
        elseif effect.kind=='status' then
            pending[#pending+1]={kind='status',source=e.source,target=target.id,status=effect.status,
                ticks=effect.ticks,magnitude=effect.magnitude,percent=effect.percent,amount=effect.amount}
        end
    end
end
local function expire(w,e,api)
    e.alive=false;e.spent=true;e.deathTick=nil;e.hit=nil
    api.emit(w,'projectile_gone',{entity=e.id})
end
-- Everything the shot could touch, filtered by the ability that fired it, in `w.order`
-- order so two peers agree on which body a line caught first.
local function candidates(w,e,ability,out)
    local n=0
    local caster=w.entities[e.source]
    if not caster then return 0 end
    for _,id in ipairs(w.order) do
        local t=w.entities[id]
        if t.category~='projectile' and Abilities.matches(w,caster,t,ability.filter) then n=n+1;out[n]=t end
    end
    return n
end
local scratch={}
function P.step(w,pending,api)
    for _,id in ipairs(w.order) do
        local e=w.entities[id]
        if e.alive and e.category=='projectile' then
            local ability=P.definition(w,e)
            if not ability then expire(w,e,api)
            else
                local px,py=e.x,e.y
                if e.target then
                    -- Homing: re-aim every tick, so a shot follows a unit that walks.
                    local t=w.entities[e.target]
                    if not t or not t.alive then expire(w,e,api)
                    else
                        local dx,dy=F.vector(t.x-e.x,t.y-e.y,e.speed)
                        e.x=e.x+dx;e.y=e.y+dy
                        e.dx=dx;e.dy=dy
                        local reach=(e.radius or 0)+G.radius(w,t)
                        if F.distance2Bounded(e.x,e.y,t.x,t.y)<=reach*reach then
                            land(w,e,t,pending)
                            api.emit(w,'projectile_hit',{entity=e.id,target=t.id})
                            expire(w,e,api)
                        end
                    end
                else
                    e.x=e.x+e.dx;e.y=e.y+e.dy
                    e.remaining=(e.remaining or 0)-e.speed
                    local list,n=scratch,candidates(w,e,ability,scratch)
                    for i=1,n do
                        local t=list[i]
                        if not (e.hit and e.hit[t.id]) then
                            local reach=(e.radius or 0)+G.radius(w,t)
                            -- Against the segment covered this tick, not the end point:
                            -- a fast shot must not step straight over a body.
                            if Abilities.segmentDistance2(px,py,e.x,e.y,t.x,t.y)<=reach*reach then
                                land(w,e,t,pending)
                                api.emit(w,'projectile_hit',{entity=e.id,target=t.id})
                                if e.pierce then e.hit=e.hit or {};e.hit[t.id]=true
                                else expire(w,e,api);break end
                            end
                        end
                    end
                    if e.alive and (e.remaining or 0)<=0 then expire(w,e,api) end
                    if e.alive and not G.terrain(w,e.x,e.y,0) then expire(w,e,api) end
                end
            end
        end
    end
end
return P
