-- Frozen short-duration mechanics fixture, pre-pacing content v2. Not playable balance.
local C = {
    version = 2,
    rules = { tickRate = 20, population = 60, pathBudget = 64, directPathBudget = 16384, harvestTicks = 20, carry = 10,
        reviveTicks = 200, reviveCost = 120, xpRange = 1536, xpThresholds = { 60, 160, 320 } },
    units = {
        worker = { label = 'Worker', radius = 80, windup = 4, hp = 70, damage = 3, range = 300, cooldown = 25, speed = 30, sight = 5, cost = { gold = 40 }, buildTicks = 60, worker = true },
        shield = { label = 'Shieldguard', radius = 80, windup = 4, hp = 180, damage = 13, range = 320, cooldown = 20, speed = 27, sight = 6, cost = { gold = 70, lumber = 10 }, buildTicks = 80 },
        crossbow = { label = 'Crossbow', radius = 80, windup = 4, hp = 90, damage = 16, range = 1152, cooldown = 30, speed = 28, sight = 7, cost = { gold = 80, lumber = 25 }, buildTicks = 100 },
        medic = { label = 'Standard bearer', radius = 80, windup = 4, hp = 110, damage = 6, range = 768, cooldown = 25, speed = 27, sight = 6, heal = 3, cost = { gold = 90, lumber = 30 }, buildTicks = 100 },
        siege = { label = 'Ram', radius = 112, windup = 4, hp = 280, damage = 38, range = 400, cooldown = 40, speed = 18, sight = 5, cost = { gold = 140, lumber = 70 }, buildTicks = 160 },
        stalker = { label = 'Stalker', radius = 80, windup = 4, hp = 115, damage = 12, range = 320, cooldown = 17, speed = 38, sight = 7, cost = { gold = 65, lumber = 10 }, buildTicks = 70 },
        thorn = { label = 'Thorn thrower', radius = 80, windup = 4, hp = 80, damage = 12, range = 1024, cooldown = 22, speed = 35, sight = 7, cost = { gold = 75, lumber = 25 }, buildTicks = 90 },
        sprite = { label = 'Grove sprite', radius = 80, windup = 4, hp = 75, damage = 5, range = 768, cooldown = 25, speed = 35, sight = 7, heal = 4, cost = { gold = 90, lumber = 30 }, buildTicks = 100 },
        beast = { label = 'Heavy beast', radius = 112, windup = 4, hp = 240, damage = 25, range = 360, cooldown = 28, speed = 30, sight = 6, cost = { gold = 130, lumber = 60 }, buildTicks = 140 },
        warden = { label = 'Warden', radius = 80, windup = 4, hp = 600, damage = 24, range = 350, cooldown = 20, speed = 32, sight = 8, hero = true },
        beastkeeper = { label = 'Beastkeeper', radius = 80, windup = 4, hp = 460, damage = 22, range = 350, cooldown = 18, speed = 40, sight = 8, hero = true },
        neutral = { label = 'Camp guardian', radius = 80, windup = 4, hp = 170, damage = 10, range = 340, cooldown = 25, speed = 24, sight = 5 }
    },
    buildings = {
        hq = { label = 'Headquarters', hp = 2200, size = 3, sight = 9, cost = {}, buildTicks = 1 },
        barracks = { label = 'War hall', hp = 700, size = 2, sight = 6, cost = { gold = 120, lumber = 60 }, buildTicks = 180 },
        tower = { label = 'Watchtower', windup = 4, hp = 450, size = 1, sight = 8, damage = 14, range = 1408, cooldown = 25, cost = { gold = 100, lumber = 50 }, buildTicks = 150 }
    },
    factions = {
        bastion = { label = 'The Bastion', hero = 'warden', roster = { 'shield', 'crossbow', 'medic', 'siege' },
            upgrades = { { 'Wide protection', 'Deep protection' }, { 'Vanguard damage', 'Guardian health' }, { 'Quick attacks', 'Enduring aura' } } },
        wild = { label = 'The Wild Pact', hero = 'beastkeeper', roster = { 'stalker', 'thorn', 'sprite', 'beast' },
            upgrades = { { 'Rapid recovery', 'Opening sprint' }, { 'Predator damage', 'Ancient health' }, { 'Quick attacks', 'Pack recovery' } } }
    }
}
return C
