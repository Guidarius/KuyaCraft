-- One-time generator: lays out maps/twin_marches.tmx from the code-authored map in
-- tools/tiled/twin_marches_legacy.lua, with organic coastlines, wooded coves and forest groves
-- in place of carved squares and rectangles. After this the .tmx is the source and is edited in
-- Tiled; rerunning the generator overwrites hand edits, so it refuses without --force when the
-- .tmx already exists.
--
-- What it keeps: every base, gold mine, road, camp, control point, anchor and unit start, in
-- the same cells and order, and the 180-degree rotation symmetry. What it changes:
--   - bays cut into dead rock, at most MAX_BAY cells deep and only where every nearby open cell
--     is a short walk from the bay's own side; cells three or more deep become woods, so coves
--     read as forest and the buildable area barely grows;
--   - outcrops of at most two cells onto open ground, away from roads and footprints;
--   - each forest rectangle becomes a grove of three lobes, with a sparse fringe along rock.
-- Then it measures walking distance between every pair of key places against the old map. A
-- route more than 3% shorter (a bay on the inside of a bend lets it cut the corner) or 6%
-- longer is repaired by restoring the old terrain along it, and the check runs again.
--
-- Usage: lovec tools/tiled/generate <project root> [--force]
local W,H,N
local GRASS,ROAD,ROCK,FOREST=1,2,3,4
local MAX_BAY=12
local function key(x,y) return y*W+x+1 end
local function coords(k) return (k-1)%W,math.floor((k-1)/W) end
local function mirrorKey(k) local x,y=coords(k);return key(W-1-x,H-1-y) end
local function blocks(t) return t==ROCK or t==FOREST end
-- Integer hash and bilinear value noise, evaluated at the canonical cell of each rotated pair.
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
    return math.floor((top*(spacing-fy)+bottom*fy)/(spacing*spacing))
end
local function canonical(x,y)
    local mx,my=W-1-x,H-1-y
    if key(mx,my)<key(x,y) then return mx,my end
    return x,y
