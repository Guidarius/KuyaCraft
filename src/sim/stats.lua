local F=require('src.sim.fixed')
-- Every gameplay-affecting statistic is resolved here and nowhere else.
--
-- It used to be that `speed` was read in movement and again in formation pacing,
-- `damage` in three places in the combat phase, `range` inside geometry and again in
-- two chase helpers, and each of them applied its own hero-specific bonus inline. That
-- worked while the only modifiers were two hero stances and six upgrade branches, and
-- it stops working the moment anything can be slowed, hasted, silenced or shielded: a
-- new effect would have to find and patch every one of those sites, and the one it
-- missed would be a bug nobody could see.
--
-- So the shape here is deliberately dull. One function per statistic, taking the world
-- and the entity, returning an integer. Content is the base, the entity's own durable
-- state (hero stance, chosen upgrades) is the first modifier layer, and `e.statuses` is
-- the second. Statuses do not exist yet; the loops that will read them are written and
-- cost one `if` against a nil field until they do.
--
-- Determinism rules apply as everywhere else in src/sim: integers only, no floats, and
-- percentages are summed before a single floored division so the order that modifiers
-- were applied in can never change the result.
local S={}
local function def(w,e) return w.content.units[e.kind] or w.content.buildings[e.kind] end
S.def=def
-- Percentage modifiers are summed and applied once. Applying them one at a time would
-- floor after each, which makes two -30% slows differ from one -60% depending on which
-- landed first -- a real desync risk the moment two players' statuses arrive in a
-- different order in the same tick.
local function apply(base,flat,percent)
    local n=base+flat
    if percent~=0 then n=F.mulDiv(n,100+percent,100) end
    return n
end
-- Walks the entity's status list once and returns the flat and percentage totals for
-- one field. Statuses are stored in application order, so the sum is order-stable.
local function modifiers(w,e,field)
    local flat,percent=0,0
    local list=e.statuses
    if not list then return flat,percent end
    local defs=w.content.statuses
    for i=1,#list do
        local status=list[i]
        local d=defs and defs[status.id]
        local m=d and d.modifiers
        if m then
            if m[field] then flat=flat+(status.magnitude or m[field]) end
            if m[field..'Percent'] then percent=percent+(status.percent or m[field..'Percent']) end
        end
    end
    return flat,percent
end
S.modifiers=modifiers
-- A flag is set by any active status that declares it: stun, root, silence,
-- invulnerability. Absent statuses mean every flag is false, which is why this is
-- cheap enough to sit in the movement loop.
function S.flag(w,e,name)
    local list=e.statuses
    if not list then return false end
    local defs=w.content.statuses
    for i=1,#list do
        local d=defs and defs[list[i].id]
        if d and d.flags and d.flags[name] then return true end
    end
    return false
end
function S.canMove(w,e) return not S.flag(w,e,'noMove') end
function S.canAttack(w,e) return not S.flag(w,e,'noAttack') end
function S.canCast(w,e) return not S.flag(w,e,'noCast') end
function S.invulnerable(w,e) return S.flag(w,e,'invulnerable') end
-- Subunits per tick. The two hero bonuses are additive and were additive before this
-- module existed; formation pacing caps the result rather than the base, so a unit that
-- has been sped up is still held in formation, and a unit already slower keeps its own
-- speed.
function S.speed(w,e)
    local rules=w.content.rules
    local flat,percent=modifiers(w,e,'speed')
    if e.kind=='beastkeeper' and e.stance==2 then flat=flat+(rules.pursuitSpeed or 8) end
    if e.sprintUntil and w.tick<e.sprintUntil then flat=flat+(rules.sprintSpeed or 12) end
    local n=apply(w.content.units[e.kind].speed,flat,percent)
    if n<1 then n=1 end
    local pace=e.groupSpeed
    if pace and pace<n then n=pace end
    return n
end
-- The speed formation pacing measures a group against: base plus modifiers, without
-- the group cap that would otherwise feed on itself, and without the two situational
-- hero bonuses, which come and go mid-march and must not change the group's pace.
function S.baseSpeed(w,e)
    local flat,percent=modifiers(w,e,'speed')
    local n=apply(w.content.units[e.kind].speed,flat,percent)
    return n<1 and 1 or n
