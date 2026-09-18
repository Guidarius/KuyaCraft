-- Integer geometry shared by navigation, occupancy and weapons. No engine APIs.
local F=require('src.sim.fixed')
local Stats=require('src.sim.stats')
local G={}
-- Rebuilt for each step and after spawn/revival. These derived buckets are
-- discarded before step returns and are never snapshot/serialization state.
function G.beginStep(w) w._geometryActive=true;w._geometry=nil end
function G.endStep(w) w._geometryActive=nil;w._geometry=nil end
function G.invalidate(w) w._geometry=nil end
local function index(w)
    if not w._geometry then
        local bins={}
        for _,id in ipairs(w.order) do local e=w.entities[id];if e.alive and e.category=='unit' then
            local key=F.cell(e.y)*256+F.cell(e.x);bins[key]=bins[key] or {};bins[key][#bins[key]+1]=e
        end end
        w._geometry=bins
    end
    return w._geometry
end
function G.radius(w,e) return e.category=='unit' and w.content.units[e.kind].radius or 0 end
function G.rectangleDistance2(x,y,left,top,right,bottom)
    local tx=math.max(left,math.min(x,right));local ty=math.max(top,math.min(y,bottom))
    return F.distance2Bounded(x,y,tx,ty)
end
function G.terrain(w,x,y,r)
    if x-r<0 or y-r<0 or x+r>w.map.width*256 or y+r>w.map.height*256 then return false end
    for cy=F.cell(y-r),F.cell(y+r) do for cx=F.cell(x-r),F.cell(x+r) do
        if w.blocked[cy*w.map.width+cx+1] and G.rectangleDistance2(x,y,cx*256,cy*256,(cx+1)*256,(cy+1)*256)<r*r then return false end
    end end
    return true
end
-- Allies compress to 75% of their combined radii. Exposed by radius so a hot loop that already
-- has both radii in hand need not look them up again.
function G.alliedGap(ra,rb) return math.floor((ra+rb)*3/4) end
function G.separation(w,a,b)
    local ra,rb=G.radius(w,a),G.radius(w,b)
    return a.owner==b.owner and G.alliedGap(ra,rb) or ra+rb
end
-- How far allies may be pressed together by a unit squeezing past, as a percentage of their
-- combined radii. Below G.separation, above this. Enemies never press: it equals separation.
G.PRESS=65
function G.pressedSeparation(w,a,b)
    local r=G.radius(w,a)+G.radius(w,b)
    return a.owner==b.owner and math.floor(r*G.PRESS/100) or r
end
local function blocks(w,e,x,y,r,except)
        -- A flyer blocks nothing on the ground.
        if e.alive and e.category=='unit' and e.id~=except and not e.garrisoned and not w.content.units[e.kind].flying then
            local gap=r+G.radius(w,e)
            if math.abs(x-e.x)<gap and math.abs(y-e.y)<gap and F.distance2Bounded(x,y,e.x,e.y)<gap*gap then return true end
        end
        return false
    end
function G.free(w,x,y,r,except)
    if not G.terrain(w,x,y,r) then return false end
    if w._geometryActive then
        local bins=index(w)
        for cy=F.cell(y)-1,F.cell(y)+1 do for cx=F.cell(x)-1,F.cell(x)+1 do
            for _,e in ipairs(bins[cy*256+cx] or {}) do if blocks(w,e,x,y,r,except) then return false end end
        end end
    else
        for _,id in ipairs(w.order) do if blocks(w,w.entities[id],x,y,r,except) then return false end end
    end
    return true
end
function G.weaponRangeAt(w,e,x,y,t,extra)
    -- Reach comes from the resolver, so anything that lengthens or shortens a weapon
    -- reaches every range check in the game through this one call.
    local range=Stats.range(w,e)+G.radius(w,e)+(extra or 0)
    if t.category=='building' then
        return G.rectangleDistance2(x,y,t.x-128,t.y-128,t.x-128+t.size*256,t.y-128+t.size*256)<=range*range
    end
    range=range+G.radius(w,t)
    return F.distance2Bounded(x,y,t.x,t.y)<=range*range
end
-- A building shoots from the edge of its footprint nearest the target, so a wide building's
-- range means reach past its wall on every side rather than from its origin cell.
function G.weaponRange(w,e,t,extra)
    local x,y=e.x,e.y
    if e.category=='building' then
        local size=e.size or 1
        x=math.max(e.x-128,math.min(t.x,e.x-128+size*256));y=math.max(e.y-128,math.min(t.y,e.y-128+size*256))
    end
    return G.weaponRangeAt(w,e,x,y,t,extra)
end
return G
