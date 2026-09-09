local T=require('src.content_time')
local C = {
    version = 3,
    rules = { profile='marches-v1', tickRate=20, population=80, pathBudget=256, directPathBudget=16384,
        startingResources={gold=500,lumber=150}, startingWorkers=5,
        harvestTicks=60, lumberTicks=160, carry=10, mineWorkers=5, mineInterval=20,
        reviveTicks=900, reviveCost=175, reviveTierTicks=100, reviveTierCost=25,
        xpRange=2560, xpThresholds={180,500,1000}, combatXpPerFood=20, heroXp=150,
        outOfCombatTicks=160, campLeash=2560, campResetTicks=60, acquireRange=1536,
        constructionHealth=true, tech={cost={gold=400,lumber=200},ticks=2000},
        heroHealth={warden=240,beastkeeper=200}, heroDamage=6, quickTicks=4,
        auraRadius=1536, auraWide=2048, auraExtra=512, auraDeep=2, offensiveDamage=4,
        recovery=8, recoveryUpgrade=14, pursuitSpeed=4, pursuitPenalty=4, sprintSpeed=4 },
    units = {},
    buildings = {
        hq={label='Headquarters',hp=2800,size=5,sight=14,cost={},buildTicks=1,dropoff={gold=true,lumber=true},damage=30,range=2048,cooldown=30,windup=6,baseHeal=10},
        barracks={label='War hall',hp=1500,size=4,sight=12,cost={gold=160,lumber=60},buildTicks=1200},
        depot={label='Lumber depot',hp=500,size=2,sight=12,cost={gold=80,lumber=40},buildTicks=600,dropoff={lumber=true}},
        outpost={label='Outpost',hp=1400,size=4,sight=12,cost={gold=350,lumber=180},buildTicks=1800,dropoff={gold=true,lumber=true}},
        tower={label='Watchtower',hp=700,size=2,sight=12,cost={gold=150,lumber=70},buildTicks=900,damage=26,range=1920,cooldown=32,windup=6}
    },
    factions = {
        bastion = { label = 'The Bastion', hero = 'warden', roster = { 'shield', 'crossbow', 'medic', 'siege' },
            upgrades = { { 'Wide protection', 'Deep protection' }, { 'Vanguard damage', 'Guardian health' }, { 'Quick attacks', 'Enduring aura' } } },
        wild = { label = 'The Wild Pact', hero = 'beastkeeper', roster = { 'stalker', 'thorn', 'sprite', 'beast' },
            upgrades = { { 'Rapid recovery', 'Opening sprint' }, { 'Predator damage', 'Ancient health' }, { 'Quick attacks', 'Pack recovery' } } }
    }
}
local function unit(id,label,gold,lumber,food,train,hp,damage,period,windup,range,speed,radius)
    C.units[id]={label=label,cost={gold=gold,lumber=lumber},food=food,buildTicks=T.ticks(train),hp=hp,damage=damage,
        cooldown=T.ticks(period),windup=T.ticks(windup),range=T.cells(range),speed=speed,radius=radius or 80,sight=12}
end
unit('worker','Worker',75,0,1,15,220,5,2,.3,.25,30,72)
unit('shield','Shieldguard',135,0,2,20,420,14,1.4,.3,.25,35)
unit('crossbow','Crossbow',190,30,3,26,320,22,1.6,.35,5,35)
unit('medic','Standard bearer',155,40,2,28,300,8,1.8,.3,4,35)
unit('siege','Ram',300,80,4,40,900,60,2.5,.5,.5,26,112)
unit('stalker','Stalker',130,0,2,20,340,13,1.25,.25,.25,40)
unit('thorn','Thorn thrower',180,30,3,25,280,19,1.45,.3,4.5,37)
unit('sprite','Grove sprite',150,40,2,28,250,7,1.6,.25,4,39)
unit('beast','Heavy beast',280,70,4,36,760,34,1.7,.4,.375,35,112)
unit('warden','Warden',0,0,5,0,1000,30,1.5,.3,.25,42,96)
unit('beastkeeper','Beastkeeper',0,0,5,0,900,27,1.35,.25,.25,44,96)
unit('neutral','Camp guard',0,0,0,0,360,12,1.6,.3,.25,30)
unit('scout','Camp scout',0,0,0,0,180,7,1.8,.3,.25,30)
unit('leader','Camp leader',0,0,0,0,700,24,1.8,.4,.25,28,112)
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
