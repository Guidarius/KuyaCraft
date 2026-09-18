-- The air layer (simulation version 23), on a copy of the fixture with a flying `hawk`
-- (a stalker that flies), a crossbow that may shoot up for less, and a ram whose blow
-- splashes a cell and a half around its target.
local Sim=require('src.sim')
local F=require('src.sim.fixed')
local Codec=require('src.sim.codec')
local Maps=require('src.maps')
local P=require('src.sim.path')
local Fixture=require('tests.fixture_content')
local M={}
local function eq(a,b,message) assert(a==b,(message or 'values differ')..': '..tostring(a)..' != '..tostring(b)) end
local function content()
    local C=Codec.copy(Fixture)
    C.units.hawk=Codec.copy(C.units.stalker);C.units.hawk.label='Hawk';C.units.hawk.flying=true
    C.units.crossbow.canAttackAir=true;C.units.crossbow.airDamage=10
    C.units.siege.splash=384
    return C
end
local function world(C)
    local m=Maps.create('air',40);m.resources={};m.camps={};m.blocked={}
    local w=Sim.create({seed=9,players={{faction='bastion'},{faction='wild'}}},C or content(),m)
    for _,id in ipairs(w.order) do local e=w.entities[id];if e.category=='unit' then e.alive=false end end
    return w
