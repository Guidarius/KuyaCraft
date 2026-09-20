local T=require('src.content_time')
-- The Orders: the conventional half of the Brood War style pivot. Workers harvest both
-- resources and build in person, Keeps are lives, and the army trains from a Barracks.
-- Numbers follow docs/FACTIONS.md: hit points, damage, costs and supply as the design
-- reference has them; times in ticks at 20 Hz; ranges in cells; speeds scaled by 0.4 to
-- this simulation's pace. Balance numbers are the user's; windups are a working default
-- of about a quarter of the attack period.
local C = {
    version = 15,
    rules = { profile='orders-v1', tickRate=20, pathBudget=256, directPathBudget=16384, smoothBudget=8192,
        -- Two resources, in display order. Supply comes from buildings and is capped.
        resources={'substrate','charge'}, supplyFromBuildings=true, supplyCap=200,
        cancelRefundPercent=75, constructionHealth=true,
        -- Several workers on one site build faster with diminishing returns: percent of a
        -- tick's progress per tick, by how many are at work. Past the table's end the last
        -- entry holds.
        coBuild={100,150,185,210,225,235},
        -- How far a worker looks for a free patch of the same resource when its own is busy.
        harvestSearch=T.cells(6),
        outOfCombatTicks=160, acquireRange=1536,
        -- Orbital logistics: how long a landing takes, and how many items may wait in orbit.
        descentTicks=T.ticks(10), callDownQueue=5,
        -- Drop pods: how many units one holds, the wait after a launch, how many may be in
        -- flight (base plus one per tier, capped), and what a garrisoned unit takes from splash.
        podCapacity=4, podCooldown=T.ticks(15), podsBase=1, podsMax=3, garrisonDamagePercent=50,
        -- Target stacks (the Associate's weapon). Each hit adds a stack, 200 fixed-point
        -- units each; the target bursts for `burst` armour-piercing damage at
        -- base + 150% of its armour + 2 per 100 max hp stacks, and stacks fade by
        -- `decay` (+`decayPerArmor` per armour point) a tick once `grace` ticks pass
        -- without a hit. See Sim.stackThreshold.
        stacks={perHit=200, base=5, armorPercent=150, perHundredHp=2, burst=45, grace=T.ticks(.75), decay=30, decayPerArmor=6},
        formationPacing=false, preciseMovement=true, sharedPaths=true, lineOfSight=true },
    units = {},
    buildings = {
        -- Every Keep is a life: the faction is defeated only when none stands and none is
        -- under construction. It takes deliveries, trains workers, feeds ten supply and
        -- shoots.
        keep={label='Keep',hp=1500,armor=2,size=4,sight=10,cost={substrate=400},buildTicks=T.ticks(70),
            dropoff=true,supply=10,produces={'worker'},damage=20,range=T.cells(7),cooldown=T.ticks(1.5),windup=6},
        depot={label='Supply Depot',hp=500,armor=1,size=2,sight=6,cost={substrate=100},buildTicks=T.ticks(25),supply=8,requires={'keep'}},
        barracks={label='Barracks',hp=1000,armor=1,size=3,sight=8,cost={substrate=150},buildTicks=T.ticks(45),
            produces={'footman','crossbow','gryphon'},requires={'keep'}},
        sanctum={label='Sanctum',hp=900,armor=1,size=3,sight=9,cost={substrate=200,charge=100},buildTicks=T.ticks(60),
            produces={'reliquary'},requires={'keep','barracks'}},
        -- The Megacorp. Nothing is built on the ground: every building but the Orbital
        -- Command is requisitioned, produced in orbit for `buildTicks`, and lands complete
        -- inside relay coverage. The Command is unique and its loss is defeat.
        orbital_command={label='Orbital Command',hp=3500,armor=5,size=4,sight=12,cost={substrate=400},buildTicks=T.ticks(60),
            supply=10,coverage=T.cells(18),produces={'command_blimp','battleship'}},
        substrate_rig={label='Substrate Rig',hp=225,armor=0,size=1,sight=6,cost={substrate=60},buildTicks=T.ticks(15),
            onNode='substrate',income={substrate=85},incomeOffline={substrate=36},supply=4},
        charge_rig={label='Charge Rig',hp=300,armor=1,size=2,sight=6,cost={substrate=75},buildTicks=T.ticks(18),
            onNode='charge',income={charge=100},incomeOffline={charge=42}},
        mc_barracks={label='Barracks',hp=1000,armor=1,size=3,sight=8,cost={substrate=150},buildTicks=T.ticks(20)},
        med_bay={label='Med Bay',hp=800,armor=1,size=2,sight=7,cost={substrate=100,charge=50},buildTicks=T.ticks(25),requires={'mc_barracks'}},
        armory={label='Armory',hp=900,armor=1,size=2,sight=7,cost={substrate=200,charge=100},buildTicks=T.ticks(25),requires={'mc_barracks'}},
        requisition_office={label='Requisition Office',hp=900,armor=1,size=3,sight=8,cost={substrate=175,charge=25},buildTicks=T.ticks(35),tier=true,garrison=4},
        orbital_relay={label='Orbital Relay',hp=450,armor=0,size=2,sight=10,cost={substrate=125},buildTicks=T.ticks(25),coverage=T.cells(14)},
        bunker={label='Bunker',hp=400,armor=2,size=2,sight=8,cost={substrate=100},buildTicks=T.ticks(20),requires={'mc_barracks'},garrison=4,garrisonFights=true}
    },
    statuses = {},
    abilities = {
        -- The Battleship's anti-air weapon: a channelled bombardment of a circle in the
        -- sky, six pulses over three seconds, broken by any new order. The ship's gun
        -- is silent while it channels.
        barrage = { label='Barrage', hotkey='w', slot=2, target='area', range=T.cells(12), radius=T.cells(4.5),
            cooldown=T.ticks(18), castPoint=T.ticks(.25), channel={ticks=T.ticks(3),period=T.ticks(.5)},
            filter={enemy=true,air=true},
            tip='Bombards the air in a 4.5-cell circle for 14 damage every half second over 3 seconds. Moving breaks it.',
            effects={{kind='damage',amount=14}} }
    },
    factions = {
        orders = { label='The Orders', blurb='The Orders: workers, Keeps and knights. Every Keep is a life.',
            hq='keep', worker='worker', defeat='all_hq', supplyCap=200,
            buildings={'keep','depot','barracks','sanctum'},
            starting={resources={substrate=400,charge=0},units={'worker','worker','worker','worker'}},
            bot='orders' },
        megacorp = { label='The Megacorp', blurb='The Megacorp: no workers. Everything arrives from orbit, inside relay coverage.',
            hq='orbital_command', worker=false, defeat='unique_hq', supplyCap=200, coverage=true,
            buildings={'substrate_rig','charge_rig','mc_barracks','med_bay','armory','requisition_office','orbital_relay','bunker'},
            starting={resources={substrate=400,charge=0},units={'command_blimp'}},
            bot='megacorp' }
    }
}
local function unit(id,label,substrate,charge,supply,train,hp,armor,damage,period,windup,range,speed,sight,radius)
    C.units[id]={label=label,cost=charge>0 and {substrate=substrate,charge=charge} or {substrate=substrate},food=supply,
        buildTicks=T.ticks(train),hp=hp,armor=armor,damage=damage,cooldown=T.ticks(period),windup=T.ticks(windup),
        range=T.cells(range),speed=speed,sight=sight,radius=radius or 80}
end
--   id         label            sub  chg sup  train  hp  arm dmg period windup range speed sight
unit('worker',  'Worker',         50,  0,  1,   18,   60,  0,   5,  1.2,  .3,   .25,   40,   7,  72)
unit('footman', 'Footman',        50,  0,  2,   22,  140,  1,  13,  1.1,  .3,   .25,   40,   7)
unit('crossbow','Crossbow',       75,  0,  2,   28,   80,  0,  20,  2.0,  .5,   9,     34,   9)
unit('gryphon', 'Gryphon Knight',150, 50,  3,   38,  180,  2,   9,  0.6, .15,   .25,   44,   8)
-- The Reliquary: the Orders' flying healer. It has no weapon, so no cadence; it heals the
-- most hurt ally within four cells by 12 a second, from the air, through anything.
C.units.reliquary={label='Reliquary',cost={substrate=150,charge=100},food=2,buildTicks=T.ticks(45),hp=150,armor=0,
    range=0,speed=42,sight=9,radius=80,flying=true,heal=12,healRange=T.cells(4)}
-- The Crossbow is the Orders' only answer to the air: a deliberately weaker shot straight up.
C.units.crossbow.canAttackAir=true;C.units.crossbow.airDamage=10
-- The Megacorp's air: the Command Blimp carries a mobile relay and nothing else; the
-- Battleship is heavy airborne siege with a weaker gun for the air, trained at the Command.
C.units.command_blimp={label='Command Blimp',cost={substrate=100},food=0,buildTicks=T.ticks(30),hp=200,armor=0,
    range=0,speed=38,sight=11,radius=96,flying=true,coverage=T.cells(12)}
C.units.battleship={label='Battleship',cost={substrate=300,charge=200},food=6,buildTicks=T.ticks(70),hp=500,armor=3,
    damage=50,cooldown=T.ticks(3),windup=T.ticks(.75),range=T.cells(12),speed=22,sight=13,radius=112,
    flying=true,canAttackAir=true,airDamage=8,splash=T.cells(1.5),abilities={'barrage'}}
-- The Megacorp's ground army arrives by drop pod. The Associate is the workhorse and the
-- only sustained anti-air; the Medic heals; the Enforcer is the melee anchor and takes two
-- garrison slots, so it belongs on the field.
C.units.associate={label='Associate',cost={substrate=50},food=1,buildTicks=T.ticks(16),hp=55,armor=0,
    damage=6,cooldown=T.ticks(.9),windup=4,range=T.cells(5),speed=44,sight=8,radius=80,canAttackAir=true,pod=true,requires={'mc_barracks'},applyStacks=true}
C.units.medic={label='Medic',cost={substrate=50,charge=25},food=1,buildTicks=T.ticks(20),hp=70,armor=1,
    range=0,speed=44,sight=8,radius=80,heal=6,healRange=T.cells(3),pod=true,requires={'med_bay'}}
C.units.enforcer={label='Enforcer',cost={substrate=125,charge=50},food=3,buildTicks=T.ticks(30),hp=250,armor=2,
    damage=25,cooldown=T.ticks(1.4),windup=7,range=T.cells(.25),speed=32,sight=7,radius=96,pod=true,garrisonSlots=2,requires={'armory'}}
-- Workers harvest both resources: ticks per load, and how much a load is.
C.units.worker.worker=true;C.units.worker.harvest={substrate=T.ticks(2),charge=T.ticks(3)};C.units.worker.carry=8
-- A shot in flight. It is a unit definition only because every entity needs one; it has
-- no damage, no sight, no food and never moves under its own orders. What it does is in
-- src/sim/projectiles.lua, and what it does to whoever it hits is in the ability.
C.units.projectile={label='Projectile',cost={},food=0,buildTicks=0,hp=1,
    cooldown=1,windup=1,range=0,speed=1,radius=1,sight=0,projectile=true}
return C
