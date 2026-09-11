-- Regression scenarios for casting and status effects. Every one drives the real command
-- path and then checks the world, not a flag: a spell that is accepted and does nothing
-- is exactly the bug these are here to catch.
local Sim=require('src.sim')
local F=require('src.sim.fixed')
local Maps=require('src.maps')
local Content=require('tests.fixture_content')
local Stats=require('src.sim.stats')
local Abilities=require('src.sim.abilities')
local M={}
local function eq(a,b,message) assert(a==b,(message or 'values differ')..': '..tostring(a)..' != '..tostring(b)) end
local function world(size)
    local m=Maps.create('test',size or 24);m.resources={};m.camps={}
    local w=Sim.create({seed=12345,players={{faction='bastion'},{faction='wild'}}},Content,m)
    -- Start from an empty field: these scenarios place exactly the units they reason
    -- about, so a starting worker cannot wander into an area effect.
    for _,id in ipairs(w.order) do local e=w.entities[id];if e.category=='unit' then e.alive=false end end
    return w
end
local function unit(w,kind,owner,x,y)
    local d=w.content.units[kind];local id=w.nextId;w.nextId=id+1
    local e={id=id,kind=kind,owner=owner,x=F.center(x),y=F.center(y),category='unit',alive=true,hp=d.hp,maxHp=d.hp,
        size=1,cooldown=0,path={},pathIndex=1,order={kind='stop'},orders={},lastCombat=-1000}
    if d.hero then e.xp=0;e.upgrades={};e.stance=1 end
    if d.mana then e.mana=d.mana;e.maxMana=d.mana end
    w.entities[id]=e;w.order[#w.order+1]=id;return e
end
local sequence={0,0,0,0}
local function cast(w,e,ability,args)
    args=args or {};args.entity=e.id;args.ability=ability
    sequence[e.owner]=w.players[e.owner].sequence+1
    return {tick=w.tick+1,player=e.owner,sequence=sequence[e.owner],kind='cast',args=args}
end
local function step(w,n) for _=1,(n or 1) do Sim.step(w,{}) end end
-- Commands are applied before the tick's visibility pass, so a unit injected straight
-- into the world is not yet visible to anyone on the tick it appears. One empty step
-- settles the fog, which is the state every real match is always in.
local function settle(w) Sim.step(w,{}) end
local function rejection(w)
    for _,event in ipairs(w.events) do if event.kind=='rejected' then return event.reason end end
    return nil
end
-- A no-target cast lands on everyone in its radius and nobody outside it.
function M.instant()
    local w=world()
    local hero=unit(w,'warden',1,10,10)
    local near=unit(w,'shield',1,11,10)
    local far=unit(w,'shield',1,20,10)
    settle(w)
    local mana=hero.mana
    local baseArmor=Stats.armor(w,near)
    Sim.step(w,{cast(w,hero,'ward')})
    assert(not rejection(w),'a legal cast was rejected: '..tostring(rejection(w)))
    assert(hero.cast,'no cast phase was started')
    eq(hero.mana,mana,'mana was spent before the cast point')
    step(w,4)
    eq(hero.mana,mana-20,'mana was not spent at the cast point')
    assert(Abilities.status(w,near,'guard'),'an ally inside the radius was not warded')
    assert(not Abilities.status(w,far,'guard'),'an ally outside the radius was warded')
    -- The status is a real modifier: it is read through the resolver, so it reduces
    -- damage everywhere damage is mitigated. The Warden's own protection aura already
    -- covers the near ally, so what is asserted is the ward's contribution on top of it.
    eq(Stats.armor(w,near),baseArmor+5,'the ward did not reach the stat resolver')
    eq(Stats.armor(w,far),0,'an unwarded ally gained armour')
    -- The cooldown is enforced through the command path, with a reason the HUD can show.
    Sim.step(w,{cast(w,hero,'ward')})
    eq(rejection(w),'ability on cooldown','a cast during the cooldown was not rejected')
    -- And the status ends on its own. Applied on the cast-point tick for 100 ticks.
    local applied=Abilities.status(w,near,'guard')['until']
    while w.tick<applied do step(w,1) end
    step(w,1)
    assert(not Abilities.status(w,near,'guard'),'the ward outlived its duration')
    eq(Stats.armor(w,near),baseArmor,'armour did not return to its unwarded value')
end
-- A unit-targeted cast walks into range, damages exactly once, and its slow is a real
-- speed reduction rather than a flag nothing reads.
function M.targeted()
    local w=world()
    local hero=unit(w,'warden',1,4,10)
    local victim=unit(w,'stalker',2,11,10)
    victim.order={kind='hold'}
    settle(w)
    local hp=victim.hp
    local speed=Stats.speed(w,victim)
    Sim.step(w,{cast(w,hero,'smite',{target=victim.id})})
    assert(not rejection(w),'a legal targeted cast was rejected: '..tostring(rejection(w)))
    eq(hero.order.kind,'cast','the cast did not become an order')
    -- Out of range at the start: the caster closes the distance rather than failing.
    assert(not hero.cast,'a cast fired from out of range')
    local guard=0
    while hero.order.kind=='cast' and guard<400 do step(w,1);guard=guard+1 end
    assert(guard<400,'the caster never got into range')
    eq(victim.hp,hp-50,'the target did not take exactly the ability damage')
    local slowed=Stats.speed(w,victim)
    assert(slowed<speed,'the slow did not reduce speed: '..slowed..' vs '..speed)
    eq(slowed,math.max(1,math.floor(speed*50/100)),'the slow was not a 50% reduction')
end
-- Moving before the cast point cancels the cast and costs nothing. Moving after it does
-- not take the effect back. This is the attack phase's bargain, applied to spells.
function M.cancellation()
    local w=world()
    local hero=unit(w,'warden',1,10,10)
    local victim=unit(w,'stalker',2,12,10)
    victim.order={kind='hold'}
    settle(w)
    local mana,hp=hero.mana,victim.hp
    Sim.step(w,{cast(w,hero,'smite',{target=victim.id})})
    step(w,1)

    assert(hero.cast,'the cast never started')
    -- One tick before the point, walk away.
    Sim.step(w,{{tick=w.tick+1,player=1,sequence=w.players[1].sequence+1,kind='move',args={entity=hero.id,x=F.center(6),y=F.center(10)}}})
    assert(not hero.cast,'moving before the cast point did not cancel the cast')
    step(w,10)
    eq(hero.mana,mana,'a cancelled cast still spent mana')
    eq(victim.hp,hp,'a cancelled cast still dealt damage')
    assert(Abilities.ready(w,hero,'smite'),'a cancelled cast still started its cooldown')
    -- Now let one complete, then move during the backswing: the damage stands.
    Sim.step(w,{cast(w,hero,'smite',{target=victim.id})})
    local guard=0
    while victim.hp==hp and guard<400 do step(w,1);guard=guard+1 end
    assert(victim.hp==hp-50,'the second cast did not land')
    Sim.step(w,{{tick=w.tick+1,player=1,sequence=w.players[1].sequence+1,kind='move',args={entity=hero.id,x=F.center(4),y=F.center(10)}}})
    step(w,5)
    eq(victim.hp,hp-50,'moving after the cast point took the damage back')
    assert(not Abilities.ready(w,hero,'smite'),'a completed cast did not start its cooldown')
end
-- An area cast hits everything in the circle, in w.order order, and a burn ticks on its
-- own period rather than all at once.
function M.area()
    local w=world()
    -- Six cells back: inside the eight-cell cast range and far outside every weapon in
    -- this scenario, so nothing here ever auto-attacks and the only damage is the spell.
    local hero=unit(w,'beastkeeper',2,7,10)
    local a=unit(w,'shield',1,13,10)
    local b=unit(w,'shield',1,13,11)
    local away=unit(w,'shield',1,20,10)
    for _,e in ipairs({a,b,away}) do e.order={kind='hold'} end
    settle(w)
    local hp=a.hp
    Sim.step(w,{cast(w,hero,'scorch',{x=F.center(13),y=F.center(10)})})
    assert(not rejection(w),'a legal area cast was rejected: '..tostring(rejection(w)))
    local guard=0
    while a.hp==hp and guard<400 do step(w,1);guard=guard+1 end
    eq(a.hp,hp-20,'the first target took the wrong damage')
    eq(b.hp,hp-20,'the second target in the circle was missed')
    eq(away.hp,hp,'a unit outside the circle was hit')
    assert(Abilities.status(w,a,'burn'),'the burn was not applied')
    -- The burn ticks once per its period, not once per tick.
    local before=a.hp
    step(w,19)
    local ticked=before-a.hp
    assert(ticked==0 or ticked==10,'the burn dealt '..ticked..' over less than one period')
    step(w,21)
    assert(a.hp<before,'the burn never dealt damage')
    assert(before-a.hp<=30,'the burn dealt damage every tick instead of every period')
end
-- A skill shot hits the first thing on its line and nothing behind it.
function M.skillshot()
    local w=world()
    local hero=unit(w,'beastkeeper',2,10,10)
    local first=unit(w,'shield',1,13,10)
    local behind=unit(w,'shield',1,15,10)
    local beside=unit(w,'shield',1,13,13)
    for _,e in ipairs({first,behind,beside}) do e.order={kind='hold'} end
    settle(w)
    local hp=first.hp
    Sim.step(w,{cast(w,hero,'lash',{x=F.center(16),y=F.center(10)})})
    local guard=0
    while first.hp==hp and guard<200 do step(w,1);guard=guard+1 end
    eq(first.hp,hp-15,'the skill shot missed the first unit on its line')
    eq(behind.hp,hp,'a skill shot that does not pierce hit a second unit')
    eq(beside.hp,hp,'the skill shot hit a unit off its line')
    -- The stun is a hard gate: it stops movement and attacking, and it cancels a swing
    -- that has not landed.
    assert(not Stats.canMove(w,first),'a stunned unit could still move')
    assert(not Stats.canAttack(w,first),'a stunned unit could still attack')
    local at=first.x
    Sim.step(w,{{tick=w.tick+1,player=1,sequence=w.players[1].sequence+1,kind='move',args={entity=first.id,x=F.center(4),y=F.center(10)}}})
    step(w,10)
    eq(first.x,at,'a stunned unit moved')
    -- And it wears off.
    local until_=Abilities.status(w,first,'stun')['until']
    while w.tick<=until_ do step(w,1) end
    assert(Stats.canMove(w,first),'the stun outlived its duration')
end
-- Mana, ownership and target legality are all enforced at the command, each with its own
-- reason, so the HUD can say what went wrong.
function M.rejections()
    local w=world()
    local hero=unit(w,'warden',1,10,10)
    local ally=unit(w,'shield',1,11,10)
    local enemy=unit(w,'stalker',2,12,10)
    settle(w)
    Sim.step(w,{cast(w,hero,'nonesuch')})
    eq(rejection(w),'unknown ability','an unknown ability was accepted')
    Sim.step(w,{cast(w,hero,'scorch',{x=F.center(11),y=F.center(10)})})
    eq(rejection(w),'unknown ability','a hero cast an ability belonging to the other faction')
    Sim.step(w,{cast(w,hero,'smite',{target=ally.id})})
    eq(rejection(w),'invalid ability target','an enemy-only ability was accepted onto an ally')
    hero.mana=0
    Sim.step(w,{cast(w,hero,'smite',{target=enemy.id})})
    eq(rejection(w),'not enough mana','a cast with no mana was accepted')
    -- Mana comes back on its own, once a second.
    local before=hero.mana
    step(w,40)
    assert(hero.mana>before,'mana did not regenerate')
    -- A silenced caster is refused outright.
    hero.mana=hero.maxMana
    Abilities.applyStatus(w,hero,{status='stun',ticks=40,source=enemy.id},{emit=function() end})
    Sim.step(w,{cast(w,hero,'smite',{target=enemy.id})})
    eq(rejection(w),'silenced','a stunned caster was allowed to cast')
end
-- Casts, statuses and cooldowns are all authoritative: a snapshot taken mid-cast and
-- mid-status continues identically, which is what makes them safe in a replay and on a
-- second machine.
function M.snapshot()
    local w=world()
    local hero=unit(w,'warden',1,10,10)
    local victim=unit(w,'stalker',2,12,10)
    victim.order={kind='hold'}
    settle(w)
    Sim.step(w,{cast(w,hero,'smite',{target=victim.id})})
    step(w,2)
    assert(hero.cast,'expected a cast in flight to snapshot')
    local clone=Sim.restore(Sim.snapshot(w))
    for _=1,200 do Sim.step(w,{});Sim.step(clone,{}) end
    eq(Sim.serializeCanonical(w),Sim.serializeCanonical(clone),'a cast diverged across a snapshot')
    -- And the same during an active status.
    local other=world()
    local caster=unit(other,'beastkeeper',2,10,10)
    local burned=unit(other,'shield',1,12,10)
    burned.order={kind='hold'}
    Sim.step(other,{cast(other,caster,'scorch',{x=F.center(12),y=F.center(10)})})
    local guard=0
    while not Abilities.status(other,burned,'burn') and guard<200 do Sim.step(other,{});guard=guard+1 end
    assert(Abilities.status(other,burned,'burn'),'expected a burn to snapshot')
    local twin=Sim.restore(Sim.snapshot(other))
    for _=1,200 do Sim.step(other,{});Sim.step(twin,{}) end
    eq(Sim.serializeCanonical(other),Sim.serializeCanonical(twin),'a status diverged across a snapshot')
end
-- An area effect resolves in w.order order whatever order the commands arrived in, which
-- is what stops two peers disagreeing about who died first.
function M.ordering()
    local function run(reverse)
        local w=world()
        local one=unit(w,'beastkeeper',2,10,10)
        local two=unit(w,'beastkeeper',2,10,14)
        local victim=unit(w,'shield',1,13,12)
        victim.order={kind='hold'}
        settle(w)
        local seq=w.players[2].sequence
        local a={tick=w.tick+1,player=2,sequence=seq+1,kind='cast',args={entity=one.id,ability='scorch',x=F.center(13),y=F.center(12)}}
        local b={tick=w.tick+1,player=2,sequence=seq+2,kind='cast',args={entity=two.id,ability='scorch',x=F.center(13),y=F.center(12)}}
        Sim.step(w,reverse and {b,a} or {a,b})
        for _=1,60 do Sim.step(w,{}) end
        return Sim.serializeCanonical(w)
    end
    eq(run(false),run(true),'two casts in one tick resolved differently depending on arrival order')
end
-- A thrown line is a body in flight, not an instant result. It takes time to arrive, it
-- can be walked out of, and it stops at the first thing it touches.
function M.projectile()
    local w=world()
    local hero=unit(w,'beastkeeper',2,10,10)
    local victim=unit(w,'shield',1,15,10)
    victim.order={kind='hold'}
    settle(w)
    local hp=victim.hp
    Sim.step(w,{cast(w,hero,'dart',{x=F.center(18),y=F.center(10)})})
    assert(not rejection(w),'a legal thrown cast was rejected: '..tostring(rejection(w)))
    -- Wait out the cast point, then look for the shot itself.
    local flying,guard=nil,0
    while not flying and guard<40 do
        step(w,1);guard=guard+1
        for _,id in ipairs(w.order) do local e=w.entities[id];if e.alive and e.category=='projectile' then flying=e end end
    end
    assert(flying,'no projectile was launched')
    eq(victim.hp,hp,'the shot dealt its damage before it had travelled anywhere')
    local startX=flying.x
    step(w,1)
    assert(flying.x>startX,'the projectile did not move')
    -- It arrives, once, and is recycled rather than left in the world.
    guard=0
    while victim.hp==hp and guard<200 do step(w,1);guard=guard+1 end
    eq(victim.hp,hp-15,'the shot did not deal its impact damage exactly once')
    assert(Abilities.status(w,victim,'stun'),'the impact status was not applied')
    step(w,1)
    for _,id in ipairs(w.order) do local e=w.entities[id];assert(not (e.alive and e.category=='projectile'),'the shot outlived its impact') end
    -- A shot aimed at nothing expires at the end of its range instead of flying forever.
    local before=0
    for _,id in ipairs(w.order) do if w.entities[id].category=='projectile' then before=before+1 end end
    hero.cooldowns=nil
    Sim.step(w,{cast(w,hero,'dart',{x=F.center(10),y=F.center(2)})})
    guard=0
    while guard<120 do
        step(w,1);guard=guard+1
        local live=false
        for _,id in ipairs(w.order) do local e=w.entities[id];if e.alive and e.category=='projectile' then live=true end end
        if not live and guard>10 then break end
    end
    local after=0
    for _,id in ipairs(w.order) do if w.entities[id].category=='projectile' then after=after+1 end end
    eq(after,before,'a spent projectile was not recycled: the entity list grew')
end
function M.run()
    M.instant();M.targeted();M.cancellation();M.area();M.skillshot();M.projectile();M.rejections();M.snapshot();M.ordering()
end
return M