end
local function unit(w,kind,owner,x,y)
    local d=w.content.units[kind];local id=w.nextId;w.nextId=id+1
    local e={id=id,kind=kind,owner=owner,x=F.center(x),y=F.center(y),category='unit',alive=true,hp=d.hp,maxHp=d.hp,size=1,cooldown=0,
        path={},pathIndex=1,order={kind='stop'},orders={},lastCombat=-1000}
    w.entities[id]=e;w.order[#w.order+1]=id;return e
end
local function command(w,e,kind,args) args=args or {};args.entity=e.id;return {tick=w.tick+1,player=e.owner,sequence=w.players[e.owner].sequence+1,kind=kind,args=args} end
local function step(w,n,commands) for i=1,n do Sim.step(w,i==1 and (commands or {}) or {}) end end
local function rejected(events) for _,ev in ipairs(events) do if ev.kind=='rejected' then return ev.reason end end end
local function wall(w,x,y0,y1) for y=y0,y1 do w.map.blocked[P.key(w.map,x,y)]=true;w.blocked[P.key(w.map,x,y)]=true end end

function M.flight()
    -- A wall from top to bottom: the hawk crosses it on a one-node path, the stalker cannot.
    local w=world();wall(w,20,0,39)
    local hawk=unit(w,'hawk',1,10,20);local walker=unit(w,'stalker',1,10,22)
    step(w,1,{command(w,hawk,'move',{x=F.center(30),y=F.center(20)})})
    eq(#hawk.path,1,'a flyer was given a searched path');eq(hawk.order.kind,'move')
    step(w,1,{command(w,walker,'move',{x=F.center(30),y=F.center(22)})})
    for _=1,400 do step(w,1);if hawk.order.kind=='stop' then break end end
    eq(hawk.order.kind,'stop','the hawk never arrived');eq(F.cell(hawk.x),30);eq(F.cell(hawk.y),20)
    step(w,300);assert(F.cell(walker.x)<20,'the stalker walked through the wall')
    -- A flyer may be sent onto blocked ground: it hovers over the wall.
    step(w,1,{command(w,hawk,'move',{x=F.center(20),y=F.center(10)})})
    for _=1,400 do step(w,1);if hawk.order.kind=='stop' then break end end
    eq(F.cell(hawk.x),20);eq(F.cell(hawk.y),10)
end

function M.passThrough()
    -- Ground units walk through a hovering flyer without yielding to it or being stopped.
    local w=world();local hawk=unit(w,'hawk',1,20,20)
    local walkers={};for i=1,3 do walkers[i]=unit(w,'stalker',1,14,19+i) end
    local commands={};for i,e in ipairs(walkers) do commands[i]=command(w,e,'move',{x=F.center(26),y=F.center(19+i)});commands[i].sequence=w.players[1].sequence+i end
    step(w,1,commands);local hx,hy=hawk.x,hawk.y
    for _=1,300 do step(w,1) end
    eq(hawk.x,hx,'the hovering flyer was moved');eq(hawk.y,hy)
    for i,e in ipairs(walkers) do eq(F.cell(e.x),26,'walker '..i..' was stopped by the flyer') end
    -- And a flyer does not stop a building going up on its cell.
    w.players[1].resources.gold=10000;local view=Sim.view(w,1)
    local ok,reason=Sim.placement(view,w.content,'barracks',F.cell(hawk.x)-1,F.cell(hawk.y)-1)
    assert(ok,'a flyer blocked a building site: '..tostring(reason))
end

function M.targeting()
    local w=world();local hawk=unit(w,'hawk',2,20,20);hawk.order={kind='hold'}
    local shield=unit(w,'shield',1,18,20);step(w,1)
    -- A melee unit may neither be ordered at nor acquire a flyer; the crossbow does both, for less.
    eq(rejected(Sim.step(w,{command(w,shield,'attack',{target=hawk.id})})),'cannot attack air')
    step(w,40);assert(not shield.combatTarget,'a melee unit acquired a flyer');eq(hawk.hp,hawk.maxHp)
    local bow=unit(w,'crossbow',1,16,20);step(w,1)
    assert(not rejected(Sim.step(w,{command(w,bow,'attack',{target=hawk.id})})),'the crossbow may not attack air')
    local shots=0
    for _=1,200 do for _,ev in ipairs(Sim.step(w,{})) do if ev.kind=='attack' and ev.source==bow.id then shots=shots+1 end end end
    assert(shots>=2,'the crossbow never shot the hawk');eq(hawk.maxHp-hawk.hp,shots*10,'air damage was not the air figure')
    -- The same crossbow hits a ground target with its full damage. The shield is retired first,
    -- or it would chase the same target and add its own blows.
    shield.alive=false;shield.hp=0
    local walker=unit(w,'stalker',2,16,22);walker.order={kind='hold'};step(w,1)
    Sim.step(w,{command(w,bow,'attack',{target=walker.id})})
    local before=walker.hp;local hits=0
    for _=1,120 do for _,ev in ipairs(Sim.step(w,{})) do if ev.kind=='attack' and ev.source==bow.id then hits=hits+1 end end;if hits>=1 then break end end
    eq(before-walker.hp,w.content.units.crossbow.damage)
end

function M.splash()
    local w=world()
    local ram=unit(w,'siege',1,10,20);local ally=unit(w,'shield',1,12,21)
    -- The enemies are workers, which never fight back, so only the ram's blow lands on anyone.
    local target=unit(w,'worker',2,12,20);local near=unit(w,'worker',2,13,20);local far=unit(w,'worker',2,15,20);local hawk=unit(w,'hawk',2,12,19)
    for _,e in ipairs({target,near,far,hawk,ally}) do e.order={kind='hold'} end
    step(w,1);Sim.step(w,{command(w,ram,'attack',{target=target.id})})
    local hit=false
    for _=1,120 do for _,ev in ipairs(Sim.step(w,{})) do if ev.kind=='attack' and ev.source==ram.id then hit=true end end;if hit then break end end
    assert(hit,'the ram never struck');step(w,1)
    assert(target.hp<target.maxHp,'the target was not hit');assert(near.hp<near.maxHp,'the neighbour within a cell and a half was not splashed')
    eq(far.hp,far.maxHp,'a unit three cells away was splashed');eq(hawk.hp,hawk.maxHp,'a flyer was splashed');eq(ally.hp,ally.maxHp,'an ally was splashed')
end

function M.snapshot()
    local w=world();wall(w,20,0,39);local hawk=unit(w,'hawk',1,10,20)
    step(w,1,{command(w,hawk,'move',{x=F.center(30),y=F.center(20)})});step(w,20)
    assert(hawk.order.kind=='move' and F.cell(hawk.x)>10,'not in flight')
    local clone=Sim.restore(Sim.snapshot(w))
    for _=1,200 do Sim.step(w,{});Sim.step(clone,{});eq(Sim.serializeCanonical(w),Sim.serializeCanonical(clone)) end
    eq(hawk.order.kind,'stop')
end
return M
