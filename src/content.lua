local T=require('src.content_time')
local C = {
    version = 7,
    rules = { profile='marches-v1', tickRate=20, population=80, pathBudget=256, directPathBudget=16384,
        -- Terrain samples per tick the path smoother may spend across every route
        -- completed that tick. A route that cannot be smoothed inside it is walked as
        -- A* produced it, which is correct, just less straight.
        smoothBudget=8192,
        startingResources={gold=650}, startingWorkers=3,
        -- Gold arrives as carriers walking from an extractor to the nearest drop-off.
        -- Income per extractor is payload * min(1/carrierEmitTicks, carrierSlots/tripTicks):
        -- a near mine is limited by the interval, a far one by how many deliveries can be
        -- in flight at once, so income falls as roughly 1/distance past the crossover at
        -- carrierSlots*carrierEmitTicks ticks of travel. The cap is also a hard bound on
        -- how many carrier entities can exist. See docs/RESOURCE_FLOW.md.
        carrierPayload=8, carrierEmitTicks=16, carrierSlots=9, carrierCorpseTicks=40,
        reviveTicks=900, reviveCost=175, reviveTierTicks=100, reviveTierCost=25,
        xpRange=2560, xpThresholds={180,500,1000}, combatXpPerFood=20, heroXp=150,
        outOfCombatTicks=160, campLeash=2560, campResetTicks=60, acquireRange=1536,
        constructionHealth=true, tech={cost={gold=600},ticks=2000},
        heroHealth={warden=240,beastkeeper=200}, heroDamage=6, quickTicks=4,
        auraRadius=1536, auraWide=2048, auraExtra=512, auraDeep=2, offensiveDamage=4,
        recovery=8, recoveryUpgrade=14, pursuitSpeed=4, pursuitPenalty=4, sprintSpeed=4,
        -- Units moved together as one group walk at the slowest member's pace, so a
        -- mixed army arrives as an army instead of arriving piecemeal. Set false to
        -- return to every unit moving at its own speed.
        formationPacing=true,
        -- Sight is blocked by terrain, buildings and forests rather than passing
        -- straight through them. Set false for the cheaper radial visibility, which
        -- costs markedly less with a large army because overlapping fields share work.
        lineOfSight=true,
        -- Control points: stand in one's circle with no enemy there for captureTicks and it
        -- is yours until the enemy does the same. Own every point on the map for holdTicks
        -- without a break and you win. See src/sim/control.lua.
        control={radius=T.cells(4),captureTicks=T.ticks(10),holdTicks=T.ticks(120)} },
    units = {},
    buildings = {
        hq={label='Headquarters',hp=2800,size=5,sight=14,cost={},buildTicks=1,dropoff=true,damage=30,range=2048,cooldown=30,windup=6,baseHeal=10},
        barracks={label='War hall',hp=1500,size=4,sight=12,cost={gold=220},buildTicks=1200},
        -- Placed on a gold mine and nowhere else; its footprint is the mine's.
        extractor={label='Extractor',hp=900,size=3,sight=8,cost={gold=120},buildTicks=600,extractor=true},
        -- A forward drop-off. Building one beside a distant mine shortens its carrier
        -- route and restores it to full rate, which is the answer to the distance penalty.
        outpost={label='Outpost',hp=1400,size=4,sight=12,cost={gold=530},buildTicks=1800,dropoff=true},
        tower={label='Watchtower',hp=700,size=2,sight=12,cost={gold=220},buildTicks=900,damage=26,range=1920,cooldown=32,windup=6}
    },
    -- Status effects. `modifiers` are read by src/sim/stats.lua and are the only way a
    -- statistic is ever changed; `flags` are the hard gates, checked where the action
    -- they forbid is decided. `stack` says what a second application does: refresh the
    -- duration, keep the stronger, or add a stack.
    statuses = {
        guard = {stack='max',beneficial=true,modifiers={armor=0}},
        slow  = {stack='refresh',modifiers={speedPercent=0}},
        root  = {stack='refresh',flags={noMove=true}},
        stun  = {stack='refresh',flags={noMove=true,noAttack=true,noCast=true}},
        -- Periodic damage. `period` is in ticks and the amount comes from whatever
        -- applied it, so one status definition serves burns of different strengths.
        burn  = {stack='refresh',period=20,effects={{kind='damage',amount=1}}}
    },
    -- Hero abilities are defined below, after the units they belong to.
    abilities = {},
    factions = {
        bastion = { label = 'The Bastion', hero = 'warden', roster = { 'shield', 'crossbow', 'medic', 'siege' },
            upgrades = { { 'Wide protection', 'Deep protection' }, { 'Vanguard damage', 'Guardian health' }, { 'Quick attacks', 'Enduring aura' } } },
        wild = { label = 'The Wild Pact', hero = 'beastkeeper', roster = { 'stalker', 'thorn', 'sprite', 'beast' },
            upgrades = { { 'Rapid recovery', 'Opening sprint' }, { 'Predator damage', 'Ancient health' }, { 'Quick attacks', 'Pack recovery' } } }
    }
}
-- Costs are gold only. The former lumber prices were folded in one to one, which keeps
-- the relative price of everything while removing the second resource.
local function unit(id,label,gold,food,train,hp,damage,period,windup,range,speed,radius)
    C.units[id]={label=label,cost={gold=gold},food=food,buildTicks=T.ticks(train),hp=hp,damage=damage,
        cooldown=T.ticks(period),windup=T.ticks(windup),range=T.cells(range),speed=speed,radius=radius or 80,sight=12}
