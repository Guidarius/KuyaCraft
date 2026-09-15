-- The code-authored Twin Marches that preceded the Tiled map, kept as the generator's input.
-- It is not loaded by the game: tools/tiled/generate reads it to lay out maps/twin_marches.tmx.
-- The only change from the original src/maps/twin_marches.lua is that forest cells and forest
-- rectangles are recorded, so the generator can tell forest from rock.
--
-- Everything is authored for player one in the north-west and rotated 180 degrees for
-- player two: a cell (x,y) becomes (191-x,191-y) and a footprint origin (192-x-size,
-- 192-y-size). The map starts solid and is carved open.
return function()
 local W,H=192,192
 local m={unitStarts={{},{}},id='twin_marches',width=W,height=H,blocked={},unbuildable={},resources={},camps={},
  starts={{x=20,y=20},{x=W-25,y=H-25}},
  anchors={naturals={{x=50,y=28},{x=W-1-50,y=H-1-28}},forward={{x=66,y=70},{x=W-1-66,y=H-1-70}},
   contested={{x=168,y=24},{x=W-1-168,y=H-1-24}}},
  controlPoints={{x=128,y=62},{x=W-1-128,y=H-1-62}},forestCells={},forestRects={}}
 local function key(x,y) return y*W+x+1 end
 for _,p in ipairs({{28,18},{16,17},{17,17},{18,17},{19,17},{26,17}}) do
  m.unitStarts[1][#m.unitStarts[1]+1]={x=p[1],y=p[2]};m.unitStarts[2][#m.unitStarts[2]+1]={x=W-1-p[1],y=H-1-p[2]}
 end
 for y=0,H-1 do for x=0,W-1 do m.blocked[key(x,y)]=true end end
 local function carve(x,y,r)
  for cy=math.max(0,y-r),math.min(H-1,y+r) do for cx=math.max(0,x-r),math.min(W-1,x+r) do
   m.blocked[key(cx,cy)]=nil;m.blocked[key(W-1-cx,H-1-cy)]=nil
  end end
 end
 local function walk(points,fn)
  for i=2,#points do local a,b=points[i-1],points[i]
   local steps=math.max(math.abs(b[1]-a[1]),math.abs(b[2]-a[2]),1)
   for j=0,steps do fn(math.floor(a[1]+(b[1]-a[1])*j/steps),math.floor(a[2]+(b[2]-a[2])*j/steps)) end
  end
 end
 local function corridor(points,r) walk(points,function(x,y) carve(x,y,r) end) end
 local function road(points)
  walk(points,function(x,y)
   carve(x,y,1)
   for cy=math.max(0,y-1),math.min(H-1,y+1) do for cx=math.max(0,x-1),math.min(W-1,x+1) do
    m.unbuildable[key(cx,cy)]=true;m.unbuildable[key(W-1-cx,H-1-cy)]=true
   end end
  end)
 end
 local function resource(x,y,amount)
  m.resources[#m.resources+1]={x=x,y=y,resource='gold',amount=amount,size=3}
  m.resources[#m.resources+1]={x=W-x-3,y=H-y-3,resource='gold',amount=amount,size=3}
  carve(x+1,y+1,1)
 end
 carve(22,22,15)
 carve(54,24,11);corridor({{30,22},{50,22}},6)
 carve(62,70,10)
 corridor({{30,30},{96,96}},7);carve(96,96,16)
 carve(168,24,11);corridor({{60,22},{160,22}},5)
 corridor({{55,77},{20,150},{16,172}},5)
 carve(26,118,5)
 resource(21,10,12000)
 resource(58,14,9000)
 resource(54,74,9000)
 resource(174,14,9000)
 road({{22,13},{22,19}})
 road({{25,22},{59,22},{59,17}})
 road({{25,25},{60,60},{60,75},{57,75}})
 road({{60,60},{95,95}})
 road({{59,22},{175,22},{175,17}})
 road({{55,77},{20,150},{16,174}})
 local function unpave(x0,y0,size) for y=y0,y0+size-1 do for x=x0,x0+size-1 do m.unbuildable[key(x,y)]=nil end end end
 for _,n in ipairs(m.resources) do unpave(n.x,n.y,n.size) end
 for _,s in ipairs(m.starts) do unpave(s.x,s.y,5) end
 for y=28,120 do
  local edge=y<41 and 171+math.floor(4*(41-y)/22) or 136+math.floor(35*(114-y)/73)
  for x=y+15,edge-5 do carve(x,y,0) end
 end
 local radius=4
 for _,p in ipairs(m.controlPoints) do
  for y=p.y-radius,p.y+radius do for x=p.x-radius,p.x+radius do
   if (x-p.x)*(x-p.x)+(y-p.y)*(y-p.y)<=radius*radius then m.unbuildable[key(x,y)]=true;m.blocked[key(x,y)]=nil end
  end end
 end
 local function forest(x0,y0,x1,y1)
  m.forestRects[#m.forestRects+1]={x0,y0,x1,y1}
  for y=y0,y1 do for x=x0,x1 do
   local k,mirror=key(x,y),key(W-1-x,H-1-y)
   local free=not m.unbuildable[k] and not m.unbuildable[mirror]
   for _,n in ipairs(m.resources) do
    if x>=n.x and x<n.x+n.size and y>=n.y and y<n.y+n.size then free=false end
   end
   if free then m.blocked[k]=true;m.blocked[mirror]=true;m.forestCells[k]=true;m.forestCells[mirror]=true end
  end end
 end
 forest(9,9,17,15);forest(27,8,35,13)
 forest(46,13,52,17);forest(70,60,73,66);forest(92,17,98,18)
 forest(70,40,76,42);forest(96,34,103,37);forest(84,50,89,55);forest(110,44,116,47)
 forest(140,40,145,46);forest(150,52,154,58);forest(100,62,104,66);forest(112,72,117,77);forest(134,78,139,83)
 local function camp(x,y,tier)
  local kinds=tier=='easy' and {'scout','scout'} or tier=='hard' and {'leader','neutral','neutral'} or {'neutral','neutral','neutral'}
  for i,kind in ipairs(kinds) do local cx,cy=x+(i-2)*2,y;carve(cx,cy,1)
   m.camps[#m.camps+1]={x=cx,y=cy,kind=kind,tier=tier};m.camps[#m.camps+1]={x=W-1-cx,y=H-1-cy,kind=kind,tier=tier}
  end
 end
 camp(48,31,'easy');camp(66,80,'easy');camp(110,26,'medium');camp(25,118,'medium');camp(166,32,'hard');camp(88,100,'hard')
 return m
end
