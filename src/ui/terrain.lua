-- Battlefield ground, drawn from the map's terrain types: grass, road, rock and forest.
--
-- Presentation only: it reads the map and never writes to the world. There are no image
-- files. Everything here is drawn procedurally until tile art exists, and the chunked path
-- is what a tileset renderer will reuse (docs/TERRAIN_AND_CAMERA_PLAN.md).
--
-- The ground is baked lazily into chunks of CHUNK cells at PX pixels per cell and drawn with
-- nearest filtering, so it reads as chunky pixels rather than a smear. Only chunks in view are
-- drawn; the ring around the view is baked one chunk a frame ahead of the camera. Each cell is
-- four sub-blocks a side. A sub-block takes the terrain of a point jittered by smooth noise, so
-- edges between types wobble organically instead of stepping cell by cell; the jitter stays
-- under half a cell, so the middle of every cell always shows its real type.
--
-- Variation comes from an integer hash of cell coordinates, never the simulation's PRNG.
local M={}
local PX,CHUNK,SUB=16,16,4
local SUBPX=PX/SUB
M.PX,M.CHUNK=PX,CHUNK
local GRASS,ROAD,ROCK,FOREST=1,2,3,4
M.GRASS,M.ROAD,M.ROCK,M.FOREST=GRASS,ROAD,ROCK,FOREST
local CODE={[string.byte('g')]=GRASS,[string.byte('r')]=ROAD,[string.byte('k')]=ROCK,[string.byte('f')]=FOREST}
-- Base colours, also used flat by the minimap.
M.PALETTE={
    [GRASS]={.31,.45,.25},
    [ROAD]={.56,.46,.32},
    [ROCK]={.43,.40,.37},
    [FOREST]={.15,.27,.15},
}
local function hash(x,y,seed)
    local h=(x*7919+y*104729+seed*1299709+17)%1000003
    h=(h*h+seed*7+x)%1000003
    h=(h*h+y+13)%1000003
    return h%1000
end
local function noise(x,y,spacing,seed)
    local gx,gy=math.floor(x/spacing),math.floor(y/spacing);local fx,fy=x%spacing,y%spacing
    local top=hash(gx,gy,seed)*(spacing-fx)+hash(gx+1,gy,seed)*fx
    local bottom=hash(gx,gy+1,seed)*(spacing-fx)+hash(gx+1,gy+1,seed)*fx
    return (top*(spacing-fy)+bottom*fy)/(spacing*spacing)
end
-- One terrain type per cell, from map.terrain or, for maps without one, from the flags.
function M.grid(map)
    local width,height=map.width,map.height;local grid={}
    local terrain=map.terrain
    for k=1,width*height do
        if terrain then grid[k]=CODE[terrain:byte(k)] or GRASS
        else grid[k]=map.blocked[k] and ROCK or map.unbuildable and map.unbuildable[k] and ROAD or GRASS end
    end
    return grid
end
function M.create(map)
    return {map=map,grid=M.grid(map),width=map.width,height=map.height,chunks={},baked=0}
end
function M.release(renderer)
    for _,canvas in pairs(renderer.chunks) do canvas:release() end
    renderer.chunks={}
end
local function cellType(r,x,y)
    if x<0 or y<0 or x>=r.width or y>=r.height then return ROCK end
    return r.grid[y*r.width+x+1]
end
-- The terrain a sub-block shows. Jitter is up to 1.5 sub-blocks, one for road edges, which
-- have to stay readable as three-cell strips.
local function subType(r,sx,sy)
    local own=cellType(r,math.floor(sx/SUB),math.floor(sy/SUB))
    local jx=(noise(sx,sy,5,11)-500)/1000*3
    local jy=(noise(sx,sy,5,23)-500)/1000*3
    local t=cellType(r,math.floor((sx+.5+jx)/SUB),math.floor((sy+.5+jy)/SUB))
    if t==ROAD or own==ROAD then
        -- Roads are three-cell strips, so their edges wobble on a finer, tighter noise: enough to
        -- break the staircase of a diagonal road without eating into the strip.
        t=cellType(r,math.floor((sx+.5+(noise(sx,sy,3,31)-500)/1000*2.4)/SUB),math.floor((sy+.5+(noise(sx,sy,3,37)-500)/1000*2.4)/SUB))
    end
    return t
