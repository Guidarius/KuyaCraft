local Sim=require('src.sim')
local F=require('src.sim.fixed')
local Rng=require('src.sim.rng')
local Codec=require('src.sim.codec')
local Content=require('tests.fixture_content')
local Maps=require('src.maps')
local Hash=require('src.hash')
local Replay=require('src.replay')
local Lock=require('src.net.lockstep')
local T={}
local function eq(a,b,message) assert(a==b,(message or 'values differ')..': '..tostring(a)..' != '..tostring(b)) end
local function fails(fn) local ok=pcall(fn);assert(not ok,'expected failure') end
local function world(size)
    local m=Maps.create('test',size or 16);m.resources={};m.camps={}
    return Sim.create({seed=12345,players={{faction='bastion'},{faction='wild'}}},Content,m)
end
local function step(w,n,commands) for i=1,n do Sim.step(w,i==1 and (commands or {}) or {}) end end
local function command(w,p,kind,e,args,sequence)
    args=args or {};args.entity=e
    return {tick=w.tick+1,player=p,sequence=sequence or w.players[p].sequence+1,kind=kind,args=args}
end
local function find(w,p,kind) for _,id in ipairs(w.order) do local e=w.entities[id];if e.owner==p and e.kind==kind then return e end end end
local tests={}
local function test(suite,name,fn) tests[#tests+1]={suite=suite,name=name,fn=fn} end
for _,case in ipairs({'queues','construction','combat','fog','minimap','lobby'}) do test(case=='lobby' and 'network' or 'simulation','UI contract: '..case,function() require('tests.ui_contracts')[case]() end) end
test('unit','context-sensitive command cards',function() require('tests.command_card').context() end)
test('unit','command costs and prerequisites',function() require('tests.command_card').availability() end)
require('tests.balance').register(test)
require('tests.controls').register(test)
require('tests.control_scenarios').register(test)
require('tests.maps').register(test)
test('balance','new-profile route report',function() require('tests.balance_scenarios').routes() end)
test('balance','new-profile mirror match',function() require('tests.balance_scenarios').match(true) end)
test('balance','new-profile asymmetric match',function() require('tests.balance_scenarios').match(false) end)
test('balance','new-profile active performance',function() require('tests.balance_scenarios').performance() end)
test('unit','filtered cosmetic feedback',function() require('tests.feedback').run() end)
test('unit','PRNG golden sequence and seed bounds',function()
    local r=Rng.create(1)
    for _,n in ipairs({16807,282475249,1622650073,984943658,1144108930}) do eq(Rng.next(r),n) end
    fails(function() Rng.create(0) end)
    for _=1,1000 do local n=Rng.range(r,-3,8);assert(n>=-3 and n<=8) end
end)
test('unit','fixed arithmetic rounding and bounds',function()
    eq(F.mulDiv(-5,3,2),-8);eq(F.mulDiv(7,3,2),10)
    fails(function() F.mulDiv(F.MAX_EXACT,2,1) end)
    fails(function() F.check(0/0) end);fails(function() F.check(1.1) end);eq(F.center(2),640)
end)
test('unit','codec canonical order and non-executable decoding',function()
    local a={b=2,a={1,true,'x\0y'}};local b={};b.a={1,true,'x\0y'};b.b=2
    eq(Codec.encode(a),Codec.encode(b));eq(Codec.encode(Codec.decode(Codec.encode(a))),Codec.encode(a))
    fails(function() Codec.decode('return os.execute("bad")') end)
    fails(function() Codec.decode('s99:x') end);fails(function() Codec.decode('d2:s1:an1:s1:an2:') end)
    fails(function() Codec.encode({n=1.5}) end);fails(function() Codec.decode('n01:') end)
    local cyclic={};cyclic.self=cyclic;fails(function() Codec.encode(cyclic) end)
end)
test('unit','content references and definition isolation',function()
    assert(require('src.content_validate')(Content));local before=Codec.encode(Content)
    local w=world();step(w,30);eq(Codec.encode(Content),before)
end)
test('simulation','command ownership, duplicates, invalid positions',function()
    local w=world();local e=find(w,1,'worker');local enemy=find(w,2,'worker')
    step(w,1,{command(w,1,'move',enemy.id,{x=0,y=0})});eq(w.events[1].kind,'rejected')
    step(w,1,{command(w,1,'move',e.id,{x=-1,y=0})});eq(w.events[1].kind,'rejected')
    step(w,1,{command(w,1,'toggle',w.players[1].hero,{},w.players[1].sequence)});eq(w.events[1].kind,'rejected')
end)
test('simulation','pathfinding obeys walls and expansion budget',function()
    local w=world(20);local e=find(w,1,'worker');local Path=require('src.sim.path')
    local sy=F.cell(e.y)
    for y=0,8 do w.blocked[Path.key(w.map,8,y)]=true end
    step(w,1,{command(w,1,'move',e.id,{x=F.center(10),y=F.center(sy)})})
    for _=1,400 do step(w,1);assert(w.metrics.pathExpansions<=Content.rules.pathBudget);assert(not w.blocked[Path.key(w.map,F.cell(e.x),F.cell(e.y))]) end
    eq(F.cell(e.x),10);eq(F.cell(e.y),sy)
end)
test('simulation','unreachable search terminates',function()
    local w=world(20);local e=find(w,1,'worker');local Path=require('src.sim.path')
    for y=0,w.map.height-1 do w.blocked[Path.key(w.map,8,y)]=true end
    step(w,1,{command(w,1,'move',e.id,{x=F.center(10),y=F.center(5)})});step(w,500)
    eq(e.lastOrderFailure,'unreachable');assert(not w.searches[e.id])
end)
test('simulation','an extractor delivers a mine and then depletes it',function()
    local m=Maps.create('extract',20);m.resources={{x=6,y=6,resource='gold',amount=16,size=3}};m.camps={}
    local w=Sim.create({seed=1,players={{faction='bastion'},{faction='wild'}}},Content,m)
    local e=find(w,1,'worker');local node=find(w,0,'resource');local before=w.players[1].resources.gold
    local cost=Content.buildings.extractor.cost.gold
    step(w,1,{command(w,1,'build',e.id,{building='extractor',x=6,y=6})})
    local site=find(w,1,'extractor');assert(site,'extractor rejected on a mine')
    -- Sixteen gold is two payloads: the mine empties, both are delivered, and the
    -- carriers that were paid for are the only ones ever emitted.
    local depleted=false
    for _=1,1200 do for _,ev in ipairs(Sim.step(w,{})) do if ev.kind=='depleted' then depleted=true end end end
    assert(depleted,'mine never depleted');assert(not node.alive)
    eq(w.players[1].resources.gold,before-cost+16)
    for _,id in ipairs(w.order) do assert(w.entities[id].category~='carrier' or not w.entities[id].alive) end
end)
test('simulation','build, production, cancellation, population reservation',function()
    local w=world(24);local worker=find(w,1,'worker')
    step(w,1,{command(w,1,'build',worker.id,{building='barracks',x=7,y=4})})
    local b=find(w,1,'barracks');assert(b,'building rejected')
    assert(w.blocked[4*w.map.width+8]);step(w,400);eq(b.remaining,0)
    step(w,1,{command(w,1,'recruit',b.id,{unit='shield'})});eq(#b.queue,1)
    local pop=Sim.population(w,1);step(w,100);eq(#b.queue,0);eq(Sim.population(w,1),pop)
    local gold=w.players[1].resources.gold
    step(w,1,{command(w,1,'recruit',b.id,{unit='crossbow'})});step(w,1,{command(w,1,'cancel',b.id)})
    eq(w.players[1].resources.gold,gold)
end)
test('simulation','nothing is built on a road, except an extractor on its own mine',function()
    local Path=require('src.sim.path')
    local m=Maps.create('road',24);m.resources={};m.camps={};m.unbuildable={}
    -- Across the war hall's first row, whatever footprint size the fixture content gives it.
    for x=0,23 do m.unbuildable[Path.key(m,x,4)]=true end
    local w=Sim.create({seed=12345,players={{faction='bastion'},{faction='wild'}}},Content,m);local worker=find(w,1,'worker')
    local valid,reason=Sim.placement(Sim.view(w,1),Content,'barracks',7,4)
    assert(not valid,'a war hall was allowed on a road');eq(reason,'Cannot build on a road')
    step(w,1,{command(w,1,'build',worker.id,{building='barracks',x=7,y=4})})
    eq(w.events[1].kind,'rejected');assert(not find(w,1,'barracks'));assert(Path.walkable(w,7,4),'a road must stay walkable')
    -- A road may run up to and across a mine's footprint; the extractor still goes on it.
    local e=Maps.create('extract',20);e.resources={{x=6,y=6,resource='gold',amount=16,size=3}};e.camps={};e.unbuildable={}
    for x=0,19 do e.unbuildable[Path.key(e,x,7)]=true end
    local x=Sim.create({seed=1,players={{faction='bastion'},{faction='wild'}}},Content,e);local builder=find(x,1,'worker')
    step(x,1,{command(x,1,'build',builder.id,{building='extractor',x=6,y=6})})
    assert(find(x,1,'extractor'),'extractor refused on a mine a road crosses')
end)
test('simulation','exclusive upgrades and revival retention',function()
    local w=world(24);local hero=w.entities[w.players[1].hero];hero.xp=400
    step(w,1,{command(w,1,'upgrade',hero.id,{milestone=1,choice=2})});eq(hero.upgrades[1],2)
    step(w,1,{command(w,1,'upgrade',hero.id,{milestone=1,choice=1})});eq(hero.upgrades[1],2)
    step(w,1,{command(w,1,'upgrade',hero.id,{milestone=2,choice=2})});eq(hero.maxHp,780)
    hero.alive=false;hero.hp=0;step(w,1,{command(w,1,'revive',hero.id)});step(w,200)
    assert(hero.alive);eq(hero.hp,hero.maxHp);eq(hero.upgrades[1],2);eq(hero.upgrades[2],2)
end)
test('simulation','fog filters enemies and rejects hidden targeting',function()
    local w=world(40);local enemy=w.entities[w.players[2].hero];assert(not Sim.visible(w,1,enemy))
    for _,e in ipairs(Sim.view(w,1).entities) do assert(e.id~=enemy.id) end
    step(w,1,{command(w,1,'attack',w.players[1].hero,{target=enemy.id})});eq(w.events[1].kind,'rejected')
end)
test('simulation','simultaneous combat and HQ draw',function()
    local w=world(24);local a=w.entities[w.players[1].hero];local b=w.entities[w.players[2].hero]
    a.x=2560;a.y=2560;b.x=2816;b.y=2560;step(w,1);a.attack=nil;b.attack=nil;a.nextCommitTick=nil;b.nextCommitTick=nil;a.hp=1;b.hp=1
    step(w,5);assert(not a.alive and not b.alive,'both heroes should die')
    w.entities[w.players[1].hq].hp=0;w.entities[w.players[2].hq].hp=0;step(w,1);eq(w.result.winner,0)
end)
test('determinism','snapshot preserves pending paths and continuation',function()
    local w=world(24);w.content.rules.directPathBudget=0;local e=find(w,1,'worker');step(w,1,{command(w,1,'move',e.id,{x=4000,y=3500})})
    local clone=Sim.restore(Codec.decode(Codec.encode(Sim.snapshot(w))))
    for _=1,150 do step(w,1);step(clone,1);eq(Sim.serializeCanonical(w),Sim.serializeCanonical(clone)) end
end)
test('determinism','changed command changes canonical state',function()
    local a,b=world(),world();local e=find(a,1,'worker')
    step(a,1,{command(a,1,'move',e.id,{x=0,y=0})});step(b,1);assert(Hash.bytes(Sim.serializeCanonical(a))~=Hash.bytes(Sim.serializeCanonical(b)))
end)
test('determinism','replay round trip and incompatible header rejection',function()
    local w=world(20);local r=Replay.create(w.config,Content,w.map)
    for _=1,120 do Sim.step(w,{});Replay.record(r,w,{}) end
    Replay.write('artifacts/fixture-sample.replay',r)
    local loaded=Replay.read('artifacts/fixture-sample.replay',Content);local b=Sim.create(loaded.header.config,Content,loaded.header.map)
    for _,frame in ipairs(loaded.frames) do Sim.step(b,frame.commands) end
    eq(Sim.serializeCanonical(w),Sim.serializeCanonical(b))
    loaded.header.runtime='wrong';Replay.write('artifacts/incompatible.replay',loaded);fails(function() Replay.read('artifacts/incompatible.replay',Content) end)
end)
test('network','lockstep waits for empty frames and checks ownership',function()
    local l=Lock.create(2);assert(Lock.submit(l,1,1,{}));assert(not Lock.take(l));assert(Lock.submit(l,2,1,{}))
    eq(Lock.take(l).tick,1);assert(not Lock.submit(l,1,1,{}))
    local c={tick=2,player=1,sequence=1,kind='stop',args={entity=3}}
    assert(not Lock.submit(l,2,2,{c}));assert(Lock.submit(l,1,2,{c}));assert(Lock.submit(l,1,2,{c}));assert(not Lock.submit(l,1,2,{}))
end)
test('network','delayed, reordered, duplicate packets preserve frames',function()
    local l=Lock.create(2);local a,b=world(24),world(24);local packets={}
    for tick=1,100 do for p=1,2 do packets[#packets+1]={p=p,tick=tick,commands={}} end end
    for i=#packets,1,-1 do local q=packets[i];if q.tick%2==1 then assert(Lock.submit(l,q.p,q.tick,q.commands)) end end
    for i=1,#packets do local q=packets[i];assert(Lock.submit(l,q.p,q.tick,q.commands)) end
    for i=1,100 do local f=assert(Lock.take(l));eq(f.tick,i);Sim.step(a,f.commands);Sim.step(b,{}) end
    eq(Sim.serializeCanonical(a),Sim.serializeCanonical(b))
end)
test('network','ENet reliable loopback',function()
    local enet=require('enet');local server=assert(enet.host_create('127.0.0.1:*',1,1))
    local address=server:get_socket_address();local client=assert(enet.host_create(nil,1,1));local peer=client:connect(address,1)
    local deadline=love.timer.getTime()+5;local received=false
    while love.timer.getTime()<deadline and not received do
        local e=client:service(0);if e and e.type=='connect' then peer:send('LoveRTS-network-proof',0,'reliable') end
        local s=server:service(0);if s and s.type=='receive' then eq(s.data,'LoveRTS-network-proof');received=true end
        client:flush();server:flush();love.timer.sleep(0.001)
    end
    peer:disconnect_now();assert(received,'ENet loopback timed out')
end)
test('simulation','new obstacle cancels stale incremental destination',function()
    local w=world(24);local e=find(w,1,'worker');local P=require('src.sim.path')
    w.content.rules.pathBudget=1;w.content.rules.directPathBudget=0
    step(w,1,{command(w,1,'move',e.id,{x=F.center(12),y=F.center(9)})})
    assert(w.searches[e.id])
    w.blocked[P.key(w.map,12,9)]=true;w.navVersion=w.navVersion+1
    step(w,10);assert(not w.searches[e.id]);eq(e.lastOrderFailure,'destination blocked')
end)
test('simulation','construction completes and releases worker',function()
    local w=world(24);local worker=find(w,1,'worker')
    step(w,1,{command(w,1,'build',worker.id,{building='barracks',x=7,y=4})})
    local clone=Sim.restore(Sim.snapshot(w))
    step(w,400);step(clone,400)
    eq(worker.order.kind,'stop');eq(Sim.serializeCanonical(w),Sim.serializeCanonical(clone))
end)
-- A site is worked by one worker. Sending a second one takes the site over, and the first used
-- to keep its build order for ever: standing beside a building it no longer worked on, and not
-- counted among idle workers, so it was lost to the player.
test('simulation','queued construction takes over only when it becomes active',function()
    local w=world(24);local workers={}
    for _,id in ipairs(w.order) do local e=w.entities[id];if e.owner==1 and e.kind=='worker' then workers[#workers+1]=e end end
    local first,second=workers[1],workers[2]
    step(w,1,{command(w,1,'build',first.id,{building='barracks',x=7,y=4})})
    local site=find(w,1,'barracks');assert(site)
    step(w,1,{command(w,1,'move',second.id,{x=15*256+128,y=15*256+128})})
    step(w,1,{command(w,1,'build',second.id,{target=site.id,append=true})})
    eq(site.builder,first.id);eq(first.order.kind,'build');eq(second.order.kind,'move')
    local clone=Sim.restore(Sim.snapshot(w));local transferred=false
    for _=1,800 do
        Sim.step(w,{});Sim.step(clone,{})
        if second.order.kind=='build' then
            transferred=true;eq(site.builder,second.id);eq(first.order.kind,'stop')
        end
    end
    assert(transferred,'queued builder never took over');eq(site.remaining,0)
    eq(Sim.serializeCanonical(w),Sim.serializeCanonical(clone))
    -- Hold does not finish by itself, so a build queued behind it must never release
    -- the active builder or steal the site, even while ticks continue.
    local v=world(24);local a=find(v,1,'worker');local b
    for _,id in ipairs(v.order) do local e=v.entities[id];if e.owner==1 and e.kind=='worker' and e.id~=a.id then b=e end end
    step(v,1,{command(v,1,'build',a.id,{building='barracks',x=7,y=4})})
    local target=find(v,1,'barracks')
    step(v,1,{command(v,1,'hold',b.id,{})})
    step(v,1,{command(v,1,'build',b.id,{target=target.id,append=true})})
    eq(target.builder,a.id);eq(a.order.kind,'build');eq(b.order.kind,'hold')
    step(v,800);eq(target.remaining,0);eq(b.order.kind,'hold')
end)
test('simulation','a site taken over releases the worker that held it',function()
    local w=world(24);local first,second
    for _,id in ipairs(w.order) do local e=w.entities[id]
        if e.owner==1 and e.kind=='worker' and e.alive then if not first then first=e elseif not second then second=e end end
    end
    step(w,1,{command(w,1,'build',first.id,{building='barracks',x=7,y=4})})
    local site;for _,id in ipairs(w.order) do local e=w.entities[id];if e.owner==1 and e.kind=='barracks' then site=e end end
    assert(site,'no construction site');step(w,40)
    step(w,1,{command(w,1,'build',second.id,{building='barracks',target=site.id})})
    eq(site.builder,second.id);eq(first.order.kind,'stop')
    step(w,600);eq(site.remaining,0)
end)
-- Work stops when nobody is assigned to a site. It is announced once, not every tick, and the
-- site stops reporting it as soon as someone takes the job.
test('simulation','a stopped site reports once and goes quiet when work resumes',function()
    local w=world(24);local first,second
    for _,id in ipairs(w.order) do local e=w.entities[id]
        if e.owner==1 and e.kind=='worker' and e.alive then if not first then first=e elseif not second then second=e end end
    end
    step(w,1,{command(w,1,'build',first.id,{building='barracks',x=7,y=4})})
    local site;for _,id in ipairs(w.order) do local e=w.entities[id];if e.owner==1 and e.kind=='barracks' then site=e end end
    step(w,40);assert(not site.stalled,'a site with a builder on its way reported itself stopped')
    first.alive=false;first.hp=0
    local stalls=0
    local function run(n) for _=1,n do for _,ev in ipairs(Sim.step(w,{})) do if ev.kind=='build_stalled' then stalls=stalls+1 end end end end
    run(60)
    eq(stalls,1);assert(site.stalled,'the site does not know that work stopped')
    local remaining=site.remaining;run(40);eq(site.remaining,remaining)
    Sim.step(w,{command(w,1,'build',second.id,{building='barracks',target=site.id})})
    run(60);eq(stalls,1);assert(not site.stalled,'the site still reports itself stopped')
    assert(site.remaining<remaining,'work did not resume')
end)
-- Whether your building has stopped is your own business: an enemy scouting it sees a site under
-- construction, not that nobody is working on it.
test('simulation','a stopped site is owner-only knowledge',function()
    local w=world(24);local worker=find(w,1,'worker')
    step(w,1,{command(w,1,'build',worker.id,{building='barracks',x=7,y=4})})
    local site=find(w,1,'barracks');assert(site,'no construction site')
    step(w,40);worker.alive=false;worker.hp=0;step(w,5)
    local mine,theirs
    for _,e in ipairs(Sim.view(w,1).entities) do if e.id==site.id then mine=e end end
    for _,e in ipairs(Sim.view(w,2).entities) do if e.id==site.id then theirs=e end end
    assert(mine and mine.stalled,'the owner cannot see that work stopped')
    if theirs then assert(theirs.stalled==nil,'an enemy can see that work stopped');assert(theirs.remaining>0,'an enemy cannot see the site at all') end
end)
-- A site can be destroyed under the worker building it. The worker has nothing left to do and
-- must be freed, rather than standing on an order pointing at rubble.
test('simulation','a worker is released when the site under it is destroyed',function()
    local w=world(24);local worker=find(w,1,'worker')
    step(w,1,{command(w,1,'build',worker.id,{building='barracks',x=7,y=4})})
    local site=find(w,1,'barracks');assert(site,'no construction site')
    step(w,40);eq(worker.order.kind,'build')
    -- Well past zero: a site being built gains health every tick from its own progress.
    site.hp=-1000;step(w,3)
    assert(not site.alive,'the site survived being destroyed');eq(worker.order.kind,'stop')
end)
-- Carriers are the gold on the road between an extractor and its drop-off. When a raid kills the
-- extractor, that gold is already out of the ground: the carriers keep walking the route they
-- were given and are paid on arrival. They used to stand there alive for the rest of the match,
-- holding gold nobody could collect and drawn on the minimap.
test('simulation','carriers finish their delivery when their extractor is destroyed',function()
    local m=Maps.create('extract',20);m.resources={{x=6,y=6,resource='gold',amount=1000000,size=3}};m.camps={}
    local w=Sim.create({seed=1,players={{faction='bastion'},{faction='wild'}}},Content,m)
    local worker=find(w,1,'worker')
    step(w,1,{command(w,1,'build',worker.id,{building='extractor',x=6,y=6})})
    local site=find(w,1,'extractor');assert(site,'extractor rejected on a mine')
    step(w,Content.buildings.extractor.buildTicks+300)
    local flying=0
    for _,id in ipairs(w.order) do local c=w.entities[id];if c.alive and c.category=='carrier' then flying=flying+1 end end
    assert(flying>0,'no carriers were on the road')
    local gold=w.players[1].resources.gold
    site.hp=-1000;step(w,400)
    assert(not site.alive,'the extractor survived')
    local left=0
    for _,id in ipairs(w.order) do local c=w.entities[id];if c.alive and c.category=='carrier' then left=left+1 end end
    eq(left,0,'carriers never arrived; '..flying..' were on the road')
    eq(w.players[1].resources.gold-gold,flying*(Content.rules.carrierPayload or 8),'gold on the road was not delivered')
    -- The dead extractor sends out no more.
    local after=w.players[1].resources.gold;step(w,200);eq(w.players[1].resources.gold,after)
end)
test('unit','state diagnostics identify subsystem paths',function()
    local differences=require('src.diagnostics').diff({tick=5,players={{gold=10}}},{tick=5,players={{gold=9}}})
    eq(#differences,1);eq(differences[1].path,'/players/1/gold')
end)
test('simulation','group destinations remain distinct and bodies respect clearance',function()
    local w=world(24);local commands={}
    for _,id in ipairs(w.order) do
        local e=w.entities[id]
        if e.owner==1 and e.category=='unit' then commands[#commands+1]=command(w,1,'move',id,{x=F.center(8),y=F.center(8)},#commands+1) end
    end
    step(w,1,commands)
    local goals={}
    for _,c in ipairs(commands) do local e=w.entities[c.args.entity];local key=e.order.x..','..e.order.y;assert(not goals[key]);goals[key]=true end
    for _=1,600 do
        step(w,1);require('tests.control_scenarios').clearance(w)
    end
    for _,c in ipairs(commands) do local e=w.entities[c.args.entity];eq(e.order.kind,'stop');assert(not e.lastOrderFailure) end
end)
test('simulation','authoritative checkpoint covers derived navigation state',function()
    -- w.blocked and the lane cache are excluded from Sim.serializeAuthoritative on
    -- the grounds that they derive from map.blocked plus the standing buildings,
    -- which the checkpoint does cover. Prove that across construction, depletion
    -- and destruction rather than asserting it in a comment.
    local Path=require('src.sim.path')
    local w=world(24)
    local builder=find(w,1,'worker')
    local function derived()
        eq(Codec.encode(w.blocked),Codec.encode(Sim.recomputeBlocked(w)),'w.blocked is not recomputable')
    end
    derived()
    -- Close enough to the worker that the footprint is inside its sight radius.
    step(w,1,{command(w,1,'build',builder.id,{building='barracks',x=7,y=6})})
    for _,event in ipairs(w.events) do assert(event.kind~='rejected','build rejected: '..tostring(event.reason)) end
    local site=find(w,1,'barracks');assert(site,'no construction site')
    derived();assert(w.blocked[Path.key(w.map,7,6)],'footprint did not block navigation')
    for _=1,400 do step(w,1);derived() end
    assert(site.remaining==0,'construction did not complete')
    site.hp=0;step(w,1);assert(not site.alive,'building survived zero health')
    derived();assert(not w.blocked[Path.key(w.map,7,6)],'destroyed footprint still blocks navigation')
    -- A checkpoint must still notice a real divergence in state it does cover.
    local a,b=world(24),world(24)
    eq(Sim.serializeAuthoritative(a),Sim.serializeAuthoritative(b))
    local mover=find(a,1,'worker');step(a,1,{command(a,1,'move',mover.id,{x=F.center(6),y=F.center(6)})});step(b,1)
    assert(Sim.serializeAuthoritative(a)~=Sim.serializeAuthoritative(b),'checkpoint missed a divergence')
end)
test('simulation','rally points direct production to a point and to a node',function() require('tests.order_scenarios').rally() end)
test('simulation','patrol walks its beat and turns at both ends',function() require('tests.order_scenarios').patrol() end)
test('simulation','follow keeps station, never acquires, and ends with its target',function() require('tests.order_scenarios').follow() end)
test('simulation','deliveries and kill tallies are authoritative',function() require('tests.order_scenarios').tallies() end)
test('simulation','new orders survive a recorded replay',function() require('tests.order_scenarios').replay() end)
test('simulation','a group move travels at the pace of its slowest member',function() require('tests.order_scenarios').formation() end)
test('simulation','an instant cast wards allies in its radius and starts a cooldown',function() require('tests.ability_scenarios').instant() end)
test('simulation','a targeted cast walks into range, damages once and really slows',function() require('tests.ability_scenarios').targeted() end)
test('simulation','moving before the cast point cancels it and costs nothing',function() require('tests.ability_scenarios').cancellation() end)
test('simulation','an area cast hits its circle and its burn ticks on a period',function() require('tests.ability_scenarios').area() end)
test('simulation','a skill shot hits the first unit on its line and stuns it',function() require('tests.ability_scenarios').skillshot() end)
test('simulation','a thrown shot travels, lands once and is recycled',function() require('tests.ability_scenarios').projectile() end)
test('simulation','casts are refused with a reason the player can act on',function() require('tests.ability_scenarios').rejections() end)
test('simulation','casts and statuses survive a snapshot identically',function() require('tests.ability_scenarios').snapshot() end)
test('simulation','an area effect resolves in world order, not arrival order',function() require('tests.ability_scenarios').ordering() end)
test('simulation','sight is blocked by terrain, buildings and forests',function() require('tests.vision_scenarios').run() end)
for _,case in ipairs({
    {'capture','a control point is captured by standing in it unopposed, and kept after leaving'},
    {'contest','an enemy in the circle freezes a capture, and a lone enemy unwinds it first'},
    {'hold','owning every control point for the full hold wins, not a tick sooner'},
    {'broken','losing a point cancels the countdown, and a new hold starts from nothing'},
    {'snapshot','control state survives a snapshot and is covered by checkpoints'},
    {'defeatedHolder','a holder that loses its headquarters loses, and its hold counts for nothing'},
    {'sameTick','a hold completing on the tick its owner\'s headquarters falls is not a control win'},
    {'capturerDies','a capture fades when its only capturing unit dies'},
    {'thirdPlayer','a third player holding every control point wins'},
    {'defeatedDoesNotContest','a defeated player\'s surviving unit does not contest a capture'}}) do
    test('simulation',case[2],function() require('tests.objective_scenarios')[case[1]]() end)
end
test('scenario','mirror bot match and replay',function() require('tests.scenarios').match(true) end)
test('scenario','asymmetric bot match and replay',function() require('tests.scenarios').match(false) end)
test('performance','240-unit four-player stress',function() require('tests.scenarios').performance() end)
test('unit','asset runtime catalog and frame selection',function() require('tests.asset_runtime').run() end)
function T.worker(options)
    local w=world(24);local worker=find(w,1,'worker');local output=assert(io.open(assert(options.output),'wb'))
    local schedule=tonumber(options.schedule);local credit,tick=0,0
    while tick<100000 do
        credit=credit+20
        while credit>=schedule and tick<100000 do
            credit=credit-schedule;tick=tick+1
            local commands={}
            if tick%100==1 then commands={command(w,1,'move',worker.id,{x=F.center(3+math.floor(tick/100)%5),y=F.center(8)})} end
            Sim.step(w,commands)
            if tick%100==0 then output:write(tick..' '..Hash.bytes(Sim.serializeCanonical(w))..'\n') end
        end
    end
    output:close();print('PASS worker: '..tick..' ticks at '..schedule..' FPS schedule');return 0
end
function T.run(options)
    if options['compare-left'] then return require('src.diagnostics').compareFiles(options['compare-left'],options['compare-right'],options.output) end
    if options['determinism-worker'] then return T.worker(options) end
    require('tests.control_scenarios').benchmarkTicks=tonumber(options['benchmark-ticks'])
    require('tests.control_scenarios').profile=options['profile-sim']
    -- Perf gates are budgets, not constants: slower reference hardware sets its own.
    local budget=tonumber(options['perf-budget']) or 10
    require('tests.control_scenarios').perfBudget=budget
    require('tests.balance_scenarios').perfBudget=budget
    local suite=options.test or 'all'
    assert(({all=true,balance=true,unit=true,simulation=true,determinism=true,network=true,scenario=true,performance=true,crowd=true,soak=true,quick=true})[suite],'unknown suite')
    -- 'quick' is unit+simulation in one process: no determinism or network child processes.
    local accepts=suite=='quick' and function(s) return s=='unit' or s=='simulation' end or function(s) return suite=='all' or s==suite end
    local passed,failed=0,0
    for _,item in ipairs(tests) do if accepts(item.suite) and (not options.filter or item.name:find(options.filter,1,true)) then
        local ok,err=xpcall(item.fn,debug.traceback)
        if ok then passed=passed+1;print('PASS '..item.name) else failed=failed+1;print('FAIL '..item.name..'\n'..err) end
    end end
    if options['self-test-failure'] then failed=failed+1;print('FAIL intentional runner failure') end
    print(string.format('RESULT %d passed, %d failed',passed,failed));return failed==0 and 0 or 1
end
return T
