local F=require('src.sim.fixed')
local G=require('src.sim.geometry')
local Stats=require('src.sim.stats')
-- Abilities and status effects.
--
-- The shape follows the attack phase rather than inventing a second one, because the
-- attack phase already solved the hard parts: a committed action has a start, a point at
-- which it takes effect and a finish; moving before the point cancels it and costs
-- nothing; the effect is collected into a list and applied with every other effect of
-- the tick, so simultaneous outcomes resolve together instead of in scan order.
--
-- Five target kinds and no more. `none` is instant, cast on the spot. `unit` needs a
-- visible entity that passes the ability's filter. `point` is a map coordinate. `area`
-- is a point with a radius, and hits everything in it that passes the filter. `direction`
-- is a point normalised into a line from the caster, which is what a skill shot is.
--
-- The effect vocabulary is fixed: damage, heal and status. It is deliberately not a
-- scripting language. Anything a faction needs that these cannot express is written as
-- ordinary Lua in this file and named by ability id, exactly as the hero passives are
-- today -- which is the roadmap's rule, and the reason not to build a universal ability
-- language before two factions have demonstrated what they actually need.
local A={}
local function def(w,e) return w.content.units[e.kind] or w.content.buildings[e.kind] end
function A.definition(w,id) return w.content.abilities and w.content.abilities[id] end
-- Does this entity have this ability at all? Ability lists live on the unit definition,
-- so they are content, shared and never mutated at runtime.
function A.has(w,e,id)
    local d=def(w,e)
    if not d or not d.abilities then return false end
    for i=1,#d.abilities do if d.abilities[i]==id then return true end end
    return false
end
function A.ready(w,e,id)
    local until_=e.cooldowns and e.cooldowns[id]
    return not until_ or w.tick>=until_
end
function A.affordable(w,e,ability)
    local cost=ability.cost and ability.cost.mana or 0
    return cost==0 or (e.mana or 0)>=cost
end
-- Who an ability may be aimed at. Neutral counts as hostile, the same as it does for
-- ordinary target acquisition, so a camp can be hit by the same spell that hits a player.
function A.matches(w,caster,target,filter)
    if not target or not target.alive then return false end
    if target.category=='node' or target.category=='carrier' then return false end
    filter=filter or {enemy=true}
    if target.category=='building' and not filter.building then return false end
    if target.id==caster.id then return filter.self==true end
    if target.owner==caster.owner then return filter.ally==true end
    return filter.enemy==true
end
-- Statuses -----------------------------------------------------------------------
--
-- Stored as an array in application order, so the modifier sums in src/sim/stats.lua
-- are order-stable. `until` is an absolute tick; a status applied on tick T for N ticks
-- is active on ticks T through T+N-1 and is swept at the top of tick T+N.
function A.status(w,e,id)
    local list=e.statuses
    if not list then return nil end
    for i=1,#list do if list[i].id==id then return list[i],i end end
    return nil
