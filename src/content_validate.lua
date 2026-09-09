local F=require('src.sim.fixed')
return function(C)
    assert(F.integer(C.rules.directPathBudget,0,65536),'invalid direct path budget')
    assert(C.rules.tickRate==20,'unsupported balance tick rate')
    for _,d in pairs(C.units) do
        if C.rules.profile then assert(F.integer(d.food,0,10),'invalid food');assert(F.integer(d.buildTicks,0,10000),'invalid production duration');assert(F.integer(d.hp,1,100000),'invalid hp') end
        assert(F.integer(d.radius,1,127),'invalid unit radius')
        assert(F.integer(d.speed,1,64),'invalid unit speed')
        assert(F.integer(d.windup,1,d.cooldown-6),'invalid windup')
        assert(F.integer(d.range,0,65536),'invalid weapon range')
    end
    for _,d in pairs(C.buildings) do if d.damage then assert(F.integer(d.windup,1,d.cooldown-1),'invalid building windup') end end
    for _, faction in pairs(C.factions) do
        assert(C.units[faction.hero] and C.units[faction.hero].hero)
        assert(#faction.roster <= 4)
        for _, id in ipairs(faction.roster) do assert(C.units[id] and not C.units[id].worker) end
        assert(#faction.upgrades == 3)
        for _, choices in ipairs(faction.upgrades) do assert(#choices == 2) end
    end
    return true
end

