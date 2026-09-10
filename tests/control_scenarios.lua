local Sim=require('src.sim')
local C=require('tests.fixture_content')
local Maps=require('src.maps')
local Codec=require('src.sim.codec')
local F=require('src.sim.fixed')
local G=require('src.sim.geometry')
local S={}
function S.world(size)
    local m=Maps.create('controls',size or 48);m.resources={};m.camps={}
    local w=Sim.create({seed=17,players={{faction='bastion'},{faction='bastion'}}},C,m)
    for _,id in ipairs(w.order) do local e=w.entities[id];if e.category=='unit' then e.alive=false end end
    return w
end
function S.unit(w,kind,owner,x,y)
    local d=w.content.units[kind];local id=w.nextId;w.nextId=id+1
    local e={id=id,kind=kind,owner=owner,x=F.center(x),y=F.center(y),category='unit',alive=true,hp=d.hp,maxHp=d.hp,size=1,cooldown=0,
        path={},pathIndex=1,order={kind='stop'},orders={},lastCombat=-1000}
    w.entities[id]=e;w.order[#w.order+1]=id;return e
end
function S.command(w,e,kind,args,sequence)
    args=Codec.copy(args or {});args.entity=e.id
    return {tick=w.tick+1,player=e.owner,sequence=sequence or w.players[e.owner].sequence+1,kind=kind,args=args}
end
function S.clearance(w)
    local units={}
    for _,id in ipairs(w.order) do local e=w.entities[id];if e.alive and e.category=='unit' then
        assert(G.terrain(w,e.x,e.y,G.radius(w,e)),'terrain clearance unit '..id..' tick '..w.tick)
        for _,other in ipairs(units) do local r=G.separation(w,e,other)
            assert(F.distance2(e.x,e.y,other.x,other.y)>=r*r,'body overlap '..id..'/'..other.id..' tick '..w.tick)
        end
        units[#units+1]=e
    end end
end
function S.wall(w,x,top,bottom)
    for y=top,bottom do w.map.blocked[y*w.map.width+x+1]=true;w.blocked[y*w.map.width+x+1]=true end
    w.navVersion=w.navVersion+1
end
function S.crowd(n,choke,opposing,mixed)
    local w=S.world(64);local units={};local commands={};local seq={0,0}
    if choke then S.wall(w,31,0,29);S.wall(w,31,32,63) end
    for side=1,opposing and 2 or 1 do
        for i=1,n do
            local x=side==1 and 12+(i-1)%10 or 42+(i-1)%10;local y=24+math.floor((i-1)/10)
            local kind=mixed and ({'worker','shield','siege','crossbow','beast'})[(i-1)%5+1] or 'worker';local e=S.unit(w,kind,side,x,y);units[#units+1]=e;seq[side]=seq[side]+1
            commands[#commands+1]=S.command(w,e,'move',{x=F.center(side==1 and 48 or 16),y=F.center(30),group=1},seq[side])
        end
    end
    Sim.step(w,commands)
    local reached={}
    for _,e in ipairs(units) do reached[e.id]={x=F.center(e.order.x),y=F.center(e.order.y)} end
    for tick=1,6000 do
        Sim.step(w,{})
        if tick%20==0 then S.clearance(w) end
        assert(w.metrics.pathExpansions<=w.content.rules.pathBudget and w.metrics.directChecks<=w.content.rules.directPathBudget)
        local done=true
        for _,e in ipairs(units) do
            local goal=reached[e.id]
            if e.order.kind~='stop' or F.distance2(e.x,e.y,goal.x,goal.y)>256^2 then done=false end
            assert(not e.lastOrderFailure,'abandoned destination '..e.id..': '..tostring(e.lastOrderFailure))
        end
        if done then print('ARRIVAL '..n..(opposing and 'x2' or '')..' '..(choke and 'choke' or 'open')..' ticks='..w.tick);return w end
    end
    local pending={}
    for _,e in ipairs(units) do local g=reached[e.id];if e.order.kind~='stop' or F.distance2(e.x,e.y,g.x,g.y)>256^2 then pending[#pending+1]=e.id..' at '..math.floor(e.x/256)..','..math.floor(e.y/256)..' goal '..math.floor(g.x/256)..','..math.floor(g.y/256)..' wait '..(e.waitTicks or 0) end end
    error('arrival timeout: '..table.concat(pending,'; '))
end
-- How far a unit actually walks, divided by the straight-line distance it needed to
-- cover. Before path smoothing this was never measured, so a route could have regressed
-- into a staircase of 45-degree hops and every crowd test would still have passed: they
-- assert that everyone arrives, never that they walked anything like a sensible line.
function S.travel(w,e,goalX,goalY)
    local startX,startY=e.x,e.y
    local walked=0
    local last=w.tick
    for _=1,4000 do
        local px,py=e.x,e.y
        Sim.step(w,{})
        walked=walked+math.floor(math.sqrt((e.x-px)^2+(e.y-py)^2)+.5)
        if e.order.kind=='stop' then break end
        last=w.tick
    end
    local direct=math.floor(math.sqrt((goalX-startX)^2+(goalY-startY)^2)+.5)
    return walked,direct,last
end
function S.register(test)
    for _,n in ipairs({1,10,50,100}) do test('crowd','open destination '..n,function() S.crowd(n,false) end) end
    -- Open ground: one unit, nothing in the way, a diagonal that A* has to express as a
    -- staircase of cell steps. Walking that staircase literally costs about 8% over the
    -- straight line and, far worse, looks like it. Smoothing should put this within a
    -- couple of percent of the direct distance.
    test('crowd','a clear route is walked as a straight line',function()
        local w=S.world(64)
        local e=S.unit(w,'shield',1,10,10)
        local gx,gy=F.center(40),F.center(28)
        Sim.step(w,{S.command(w,e,'move',{x=gx,y=gy})})
        local walked,direct=S.travel(w,e,gx,gy)
        assert(e.order.kind=='stop','the unit never arrived')
        local ratio=walked*100/direct
        print('STRAIGHTNESS open diagonal: walked '..walked..' direct '..direct..' ratio '..string.format('%.3f',ratio/100))
        assert(ratio<=104,'a clear diagonal was walked '..string.format('%.1f',ratio-100)..'% longer than the straight line')
    end)
    -- Around a real obstacle the route is allowed to be longer, but it must bend at the
    -- obstacle rather than everywhere: a wall with a gap should cost well under a third
    -- over the direct line.
    test('crowd','a route around a wall bends only at the wall',function()
        local w=S.world(64)
        S.wall(w,26,0,26);S.wall(w,26,30,63)
        local e=S.unit(w,'shield',1,12,28)
        local gx,gy=F.center(44),F.center(28)
        Sim.step(w,{S.command(w,e,'move',{x=gx,y=gy})})
        local walked,direct=S.travel(w,e,gx,gy)
        assert(e.order.kind=='stop','the unit never got past the wall')
        local ratio=walked*100/direct
        print('STRAIGHTNESS wall gap: walked '..walked..' direct '..direct..' ratio '..string.format('%.3f',ratio/100))
        assert(ratio<=130,'a route through a wall gap was '..string.format('%.1f',ratio-100)..'% longer than the straight line')
    end)
    -- A building dropped across a route that is already under way. The next waypoint is
    -- still walkable, so the old code noticed nothing until the unit reached the
    -- obstacle and spent ten ticks stuck; the finished path is now re-checked when the
    -- navigation set changes.
    test('crowd','a wall built across a route in progress is noticed at once',function()
        local w=S.world(64)
        local e=S.unit(w,'shield',1,10,30)
        local gx,gy=F.center(50),F.center(30)
        Sim.step(w,{S.command(w,e,'move',{x=gx,y=gy})})
        for _=1,20 do Sim.step(w,{}) end
        local before=Codec.copy(e.path)
        S.wall(w,30,20,40)
        Sim.step(w,{})
        local changed=#e.path~=#before or w.searches[e.id]~=nil
        assert(changed,'the route was not re-planned on the tick the wall appeared')
        local walked,direct=S.travel(w,e,gx,gy)
        assert(e.order.kind=='stop','the unit never reached its destination past the new wall')
        assert(walked>0 and direct>0)
    end)
    for _,n in ipairs({5,20,100}) do test('crowd','chokepoint '..n,function() S.crowd(n,true) end) end
    test('crowd','20 mixed sizes and speeds',function() S.crowd(20,true,false,true) end)
    test('crowd','50 versus 50 counterflow',function() S.crowd(50,true,true) end)
    test('crowd','Hold blocker preserves pending order and death releases passage',function()
        local w=S.world(64);S.wall(w,31,0,29);S.wall(w,31,31,63)
        local e=S.unit(w,'worker',1,28,30);local blocker=S.unit(w,'worker',1,31,30);blocker.order={kind='hold'}
        Sim.step(w,{S.command(w,e,'move',{x=F.center(35),y=F.center(30)})})
        for _=1,200 do Sim.step(w,{});S.clearance(w) end
        assert(e.order.kind=='move' and e.x<F.center(31) and not e.lastOrderFailure)
        assert(blocker.x==F.center(31) and blocker.y==F.center(30))
        blocker.hp=0;Sim.step(w,{})
        for _=1,500 do Sim.step(w,{}) end
        assert(e.order.kind=='stop' and e.x==F.center(35))
    end)
    test('crowd','stationary ally yields and midway reversal crosses back',function()
        local w=S.world(64);S.wall(w,31,0,29);S.wall(w,31,32,63)
        local e=S.unit(w,'worker',1,27,31);local blocker=S.unit(w,'worker',1,31,31)
        Sim.step(w,{S.command(w,e,'move',{x=F.center(35),y=F.center(31)})})
        local turned=false
        for _=1,700 do
            local commands={}
            if not turned and e.x>=F.center(31) then commands={S.command(w,e,'move',{x=F.center(25),y=F.center(31)})};turned=true end
            Sim.step(w,commands);S.clearance(w)
        end
        assert(turned and e.x==F.center(25) and e.order.kind=='stop')
        assert(F.distance2(blocker.x,blocker.y,F.center(31),F.center(31))<=256^2)
    end)
    test('crowd','navigation lab U, concavity, forest, doorway and corridor',function()
        local routes={{32,10,32,20},{47,12,51,20},{8,40,29,52},{8,20,8,27},{26,30,47,30}}
        for _,r in ipairs(routes) do
            local map=Maps.create('movement_lab');local w=Sim.create({seed=3,players={{faction='bastion'},{faction='bastion'}}},C,map)
            for _,id in ipairs(w.order) do if w.entities[id].category=='unit' then w.entities[id].alive=false end end
            local e=S.unit(w,'worker',1,r[1],r[2])
            Sim.step(w,{S.command(w,e,'move',{x=F.center(r[3]),y=F.center(r[4])})})
            for _=1,1800 do Sim.step(w,{});S.clearance(w) end
            assert(e.order.kind=='stop' and not e.lastOrderFailure and e.x==F.center(r[3]) and e.y==F.center(r[4]),'lab route failed '..table.concat(r,','))
        end
    end)
    test('determinism','congestion snapshot and queued continuation',function()
        local w=S.world(64);S.wall(w,31,0,29);S.wall(w,31,32,63);local commands={}
        for i=1,20 do local e=S.unit(w,'worker',1,23+(i-1)%4,28+math.floor((i-1)/4));commands[#commands+1]=S.command(w,e,'move',{x=F.center(40),y=F.center(30)},i) end
        Sim.step(w,commands)
        local e=w.entities[w.order[#w.order]];Sim.step(w,{S.command(w,e,'move',{x=F.center(20),y=F.center(30),append=true})})
        for _=1,80 do Sim.step(w,{}) end
        local clone=Sim.restore(Codec.decode(Codec.encode(Sim.snapshot(w))))
        for _=1,700 do Sim.step(w,{});Sim.step(clone,{});assert(Sim.serializeCanonical(w)==Sim.serializeCanonical(clone)) end
    end)
    test('soak','100 units seeded command abuse over 10000 ticks',function()
        local Rng=require('src.sim.rng');local rng=Rng.create(90210);local w=S.world(64);local units={}
        for i=1,100 do units[i]=S.unit(w,'worker',1,10+(i-1)%10,12+math.floor((i-1)/10)) end
        local initialMemory,finalMemory
        for tick=1,10000 do
            local commands={}
            if tick%17==1 then
                local e=units[Rng.range(rng,1,#units)];local kind=tick%7==1 and 'hold' or tick%5==1 and 'stop' or 'move'
                commands={S.command(w,e,kind,{x=F.center(Rng.range(rng,8,53)),y=F.center(Rng.range(rng,8,53))})}
            end
            Sim.step(w,commands);assert(w.metrics.pathExpansions<=C.rules.pathBudget and w.metrics.directChecks<=C.rules.directPathBudget)
            if tick%100==0 then S.clearance(w) end
            if tick==5000 then collectgarbage('collect');initialMemory=collectgarbage('count') end
        end
        collectgarbage('collect');finalMemory=collectgarbage('count')
        assert(finalMemory-initialMemory<4096,'unbounded retained memory in command soak')
        print(string.format('SOAK 10000 ticks, retained heap at 5000/10000: %.0f / %.0f KiB',initialMemory,finalMemory))
    end)
    test('performance','240 active units over 10000 ticks',function()
        local w=S.world(64);local units={};local times={};local attacks=0;local moved=0
        for p=1,2 do for i=1,120 do
            local e=S.unit(w,i%3==0 and 'crossbow' or 'shield',p,(p==1 and 16 or 34)+(i-1)%10,20+math.floor((i-1)/10))
            e.hp=1000000;e.maxHp=e.hp;units[#units+1]=e
        end end
        local ticks=S.benchmarkTicks or 10000;assert(ticks>=2000 and ticks%1000==0,'benchmark ticks must be a multiple of 1000, at least 2000')
        local stopProfile=S.profile and require('tests.sim_profile').start(S.profile)
        local memory={}
        for tick=1,ticks do
            local commands={}
            if tick%400==1 or tick%400==301 then
                local seq={w.players[1].sequence,w.players[2].sequence};local attacking=tick%400==1
                for _,e in ipairs(units) do
                    seq[e.owner]=seq[e.owner]+1
                    commands[#commands+1]=S.command(w,e,attacking and 'attack_move' or 'move',{x=F.center(attacking and (e.owner==1 and 33 or 29) or (e.owner==1 and 20 or 42)),y=F.center(26),group=tick},seq[e.owner])
                end
            end
            local x,y=units[1].x,units[1].y;local start=love.timer.getTime();Sim.step(w,commands);times[#times+1]=(love.timer.getTime()-start)*1000
            if units[1].x~=x or units[1].y~=y then moved=moved+1 end
            for _,event in ipairs(w.events) do if event.kind=='attack' then attacks=attacks+1 end end
            assert(w.metrics.pathExpansions<=C.rules.pathBudget and w.metrics.directChecks<=C.rules.directPathBudget)
            if tick%1000==0 then collectgarbage('collect');memory[#memory+1]=collectgarbage('count');S.clearance(w) end
        end
        if stopProfile then stopProfile() end
        table.sort(times);local p95=times[math.ceil(#times*.95)]
        local middle=memory[math.ceil(#memory/2)];local last=memory[#memory]
        local report=string.format('240 live mobile units, 2 players; %d ticks; 300 attack-move ticks / 100 retreat ticks per cycle; high HP keeps population constant\nSim.step p50 %.3f ms; p95 %.3f ms; max %.3f ms; attacks %d; lead unit moving ticks %d\nRetained Lua heap at warmup/midpoint/end %.0f / %.0f / %.0f KiB\nIncludes command application, paths, local movement, visibility and combat; excludes rendering, bots, transport and replay encoding.\n',ticks,times[math.ceil(#times*.5)],p95,times[#times],attacks,moved,memory[1],middle,last)
        local file=assert(io.open('artifacts/control-performance.txt','wb'));file:write(report);file:close();print(report)
        assert(attacks>100 and moved>100,'benchmark did not exercise active movement and combat')
        assert(last-middle<4096,'retained heap growth exceeds 4 MiB')
        local budget=S.perfBudget or 10
        assert(p95<budget,string.format('active simulation exceeds %g ms p95 target (%.3f ms)',budget,p95))
    end)
end
return S