end
function A.applyStatus(w,target,fx,api)
    local d=w.content.statuses and w.content.statuses[fx.status]
    if not d then return end
    -- Invulnerability turns aside anything harmful and lets a friendly buff through.
    if not d.beneficial and Stats.invulnerable(w,target) then return end
    local existing,index=A.status(w,target,fx.status)
    local record={id=fx.status,source=fx.source,appliedTick=w.tick,
        ['until']=w.tick+(fx.ticks or 1),magnitude=fx.magnitude,percent=fx.percent,amount=fx.amount,stacks=1}
    if existing then
        local policy=d.stack or 'refresh'
        if policy=='refresh' then
            target.statuses[index]=record
        elseif policy=='max' then
            -- The stronger of the two wins outright, and keeps the longer remaining
            -- time, so re-applying a weaker version can never cut a stronger one short.
            local keep=(existing.magnitude or 0)>=(record.magnitude or 0) and existing or record
            if (existing['until'] or 0)>(record['until'] or 0) then keep['until']=existing['until'] else keep['until']=record['until'] end
            target.statuses[index]=keep
        else
            existing.stacks=math.min((existing.stacks or 1)+1,d.maxStacks or 8)
            existing['until']=record['until']
        end
    else
        target.statuses=target.statuses or {}
        target.statuses[#target.statuses+1]=record
    end
    -- A stun stops a swing that has not landed. The same rule the attack phase already
    -- uses for movement: before the impact tick nothing has been committed.
    if d.flags and (d.flags.noAttack or d.flags.noCast) and target.attack and w.tick<=target.attack.impact then target.attack=nil end
    if d.flags and d.flags.noCast and target.cast and w.tick<=target.cast.point then target.cast=nil end
    if api then api.emit(w,'status_applied',{entity=target.id,status=fx.status,source=fx.source}) end
end
-- Swept at the top of the step, before commands, so nothing observes a status on a tick
-- it is no longer meant to be active for.
function A.expire(w,api)
    for _,id in ipairs(w.order) do
        local e=w.entities[id]
        local list=e.statuses
        if list then
            for i=#list,1,-1 do
                if (list[i]['until'] or 0)<=w.tick then
                    local gone=table.remove(list,i)
                    api.emit(w,'status_expired',{entity=e.id,status=gone.id})
                end
            end
            if #list==0 then e.statuses=nil end
        end
    end
end
-- Target selection ---------------------------------------------------------------
local function pointOf(w,e,order)
    if order.target then
        local t=w.entities[order.target]
        if t then return t.x,t.y end
        return nil
    end
    return order.x,order.y
end
-- Everything the ability lands on, in `w.order` order so two peers resolve an area the
-- same way regardless of how the commands arrived.
function A.targets(w,caster,ability,order,out)
    local n=0
    if ability.target=='unit' then
        local t=w.entities[order.target]
        if A.matches(w,caster,t,ability.filter) then n=1;out[1]=t end
        return n
    end
    if ability.target=='none' or ability.target=='point' or ability.target=='area' then
        local cx,cy=caster.x,caster.y
        if ability.target~='none' then cx,cy=pointOf(w,caster,order) end
        if not cx then return 0 end
        local radius=ability.radius or 0
        if radius<=0 then return 0 end
        for _,id in ipairs(w.order) do
            local t=w.entities[id]
            if A.matches(w,caster,t,ability.filter) and F.distance2Bounded(cx,cy,t.x,t.y)<=F.sq(radius+G.radius(w,t)) then
                n=n+1;out[n]=t
            end
        end
        return n
    end
    if ability.target=='direction' then
        -- A skill shot: a line from the caster toward the aimed point, of the ability's
        -- range, with a width. Everything it passes through in `w.order` order is hit,
        -- or only the first if it does not pierce. Resolved as a line today; the
        -- travelling version is the same geometry with a position that advances.
        local px,py=pointOf(w,caster,order)
        if not px then return 0 end
        local dx,dy=F.vector(px-caster.x,py-caster.y,ability.range or 1024)
        if dx==0 and dy==0 then return 0 end
        local ex,ey=caster.x+dx,caster.y+dy
        local half=(ability.width or 256)/2
        for _,id in ipairs(w.order) do
            local t=w.entities[id]
            if A.matches(w,caster,t,ability.filter) then
                local reach=half+G.radius(w,t)
                if A.segmentDistance2(caster.x,caster.y,ex,ey,t.x,t.y)<=reach*reach then
                    n=n+1;out[n]=t
                    if not ability.pierce then return n end
                end
            end
        end
        return n
    end
    return 0
end
-- Squared distance from a point to a segment, in integers. The projection is a floored
-- division of exact integer products, so it is identical on every machine.
function A.segmentDistance2(x0,y0,x1,y1,px,py)
    local dx,dy=x1-x0,y1-y0
    local len2=dx*dx+dy*dy
    if len2==0 then return F.distance2Bounded(x0,y0,px,py) end
    local t=(px-x0)*dx+(py-y0)*dy
    if t<=0 then return F.distance2Bounded(x0,y0,px,py) end
    if t>=len2 then return F.distance2Bounded(x1,y1,px,py) end
    local cx=x0+F.mulDiv(dx,t,len2)
    local cy=y0+F.mulDiv(dy,t,len2)
    return F.distance2Bounded(cx,cy,px,py)
end
-- Casting ------------------------------------------------------------------------
--
-- Range is not checked when the command is accepted: a cast is an order, so a caster
-- out of range walks into range first, exactly as an attack order does.
function A.castRange(w,e,ability,order)
    -- A no-target ability is cast where the caster stands, so it is always in range.
    if ability.target=='none' then return true end
    local px,py=pointOf(w,e,order)
    if not px then return false end
    local reach=(ability.range or 0)+G.radius(w,e)
    local t=order.target and w.entities[order.target]
    if t then reach=reach+G.radius(w,t) end
    return F.distance2Bounded(e.x,e.y,px,py)<=reach*reach
end
local function fire(w,e,ability,order,pending,api)
    local out={}
    local px,py=pointOf(w,e,order)
    -- A projectile effect launches rather than resolving: the ability's targets are
    -- decided when the shot arrives, not when it leaves, which is what makes a skill
    -- shot something a player can walk out of.
    local launched=false
    for index,effect in ipairs(ability.effects or {}) do
        if effect.kind=='projectile' then
            launched=true
            api.launch(w,e,ability,index,effect,order,px,py)
        end
    end
    if launched then
        api.emit(w,'cast',{source=e.id,ability=order.ability,target=order.target,castX=px,castY=py,hits=0})
        return 0
    end
    local n=A.targets(w,e,ability,order,out)
    for _,effect in ipairs(ability.effects or {}) do
        for i=1,n do
            local t=out[i]
            if effect.kind=='damage' then
                pending[#pending+1]={kind='damage',source=e.id,target=t.id,damage=math.max(1,effect.amount-Stats.armor(w,t))}
            elseif effect.kind=='heal' then
                pending[#pending+1]={kind='heal',source=e.id,target=t.id,amount=effect.amount}
            elseif effect.kind=='status' then
                pending[#pending+1]={kind='status',source=e.id,target=t.id,status=effect.status,
                    ticks=effect.ticks,magnitude=effect.magnitude,percent=effect.percent,amount=effect.amount}
            end
        end
    end
    api.emit(w,'cast',{source=e.id,ability=order.ability,target=order.target,castX=px,castY=py,hits=n})
    return n
end
-- The cast phase, run between order completion and combat so that a stun applied this
-- tick is already in force when the combat phase asks whether its victim may swing.
function A.step(w,pending,api)
    if not w.content.abilities then return end
    for _,id in ipairs(w.order) do
        local e=w.entities[id]
        if e.alive and e.category=='unit' then
            -- Mana, and any status that ticks on its own.
            local d=def(w,e)
            if d.mana and w.tick%20==0 and (e.mana or 0)<(e.maxMana or d.mana) then
                e.mana=math.min(e.maxMana or d.mana,(e.mana or 0)+(d.manaRegen or 0))
            end
            local list=e.statuses
            if list then
                for i=1,#list do
                    local status=list[i]
                    local sd=w.content.statuses[status.id]
                    if sd and sd.period and (w.tick-status.appliedTick)>0 and (w.tick-status.appliedTick)%sd.period==0 then
                        for _,effect in ipairs(sd.effects or {}) do
                            if effect.kind=='damage' then
                                pending[#pending+1]={kind='damage',source=status.source or e.id,target=e.id,damage=math.max(1,(status.amount or effect.amount or 1)*(status.stacks or 1))}
                            elseif effect.kind=='heal' then
                                pending[#pending+1]={kind='heal',source=status.source or e.id,target=e.id,amount=(status.amount or effect.amount or 1)*(status.stacks or 1)}
                            end
                        end
                    end
                end
            end
            local order=e.order
            if order.kind=='cast' then
                local ability=A.definition(w,order.ability)
                if not ability or not A.has(w,e,order.ability) then api.nextOrder(w,e)
                elseif not Stats.canCast(w,e) then
                    -- Silenced or stunned mid-approach. The order stands; it resumes.
                    e.cast=nil
                elseif e.cast then
                    -- committed below
                elseif ability.target=='unit' and not A.matches(w,e,w.entities[order.target],ability.filter) then
                    api.nextOrder(w,e)
                elseif not A.ready(w,e,order.ability) or not A.affordable(w,e,ability) then
                    -- Waiting on a cooldown or on mana is not a failure; the caster holds
                    -- the order and casts when it can, which is what a queued spell means.
                elseif A.castRange(w,e,ability,order) then
                    api.halt(w,e)
                    -- A no-target ability is cast on the spot, so its point is the
                    -- caster's own position and its facing is left alone.
                    local px,py=pointOf(w,e,order)
                    if not px then px,py=e.x,e.y end
                    local point=w.tick+(ability.castPoint or 0)
                    e.cast={ability=order.ability,start=w.tick,point=point,finish=point+(ability.backswing or 0),
                        target=order.target,x=px,y=py,dx=px-e.x,dy=py-e.y}
                    api.emit(w,'casting',{source=e.id,ability=order.ability,target=order.target})
                else
                    api.approachCast(w,e,ability,order)
                end
            elseif e.cast then
                -- The order changed underneath an uncommitted cast: nothing was spent.
                if w.tick<=e.cast.point then e.cast=nil end
            end
            local phase=e.cast
            if phase and w.tick>=phase.point then
                local ability=A.definition(w,phase.ability)
                if w.tick==phase.point and ability then
                    local order2={ability=phase.ability,target=phase.target,x=phase.x,y=phase.y}
                    -- Revalidated at the point, exactly as an attack is revalidated at
                    -- its impact: the target may have died or left while the arm swung.
                    local ok=true
                    if ability.target=='unit' then ok=A.matches(w,e,w.entities[phase.target],ability.filter) and A.castRange(w,e,ability,order2) end
                    if ok then
                        e.mana=(e.mana or 0)-(ability.cost and ability.cost.mana or 0)
                        e.cooldowns=e.cooldowns or {}
                        e.cooldowns[phase.ability]=w.tick+(ability.cooldown or 0)
                        fire(w,e,ability,order2,pending,api)
                    end
                    if e.order.kind=='cast' then api.nextOrder(w,e) end
                end
                if w.tick>=phase.finish then e.cast=nil end
            end
        end
    end
end
return A
