-- Cell origins for footprints; camp/expansion anchors are world-cell centers.
return function()
 local m={unitStarts={{},{}},id='twin_marches',width=128,height=112,blocked={},resources={},camps={},starts={{x=14,y=14},{x=109,y=93}},
  anchors={naturals={{x=40,y=20},{x=88,y=92}},contested={{x=28,y=70},{x=100,y=42}}}}
 for _,p in ipairs({{20,18},{15,12},{16,12},{17,12},{18,12},{19,12}}) do m.unitStarts[1][#m.unitStarts[1]+1]={x=p[1],y=p[2]};m.unitStarts[2][#m.unitStarts[2]+1]={x=127-p[1],y=111-p[2]} end
 for y=0,111 do for x=0,127 do m.blocked[y*128+x+1]=true end end
 local function carve(x,y,r)
  for cy=math.max(0,y-r),math.min(111,y+r) do for cx=math.max(0,x-r),math.min(127,x+r) do m.blocked[cy*128+cx+1]=nil;m.blocked[(111-cy)*128+127-cx+1]=nil end end
 end
 local function road(points,r)
  for i=2,#points do local a,b=points[i-1],points[i];local steps=math.max(math.abs(b[1]-a[1]),math.abs(b[2]-a[2]));for j=0,steps do carve(math.floor(a[1]+(b[1]-a[1])*j/math.max(1,steps)),math.floor(a[2]+(b[2]-a[2])*j/math.max(1,steps)),r) end end
 end
 -- Main diagonal, northern/southern economic wings, and longer outside flanks.
 carve(17,17,11)
 road({{25,17},{35,17},{40,20},{45,32},{55,44},{64,56}},4)
 road({{18,26},{18,43},{28,52},{28,70},{44,80},{63,88},{85,84},{104,84}},3)
 road({{18,43},{34,38},{45,40},{55,44}},3)
 road({{28,70},{43,62},{64,56}},3)
 for _,p in ipairs({{40,20},{45,40},{28,70},{64,56}}) do carve(p[1],p[2],10) end
 for _,p in ipairs({{28,30},{18,43},{53,55}}) do carve(p[1],p[2],5) end
 road({{28,30},{34,30},{40,32}},2)
 local function resource(x,y,kind,amount,size)
  size=size or 1
  local function add(cx,cy) m.resources[#m.resources+1]={x=cx,y=cy,resource=kind,amount=amount,size=size};for yy=cy,cy+size-1 do for xx=cx,cx+size-1 do m.blocked[yy*128+xx+1]=nil end end end
  add(x,y);add(128-x-size,112-y-size)
 end
 resource(14,8,'gold',12000,3)
 resource(39,18,'gold',9000,3);resource(27,68,'gold',9000,3)
 -- Forests are terrain, not a resource. They block movement and, since sight is cast
 -- rather than radial, they block sight too, so they are cover for a raid on a carrier
 -- route. Marking the cells directly rather than spawning a node for each one keeps
 -- about 180 entities out of every match, which every per-entity loop in the step pays
 -- for. A tree is never placed over a mine footprint.
 local function forest(x0,y0,x1,y1)
  for y=y0,y1 do for x=x0,x1 do
   local blocked=false
   for _,n in ipairs(m.resources) do
    if x>=n.x and x<n.x+(n.size or 1) and y>=n.y and y<n.y+(n.size or 1) then blocked=true end
   end
   if not blocked then
    m.blocked[y*128+x+1]=true;m.blocked[(111-y)*128+(127-x)+1]=true
   end
  end end
 end
 forest(5,8,14,13)
 forest(46,13,51,17);forest(20,74,25,78)
 local function camp(x,y,tier)
  local kinds=tier=='easy' and {'scout','scout'} or tier=='hard' and {'leader','neutral','neutral'} or {'neutral','neutral','neutral'}
  for i,kind in ipairs(kinds) do local cx,cy=x+(i-2)*2,y;carve(cx,cy,1)
   m.camps[#m.camps+1]={x=cx,y=cy,kind=kind,tier=tier};m.camps[#m.camps+1]={x=127-cx,y=111-cy,kind=kind,tier=tier}
  end
 end
 camp(28,30,'easy');camp(18,43,'easy');camp(45,40,'medium');camp(44,25,'medium');camp(53,55,'hard')
 return m
end
