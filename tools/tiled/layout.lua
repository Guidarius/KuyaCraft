-- Helpers for a code-authored map layout, the generator's input (tools/tiled/generate).
-- A layout is written for player one and everything is rotated 180 degrees for player two:
-- a cell (x,y) becomes (W-1-x,H-1-y) and a footprint origin (W-x-size,H-y-size). The map
-- starts solid rock and is carved open. tools/tiled/twin_marches_legacy.lua predates this
-- file and keeps its own copy of the same helpers so its output never moves.
--
-- Field patterns are the Twin Marches ones, given as offsets so every map's bases mine
-- alike: a main has seven one-cell substrate patches in an arc and a two-cell charge geyser,
-- a natural six and a geyser, a third base four and a geyser. `fx`/`fy` of -1 flip a pattern
-- about its keep or anchor, so a base may face any way.
local MAIN={patches={{-2,-4},{-1,-6},{1,-7},{3,-7},{5,-7},{7,-6},{8,-4}},geyser={10,-2},
    units={{8,-2},{-4,-3},{-3,-3},{-2,-3},{-1,-3},{6,-3}}}
local NATURAL={patches={{7,-4},{9,-3},{10,-1},{10,1},{10,3},{9,5}},geyser={6,6}}
local THIRD={patches={{-5,-2},{-6,0},{-6,2},{-5,4}},geyser={-9,1}}
return function(id,W,H)
    local m={id=id,width=W,height=H,blocked={},unbuildable={},resources={},camps={},starts={},unitStarts={{},{}},
        anchors={naturals={},forward={},contested={}},controlPoints={},forestCells={},forestRects={}}
    local L={map=m,MAIN=MAIN,NATURAL=NATURAL,THIRD=THIRD}
    local function key(x,y) return y*W+x+1 end
    local function inside(x,y) return x>=0 and y>=0 and x<W and y<H end
    for y=0,H-1 do for x=0,W-1 do m.blocked[key(x,y)]=true end end
    local function open(x,y) if inside(x,y) then m.blocked[key(x,y)]=nil;m.blocked[key(W-1-x,H-1-y)]=nil end end
    local function close(x,y) if inside(x,y) then m.blocked[key(x,y)]=true;m.blocked[key(W-1-x,H-1-y)]=true end end
    -- A square of open ground, radius r, and an open or solid rectangle.
    function L.carve(x,y,r) for cy=y-r,y+r do for cx=x-r,x+r do open(cx,cy) end end end
    -- A disc reads less like a box once the generator has roughened its edge.
    function L.disc(x,y,r) for cy=y-r,y+r do for cx=x-r,x+r do if (cx-x)*(cx-x)+(cy-y)*(cy-y)<=r*r then open(cx,cy) end end end end
    function L.rect(x0,y0,x1,y1) for cy=y0,y1 do for cx=x0,x1 do open(cx,cy) end end end
    function L.rock(x0,y0,x1,y1) for cy=y0,y1 do for cx=x0,x1 do close(cx,cy) end end end
    local function walk(points,fn)
        for i=2,#points do local a,b=points[i-1],points[i]
            local steps=math.max(math.abs(b[1]-a[1]),math.abs(b[2]-a[2]),1)
            for j=0,steps do fn(math.floor(a[1]+(b[1]-a[1])*j/steps),math.floor(a[2]+(b[2]-a[2])*j/steps)) end
        end
    end
    function L.corridor(points,r) walk(points,function(x,y) L.carve(x,y,r) end) end
    -- A road: walkable, three cells wide, and nobody may build on it.
    function L.road(points)
        walk(points,function(x,y)
            L.carve(x,y,1)
            for cy=y-1,y+1 do for cx=x-1,x+1 do if inside(cx,cy) then
                m.unbuildable[key(cx,cy)]=true;m.unbuildable[key(W-1-cx,H-1-cy)]=true
            end end end
        end)
    end
    function L.node(x,y,size,resource,amount)
        assert(inside(x,y) and inside(x+size-1,y+size-1),id..': a '..resource..' node at '..x..','..y..' is off the map')
        m.resources[#m.resources+1]={x=x,y=y,resource=resource,amount=amount,size=size}
        m.resources[#m.resources+1]={x=W-x-size,y=H-y-size,resource=resource,amount=amount,size=size}
        for cy=y,y+size-1 do for cx=x,x+size-1 do open(cx,cy) end end
    end
    -- A pattern of patches and a geyser about an origin. `span` is the footprint the pattern
    -- was drawn around (4 for a keep, 1 for an anchor cell), which is what a flip turns about.
    local function field(pattern,ox,oy,span,fx,fy,patchAmount,geyserAmount)
        local function place(offset,size)
            local dx,dy=offset[1],offset[2]
            if fx==-1 then dx=span-size-dx end
            if fy==-1 then dy=span-size-dy end
            return ox+dx,oy+dy
        end
        for _,p in ipairs(pattern.patches) do local x,y=place(p,1);L.node(x,y,1,'substrate',patchAmount) end
        local gx,gy=place(pattern.geyser,2);L.node(gx,gy,2,'charge',geyserAmount)
        return place
    end
    -- Player one's headquarters at (x,y) with its main field and starting units; player two's
    -- is the rotation. The start box is five cells, as the simulation's spawn rules expect.
    function L.base(x,y,fx,fy)
        m.starts[1]={x=x,y=y};m.starts[2]={x=W-x-5,y=H-y-5}
        local place=field(MAIN,x,y,4,fx or 1,fy or 1,1500,5000)
        for _,u in ipairs(MAIN.units) do
            local ux,uy=place(u,1);open(ux,uy)
            m.unitStarts[1][#m.unitStarts[1]+1]={x=ux,y=uy};m.unitStarts[2][#m.unitStarts[2]+1]={x=W-1-ux,y=H-1-uy}
        end
    end
    -- An expansion: the anchor the bots build at, and its field. kind is naturals, forward or
    -- contested; every map gives one of each per player because the bots and tests read them.
    function L.expansion(kind,x,y,pattern,fx,fy,patchAmount,geyserAmount)
        local list=m.anchors[kind];list[1]={x=x,y=y};list[2]={x=W-1-x,y=H-1-y}
        field(pattern,x,y,1,fx or 1,fy or 1,patchAmount,geyserAmount)
    end
    -- Woods: blocks movement and sight. The generator grows each rectangle into a grove.
    function L.forest(x0,y0,x1,y1)
        m.forestRects[#m.forestRects+1]={x0,y0,x1,y1}
        for y=y0,y1 do for x=x0,x1 do if inside(x,y) then
            local k,mirror=key(x,y),key(W-1-x,H-1-y)
            local free=not m.unbuildable[k] and not m.unbuildable[mirror]
            for _,n in ipairs(m.resources) do if x>=n.x and x<n.x+n.size and y>=n.y and y<n.y+n.size then free=false end end
            if free then m.blocked[k]=true;m.blocked[mirror]=true;m.forestCells[k]=true;m.forestCells[mirror]=true end
        end end end
    end
    -- Last: nothing is paved under a node or a headquarters, and nothing that must be open is shut.
    function L.finish()
        local function unpave(x0,y0,size) for y=y0,y0+size-1 do for x=x0,x0+size-1 do m.unbuildable[key(x,y)]=nil;m.blocked[key(x,y)]=nil;m.forestCells[key(x,y)]=nil end end end
        for _,n in ipairs(m.resources) do unpave(n.x,n.y,n.size) end
        for _,s in ipairs(m.starts) do unpave(s.x,s.y,5) end
        for _,list in ipairs(m.unitStarts) do for _,u in ipairs(list) do unpave(u.x,u.y,1) end end
        for _,kind in ipairs({'naturals','forward','contested'}) do assert(#m.anchors[kind]==2,id..': no '..kind..' anchors') end
        assert(#m.starts==2,id..': no base');return m
    end
    return L
end
