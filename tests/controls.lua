local Sim=require('src.sim')
local F=require('src.sim.fixed')
local Codec=require('src.sim.codec')
local G=require('src.sim.geometry')
local S=require('tests.control_scenarios')
local T={}
local function duel()
    local w=S.world();local a=S.unit(w,'crossbow',1,16,16);local b=S.unit(w,'worker',2,19,16)
    b.hp=10000;b.maxHp=10000;b.order={kind='hold'};Sim.step(w,{})
    a.attack=nil;a.combatTarget=nil;a.engagement=nil
    return w,a,b
end
function T.register(test)
    test('simulation','repeated attack orders preserve windup and cadence',function()
        local function run(spam)
            local w,a,b=duel();local shots={}
            for i=1,100 do
                local commands=(i==1 or spam) and {S.command(w,a,'attack',{target=b.id})} or {}
                for _,event in ipairs(Sim.step(w,commands)) do if event.kind=='attack' and event.source==a.id then shots[#shots+1]=w.tick end end
            end
            assert(#shots>=3);for i=2,#shots do assert(shots[i]-shots[i-1]==w.content.units.crossbow.cooldown) end
            return Codec.encode(shots)
        end
        assert(run(false)==run(true))
    end)
    test('simulation','commit boundary cancellation and cooldown preservation',function()
        for _,offset in ipairs({-1,0,1}) do
            local w,a,b=duel();Sim.step(w,{S.command(w,a,'attack',{target=b.id})});local impact=a.attack.impact;local hp=b.hp
            while w.tick<impact+offset-1 do Sim.step(w,{}) end
            Sim.step(w,{S.command(w,a,'move',{x=F.center(12),y=F.center(16)})})
            if offset<=0 then assert(b.hp==hp and not a.nextCommitTick,'precommit cancellation spent cooldown')
            else assert(b.hp<hp and a.nextCommitTick==impact+30,'committed hit/cooldown lost') end
            assert(not a.attack and not a.attackTick)
        end
    end)
    test('simulation','Stop suppresses this tick and Hold never chases',function()
        local w,a,b=duel();b.x=F.center(22);Sim.step(w,{})
        local x,y=a.x,a.y;Sim.step(w,{S.command(w,a,'stop')});assert(a.x==x and a.y==y and not a.goal and not a.attack)
        Sim.step(w,{S.command(w,a,'hold')})
        for _=1,100 do Sim.step(w,{}) end
        assert(a.x==x and a.y==y and not a.goal)
        b.x=a.x+400;local hp=b.hp
        for _=1,10 do Sim.step(w,{}) end
        assert(b.hp<hp and a.x==x and a.y==y)
    end)
    test('simulation','attack-move retains destination through combat and resumes',function()
        local w,a,b=duel();b.hp=1
        Sim.step(w,{S.command(w,a,'attack_move',{x=F.center(25),y=F.center(16)})})
        local x,y=a.order.x,a.order.y
        for _=1,3 do Sim.step(w,{});assert(a.order.kind=='attack_move') end
        for _=1,400 do Sim.step(w,{}) end
        assert(not b.alive and a.x==F.center(x) and a.y==F.center(y),'attack-move did not resume')
    end)
    test('simulation','repeated move retains slots and pending paths',function()
        local w=S.world();local a=S.unit(w,'worker',1,12,12);w.content.rules.pathBudget=1;w.content.rules.directPathBudget=0
        local args={x=F.center(30),y=F.center(30),group=1}
        Sim.step(w,{S.command(w,a,'move',args)});local x,y=a.order.x,a.order.y
        for _=1,100 do Sim.step(w,{S.command(w,a,'move',args)});assert(a.order.x==x and a.order.y==y) end
        for _=1,1000 do Sim.step(w,{}) end
        assert(a.x==F.center(x) and a.y==F.center(y))
    end)
    test('simulation','weapon radii and building footprint boundaries',function()
        local w,a,b=duel();local range=w.content.units[a.kind].range+G.radius(w,a)+G.radius(w,b)
        b.x=a.x+range;b.y=a.y;assert(G.weaponRange(w,a,b));b.x=b.x+1;assert(not G.weaponRange(w,a,b))
        local h=w.entities[w.players[2].hq];a.x=h.x-128-w.content.units[a.kind].range-G.radius(w,a);a.y=h.y
        assert(G.weaponRange(w,a,h));a.x=a.x-1;assert(not G.weaponRange(w,a,h))
    end)
    test('determinism','windup continuation and entity insertion histories',function()
        local w,a,b=duel();Sim.step(w,{S.command(w,a,'attack',{target=b.id})})
        local clone=Sim.restore(Sim.snapshot(w));local entities={}
        for i=#clone.order,1,-1 do local id=clone.order[i];entities[id]=clone.entities[id] end;clone.entities=entities
        for _=1,100 do Sim.step(w,{});Sim.step(clone,{});assert(Sim.serializeCanonical(w)==Sim.serializeCanonical(clone)) end
    end)
    test('unit','integer vector lengths and content bounds',function()
        for n=0,1000 do local r=F.isqrt(n);assert(r*r<=n and (r+1)^2>n) end
        for dx=-100,100,7 do for dy=-100,100,7 do local x,y=F.vector(dx,dy,32);assert(x*x+y*y<=32^2) end end
        local c=Codec.copy(require('src.content'));c.units.worker.radius=128;assert(not pcall(require('src.content_validate'),c))
    end)
    test('simulation','explicit target beats closer enemy and automatic targets persist',function()
        local w,a,b=duel();local closer=S.unit(w,'worker',2,17,16);closer.order={kind='hold'}
        Sim.step(w,{S.command(w,a,'attack',{target=b.id})});assert(a.combatTarget==b.id)
        for _=1,5 do Sim.step(w,{}) end
        assert(b.hp<b.maxHp and closer.hp==closer.maxHp)
        Sim.step(w,{S.command(w,a,'stop')});Sim.step(w,{});assert(a.combatTarget==closer.id)
        b.x=a.x+200;b.y=a.y+100;Sim.step(w,{});assert(a.combatTarget==closer.id,'automatic target oscillated')
    end)
    test('simulation','death and fog loss before commit prevent damage',function()
        for _,fog in ipairs({false,true}) do
            local w,a,b=duel();Sim.step(w,{S.command(w,a,'attack',{target=b.id})});local hp=b.hp
            if fog then
                -- Sight changes are fixture setup; visibility is recomputed on the next tick.
                w.content.units.crossbow.sight=1
            else b.hp=0 end
            for _=1,6 do Sim.step(w,{}) end
            if fog then assert(b.hp==hp and a.order.kind=='stop') else assert(not b.alive) end
            assert(not a.nextCommitTick)
        end
    end)
    test('simulation','autonomous pursuit respects its engagement leash',function()
        local w=S.world();local a=S.unit(w,'shield',1,15,15);local b=S.unit(w,'worker',2,17,15);b.order={kind='hold'}
        Sim.step(w,{});Sim.step(w,{});assert(a.combatTarget==b.id)
        b.x=F.center(21);local x=a.x
        for _=1,30 do Sim.step(w,{}) end
        assert(not a.combatTarget and a.x==x,'automatic target dragged unit past leash')
        Sim.step(w,{S.command(w,a,'attack',{target=b.id})})
        for _=1,60 do Sim.step(w,{}) end
        assert(a.x>x,'explicit visible target was constrained by automatic leash')
    end)
    test('simulation','50 ranged units commit then retreat without extra attacks',function()
        local w=S.world(64);local shooters={};local targets={};local commands={}
        for i=1,50 do
            local x=8+(i-1)%5*10;local y=8+math.floor((i-1)/5)*4
            shooters[i]=S.unit(w,'crossbow',1,x,y);targets[i]=S.unit(w,'worker',2,x+3,y);targets[i].order={kind='hold'}
            targets[i].hp=10000;targets[i].maxHp=10000
        end
        Sim.step(w,{})
        for i,e in ipairs(shooters) do commands[i]=S.command(w,e,'attack',{target=targets[i].id},i) end
        local shots=0
        for tick=1,5 do for _,event in ipairs(Sim.step(w,tick==1 and commands or {})) do if event.kind=='attack' then shots=shots+1 end end end
        assert(shots==50,'ranged group did not commit together')
        commands={};for i,e in ipairs(shooters) do commands[i]=S.command(w,e,'move',{x=e.x-512,y=e.y},w.players[1].sequence+i) end
        Sim.step(w,commands)
        for _,e in ipairs(shooters) do assert(not e.attack and e.cooldown==29) end
        for _=1,12 do for _,event in ipairs(Sim.step(w,{})) do assert(event.kind~='attack','retreat generated an extra attack') end end
    end)
end
return T
