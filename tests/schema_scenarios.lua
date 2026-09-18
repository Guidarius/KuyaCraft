-- Faction schema v2 (simulation version 20): what a faction declares about itself, and the
-- defaults that keep the fixture content playing exactly as before. Every scenario works on
-- a copy of the fixture so the shared definition is never touched.
local Sim=require('src.sim')
local F=require('src.sim.fixed')
local Codec=require('src.sim.codec')
local Maps=require('src.maps')
local Fixture=require('tests.fixture_content')
local validate=require('src.content_validate')
local M={}
local function eq(a,b,message) assert(a==b,(message or 'values differ')..': '..tostring(a)..' != '..tostring(b)) end
local function content() return Codec.copy(Fixture) end
local function world(C,size,resources,factions)
    local m=Maps.create('schema',size or 24);m.resources=resources or {};m.camps={}
    return Sim.create({seed=5,players=factions or {{faction='bastion'},{faction='wild'}}},C,m)
end
local function step(w,n,commands) for i=1,n do Sim.step(w,i==1 and (commands or {}) or {}) end end
local function command(w,p,kind,e,args)
    args=args or {};args.entity=e
    return {tick=w.tick+1,player=p,sequence=w.players[p].sequence+1,kind=kind,args=args}
end
local function find(w,p,kind) for _,id in ipairs(w.order) do local e=w.entities[id];if e.owner==p and e.kind==kind and e.alive then return e end end end
-- A finished building placed directly, the way tests/balance.lua does it.
local function building(w,kind,owner,x,y,remaining)
    local d=w.content.buildings[kind];local id=w.nextId;w.nextId=id+1
    local e={id=id,kind=kind,category='building',owner=owner,alive=true,x=F.center(x),y=F.center(y),size=d.size,hp=d.hp,maxHp=d.hp,remaining=remaining or 0,queue={},order={kind='stop'},orders={},path={},pathIndex=1,cooldown=0,lastCombat=-1000}
    w.entities[id]=e;w.order[#w.order+1]=id;w.navVersion=w.navVersion+1;w.blocked=Sim.recomputeBlocked(w);return e
end
local function rejected(events) for _,ev in ipairs(events) do if ev.kind=='rejected' then return ev.reason end end end

function M.validator()
    assert(validate(content()),'the fixture no longer validates')
    -- The v2 shape, with every new field, validates.
    local C=content()
    C.rules.resources={'gold','charge'};C.rules.supplyFromBuildings=true;C.rules.cancelRefundPercent=75
    C.buildings.depot={label='Depot',hp=100,size=1,sight=4,cost={gold=50,charge=10},buildTicks=20,supply=8,armor=1}
    C.buildings.barracks.produces={'shield'};C.buildings.barracks.requires={'depot'}
    C.units.shield.requires={'barracks'};C.units.shield.armor=2
    C.factions.keeps={label='Keeps',hq='hq',worker='worker',defeat='all_hq',supplyCap=200,buildings={'hq','depot','barracks'},
        starting={resources={gold=400,charge=0},units={'worker','worker'}}}
    assert(validate(C))
    -- Dangling references and unknown resources are refused, each with its own message.
    local function refuses(mutate,needle)
        local c=content();mutate(c)
        local ok,err=pcall(validate,c)
        assert(not ok,'accepted content that should be refused ('..needle..')')
        assert(tostring(err):find(needle,1,true),'wrong refusal for '..needle..': '..tostring(err))
    end
    refuses(function(c) c.buildings.barracks.requires={'chapel'} end,'unknown kind chapel')
    refuses(function(c) c.buildings.barracks.produces={'dragon'} end,'unknown kind dragon')
    refuses(function(c) c.units.shield.cost={gold=10,lumber=5} end,'unknown resource lumber')
    refuses(function(c) c.factions.bastion.defeat='never' end,'unknown defeat rule')
    refuses(function(c) c.factions.bastion.hq='chapel' end,'no headquarters building')
    refuses(function(c) c.factions.bastion.worker='shield' end,'not one')
    refuses(function(c) c.factions.bastion.starting={units={'dragon'}} end,'unknown kind dragon')
end

function M.supply()
    local C=content();C.rules.supplyFromBuildings=true;C.rules.supplyCap=20
    C.buildings.depot={label='Depot',hp=100,size=1,sight=4,cost={gold=50},buildTicks=20,supply=8}
    C.buildings.hq.supply=6;C.units.worker.food=4
    local w=world(C)
    eq(Sim.supplyCap(w,1),6,'the headquarters alone provides its own supply')
    eq(Sim.view(w,1).player.supplyCap,6,'the view reports the cap')
    -- A site under construction provides nothing; the finished depot does.
    local site=building(w,'depot',1,3,3,20)
    eq(Sim.supplyCap(w,1),6);site.remaining=0;eq(Sim.supplyCap(w,1),14)
    -- Three workers at four food and a hero at one: thirteen used against a cap of fourteen,
    -- so the next worker is refused until another depot finishes.
    local hq=find(w,1,'hq');w.players[1].resources.gold=100000
    eq(Sim.population(w,1),13)
    eq(rejected(Sim.step(w,{command(w,1,'recruit',hq.id,{unit='worker'})})),'cannot recruit')
    building(w,'depot',1,5,3);eq(Sim.supplyCap(w,1),20,'clamped at the rule ceiling')
    building(w,'depot',1,7,3);eq(Sim.supplyCap(w,1),20)
    assert(not rejected(Sim.step(w,{command(w,1,'recruit',hq.id,{unit='worker'})})),'refused below the cap')
    eq(Sim.population(w,1),17)
    eq(rejected(Sim.step(w,{command(w,1,'recruit',hq.id,{unit='worker'})})),'cannot recruit')
    -- The faction ceiling wins over the rule ceiling when it is lower.
    w.content.factions.bastion.supplyCap=15;eq(Sim.supplyCap(w,1),15)
    -- The flat rule is untouched for content that does not opt in.
    local legacy=world(content());eq(Sim.supplyCap(legacy,1),Fixture.rules.population)
end

function M.requires()
    local C=content();C.units.shield.requires={'tower'}
    local w=world(C);w.players[1].resources.gold=100000
    local hall=building(w,'barracks',1,3,3)
    eq(rejected(Sim.step(w,{command(w,1,'recruit',hall.id,{unit='shield'})})),'requirement missing')
    eq(Sim.missingRequirement(w,1,C.units.shield.requires),'tower')
    -- A tower still under construction does not count.
    local tower=building(w,'tower',1,8,8,50)
    eq(rejected(Sim.step(w,{command(w,1,'recruit',hall.id,{unit='shield'})})),'requirement missing')
    tower.remaining=0
    assert(not rejected(Sim.step(w,{command(w,1,'recruit',hall.id,{unit='shield'})})),'refused with the requirement met')
    eq(#hall.queue,1)
    -- The view answers the same question for the HUD and the bot.
    assert(Sim.missingRequirement(Sim.view(w,1),1,C.units.shield.requires)==nil)
    -- Building requirements are checked at placement, with a reason a player can act on.
    C=content();C.buildings.barracks.requires={'tower'};w=world(C);w.players[1].resources.gold=100000
    local view=Sim.view(w,1)
    local ok,reason=Sim.placement(view,C,'barracks',10,10);assert(not ok);eq(reason,'Requires Watchtower')
    building(w,'tower',1,14,14);view=Sim.view(w,1)
    ok=Sim.placement(view,C,'barracks',4,10);assert(ok,'placement refused with the requirement met')
end

function M.allHq()
    -- The default rule: the fixture factions already lose on their one headquarters, and
    -- that is unchanged because they cannot build another.
    local w=world(content())
    local hq=find(w,1,'hq');hq.hp=0;step(w,1);assert(w.players[1].defeated);assert(w.result and w.result.winner==2)
    -- A faction that may build its headquarters survives on a second one.
    local C=content();C.factions.bastion.buildings={'hq','barracks'}
    w=world(C);hq=find(w,1,'hq')
    w.players[1].resources.gold=100000;local view=Sim.view(w,1)
    -- Within the starting headquarters' sight, so only the schema decides.
    local ok,reason=Sim.placement(view,C,'hq',8,9);assert(ok,'a listed headquarters could not be placed: '..tostring(reason))

    local second=building(w,'hq',1,12,12)
    hq.hp=0;step(w,1);assert(not w.players[1].defeated,'defeated with a second headquarters standing');assert(not w.result)
    second.hp=0;step(w,1);assert(w.players[1].defeated,'not defeated with every headquarters gone')
    -- A site under construction is a life too.
    w=world(C);hq=find(w,1,'hq');building(w,'hq',1,12,12,100)
    hq.hp=0;step(w,1);assert(not w.players[1].defeated,'defeated with a headquarters under construction')
    -- The state survives a snapshot and is covered by the checkpoint.
    local clone=Sim.restore(Sim.snapshot(w));step(w,5);step(clone,5);eq(Sim.serializeAuthoritative(w),Sim.serializeAuthoritative(clone))
end

function M.uniqueHq()
    local C=content();C.factions.bastion.defeat='unique_hq';C.factions.bastion.buildings={'hq','barracks'}
    local w=world(C);w.players[1].resources.gold=100000
    -- Cannot be built again, whatever the build list says.
    local ok,reason=Sim.placement(Sim.view(w,1),C,'hq',12,12);assert(not ok);eq(reason,'Cannot be built')
    -- Placed by hand anyway, it does not save the player.
    building(w,'hq',1,12,12)
    local hq=find(w,1,'hq');hq.hp=0;step(w,1);assert(w.players[1].defeated,'survived the loss of the unique headquarters')
end

function M.resources()
    local C=content();C.rules.resources={'gold','ore'};C.rules.startingResources={gold=650,ore=0}
    -- `onNode` is where it stands; `extractor` is what it does once it does.
    C.buildings.orepit={label='Ore pit',hp=400,size=3,sight=5,cost={gold=10},buildTicks=1,onNode='ore',extractor=true}

    C.factions.bastion.buildings={'extractor','orepit'}
    assert(validate(C))
    local w=world(C,24,{{x=6,y=6,resource='ore',amount=16,size=3},{x=14,y=6,resource='gold',amount=16,size=3}})
    local worker=find(w,1,'worker');local view=Sim.view(w,1)
    -- Each node accepts only its own extractor kind.
    local ok,reason=Sim.placement(view,C,'orepit',14,6);assert(not ok);eq(reason,'Must be built on a ore node')
    ok,reason=Sim.placement(view,C,'extractor',6,6);assert(not ok);eq(reason,'Must be built on a gold node')
    assert(Sim.placement(view,C,'orepit',6,6))
    step(w,1,{command(w,1,'build',worker.id,{building='orepit',x=6,y=6})})
    assert(find(w,1,'orepit'),'ore pit refused on an ore node')
    local delivered=0
    for _=1,1200 do for _,ev in ipairs(Sim.step(w,{})) do if ev.kind=='delivered' then eq(ev.resource,'ore');delivered=delivered+ev.amount end end end
    eq(delivered,16);eq(w.players[1].resources.ore,16);eq(w.players[1].resources.gold,640,'ore was credited as gold')
    -- Cancel refunds follow the rule percentage on every resource.
    C=content();C.rules.cancelRefundPercent=75;C.rules.resources={'gold','ore'};C.buildings.barracks.cost={gold=100,ore=40}
    w=world(C,24);w.players[1].resources={gold=1000,ore=1000};worker=find(w,1,'worker')
    step(w,1,{command(w,1,'build',worker.id,{building='barracks',x=8,y=4})});local site=find(w,1,'barracks');assert(site)
    step(w,1,{command(w,1,'cancel',site.id)})
    eq(w.players[1].resources.gold,975);eq(w.players[1].resources.ore,990)
end

function M.produces()
    local C=content()
    C.buildings.tower.produces={'stalker'};C.buildings.hq.produces={'worker','shield'}
    local w=world(C);w.players[1].resources.gold=100000
    local hq=find(w,1,'hq');local tower=building(w,'tower',1,8,8)
    assert(not rejected(Sim.step(w,{command(w,1,'recruit',tower.id,{unit='stalker'})})),'a building could not train what it produces')
    assert(not rejected(Sim.step(w,{command(w,1,'recruit',hq.id,{unit='shield'})})),'the headquarters could not train its listed unit')
    eq(rejected(Sim.step(w,{command(w,1,'recruit',tower.id,{unit='shield'})})),'cannot recruit')
    -- The defaults: the war hall trains the roster, the headquarters trains workers.
    w=world(content());w.players[1].resources.gold=100000;hq=find(w,1,'hq')
    local hall=building(w,'barracks',1,8,8)
    assert(not rejected(Sim.step(w,{command(w,1,'recruit',hall.id,{unit='shield'})})))
    eq(rejected(Sim.step(w,{command(w,1,'recruit',hall.id,{unit='stalker'})})),'cannot recruit','another faction\'s roster was trainable')
    assert(not rejected(Sim.step(w,{command(w,1,'recruit',hq.id,{unit='worker'})})))
    eq(rejected(Sim.step(w,{command(w,1,'recruit',hq.id,{unit='shield'})})),'cannot recruit')
    -- A starting layout from content replaces the hero-and-workers default.
    C=content();C.factions.bastion.starting={resources={gold=400},units={'worker','worker','shield'}}
    w=world(C)
    eq(w.players[1].resources.gold,400);eq(Sim.unitCount(w,1),3);assert(not w.players[1].hero,'a hero was spawned without being asked for')
    eq(w.players[2].resources.gold,650,'the other faction kept the rule default')
end
return M