end
unit('worker','Worker',75,1,15,220,5,2,.3,.25,30,72)
unit('shield','Shieldguard',135,2,20,420,14,1.4,.3,.25,35)
unit('crossbow','Crossbow',220,3,26,320,22,1.6,.35,5,35)
unit('medic','Standard bearer',195,2,28,300,8,1.8,.3,4,35)
unit('siege','Ram',380,4,40,900,60,2.5,.5,.5,26,112)
unit('stalker','Stalker',130,2,20,340,13,1.25,.25,.25,40)
unit('thorn','Thorn thrower',210,3,25,280,19,1.45,.3,4.5,37)
unit('sprite','Grove sprite',190,2,28,250,7,1.6,.25,4,39)
unit('beast','Heavy beast',350,4,36,760,34,1.7,.4,.375,35,112)
unit('warden','Warden',0,5,0,1000,30,1.5,.3,.25,42,96)
unit('beastkeeper','Beastkeeper',0,5,0,900,27,1.35,.25,.25,44,96)
unit('neutral','Camp guard',0,0,0,360,12,1.6,.3,.25,30)
unit('scout','Camp scout',0,0,0,180,7,1.8,.3,.25,30)
unit('leader','Camp leader',0,0,0,700,24,1.8,.4,.25,28,112)
-- Carriers are defined by hand rather than through unit(): they must have no `damage`
-- key at all, because that is what tells the combat phase they never attack. They are
-- never recruited, cost nothing, eat no food, and grant no vision -- a convoy does not
-- scout for you, so an ambush on your supply line is something you have to go and see.
-- A shot in flight. It is a unit definition only because every entity needs one; it has
-- no damage, no sight, no food and never moves under its own orders. What it does is in
-- src/sim/projectiles.lua, and what it does to whoever it hits is in the ability.
C.units.projectile={label='Projectile',cost={},food=0,buildTicks=0,hp=1,
    cooldown=1,windup=1,range=0,speed=1,radius=1,sight=0,projectile=true}
C.units.carrier={label='Gold carrier',cost={},food=0,buildTicks=0,hp=40,
    cooldown=1,windup=1,range=0,speed=40,radius=56,sight=0,carrier=true}
-- The four targeting kinds, one hero ability each, so that every path through the cast
-- phase is exercised by shipping content rather than only by a fixture. Slot is the
-- fixed position on the command card: the button never moves when the selection changes,
-- which is what makes a hotkey worth learning.
C.abilities = {
    -- Instant, no target: the Warden plants itself and hardens everyone nearby.
    bulwark = { label='Bulwark', hotkey='w', slot=2, target='none', radius=T.cells(6),
        filter={ally=true,self=true}, cost={mana=60}, cooldown=T.ticks(24),
        castPoint=T.ticks(.25), backswing=T.ticks(.3),
        tip='Allies within 6 cells take 4 less damage from each hit for 8 seconds.',
        effects={{kind='status',status='guard',ticks=T.ticks(8),magnitude=4}} },
    -- Unit target: a single enemy is called out, slowed and hurt.
    challenge = { label='Challenge', hotkey='e', slot=3, target='unit', range=T.cells(5),
        filter={enemy=true,building=false}, cost={mana=45}, cooldown=T.ticks(12),
        castPoint=T.ticks(.3), backswing=T.ticks(.35),
        tip='Deals 60 damage and slows one enemy by 35% for 4 seconds.',
        effects={{kind='damage',amount=60},{kind='status',status='slow',ticks=T.ticks(4),percent=-35}} },
    -- Area target: a circle on the ground that burns whatever is standing in it.
    thornfall = { label='Thornfall', hotkey='w', slot=2, target='area', range=T.cells(8), radius=T.cells(2.5),
        filter={enemy=true,building=false}, cost={mana=70}, cooldown=T.ticks(20),
        castPoint=T.ticks(.4), backswing=T.ticks(.3),
        tip='Deals 30 damage in a 2.5-cell circle and burns for 15 a second over 5 seconds.',
        effects={{kind='damage',amount=30},{kind='status',status='burn',ticks=T.ticks(5),amount=15}} },
    -- Direction: a skill shot down a line, rooting the first thing it catches.
    snare = { label='Snare', hotkey='e', slot=3, target='direction', range=T.cells(7), width=T.cells(1.25),
        filter={enemy=true,building=false}, cost={mana=50}, cooldown=T.ticks(16),
        castPoint=T.ticks(.35), backswing=T.ticks(.35),
        tip='A thrown line 7 cells long. The first enemy it catches takes 35 damage and cannot move for 3 seconds.',
        -- A real shot rather than an instant line: it travels at 3 cells a second, so it
        -- can be walked out of, which is what makes aiming it a skill rather than a click.
        effects={{kind='projectile',speed=60,radius=160,
            onHit={{kind='damage',amount=35},{kind='status',status='root',ticks=T.ticks(3)}}}} }
}

C.units.warden.abilities={'bulwark','challenge'};C.units.warden.mana=200;C.units.warden.manaRegen=1
C.units.beastkeeper.abilities={'thornfall','snare'};C.units.beastkeeper.mana=200;C.units.beastkeeper.manaRegen=1
C.units.worker.worker=true;C.units.worker.sight=10;C.units.siege.sight=10
for _,id in ipairs({'warden','beastkeeper'}) do C.units[id].hero=true;C.units[id].sight=14 end
for _,id in ipairs({'medic','siege','sprite','beast'}) do C.units[id].tech=true end
C.units.medic.heal=12;C.units.medic.healRange=1280
C.units.sprite.heal=10;C.units.sprite.healRange=1024
for _,id in ipairs({'neutral','scout','leader'}) do C.units[id].sight=6 end
C.units.scout.bounty=20;C.units.scout.xp=30
C.units.neutral.bounty=30;C.units.neutral.xp=50
C.units.leader.bounty=100;C.units.leader.xp=120
return C
