-- Twin Marches: a 192x192 1v1 map. Cell origins for footprints; anchors are world-cell centers.
--
-- Everything is authored for player one in the north-west and rotated 180 degrees for
-- player two: a cell (x,y) becomes (191-x,191-y) and a footprint origin (192-x-size,
-- 192-y-size). The map starts solid and is carved open, so every clearing and corridor
-- is named below.
--
-- Roads are walkable ground that nobody may build on. They run from every gold mine to a
-- headquarters and from mine to mine, three cells wide, so no wall of buildings -- yours
-- or an enemy's -- can cut a mine off from the bases. They change nothing about movement
-- or sight: a unit walks a road exactly as it walks open ground.
return function()
 local W,H=192,192
 local m={unitStarts={{},{}},id='twin_marches',width=W,height=H,blocked={},unbuildable={},resources={},camps={},
  starts={{x=20,y=20},{x=W-25,y=H-25}},
  anchors={naturals={{x=50,y=28},{x=W-1-50,y=H-1-28}},forward={{x=66,y=70},{x=W-1-66,y=H-1-70}},
   contested={{x=168,y=24},{x=W-1-168,y=H-1-24}}}}
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
 -- Every cell a polyline passes through, in order. Consecutive cells differ by at most one
 -- step on each axis, so a brush stamped on each of them leaves no gap.
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
 -- Ground: the base, its natural and forward expansions, the corner it contests with the
 -- enemy, and the center, joined by a broad diagonal and two long outer corridors.
 carve(22,22,15)
 carve(54,24,11);corridor({{30,22},{50,22}},6)
 carve(62,70,10)
 corridor({{30,30},{96,96}},7);carve(96,96,16)
 carve(168,24,11);corridor({{60,22},{160,22}},5)
 corridor({{55,77},{20,150},{16,172}},5)
 carve(26,118,5)
 -- Gold. The home mine, the natural, the forward mine, and the north-east corner; the
 -- corner's rotation is the south-west one, so each player is nearer one corner.
 resource(21,10,12000)
 resource(58,14,9000)
 resource(54,74,9000)
 resource(174,14,9000)
 -- Roads, each ending against the footprint it serves. Every mine reaches a headquarters,
 -- and the forward roads meet player two's in the center, so the network is one piece.
 road({{22,13},{22,19}})
 road({{25,22},{59,22},{59,17}})
 road({{25,25},{60,60},{60,75},{57,75}})
 road({{60,60},{95,95}})
 road({{59,22},{175,22},{175,17}})
 road({{55,77},{20,150},{16,174}})
 -- A road ends at a footprint, never under it: an extractor is built on its mine, and a
 -- headquarters stands where it starts.
 local function unpave(x0,y0,size) for y=y0,y0+size-1 do for x=x0,x0+size-1 do m.unbuildable[key(x,y)]=nil end end end
 for _,n in ipairs(m.resources) do unpave(n.x,n.y,n.size) end
 for _,s in ipairs(m.starts) do unpave(s.x,s.y,5) end
 -- Forests are terrain, not a resource. They block movement and, since sight is cast
 -- rather than radial, they block sight too, so they are cover for a raid on a carrier
 -- route. Marking the cells directly rather than spawning a node for each one keeps them
 -- out of every per-entity loop in the step. A tree never grows on a mine or a road.
 local function forest(x0,y0,x1,y1)
  for y=y0,y1 do for x=x0,x1 do
   local k,mirror=key(x,y),key(W-1-x,H-1-y)
   local free=not m.unbuildable[k] and not m.unbuildable[mirror]
   for _,n in ipairs(m.resources) do
    if x>=n.x and x<n.x+n.size and y>=n.y and y<n.y+n.size then free=false end
   end
   if free then m.blocked[k]=true;m.blocked[mirror]=true end
  end end
 end
 forest(9,9,17,15);forest(27,8,35,13)
 forest(46,13,52,17);forest(70,60,73,66);forest(92,17,98,18)
 local function camp(x,y,tier)
  local kinds=tier=='easy' and {'scout','scout'} or tier=='hard' and {'leader','neutral','neutral'} or {'neutral','neutral','neutral'}
  for i,kind in ipairs(kinds) do local cx,cy=x+(i-2)*2,y;carve(cx,cy,1)
   m.camps[#m.camps+1]={x=cx,y=cy,kind=kind,tier=tier};m.camps[#m.camps+1]={x=W-1-cx,y=H-1-cy,kind=kind,tier=tier}
  end
 end
 camp(48,31,'easy');camp(66,80,'easy');camp(110,26,'medium');camp(25,118,'medium');camp(166,32,'hard');camp(88,100,'hard')
 return m
end
