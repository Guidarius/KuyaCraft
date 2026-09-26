local Sim=require('src.sim')
local Content=require('src.content')
local Maps=require('src.maps')
local F=require('src.sim.fixed')
local Stats=require('src.sim.stats')
local Path=require('src.sim.path')
local G=require('src.sim.geometry')
local S=require('tests.control_scenarios')
local R={}
function R.world(size)
    local map=Maps.create('controls',size or 64);map.resources={};map.camps={}
    local w=Sim.create({seed=17,players={{faction='orders'},{faction='megacorp'}}},Content,map)
    for _,id in ipairs(w.order) do local e=w.entities[id];if e.category=='unit' then e.alive=false end end
    return w
end
function R.wallGroup(n)
    local w=R.world();S.wall(w,32,0,55)
    local units,commands,origins={},{},{}
    for i=1,n do
        local e=S.unit(w,'worker',1,8+(i-1)%6,8+math.floor((i-1)/6))
        units[i]=e;origins[i]={x=e.x,y=e.y}
        commands[i]=S.command(w,e,'move',{x=F.center(52),y=F.center(10),group=1},i)
    end
    Sim.step(w,commands)
    return w,units,origins
end
-- Appended to each fresh-process determinism worker, covering shipping route sharing,
-- cancellations, terrain invalidation and a restore with the host's JIT settings.
function R.checkpoints(output,schedule)
    local w,units=R.wallGroup(24);local credit=0
    while w.tick<1800 do
        credit=credit+20
        while credit>=schedule and w.tick<1800 do
            credit=credit-schedule
            local commands={}
            if w.tick==1 then units[1].hp=0 end
            if w.tick==2 then commands={S.command(w,units[2],'hold',{})} end
            if w.tick==400 then S.wall(w,25,14,40) end
            if w.tick==600 then w=Sim.restore(Sim.snapshot(w));for i,e in ipairs(units) do units[i]=w.entities[e.id] end end
            if w.tick==800 then commands={S.command(w,units[3],'move',{x=52*256+90,y=11*256+160})} end
            Sim.step(w,commands)
            if w.tick%100==0 then output:write('shipping '..w.tick..' '..require('src.hash').bytes(Sim.serializeCanonical(w))..'\n') end
        end
    end
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
    test('simulation','destination counts preserve queued overlap and release stopped orders',function()
        for _,release in ipairs({false,true}) do
            local w=R.world();local a=S.unit(w,'worker',1,10,10);local b=S.unit(w,'worker',1,12,10);local c=S.unit(w,'worker',1,14,10)
            a.order={kind='move',x=30,y=30};b.order={kind='move',x=50,y=50};b.orders={{kind='move',x=30,y=30}}
            local commands={S.command(w,a,'move',{x=F.center(40),y=F.center(40)},1),S.command(w,c,'move',{x=F.center(30),y=F.center(30)},2)}
            if release then
                commands[#commands+1]=S.command(w,b,'stop',{},3)
                commands[#commands+1]=S.command(w,c,'patrol',{x=F.center(30),y=F.center(30)},4)
            end
            Sim.step(w,commands)
            assert((c.order.x==30 and c.order.y==30)==release,'queued reservation count or stop invalidation was lost')
            assert(not w.destinationClaims and not w.commandClaims,'command scratch leaked into a snapshot')
        end
    end)
    test('simulation','precise destinations respond within a cell and survive queued restore',function()
        local w=R.world();local e=S.unit(w,'worker',1,10,10)
        Sim.step(w,{S.command(w,e,'move',{x=20*256+80,y=10*256+80})})
        Sim.step(w,{S.command(w,e,'move',{x=20*256+200,y=10*256+200})})
        assert(e.order.px==20*256+200 and e.order.py==10*256+200,'same-cell adjustment was discarded')
        local clone=Sim.restore(Sim.snapshot(w))
        for _=1,150 do Sim.step(w,{});Sim.step(clone,{}) end
        assert(e.x==20*256+200 and e.y==10*256+200 and e.order.kind=='stop','did not arrive at the click')
        assert(Sim.serializeCanonical(w)==Sim.serializeCanonical(clone))
        Sim.step(w,{S.command(w,e,'move',{x=21*256+80,y=11*256+80})})
        Sim.step(w,{S.command(w,e,'move',{x=23*256+180,y=13*256+180,append=true})})
        clone=Sim.restore(Sim.snapshot(w))
        for _=1,180 do Sim.step(w,{});Sim.step(clone,{}) end
        assert(e.x==23*256+180 and e.y==13*256+180 and e.order.kind=='stop','queued endpoint lost')
        assert(Sim.serializeCanonical(w)==Sim.serializeCanonical(clone))
    end)
    test('simulation','precise endpoints retain terrain clearance and patrol endpoints',function()
        local w=R.world();local e=S.unit(w,'worker',1,10,20);S.wall(w,21,15,25)
        Sim.step(w,{S.command(w,e,'move',{x=21*256-1,y=F.center(20)})})
        assert(not e.order.px,'accepted a body inside the wall')
        for _=1,150 do Sim.step(w,{});assert(G.terrain(w,e.x,e.y,G.radius(w,e))) end
        assert(e.order.kind=='stop')
        local startX,startY=e.x,e.y
        Sim.step(w,{S.command(w,e,'patrol',{x=18*256+90,y=18*256+90})})
        local seen=false
        for _=1,180 do Sim.step(w,{});if e.x==18*256+90 and e.y==18*256+90 then seen=true end end
        assert(seen and (e.order.originPX==startX or e.order.px==startX),'patrol dropped its exact ends')
    end)
    test('simulation','smoothing charges failed probes and never exceeds its sample budget',function()
        for _,blocked in ipairs({false,true}) do
            local w=R.world();local e=S.unit(w,'worker',1,10,10)
            if blocked then S.wall(w,25,0,55) end
            w.content.rules.smoothBudget=12;w.metrics.smoothChecks=0
            local path={};for x=11,50 do path[#path+1]={x=x,y=10} end
            local actual=0;local terrain=G.terrain
            G.terrain=function(...) actual=actual+1;return terrain(...) end
            local ok,result=pcall(Path.smooth,w,e,path);G.terrain=terrain
            assert(ok,result);assert(actual<=12 and w.metrics.smoothChecks==actual,'unaccounted smoothing work')
            assert(result[#result].x==50,'budget exhaustion dropped the destination')
        end
    end)
    for _,n in ipairs({1,12,24,48}) do
        test('crowd','shipping first movement around a wall: '..n..' workers',function()
            local w,units,origins=R.wallGroup(n);local first={}
            for tick=1,40 do
                if tick>1 then Sim.step(w,{}) end
                for i,e in ipairs(units) do if not first[i] and (e.x~=origins[i].x or e.y~=origins[i].y) then first[i]=tick end end
                assert(w.metrics.pathExpansions<=w.content.rules.pathBudget)
                assert(w.metrics.directChecks<=w.content.rules.directPathBudget)
                assert(w.metrics.smoothChecks<=w.content.rules.smoothBudget)
            end
            local last=0;for i=1,n do assert(first[i],'unit '..i..' waited over two seconds');last=math.max(last,first[i]) end
            print('RESPONSE '..n..' workers: all started by '..last..' ticks')
        end)
    end
    test('determinism','shared searches survive restore, replacement and leader death',function()
        for _,cancel in ipairs({false,true}) do
            local w,units=R.wallGroup(24)
            assert(w.searches[units[2].id].leader,'fixture did not share a search')
            if cancel then Sim.step(w,{S.command(w,units[1],'hold',{})})
            else units[1].hp=0;Sim.step(w,{}) end
            local clone=Sim.restore(Sim.snapshot(w))
            for tick=1,1600 do
                Sim.step(w,{});Sim.step(clone,{})
                if tick%100==0 then assert(Sim.serializeCanonical(w)==Sim.serializeCanonical(clone));S.clearance(w) end
            end
            for i=2,#units do assert(units[i].x>F.center(32),'follower stranded after leader left') end
        end
    end)
    -- Two opposing radius-160 vehicles require 640 subunits across: a two-cell
    -- (512) gap cannot pass them side by side without breaking hard clearance.
    for _,vehicles in ipairs({false,true}) do
    test('crowd',vehicles and 'vehicle counterflow retains orders and recovers when opposing traffic clears' or 'shipping shared routes finish infantry mixed 50 versus 50 counterflow',function()
        local w=R.world();S.wall(w,31,0,29);S.wall(w,31,vehicles and 33 or 32,63)
        local units,commands,goals={},{},{}
        for p=1,2 do for i=1,50 do
            local e=S.unit(w,({'worker','footman','crossbow',vehicles and 'enforcer' or 'associate'})[(i-1)%4+1],p,
                (p==1 and 12 or 42)+(i-1)%10,24+math.floor((i-1)/10))
            -- Arrival is a navigation test; early arrivals may auto-acquire the
            -- opposing queue. Keep combat from deleting the bodies being measured.
            e.hp=1000000;e.maxHp=e.hp
            units[#units+1]=e
            commands[#commands+1]=S.command(w,e,'move',{x=F.center(p==1 and 48 or 16),y=F.center(30),group=1},i)
        end end
        Sim.step(w,commands)
        for _,e in ipairs(units) do goals[e.id]={x=e.order.px or F.center(e.order.x),y=e.order.py or F.center(e.order.y)} end
        local finished=false;local arrived={}
        for tick=1,6000 do
            local release={}
            if vehicles and tick==1500 then
                for _,e in ipairs(units) do if e.owner==1 then
                    release[#release+1]=S.command(w,e,'move',{x=F.center(18),y=F.center(48),group=2},w.players[1].sequence+#release+1)
                end end
            end
            Sim.step(w,release)
            if #release>0 then for _,e in ipairs(units) do if e.owner==1 then arrived[e.id]=nil;goals[e.id]={x=e.order.px or F.center(e.order.x),y=e.order.py or F.center(e.order.y)} end end end
            if tick%20==0 then S.clearance(w) end
            local done=true
            for _,e in ipairs(units) do
                assert(not e.lastOrderFailure,'shared route abandoned '..e.id..' '..e.kind..' tick'..w.tick..' at '..(e.x/256)..','..(e.y/256)..' reason '..tostring(e.lastOrderFailure))
                local g=goals[e.id]
                if e.order.kind=='stop' and F.distance2(e.x,e.y,g.x,g.y)<=256^2 then arrived[e.id]=true end
                if not arrived[e.id] then done=false end
            end
            if done then finished=true;print('SHARED COUNTERFLOW arrived at tick '..w.tick);break end
        end
        if not finished then for _,e in ipairs(units) do if not arrived[e.id] then print(string.format('PENDING %d %s owner%d %.2f,%.2f goal%.2f,%.2f wait%d path%d/%d search%s alive%s blocked%s',e.id,e.kind,e.owner,e.x/256,e.y/256,goals[e.id].x/256,goals[e.id].y/256,e.waitTicks or 0,e.pathIndex,#e.path,tostring(w.searches[e.id]~=nil),tostring(e.alive),tostring(e.blockedReason))) end end end
        assert(finished,'shared routes deadlocked mixed counterflow')
    end)
    end
    test('simulation','shared searches revalidate after terrain changes',function()
        local w,units=R.wallGroup(12)
        S.wall(w,25,14,40)
        for tick=1,1800 do Sim.step(w,{});if tick%20==0 then S.clearance(w) end end
        for _,e in ipairs(units) do assert(e.x>F.center(32) and not e.lastOrderFailure,'stale terrain route stranded a follower') end
    end)
end
return R
