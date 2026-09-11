-- Line-of-sight field of view: recursive shadowcasting over eight octants.
--
-- Slopes are rational numbers held as integer numerator/denominator pairs and compared
-- by cross-multiplication, never as floats. Every denominator here is positive by
-- construction, so a comparison is a plain integer product. With a sight radius of
-- fourteen cells the largest product is under a thousand, so this is exact on any
-- platform and carries the same guarantees as the rest of the simulation.
--
-- An obstruction is any cell in w.blocked: terrain, buildings and resource nodes alike,
-- the same set that stops movement. A blocking cell is itself visible -- you can see the
-- wall, just not past it.
local F=require('src.sim.fixed')
local V={}
-- xx, xy, yx, yy per octant.
local OCTANTS={
    {1,0,0,1},{0,1,1,0},{0,-1,1,0},{-1,0,0,1},
    {-1,0,0,-1},{0,-1,-1,0},{0,1,-1,0},{1,0,0,-1},
}
-- Recording state for the field currently being built. Single-threaded and used only
-- within one V.field call, including its recursion.
local outVisible,outExplored,outKeys,outCount
local function emit(key)
    outCount=outCount+1;outKeys[outCount]=key
    outVisible[key]=true;outExplored[key]=true
end
-- ox0..oy1 is a rectangle the observer may see through regardless of w.blocked: its own
-- footprint. Without it a building would be blinded by its own body, because its sight
-- originates inside a blocked rectangle.
local function cast(w,cx,cy,radius,row,startNum,startDen,endNum,endDen,xx,xy,yx,yy,ox0,oy0,ox1,oy1)
    if startNum*endDen<=endNum*startDen then return end
    local blocked=w.blocked
    local width,height=w.map.width,w.map.height
    local radius2=radius*radius
    for j=row,radius do
        local scanning=false
        local nextStartNum,nextStartDen=startNum,startDen
        local dy=-j
        local dx=-j-1
        while dx<=0 do
            dx=dx+1
            local x=cx+dx*xx+dy*xy
            local y=cy+dx*yx+dy*yy
            -- Left and right edges of this cell, rewritten so both denominators are
            -- positive: l = (1-2dx)/(2j-1), r = (-1-2dx)/(2j+1).
            local leftNum,leftDen=1-2*dx,2*j-1
            local rightNum,rightDen=-1-2*dx,2*j+1
            if startNum*rightDen<rightNum*startDen then
                -- The beam has not reached this cell yet.
            elseif endNum*leftDen>leftNum*endDen then
                break
            else
                local inside=x>=0 and y>=0 and x<width and y<height
                -- Beyond the map edge counts as solid so the cone closes the same way.
                local solid=true
                if inside then
                    local key=y*width+x+1
                    if dx*dx+dy*dy<=radius2 then emit(key) end
                    solid=blocked[key] and not (x>=ox0 and x<=ox1 and y>=oy0 and y<=oy1) or false
                end
                if scanning then
                    if solid then nextStartNum,nextStartDen=rightNum,rightDen
                    else scanning=false;startNum,startDen=nextStartNum,nextStartDen end
                elseif solid and j<radius then
                    scanning=true
                    cast(w,cx,cy,radius,j+1,startNum,startDen,leftNum,leftDen,xx,xy,yx,yy,ox0,oy0,ox1,oy1)
                    nextStartNum,nextStartDen=rightNum,rightDen
                end
            end
        end
        if scanning then break end
    end
end
-- A field depends on exactly two things: where the observer stands and which cells
-- block sight. An observer that has not changed cell, on a map whose obstructions have
-- not changed, sees precisely what it saw last tick. Replaying a recorded field is a
-- table write per cell instead of the whole shadowcast, which matters because buildings
-- never move and most of an economy stands still. The cache is keyed by world with weak
-- keys and wiped whenever navVersion changes, which is also what prunes dead entities.
--
-- Cells on an octant boundary are recorded twice. That is left alone deliberately:
-- de-duplicating costs more than the handful of repeated writes it would save, and a
-- repeated write cannot change the result.
local caches=setmetatable({},{__mode='k'})
local function cacheFor(w)
    local cache=caches[w]
    if not cache or cache.version~=w.navVersion then cache={version=w.navVersion,fields={}};caches[w]=cache end
    return cache.fields
end
-- Mark everything the entity can see. Sight originates at the middle of the entity's
-- footprint rather than its corner, so a large building looks out from its centre.
function V.field(w,e,sight,visible,explored)
    local size=e.size or 1
    local offset=math.floor((size-1)/2)
    local cx,cy=F.cell(e.x)+offset,F.cell(e.y)+offset
    local width,height=w.map.width,w.map.height
    if cx<0 or cy<0 or cx>=width or cy>=height then return end
    local origin=cy*width+cx+1
    local fields=cacheFor(w)
    local recorded=fields[e.id]
    if recorded and recorded.origin==origin and recorded.sight==sight then
        local keys=recorded.keys
        for i=1,recorded.count do local key=keys[i];visible[key]=true;explored[key]=true end
        return
    end
    if not recorded then recorded={keys={}};fields[e.id]=recorded end
    recorded.origin=origin;recorded.sight=sight
    outVisible,outExplored,outKeys,outCount=visible,explored,recorded.keys,0
    emit(origin)
    local ox0,oy0=F.cell(e.x),F.cell(e.y)
    local ox1,oy1=ox0+size-1,oy0+size-1
    for i=1,8 do
        local o=OCTANTS[i]
        cast(w,cx,cy,sight,1,1,1,0,1,o[1],o[2],o[3],o[4],ox0,oy0,ox1,oy1)
    end
    recorded.count=outCount
    outVisible,outExplored,outKeys=nil,nil,nil
end
return V