end
-- Damage dealt by one committed hit, before the target's mitigation.
function S.damage(w,e)
    local d=def(w,e)
    if not d or not d.damage then return 0 end
    local rules=w.content.rules
    local flat,percent=modifiers(w,e,'damage')
    if e.upgrades and e.upgrades[2]==1 then flat=flat+(rules.heroDamage or 8) end
    if e.kind=='warden' and e.stance==2 then flat=flat+(rules.offensiveDamage or 6) end
    if e.kind=='beastkeeper' and e.stance==2 then flat=flat-(rules.pursuitPenalty or 5) end
    local n=apply(d.damage,flat,percent)
    return n<1 and 1 or n
end
-- Every warden in the world, in `w.order` order. Gathered once per tick by the combat
-- phase because the aura is a scan over heroes rather than a field on the target.
function S.protectors(w)
    local out={}
    for _,id in ipairs(w.order) do
        local e=w.entities[id]
        if e.alive and e.kind=='warden' then out[#out+1]=e end
    end
    return out
end
-- Deliberately identical to the simulation's own inRange, including the detail that it
-- clamps the *second* argument's footprint. The aura passes a hero there, which is never
-- a building, so the clamp never fires -- but reproducing the shape exactly is what lets
-- the golden replays prove this refactor changed nothing.
local function inRange(e,t,radius)
    local tx,ty=t.x,t.y
    if t.category=='building' or t.category=='node' then
        tx=math.max(t.x-128,math.min(e.x,t.x-128+t.size*256))
        ty=math.max(t.y-128,math.min(e.y,t.y-128+t.size*256))
    end
    return F.distance2Bounded(e.x,e.y,tx,ty)<=radius*radius
end
-- Flat damage reduction. Today the only source is the Warden's protection aura, which
-- does not stack with itself: two wardens covering the same soldier give the stronger
-- reduction, not the sum. Status armour is additive on top, because a shield spell and
-- an aura are different things and a player expects them to add.
function S.armor(w,e,protectors)
    local reduction=0
    local rules=w.content.rules
    for _,hero in ipairs(protectors or S.protectors(w)) do
        if hero.alive and hero.owner==e.owner and hero.kind=='warden' then
            local radius=hero.upgrades[1]==1 and (rules.auraWide or 1536) or (rules.auraRadius or 1024)
            if hero.upgrades[3]==2 then radius=radius+(rules.auraExtra or 256) end
            if inRange(e,hero,radius) then
                local deep=(hero.stance==1 and 3 or 1)+(hero.upgrades[1]==2 and (rules.auraDeep or 3) or 0)
                if deep>reduction then reduction=deep end
            end
        end
    end
    -- Content armour is the base every unit and building carries into the fight.
    local d=def(w,e)
    local flat=modifiers(w,e,'armor')+(d and d.armor or 0)
    return reduction+flat
end
-- Commit-to-commit period in ticks. The windup lives inside it and is never added to it.
function S.attackPeriod(w,e)
    local d=def(w,e)
    local flat,percent=modifiers(w,e,'attackPeriod')
    if e.upgrades and e.upgrades[3]==1 then flat=flat-(w.content.rules.quickTicks or 5) end
    local n=apply(d.cooldown,flat,percent)
    return n<1 and 1 or n
end
function S.windup(w,e)
    local d=def(w,e)
    local flat,percent=modifiers(w,e,'windup')
    local n=apply(d.windup,flat,percent)
    return n<1 and 1 or n
end
-- Weapon reach in subunits, measured edge to edge by the caller.
function S.range(w,e)
    local d=def(w,e)
    local flat,percent=modifiers(w,e,'range')
    local n=apply(d.range,flat,percent)
    return n<0 and 0 or n
end
-- Sight radius in whole cells: the visibility field and the acquisition box are both
-- built per cell, so a fractional sight would not mean anything to either.
function S.sight(w,e)
    local d=def(w,e)
    local flat,percent=modifiers(w,e,'sight')
    local n=apply(d.sight,flat,percent)
    return n<0 and 0 or n
end
return S