end
local function symmetrise(set) for k=1,N do local mk=mirrorKey(k);if mk>k then set[mk]=set[k] end end end
-- Chebyshev distance from every cell to the nearest source cell.
local function distanceFrom(isSource)
    local d,queue,head={},{},1
    for k=1,N do if isSource(k) then d[k]=0;queue[#queue+1]=k end end
    while queue[head] do
        local k=queue[head];head=head+1;local x,y=coords(k)
        for dy=-1,1 do for dx=-1,1 do
            local nx,ny=x+dx,y+dy
            if nx>=0 and ny>=0 and nx<W and ny<H then local nk=key(nx,ny);if not d[nk] then d[nk]=d[k]+1;queue[#queue+1]=nk end end
        end end
    end
    for k=1,N do d[k]=d[k] or 1e9 end
    return d
end
-- Walking cost on an 8-way grid, straight 5 and diagonal 7, no corner cutting.
local function walking(grid,startKey)
    local d={[startKey]=0};local buckets={[0]={startKey}};local cost=0;local maxCost=0
    while cost<=maxCost do
        local bucket=buckets[cost]
        if bucket then
            for i=1,#bucket do local k=bucket[i]
                if d[k]==cost then
                    local x,y=coords(k)
                    for dy=-1,1 do for dx=-1,1 do if dx~=0 or dy~=0 then
                        local nx,ny=x+dx,y+dy
                        if nx>=0 and ny>=0 and nx<W and ny<H then
                            local nk=key(nx,ny)
                            if not blocks(grid[nk]) and (dx==0 or dy==0 or (not blocks(grid[key(nx,y)]) and not blocks(grid[key(x,ny)]))) then
                                local c=cost+((dx==0 or dy==0) and 5 or 7)
                                if not d[nk] or c<d[nk] then d[nk]=c;buckets[c]=buckets[c] or {};local b=buckets[c];b[#b+1]=nk;if c>maxCost then maxCost=c end end
                            end
                        end
                    end end end
                end
            end
            buckets[cost]=nil
        end
        cost=cost+1
    end
    return d
end
-- The cells of one shortest walk from `from` to `to`, given distances from `from`.
local function trace(grid,dist,to)
    local cells={to};local k=to
    while dist[k]>0 do
        local x,y=coords(k);local best,bestCost
        for dy=-1,1 do for dx=-1,1 do if dx~=0 or dy~=0 then
            local nx,ny=x+dx,y+dy
            if nx>=0 and ny>=0 and nx<W and ny<H then
                local nk=key(nx,ny);local step=(dx==0 or dy==0) and 5 or 7
                if dist[nk] and dist[nk]+step==dist[k] and (not bestCost or dist[nk]<bestCost) then best,bestCost=nk,dist[nk] end
            end
        end end end
        if not best then break end
        k=best;cells[#cells+1]=k
    end
    return cells
end
local function write(path,text) local f=assert(io.open(path,'wb'));f:write(text);f:close() end
function love.load(args)
    local root=(args[1] or '.'):gsub('\\','/'):gsub('/$','')..'/'
    local force=false;for _,a in ipairs(args) do if a=='--force' then force=true end end
    local out=root..'maps/twin_marches.tmx'
    local existing=io.open(out,'rb')
    if existing then existing:close();if not force then print('REFUSED '..out..' exists; it is the hand-edited source now. Pass --force to overwrite it.');love.event.quit(1);return end end
    local L=dofile(root..'tools/tiled/twin_marches_legacy.lua')()
    W,H=L.width,L.height;N=W*H

    local legacy={}
    for k=1,N do
        legacy[k]=L.unbuildable[k] and not L.blocked[k] and ROAD or L.forestCells[k] and FOREST or L.blocked[k] and ROCK or GRASS
    end

    -- Places that must stay exactly as they are, with a margin around each.
    local protected={}
    local function protect(x0,y0,x1,y1) for y=math.max(0,y0),math.min(H-1,y1) do for x=math.max(0,x0),math.min(W-1,x1) do protected[key(x,y)]=true end end end
    for _,n in ipairs(L.resources) do protect(n.x-2,n.y-2,n.x+n.size+1,n.y+n.size+1) end
    for _,s in ipairs(L.starts) do protect(s.x-3,s.y-3,s.x+7,s.y+7) end
    for _,c in ipairs(L.camps) do protect(c.x-2,c.y-2,c.x+2,c.y+2) end
    for _,list in ipairs(L.unitStarts) do for _,u in ipairs(list) do protect(u.x-1,u.y-1,u.x+1,u.y+1) end end
    for _,group in pairs(L.anchors) do for _,a in ipairs(group) do protect(a.x-3,a.y-3,a.x+3,a.y+3) end end
    for _,p in ipairs(L.controlPoints) do protect(p.x-6,p.y-6,p.x+6,p.y+6) end
    local roadDistance=distanceFrom(function(k) return legacy[k]==ROAD end)
    local protectedDistance=distanceFrom(function(k) return protected[k] end)
    local toOpen=distanceFrom(function(k) return legacy[k]~=ROCK end)
    local toRock=distanceFrom(function(k) return legacy[k]==ROCK end)

    -- Where a bay may open: every open cell near it must be a short walk from its own nearest
    -- open cell, so the bay is a dead end off one area and never a passage between two.
    local seed={};do
        local queue,head={},1
        for k=1,N do if legacy[k]~=ROCK then seed[k]=k;queue[#queue+1]=k end end
        while queue[head] do
            local k=queue[head];head=head+1;local x,y=coords(k)
            for dy=-1,1 do for dx=-1,1 do local nx,ny=x+dx,y+dy
                if nx>=0 and ny>=0 and nx<W and ny<H then local nk=key(nx,ny);if not seed[nk] then seed[nk]=seed[k];queue[#queue+1]=nk end end
            end end
        end
    end
    local walks={}
    local function localWalk(from)
        local d=walks[from]
        if not d then
            d={[from]=0};local queue,head={from},1
            while queue[head] do
                local k=queue[head];head=head+1
                if d[k]<60 then
                    local x,y=coords(k)
                    for dy=-1,1 do for dx=-1,1 do local nx,ny=x+dx,y+dy
                        if nx>=0 and ny>=0 and nx<W and ny<H then local nk=key(nx,ny)
                            if legacy[nk]~=ROCK and not d[nk] then d[nk]=d[k]+1;queue[#queue+1]=nk end
                        end
                    end end
                end
            end
            walks[from]=d
        end
        return d
    end
    local safe={}
    for k=1,N do
        if legacy[k]==ROCK and toOpen[k]<=MAX_BAY then
            local x,y=coords(k);local from=seed[k];local fx,fy=coords(from);local walk=localWalk(from)
            local ok=true;local reach=toOpen[k]+6
            for dy=-reach,reach do if not ok then break end for dx=-reach,reach do
                local nx,ny=x+dx,y+dy
                if nx>=0 and ny>=0 and nx<W and ny<H then local nk=key(nx,ny)
                    if legacy[nk]~=ROCK then
                        local straight=math.max(math.abs(nx-fx),math.abs(ny-fy))
                        if not walk[nk] or walk[nk]>straight*3/2+6 then ok=false;break end
                    end
                end
            end end
            safe[k]=ok
        end
    end
    for k=1,N do local mk=mirrorKey(k)
        if mk>k then local both=(safe[k] and safe[mk]) and true or nil;safe[k]=both;safe[mk]=both end
    end

    -- Coastline. Slow noise, contrast-stretched, decides bay depth; fine noise roughens edges.
    local rock={}
    for k=1,N do
        local x,y=coords(k);local cx,cy=canonical(x,y)
        local stretched=math.max(0,math.min(999,math.floor((noise(cx,cy,27,1)-500)*9/5)+500))
        local n=math.floor(stretched*(MAX_BAY+5)/1000)-4+math.floor(noise(cx,cy,4,2)*3/1000)-1
        local border=x<2 or y<2 or x>W-3 or y>H-3
        if legacy[k]==ROCK then
            rock[k]=border or not (safe[k] and toOpen[k]<=n)
        else
            rock[k]=legacy[k]~=ROAD and 1-toRock[k]-math.max(-2,n)>=1 and roadDistance[k]>=5 and protectedDistance[k]>=3
        end
    end
    symmetrise(rock)
    for _=1,2 do
        local next={}
        for k=1,N do
            local x,y=coords(k);local count=0
            for dy=-1,1 do for dx=-1,1 do if dx~=0 or dy~=0 then
                local nx,ny=x+dx,y+dy
                if nx<0 or ny<0 or nx>=W or ny>=H or rock[key(nx,ny)] then count=count+1 end
            end end end
            local canClose=legacy[k]~=ROAD and roadDistance[k]>=5 and protectedDistance[k]>=3
            local canOpen=legacy[k]~=ROCK or (safe[k] and not (x<2 or y<2 or x>W-3 or y>H-3))
            if count>=6 and canClose then next[k]=true elseif count<=2 and canOpen then next[k]=false else next[k]=rock[k] end
        end
        rock=next
        symmetrise(rock)
    end

    -- Groves from the old forest rectangles, three lobes each, mirrored.
    local forest={}
    local function clump(x0,y0,x1,y1)
        local w,h=x1-x0+1,y1-y0+1
        local lobes={}
        for i=1,3 do
            local hx=hash(x0+x1,y0+y1,50+i)
            lobes[i]={cx=(x0+x1)/2+(hx%100-50)*w/150,cy=(y0+y1)/2+(math.floor(hx/100)%10-5)*h/15,rx=w*.42+.8,ry=h*.42+.8}
        end
        for y=y0-4,y1+4 do for x=x0-4,x1+4 do
            if x>=0 and y>=0 and x<W and y<H then
                local px,py=canonical(x,y)
                local jitter=(noise(px,py,3,3)-500)/1000*.8
                for _,l in ipairs(lobes) do
                    local dx,dy=(x-l.cx)/l.rx,(y-l.cy)/l.ry
                    if dx*dx+dy*dy+jitter<1 then local k=key(x,y);forest[k]=true;forest[mirrorKey(k)]=true;break end
                end
            end
        end end
    end
    for _,r in ipairs(L.forestRects) do clump(r[1],r[2],r[3],r[4]) end
    -- Woods: deep bay cells, with clearings, and a sparse fringe where open ground meets rock.
    local newToRock=distanceFrom(function(k) return rock[k] end)
    for k=1,N do
        local x,y=coords(k);local cx,cy=canonical(x,y)
        if not rock[k] and roadDistance[k]>=4 and protectedDistance[k]>=3 then
            local bay=legacy[k]==ROCK
            if (bay and toOpen[k]>=3 and noise(cx,cy,6,5)>300) or (roadDistance[k]>=6 and protectedDistance[k]>=4 and newToRock[k]==1 and noise(cx,cy,5,4)>650) then forest[k]=true end
        end
    end

    local mineCell={}
    for _,n in ipairs(L.resources) do for y=n.y,n.y+n.size-1 do for x=n.x,n.x+n.size-1 do mineCell[key(x,y)]=true end end end
    local grid={}
    for k=1,N do
        if legacy[k]==ROAD then grid[k]=ROAD
        elseif rock[k] then grid[k]=ROCK
        elseif forest[k] and not protected[k] and not mineCell[k] and roadDistance[k]>=2 then grid[k]=FOREST
        else grid[k]=GRASS end
    end

    local places={}
    local function place(name,x,y) places[#places+1]={name=name,key=key(x,y)} end
    place('home 1',L.starts[1].x+2,L.starts[1].y+2);place('home 2',L.starts[2].x+2,L.starts[2].y+2)
    for _,kind in ipairs({'naturals','forward','contested'}) do for p,a in ipairs(L.anchors[kind]) do place(kind..' '..p,a.x,a.y) end end
    for i,p in ipairs(L.controlPoints) do place('control '..i,p.x,p.y) end
    local legacyWalks={};for i,a in ipairs(places) do legacyWalks[i]=walking(legacy,a.key) end
    local function fillUnreachable()
        local reach=walking(grid,places[1].key);local filled=0
        for k=1,N do if grid[k]==GRASS and not reach[k] then grid[k]=ROCK;filled=filled+1 end end
        return filled
    end
    local filled=fillUnreachable()
    -- Route check and repair.
    local repaired=0
    for round=1,30 do
        local failures={}
        for i,a in ipairs(places) do
            local now=walking(grid,a.key)
            for j=i+1,#places do local b=places[j]
                local was=legacyWalks[i][b.key];local ratio=now[b.key] and now[b.key]/was or 99
                if ratio<0.97 or ratio>1.06 then failures[#failures+1]={i=i,j=j,now=now,ratio=ratio} end
            end
        end
        if #failures==0 then break end
        assert(round<30,'route repair did not converge')
        for _,f in ipairs(failures) do
            -- Too short: close what was opened near the new route. Too long: reopen the old route.
            local path=f.ratio<1 and trace(grid,f.now,places[f.j].key) or trace(legacy,legacyWalks[f.i],places[f.j].key)
            for _,pk in ipairs(path) do
                local px,py=coords(pk)
                for dy=-2,2 do for dx=-2,2 do local nx,ny=px+dx,py+dy
                    if nx>=0 and ny>=0 and nx<W and ny<H then local nk=key(nx,ny)
                        local restore=(f.ratio<1 and legacy[nk]==ROCK and grid[nk]~=ROCK) or (f.ratio>1 and not blocks(legacy[nk]) and blocks(grid[nk]))
                        if restore then grid[nk]=legacy[nk];grid[mirrorKey(nk)]=legacy[mirrorKey(nk)];repaired=repaired+1 end
                    end
                end end
            end
        end
    end
    filled=filled+fillUnreachable()

    -- Checks and report.
    for k=1,N do assert(grid[k]==grid[mirrorKey(k)],'asymmetric at cell '..k) end
    for k=1,N do if legacy[k]==ROAD then assert(grid[k]==ROAD) end end
    for k in pairs(mineCell) do assert(not blocks(grid[k]),'mine covered') end
    local worst=0
    for i,a in ipairs(places) do
        local now=walking(grid,a.key)
        for j=i+1,#places do local b=places[j]
            local was=legacyWalks[i][b.key];assert(now[b.key],'unreachable: '..a.name..' to '..b.name)
            local ratio=now[b.key]/was;worst=math.max(worst,math.abs(ratio-1))
            assert(ratio>=0.97 and ratio<=1.06,'route still out of range after repair: '..a.name..' to '..b.name)
            print(string.format('ROUTE %-12s -> %-12s %6.1f cells, was %6.1f (%+.1f%%)',a.name,b.name,now[b.key]/5,was/5,(ratio-1)*100))
        end
    end
    local counts={0,0,0,0};local legacyCounts={0,0,0,0};local buildableNow,buildableWas=0,0
    for k=1,N do
        counts[grid[k]]=counts[grid[k]]+1;legacyCounts[legacy[k]]=legacyCounts[legacy[k]]+1
        if grid[k]==GRASS then buildableNow=buildableNow+1 end;if legacy[k]==GRASS then buildableWas=buildableWas+1 end
    end
    print(string.format('CELLS grass %d (was %d) road %d (was %d) rock %d (was %d) forest %d (was %d); %d cells repaired, %d unreachable filled; worst route change %.1f%%',
        counts[1],legacyCounts[1],counts[2],legacyCounts[2],counts[3],legacyCounts[3],counts[4],legacyCounts[4],repaired,filled,worst*100))

    -- The editor palette: four flat swatches, one per terrain type. Tiled needs an image to paint
    -- with; the game never loads it.
    local swatches=love.image.newImageData(128,32)
    local colours={{.31,.45,.25},{.56,.46,.32},{.43,.40,.37},{.15,.27,.15}}
    for i,c in ipairs(colours) do for y=0,31 do for x=0,31 do swatches:setPixel((i-1)*32+x,y,c[1],c[2],c[3],1) end end end
    write(root..'maps/tilesets/terrain.png',swatches:encode('png'):getString())

    local lines={}
    local function add(s) lines[#lines+1]=s end
    local objects={};local nextId=1
    local function object(class,x,y,w,h,props,name)
        objects[#objects+1]={id=nextId,class=class,x=x,y=y,w=w,h=h,props=props,name=name};nextId=nextId+1
    end
    local function point(class,cx,cy,props,name) object(class,cx*32+16,cy*32+16,nil,nil,props,name) end
    for p,s in ipairs(L.starts) do object('start',s.x*32,s.y*32,5*32,5*32,{{'player','int',p}},'headquarters '..p) end
    for _,n in ipairs(L.resources) do object('gold',n.x*32,n.y*32,n.size*32,n.size*32,{{'amount','int',n.amount}}) end
    for _,c in ipairs(L.camps) do point('camp',c.x,c.y,{{'kind','string',c.kind},{'tier','string',c.tier}}) end
    for p,list in ipairs(L.unitStarts) do for slot,u in ipairs(list) do point('unit_start',u.x,u.y,{{'player','int',p},{'slot','int',slot}}) end end
    for _,kind in ipairs({'naturals','forward','contested'}) do for p,a in ipairs(L.anchors[kind]) do point('anchor',a.x,a.y,{{'kind','string',kind},{'player','int',p}},kind..' '..p) end end
    for _,c in ipairs(L.controlPoints) do point('control',c.x,c.y,{},'control point') end
    add('<?xml version="1.0" encoding="UTF-8"?>')
    add(string.format('<map version="1.10" tiledversion="1.12.2" class="" orientation="orthogonal" renderorder="right-down" width="%d" height="%d" tilewidth="32" tileheight="32" infinite="0" nextlayerid="3" nextobjectid="%d">',W,H,nextId))
    add(' <properties>')
    add('  <property name="id" value="twin_marches"/>')
    add(' </properties>')
    add(' <tileset firstgid="1" name="terrain" tilewidth="32" tileheight="32" tilecount="4" columns="4">')
    add('  <image source="tilesets/terrain.png" width="128" height="32"/>')
    for i,name in ipairs({'grass','road','rock','forest'}) do
        add(string.format('  <tile id="%d">',i-1));add('   <properties>')
        add(string.format('    <property name="terrain" value="%s"/>',name))
        add('   </properties>');add('  </tile>')
    end
    add(' </tileset>')
    add(string.format(' <layer id="1" name="ground" width="%d" height="%d">',W,H))
    add('  <data encoding="csv">')
    for y=0,H-1 do
        local row={}
        for x=0,W-1 do row[#row+1]=tostring(grid[key(x,y)]) end
        add(table.concat(row,',')..(y<H-1 and ',' or ''))
    end
    add('</data>')
    add(' </layer>')
    add(' <objectgroup id="2" name="gameplay">')
    for _,o in ipairs(objects) do
        local attrs=string.format('id="%d"%s class="%s" x="%d" y="%d"',o.id,o.name and (' name="'..o.name..'"') or '',o.class,o.x,o.y)
        if o.w then attrs=attrs..string.format(' width="%d" height="%d"',o.w,o.h) end
        add('  <object '..attrs..'>')
        if #o.props>0 then
            add('   <properties>')
            for _,p in ipairs(o.props) do
                if p[2]=='int' then add(string.format('    <property name="%s" type="int" value="%d"/>',p[1],p[3]))
                else add(string.format('    <property name="%s" value="%s"/>',p[1],p[3])) end
            end
            add('   </properties>')
        end
        if not o.w then add('   <point/>') end
        add('  </object>')
    end
    add(' </objectgroup>')
    add('</map>')
    write(out,table.concat(lines,'\n')..'\n')
    print('WROTE '..out)
    love.event.quit(0)
end
