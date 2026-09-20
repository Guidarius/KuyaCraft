local Sim=require('src.sim')
local Content=require('src.content')
local Maps=require('src.maps')
local F=require('src.sim.fixed')
local Stats=require('src.sim.stats')
local S=require('tests.control_scenarios')
local R={}
function R.world(size)
    local map=Maps.create('controls',size or 64);map.resources={};map.camps={}
    local w=Sim.create({seed=17,players={{faction='orders'},{faction='megacorp'}}},Content,map)
    for _,id in ipairs(w.order) do local e=w.entities[id];if e.category=='unit' then e.alive=false end end
    return w
end
function R.register(test)
    test('simulation','formation pacing never shares speeds between players',function()
        local w=R.world();w.content.rules.formationPacing=true
        local a=S.unit(w,'footman',1,10,10);local b=S.unit(w,'battleship',2,45,45)
        Sim.step(w,{S.command(w,a,'move',{x=F.center(25),y=F.center(10),group=1}),
            S.command(w,b,'move',{x=F.center(35),y=F.center(45),group=1})})
        assert(Stats.speed(w,a)==40 and Stats.speed(w,b)==22,'opposing orders changed movement speed')
        local clone=Sim.restore(Sim.snapshot(w))
        for _=1,40 do Sim.step(w,{});Sim.step(clone,{}) end
        assert(Sim.serializeCanonical(w)==Sim.serializeCanonical(clone))
    end)
    test('simulation','shipping mixed selections retain individual movement speeds',function()
        local w=R.world()
        local a=S.unit(w,'associate',2,10,20);local b=S.unit(w,'battleship',2,10,24)
        Sim.step(w,{S.command(w,a,'move',{x=F.center(40),y=F.center(20),group=7},1),
            S.command(w,b,'move',{x=F.center(40),y=F.center(24),group=7},2)})
        local ax,bx=a.x,b.x
        for _=1,20 do Sim.step(w,{}) end
        assert(Stats.speed(w,a)==44 and Stats.speed(w,b)==22,'selection capped a unit speed')
        assert(a.x-ax>b.x-bx,'the faster unit did not pull ahead')
    end)
end
return R
