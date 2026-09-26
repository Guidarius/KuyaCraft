-- Line-of-sight regression. Uses shipping content, because the rule that enables it
-- lives there; the fixture content keeps radial visibility.
local Sim=require('src.sim')
local F=require('src.sim.fixed')
local Maps=require('src.maps')
local C=require('src.content')
local P=require('src.sim.path')
local S=require('tests.control_scenarios')
local M={}
local function eq(a,b,message) assert(a==b,(message or 'values differ')..': '..tostring(a)..' != '..tostring(b)) end
-- An open arena with no terrain, no resources and no camps, so the only obstructions
-- are the ones a scenario puts there deliberately.
local function arena(size)
    local map=Maps.create('vision',size or 40)
    map.resources={};map.camps={};map.blocked={}
    return Sim.create({seed=7,players={{faction='orders'},{faction='orders'}}},C,map)
end
local function sees(w,player,x,y) return w.players[player].visible[P.key(w.map,x,y)]==true end
local function wall(w,x,y0,y1)
    for y=y0,y1 do w.map.blocked[P.key(w.map,x,y)]=true;w.blocked[P.key(w.map,x,y)]=true end
end

-- A wall casts a shadow: cells directly behind it are hidden, and the wall itself is
-- seen. Without line of sight every one of these cells would be visible.
function M.shadow()
    assert(C.rules.lineOfSight,'shipping content no longer enables line of sight')
    local w=arena()
    local scout=S.unit(w,'crossbow',1,10,20)
    local sight=C.units.crossbow.sight
    assert(sight>=6,'this scenario needs a scout that can see past the wall')
    wall(w,13,16,24)
    Sim.step(w,{})
    assert(sees(w,1,12,20),'the cell in front of the wall is not visible')
    assert(sees(w,1,13,20),'the wall itself must be visible')
    assert(not sees(w,1,14,20),'sight passed straight through the wall')
    assert(not sees(w,1,15,20),'sight passed straight through the wall')
    -- Around the end of the wall, at the same distance, sight is unobstructed.
    assert(sees(w,1,14,14) or sees(w,1,14,26),'the wall blocked sight around its ends too')
    -- Behind the scout, away from the wall, nothing is shadowed.
    assert(sees(w,1,10-4,20),'sight was blocked in the opposite direction')
end

-- With nothing in the way, line of sight sees the same disc the radial rule does.
-- This is what proves the shadowcast is a restriction of the old behaviour and not a
-- differently shaped field.
-- Everything except one scout is silenced, so the comparison measures that scout's
-- field alone. Buildings are excluded deliberately: line of sight moves their origin to
-- the middle of their footprint, which is a real difference from the radial rule and is
-- covered by its own scenario below.
local function soloScout(lineOfSight)
    local w=arena()
    w.content.rules.lineOfSight=lineOfSight
    local scout=S.unit(w,'crossbow',1,20,20)
    for _,id in ipairs(w.order) do local e=w.entities[id];if e.id~=scout.id then e.alive=false end end
    Sim.step(w,{})
    return w
end
function M.matchesRadialInTheOpen()
    local los=soloScout(true)
    local radial=soloScout(false)
    local width,height=los.map.width,los.map.height
    local seen,differences=0,0
    for y=0,height-1 do for x=0,width-1 do
        if sees(los,1,x,y) then seen=seen+1 end
        if sees(los,1,x,y)~=sees(radial,1,x,y) then differences=differences+1 end
    end end
    assert(seen>100,'the scout saw almost nothing, so this proves little: '..seen..' cells')
    eq(differences,0,'line of sight and radial sight disagree on empty ground')
end

-- Buildings must not be blinded by their own footprint, and they look out from their
-- middle rather than a corner.
function M.buildingsSeeOutOfThemselves()
    local w=arena()
    local base=w.entities[w.players[1].hq]
    local size=base.size
    local cx,cy=F.cell(base.x)+math.floor((size-1)/2),F.cell(base.y)+math.floor((size-1)/2)
    Sim.step(w,{})
    local seen=0
    for y=cy-3,cy+3 do for x=cx-3,cx+3 do
        if x>=0 and y>=0 and x<w.map.width and y<w.map.height and sees(w,1,x,y) then seen=seen+1 end
    end end
    assert(seen>=40,'the headquarters was blinded by its own footprint, saw '..seen..' of 49 nearby cells')
end

-- Sight is symmetric enough to matter in play: if A can see B's cell, B can see A's.
function M.reciprocal()
    local w=arena()
    wall(w,20,10,30)
    local a=S.unit(w,'crossbow',1,17,20)
    local b=S.unit(w,'crossbow',1,23,20)
    Sim.step(w,{})
    local ax,ay=F.cell(a.x),F.cell(a.y)
    local bx,by=F.cell(b.x),F.cell(b.y)
    -- Both are the same player, so compare against a fresh world where each looks alone.
    local left=arena();wall(left,20,10,30);S.unit(left,'crossbow',1,17,20);Sim.step(left,{})
    local right=arena();wall(right,20,10,30);S.unit(right,'crossbow',1,23,20);Sim.step(right,{})
    eq(sees(left,1,bx,by),sees(right,1,ax,ay),'sight through the same wall is not reciprocal')
    assert(not sees(left,1,bx,by),'the wall between them should hide both')
end

-- Fog still hides enemies, and an enemy behind a wall cannot be targeted.
function M.hidesEnemies()
    local w=arena()
    wall(w,15,10,30)
    S.unit(w,'crossbow',1,12,20)
    local hidden=S.unit(w,'footman',2,18,20)
    Sim.step(w,{})
    assert(not Sim.visible(w,1,hidden),'an enemy behind a wall was visible')
    local view=Sim.view(w,1)
    for _,e in ipairs(view.entities) do assert(e.id~=hidden.id,'a hidden enemy leaked into the view') end
end

function M.run()
    M.shadow();M.matchesRadialInTheOpen();M.buildingsSeeOutOfThemselves();M.reciprocal();M.hidesEnemies()
end
return M
