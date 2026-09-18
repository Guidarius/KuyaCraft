local F=require('src.sim.fixed')
return function(C)
    assert(F.integer(C.rules.directPathBudget,0,65536),'invalid direct path budget')
    assert(C.rules.tickRate==20,'unsupported balance tick rate')
    for _,d in pairs(C.units) do
        if C.rules.profile then assert(F.integer(d.food,0,10),'invalid food');assert(F.integer(d.buildTicks,0,10000),'invalid production duration');assert(F.integer(d.hp,1,100000),'invalid hp') end
        assert(F.integer(d.radius,1,127),'invalid unit radius')
        assert(F.integer(d.speed,1,64),'invalid unit speed')
        assert(F.integer(d.range,0,65536),'invalid weapon range')
        -- A projectile never attacks: no damage key, so nothing ever reads a windup or a
        -- cooldown from it. Asserting a firing cadence on one would only mean inventing
        -- numbers to satisfy the check. The same holds for any unit without a weapon.
        if d.projectile or not d.damage then assert(not d.damage,'a projectile must not have damage')
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
        if d.channel then
            assert(F.integer(d.channel.ticks,1,100000),'ability '..id..' channels for an invalid time')
            assert(F.integer(d.channel.period,1,d.channel.ticks),'ability '..id..' has an invalid channel period')
            assert(d.target~='unit','ability '..id..' channels on a unit; only points and areas are supported')
        end
        if d.filter then assert(not (d.filter.air and d.filter.ground),'ability '..id..' is both air-only and ground-only') end
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
    for id,d in pairs(C.units) do if d.applyStacks then assert(d.damage,'unit '..id..' applies stacks but has no attack') end end
    if C.rules.stacks then
        local s=C.rules.stacks
        for _,key in ipairs({'perHit','base','armorPercent','perHundredHp','burst','grace','decay','decayPerArmor'}) do
            assert(F.integer(s[key],key=='decayPerArmor' and 0 or 1,100000),'invalid stacks rule '..key)
        end
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
            local costed=false
            for _,name in ipairs(d.abilities) do local ability=C.abilities[name];if ability.cost and (ability.cost.mana or 0)>0 then costed=true end end
            if costed or d.mana then assert(F.integer(d.mana,1,100000),'unit '..id..' has a mana-costed ability but no mana') end
            assert(F.integer(d.manaRegen or 0,0,10000),'unit '..id..' has an invalid mana regeneration')
        end
    end
    -- Resources and costs. Every cost key must be a ledger key, or it could never be paid.
    local RESOURCES={};for _,key in ipairs(C.rules.resources or {'gold'}) do assert(type(key)=='string','invalid resource key');RESOURCES[key]=true end
    local function costOk(cost,what)
        for key,amount in pairs(cost or {}) do
            assert(RESOURCES[key],what..' costs the unknown resource '..tostring(key))
            assert(F.integer(amount,0,1000000),what..' has an invalid '..key..' cost')
        end
    end
    if C.rules.startingResources then costOk(C.rules.startingResources,'startingResources') end
    if C.rules.tech then costOk(C.rules.tech.cost,'tech') end
    assert(F.integer(C.rules.cancelRefundPercent or 50,0,100),'invalid cancel refund percent')
    if C.rules.supplyCap then assert(F.integer(C.rules.supplyCap,1,1000),'invalid supply cap') end
    if C.rules.descentTicks then assert(F.integer(C.rules.descentTicks,1,10000),'invalid descent time') end
    if C.rules.callDownQueue then assert(F.integer(C.rules.callDownQueue,1,20),'invalid call-down queue size') end
    if C.rules.podCapacity then assert(F.integer(C.rules.podCapacity,1,16),'invalid pod capacity') end
    if C.rules.podCooldown then assert(F.integer(C.rules.podCooldown,0,10000),'invalid pod cooldown') end
    if C.rules.podsBase then assert(F.integer(C.rules.podsBase,1,8),'invalid base pod count') end
    if C.rules.podsMax then assert(F.integer(C.rules.podsMax,1,8),'invalid pod cap') end
    if C.rules.garrisonDamagePercent then assert(F.integer(C.rules.garrisonDamagePercent,0,100),'invalid garrison damage percent') end
    local function refs(list,catalogue,what)
        for _,kind in ipairs(list or {}) do assert(type(kind)=='string' and catalogue[kind],what..' names the unknown kind '..tostring(kind)) end
    end
    for id,d in pairs(C.units) do
        costOk(d.cost,'unit '..id)
        -- The air layer: flags are booleans, an air weapon needs the flag that lets it fire,
        -- and splash needs a weapon to splash from.
        if d.flying~=nil then assert(type(d.flying)=='boolean','unit '..id..' has an invalid flying flag') end
        if d.canAttackAir~=nil then assert(type(d.canAttackAir)=='boolean','unit '..id..' has an invalid canAttackAir flag') end
        if d.airDamage then assert(d.canAttackAir==true,'unit '..id..' has an air weapon it may not use');assert(F.integer(d.airDamage,1,100000),'unit '..id..' has an invalid air damage') end
        if d.splash then assert(d.damage,'unit '..id..' splashes without a weapon');assert(F.integer(d.splash,1,65536),'unit '..id..' has an invalid splash radius') end
        if d.coverage then assert(F.integer(d.coverage,256,65536),'unit '..id..' has an invalid coverage radius') end
        if d.pod~=nil then assert(type(d.pod)=='boolean','unit '..id..' has an invalid pod flag') end
        if d.garrisonSlots then assert(F.integer(d.garrisonSlots,1,16),'unit '..id..' has invalid garrison slots') end
        if d.armor then assert(F.integer(d.armor,0,100),'unit '..id..' has invalid armor') end
        refs(d.requires,C.buildings,'unit '..id..' requires')
    end
    for id,d in pairs(C.buildings) do
        costOk(d.cost,'building '..id)
        if d.armor then assert(F.integer(d.armor,0,100),'building '..id..' has invalid armor') end
        if d.supply then assert(F.integer(d.supply,0,1000),'building '..id..' has invalid supply') end
        if d.onNode then assert(type(d.onNode)=='string','building '..id..' has an invalid onNode') end
        if d.coverage then assert(F.integer(d.coverage,256,65536),'building '..id..' has an invalid coverage radius') end
        if d.tier~=nil then assert(type(d.tier)=='boolean','building '..id..' has an invalid tier flag') end
        if d.garrison then assert(F.integer(d.garrison,1,16),'building '..id..' has an invalid garrison') end
        if d.garrisonFights~=nil then assert(d.garrison,'building '..id..' lets occupants fight but holds none');assert(type(d.garrisonFights)=='boolean','building '..id..' has an invalid garrisonFights flag') end
        for _,field in ipairs({'income','incomeOffline'}) do if d[field] then assert(type(d[field])=='table','building '..id..' has an invalid '..field);for key,amount in pairs(d[field]) do assert(RESOURCES[key],'building '..id..' earns the unknown resource '..tostring(key));assert(F.integer(amount,0,100000),'building '..id..' has an invalid '..field..' rate') end end end
        if d.incomeOffline then assert(d.income,'building '..id..' has an offline rate but no income') end
        refs(d.produces,C.units,'building '..id..' produces')
        refs(d.requires,C.buildings,'building '..id..' requires')
    end
    -- Factions. The hero trio is the legacy shape and is checked only when a hero is named;
    -- the rest of the schema is checked for every faction.
    for id, faction in pairs(C.factions) do
        if faction.hero then
            assert(C.units[faction.hero] and C.units[faction.hero].hero,'faction '..id..' has an invalid hero')
            assert(#faction.roster <= 4)
            assert(#faction.upgrades == 3)
            for _, choices in ipairs(faction.upgrades) do assert(#choices == 2) end
        end
        for _, unit in ipairs(faction.roster or {}) do assert(C.units[unit] and not C.units[unit].worker,'faction '..id..' has an invalid roster') end
        assert(C.buildings[faction.hq or 'hq'],'faction '..id..' has no headquarters building')
        if faction.worker then assert(C.units[faction.worker] and C.units[faction.worker].worker,'faction '..id..' names a worker that is not one') end
        refs(faction.buildings,C.buildings,'faction '..id..' buildings')
        if faction.starting then
            costOk(faction.starting.resources,'faction '..id..' starting resources')
            refs(faction.starting.units,C.units,'faction '..id..' starting units')
        end
        assert(faction.defeat==nil or faction.defeat=='all_hq' or faction.defeat=='unique_hq','faction '..id..' has an unknown defeat rule')
        if faction.supplyCap then assert(F.integer(faction.supplyCap,1,1000),'faction '..id..' has an invalid supply cap') end
        if faction.coverage~=nil then assert(type(faction.coverage)=='boolean','faction '..id..' has an invalid coverage flag') end
    end
    return true
end

