local T=require('src.content_time')
-- The Orders: the conventional half of the Brood War style pivot. Workers harvest both
-- resources and build in person, Keeps are lives, and the army trains from a Barracks.
-- Numbers follow docs/FACTIONS.md: hit points, damage, costs and supply as the design
-- reference has them; times in ticks at 20 Hz; ranges in cells; speeds scaled by 0.4 to
-- this simulation's pace. Balance numbers are the user's; windups are a working default
-- of about a quarter of the attack period.
local C = {
    version = 11,
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
        formationPacing=true, lineOfSight=true },
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
            produces={'reliquary'},requires={'keep','barracks'}}
    },
    statuses = {},
    abilities = {},
    factions = {
        orders = { label='The Orders', blurb='The Orders: workers, Keeps and knights. Every Keep is a life.',
            hq='keep', worker='worker', defeat='all_hq', supplyCap=200,
            buildings={'keep','depot','barracks','sanctum'},
            starting={resources={substrate=400,charge=0},units={'worker','worker','worker','worker'}},
            bot='orders' }
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
-- Workers harvest both resources: ticks per load, and how much a load is.
C.units.worker.worker=true;C.units.worker.harvest={substrate=T.ticks(2),charge=T.ticks(3)};C.units.worker.carry=8
-- A shot in flight. It is a unit definition only because every entity needs one; it has
-- no damage, no sight, no food and never moves under its own orders. What it does is in
-- src/sim/projectiles.lua, and what it does to whoever it hits is in the ability.
C.units.projectile={label='Projectile',cost={},food=0,buildTicks=0,hp=1,
    cooldown=1,windup=1,range=0,speed=1,radius=1,sight=0,projectile=true}
return C
