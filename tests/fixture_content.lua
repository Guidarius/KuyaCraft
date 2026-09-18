-- Frozen short-duration mechanics fixture, pre-pacing content v2. Not playable balance.
local C = {
    version = 2,
    rules = { tickRate = 20, population = 60, pathBudget = 64, directPathBudget = 16384,
        -- Small like the path budget, so the crowd fixtures exercise the smoother's
        -- exhaustion path rather than always having room to finish.
        smoothBudget = 2048,
        startingResources = { gold = 650 }, startingWorkers = 3,
        carrierPayload = 8, carrierEmitTicks = 16, carrierSlots = 9, carrierCorpseTicks = 40,
        reviveTicks = 200, reviveCost = 120, xpRange = 1536, xpThresholds = { 60, 160, 320 },
        -- Matches the shipping rule, so the crowd fixtures exercise formation pacing
        -- rather than silently skipping it.
        formationPacing = true },
    units = {
        worker = { label = 'Worker', radius = 80, windup = 4, hp = 70, damage = 3, range = 300, cooldown = 25, speed = 30, sight = 5, cost = { gold = 40 }, buildTicks = 60, worker = true },
        shield = { label = 'Shieldguard', radius = 80, windup = 4, hp = 180, damage = 13, range = 320, cooldown = 20, speed = 27, sight = 6, cost = { gold = 80 }, buildTicks = 80 },
        crossbow = { label = 'Crossbow', radius = 80, windup = 4, hp = 90, damage = 16, range = 1152, cooldown = 30, speed = 28, sight = 7, cost = { gold = 105 }, buildTicks = 100 },
        medic = { label = 'Standard bearer', radius = 80, windup = 4, hp = 110, damage = 6, range = 768, cooldown = 25, speed = 27, sight = 6, heal = 3, cost = { gold = 120 }, buildTicks = 100 },
        siege = { label = 'Ram', radius = 112, windup = 4, hp = 280, damage = 38, range = 400, cooldown = 40, speed = 18, sight = 5, cost = { gold = 210 }, buildTicks = 160 },
        stalker = { label = 'Stalker', radius = 80, windup = 4, hp = 115, damage = 12, range = 320, cooldown = 17, speed = 38, sight = 7, cost = { gold = 75 }, buildTicks = 70 },
        thorn = { label = 'Thorn thrower', radius = 80, windup = 4, hp = 80, damage = 12, range = 1024, cooldown = 22, speed = 35, sight = 7, cost = { gold = 100 }, buildTicks = 90 },
        sprite = { label = 'Grove sprite', radius = 80, windup = 4, hp = 75, damage = 5, range = 768, cooldown = 25, speed = 35, sight = 7, heal = 4, cost = { gold = 120 }, buildTicks = 100 },
        beast = { label = 'Heavy beast', radius = 112, windup = 4, hp = 240, damage = 25, range = 360, cooldown = 28, speed = 30, sight = 6, cost = { gold = 190 }, buildTicks = 140 },
        warden = { label = 'Warden', radius = 80, windup = 4, hp = 600, damage = 24, range = 350, cooldown = 20, speed = 32, sight = 8, hero = true },
        beastkeeper = { label = 'Beastkeeper', radius = 80, windup = 4, hp = 460, damage = 22, range = 350, cooldown = 18, speed = 40, sight = 8, hero = true },
        neutral = { label = 'Camp guardian', radius = 80, windup = 4, hp = 170, damage = 10, range = 340, cooldown = 25, speed = 24, sight = 5 },
        -- The two other camp kinds the shipping Twin Marches places, so the rendered suite can
        -- run this fixture on that map. Never spawned by the fixture maps themselves.
        scout = { label = 'Camp scout', radius = 80, windup = 4, hp = 90, damage = 6, range = 340, cooldown = 25, speed = 30, sight = 5 },
        leader = { label = 'Camp leader', radius = 112, windup = 4, hp = 320, damage = 18, range = 340, cooldown = 28, speed = 24, sight = 5 },
        carrier = { label = 'Gold carrier', radius = 56, hp = 40, cooldown = 1, windup = 1, range = 0, speed = 40, sight = 0, food = 0, buildTicks = 0, cost = {}, carrier = true },
        projectile = { label = 'Projectile', radius = 1, hp = 1, cooldown = 1, windup = 1, range = 0, speed = 1, sight = 0, food = 0, buildTicks = 0, cost = {}, projectile = true }
    },
    buildings = {
        hq = { label = 'Headquarters', hp = 2200, size = 3, sight = 9, cost = {}, buildTicks = 1, dropoff = true },
        extractor = { label = 'Extractor', hp = 400, size = 3, sight = 5, cost = { gold = 120 }, buildTicks = 60, extractor = true },
        outpost = { label = 'Outpost', hp = 600, size = 2, sight = 8, cost = { gold = 300 }, buildTicks = 200, dropoff = true },
        barracks = { label = 'War hall', hp = 700, size = 2, sight = 6, cost = { gold = 180 }, buildTicks = 180 },
        tower = { label = 'Watchtower', windup = 4, hp = 450, size = 1, sight = 8, damage = 14, range = 1408, cooldown = 25, cost = { gold = 150 }, buildTicks = 150 }
    },
    factions = {
        bastion = { label = 'The Bastion', hero = 'warden', roster = { 'shield', 'crossbow', 'medic', 'siege' },
            upgrades = { { 'Wide protection', 'Deep protection' }, { 'Vanguard damage', 'Guardian health' }, { 'Quick attacks', 'Enduring aura' } } },
        wild = { label = 'The Wild Pact', hero = 'beastkeeper', roster = { 'stalker', 'thorn', 'sprite', 'beast' },
            upgrades = { { 'Rapid recovery', 'Opening sprint' }, { 'Predator damage', 'Ancient health' }, { 'Quick attacks', 'Pack recovery' } } }
    }
}
-- Abilities for the mechanics fixture. Round numbers and short durations, chosen so a
-- scenario can assert an exact hit point total rather than a range, and so one covers
-- each of the four target kinds. These are additions: no existing fixture unit gains an
-- ability, so every scenario written before them behaves exactly as it did.
C.statuses={
    guard={stack='max',beneficial=true,modifiers={armor=0}},
    slow={stack='refresh',modifiers={speedPercent=0}},
    root={stack='refresh',flags={noMove=true}},
    stun={stack='refresh',flags={noMove=true,noAttack=true,noCast=true}},
    burn={stack='refresh',period=20,effects={{kind='damage',amount=1}}}
}
C.abilities={
    ward={label='Ward',slot=2,target='none',radius=1024,filter={ally=true,self=true},
        cost={mana=20},cooldown=40,castPoint=4,backswing=4,
        effects={{kind='status',status='guard',ticks=100,magnitude=5}}},
    smite={label='Smite',slot=3,target='unit',range=1024,filter={enemy=true},
        cost={mana=30},cooldown=40,castPoint=4,backswing=4,
        effects={{kind='damage',amount=50},{kind='status',status='slow',ticks=40,percent=-50}}},
    scorch={label='Scorch',slot=2,target='area',range=2048,radius=768,filter={enemy=true},
        cost={mana=30},cooldown=40,castPoint=4,backswing=4,
        effects={{kind='damage',amount=20},{kind='status',status='burn',ticks=60,amount=10}}},
    -- Instant line: the hitscan path, kept so both direction resolutions stay covered.
    lash={label='Lash',slot=3,target='direction',range=1536,width=256,filter={enemy=true},
        cost={mana=25},cooldown=40,castPoint=4,backswing=4,
        effects={{kind='damage',amount=15},{kind='status',status='stun',ticks=40}}},
    -- Thrown line: the same geometry with a position that advances, so it can be dodged.
    dart={label='Dart',slot=4,target='direction',range=1536,width=256,filter={enemy=true},
        cost={mana=25},cooldown=40,castPoint=4,backswing=4,
        effects={{kind='projectile',speed=64,radius=128,
            onHit={{kind='damage',amount=15},{kind='status',status='stun',ticks=40}}}}}
}
C.units.warden.abilities={'ward','smite'};C.units.warden.mana=100;C.units.warden.manaRegen=1
C.units.beastkeeper.abilities={'scorch','lash','dart'};C.units.beastkeeper.mana=100;C.units.beastkeeper.manaRegen=1
return C