end
local function shade(g,c,amount,alpha) g.setColor(c[1]*amount,c[2]*amount,c[3]*amount,alpha or 1) end
local function bake(r,cx,cy)
    local g=love.graphics
    local size=CHUNK*PX
    local canvas=g.newCanvas(size,size,{dpiscale=1})
    canvas:setFilter('nearest','nearest')
    local x0,y0=cx*CHUNK,cy*CHUNK
    -- Sub-block types for the chunk plus a two-sub-block border, so cliffs and shadows at the
    -- chunk's edge see their neighbours and chunks meet without seams.
    local sx0,sy0=x0*SUB-2,y0*SUB-2
    local span=CHUNK*SUB+4
    local types={}
    for j=0,span-1 do for i=0,span-1 do types[j*span+i]=subType(r,sx0+i,sy0+j) end end
    local function at(i,j)
        if i<0 or j<0 or i>=span or j>=span then return subType(r,sx0+i,sy0+j) end
        return types[j*span+i]
    end
    g.push('all');g.setCanvas(canvas);g.origin();g.setScissor();g.clear(0,0,0,1)
    -- Ground.
    for j=2,span-3 do for i=2,span-3 do
        local t=at(i,j);local sx,sy=sx0+i,sy0+j
        local base=M.PALETTE[t]
        -- Broad patches (meadows, worn ground, rock strata) plus a little per-sub-block grain.
        local broad=noise(sx,sy,14,t)/1000;local patch=noise(sx,sy,37,t+9)/1000;local fine=hash(sx,sy,t+40)/1000
        local amount=.72+broad*.22+patch*.2+fine*.07
        local px,py=(i-2)*SUBPX,(j-2)*SUBPX
        if t==ROCK then
            local below,below2,above=at(i,j+1),at(i,j+2),at(i,j-1)
            if below~=ROCK then g.setColor(.21,.18,.16)              -- cliff face, lower
            elseif below2~=ROCK then g.setColor(.30,.26,.23)          -- cliff face, upper
            elseif above~=ROCK then shade(g,base,1.25)                -- lit rim
            elseif noise(sx,sy,3,77)>640 and hash(sx,sy,78)%3==0 then shade(g,base,.62) -- cracks
            else shade(g,base,amount) end
        else
            local above,above2=at(i,j-1),at(i,j-2)
            if above==ROCK then amount=amount*.62 elseif above2==ROCK then amount=amount*.8 end
            if t==ROAD then
                local left,right=at(i-1,j),at(i+1,j)
                if left~=ROAD or right~=ROAD or at(i,j-1)~=ROAD or at(i,j+1)~=ROAD then amount=amount*.9 end
            end
            shade(g,base,amount)
        end
        g.rectangle('fill',px,py,SUBPX,SUBPX)
    end end
    -- Small detail: grass tufts, road pebbles, loose stones on rock.
    for y=y0,y0+CHUNK-1 do for x=x0,x0+CHUNK-1 do
        local t=cellType(r,x,y)
        for n=1,3 do
            local h=hash(x,y,60+n)
            local px,py=(x-x0)*PX+h%PX,(y-y0)*PX+math.floor(h/16)%PX
            local sub=at(math.floor(px/SUBPX)+2,math.floor(py/SUBPX)+2)
            if sub==t and t==GRASS and h%3==0 then
                shade(g,M.PALETTE[GRASS],h%2==0 and .7 or 1.25);g.rectangle('fill',px,py,1,2);g.rectangle('fill',px+1,py-1,1,2)
            elseif sub==t and t==ROAD and h%4==0 then
                shade(g,M.PALETTE[ROAD],1.3);g.rectangle('fill',px,py,1,1)
            elseif sub==t and t==ROCK and h%5==0 and at(math.floor(px/SUBPX)+2,math.floor(py/SUBPX)+4)==ROCK then
                shade(g,M.PALETTE[ROCK],1.5);g.rectangle('fill',px,py,2,1)
            end
        end
    end end
    -- Forest canopy: shadows first, then crowns top to bottom, from a cell's margin outside the
    -- chunk too, so crowns that overhang a chunk edge are drawn on both sides of it.
    for pass=1,2 do
        for y=y0-1,y0+CHUNK do for x=x0-1,x0+CHUNK do
            if cellType(r,x,y)==FOREST then
                local crowns=1+hash(x,y,80)%2
                for n=1,crowns do
                    local h=hash(x,y,80+n)
                    local px=(x-x0)*PX+PX/2+(h%9)-4
                    local py=(y-y0)*PX+PX/2+(math.floor(h/9)%9)-4
                    local radius=5+math.floor(h/81)%4
                    if pass==1 then
                        g.setColor(0,0,0,.35);g.circle('fill',px+2,py+3,radius,10)
                    else
                        local tone=.8+(h%5)*.07
                        g.setColor(.12*tone,.29*tone,.13*tone);g.circle('fill',px,py,radius,10)
                        g.setColor(.2*tone,.42*tone,.2*tone);g.circle('fill',px-1,py-1,radius-2,8)
                        g.setColor(.3*tone,.55*tone,.27*tone);g.circle('fill',px-2,py-2,math.max(1,radius-4),6)
                    end
                end
            end
        end end
    end
    g.pop()
    r.baked=r.baked+1
    return canvas
end
-- Draws the ground. The cell at map (0,0) has its top-left at (originX,originY) on screen, each
-- cell is cellW by cellH screen pixels, and view is the on-screen rectangle to cover.
function M.draw(r,originX,originY,cellW,cellH,view)
    local g=love.graphics
    local cx0=math.max(0,math.floor((view.x-originX)/cellW/CHUNK))
    local cy0=math.max(0,math.floor((view.y-originY)/cellH/CHUNK))
    local cx1=math.min(math.ceil(r.width/CHUNK)-1,math.floor((view.x+view.w-originX)/cellW/CHUNK))
    local cy1=math.min(math.ceil(r.height/CHUNK)-1,math.floor((view.y+view.h-originY)/cellH/CHUNK))
    local sx,sy=cellW/PX,cellH/PX
    g.setColor(1,1,1)
    for cy=cy0,cy1 do for cx=cx0,cx1 do
        local k=cy*256+cx
        local canvas=r.chunks[k]
        if not canvas then canvas=bake(r,cx,cy);r.chunks[k]=canvas end
        g.draw(canvas,originX+cx*CHUNK*cellW,originY+cy*CHUNK*cellH,0,sx,sy)
    end end
    -- Warm one chunk of the ring around the view, nearest the centre first.
    local best,bestDistance
    for cy=math.max(0,cy0-1),math.min(math.ceil(r.height/CHUNK)-1,cy1+1) do
        for cx=math.max(0,cx0-1),math.min(math.ceil(r.width/CHUNK)-1,cx1+1) do
            if not r.chunks[cy*256+cx] then
                local d=math.abs(2*cx-cx0-cx1)+math.abs(2*cy-cy0-cy1)
                if not bestDistance or d<bestDistance then best,bestDistance={cx,cy},d end
            end
        end
    end
    if best then r.chunks[best[2]*256+best[1]]=bake(r,best[1],best[2]) end
end
return M
