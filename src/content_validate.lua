local F=require('src.sim.fixed')
return function(C)
    assert(F.integer(C.rules.directPathBudget,0,65536),'invalid direct path budget')
    assert(C.rules.tickRate==20,'unsupported balance tick rate')
    for _,d in pairs(C.units) do
        if C.rules.profile then assert(F.integer(d.food,0,10),'invalid food');assert(F.integer(d.buildTicks,0,10000),'invalid production duration');assert(F.integer(d.hp,1,100000),'invalid hp') end
        assert(F.integer(d.radius,1,127),'invalid unit radius')
        assert(F.integer(d.speed,1,64),'invalid unit speed')
        assert(F.integer(d.range,0,65536),'invalid weapon range')
        -- Neither carriers nor projectiles ever attack: no damage key, so nothing ever
        -- reads a windup or a cooldown from them. Asserting a firing cadence on one
        -- would only mean inventing numbers to satisfy the check.
        if d.carrier or d.projectile then assert(not d.damage,'a carrier or projectile must not have damage')
        else assert(F.integer(d.windup,1,d.cooldown-6),'invalid windup') end
    end
    for _,d in pairs(C.buildings) do if d.damage then assert(F.integer(d.windup,1,d.cooldown-1),'invalid building windup') end end
    -- Abilities and statuses. Every one of these is a mistake that would otherwise show
    -- up as a spell that silently does nothing in a match, which is the worst possible
    -- place to find it.
    local TARGETS={none=true,unit=true,point=true,area=true,direction=true}
    for id,d in pairs(C.abilities or {}) do
        assert(TARGETS[d.target],'ability '..id..' has an unknown target kind')
        assert(type(d.label)=='string' and #d.label>0,'ability '..id..' has no label')
        assert(F.integer(d.castPoint or 0,0,400),'ability '..id..' has an invalid cast point')
        assert(F.integer(d.backswing or 0,0,400),'ability '..id..' has an invalid backswing')
        assert(F.integer(d.cooldown or 0,0,100000),'ability '..id..' has an invalid cooldown')
        assert(F.integer(d.cost and d.cost.mana or 0,0,100000),'ability '..id..' has an invalid mana cost')
        -- A no-target ability is cast where the caster stands, so a range would mean
        -- nothing; every other kind needs somewhere to reach.
        if d.target=='none' then assert((d.range or 0)==0,'ability '..id..' takes no target, so it cannot have a range')
        else assert(F.integer(d.range,1,65536),'ability '..id..' needs a range') end
        if d.target=='none' or d.target=='area' then assert(F.integer(d.radius,1,65536),'ability '..id..' needs a radius') end
        if d.target=='direction' then assert(F.integer(d.width,1,65536),'ability '..id..' needs a width') end
        assert(d.effects and #d.effects>0,'ability '..id..' does nothing')
        for _,effect in ipairs(d.effects) do
            assert(effect.kind=='damage' or effect.kind=='heal' or effect.kind=='status' or effect.kind=='projectile','ability '..id..' has an unknown effect kind')
            if effect.kind=='projectile' then
                assert(d.target~='none','ability '..id..' launches a projectile but takes no target to aim it at')
                assert(F.integer(effect.speed,1,4096),'ability '..id..' has an invalid projectile speed')
                assert(F.integer(effect.radius or 1,1,65536),'ability '..id..' has an invalid projectile radius')
                assert(effect.onHit and #effect.onHit>0,'ability '..id..' fires a projectile that does nothing on impact')
                for _,hit in ipairs(effect.onHit) do
                    assert(hit.kind=='damage' or hit.kind=='heal' or hit.kind=='status','ability '..id..' has an unknown impact effect')
                    if hit.kind=='status' then assert(C.statuses and C.statuses[hit.status],'ability '..id..' applies the unknown status '..tostring(hit.status)) end
                end
            elseif effect.kind=='status' then
                assert(C.statuses and C.statuses[effect.status],'ability '..id..' applies the unknown status '..tostring(effect.status))
                assert(F.integer(effect.ticks,1,100000),'ability '..id..' applies a status with no duration')
            else assert(F.integer(effect.amount,1,100000),'ability '..id..' has an invalid effect amount') end
        end
    end
    for id,d in pairs(C.statuses or {}) do
        assert(d.stack=='refresh' or d.stack=='max' or d.stack=='stack','status '..id..' has an unknown stacking rule')
        if d.period then assert(F.integer(d.period,1,10000),'status '..id..' has an invalid period') end
        if d.maxStacks then assert(F.integer(d.maxStacks,1,64),'status '..id..' has an invalid stack cap') end
    end
    if C.rules.control then
        local control=C.rules.control
        assert(F.integer(control.radius,256,8192),'invalid control point radius')
        assert(F.integer(control.captureTicks,1,72000),'invalid control point capture time')
        assert(F.integer(control.holdTicks,1,72000),'invalid control point hold time')
    end
    -- Two abilities on the same unit may not claim the same command-card slot, or one of
    -- them would be unreachable.
    for id,d in pairs(C.units) do
        if d.abilities then
            local slots={}
            for _,name in ipairs(d.abilities) do
                local ability=C.abilities and C.abilities[name]
                assert(ability,'unit '..id..' has the unknown ability '..name)
                local slot=ability.slot
                if slot then assert(not slots[slot],'unit '..id..' has two abilities in card slot '..slot);slots[slot]=true end
            end
            assert(F.integer(d.mana,1,100000),'unit '..id..' has abilities but no mana')
            assert(F.integer(d.manaRegen or 0,0,10000),'unit '..id..' has an invalid mana regeneration')
        end
    end
    for _, faction in pairs(C.factions) do
        assert(C.units[faction.hero] and C.units[faction.hero].hero)
        assert(#faction.roster <= 4)
        for _, id in ipairs(faction.roster) do assert(C.units[id] and not C.units[id].worker) end
        assert(#faction.upgrades == 3)
        for _, choices in ipairs(faction.upgrades) do assert(#choices == 2) end
    end
    return true
end

