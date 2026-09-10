local Content=require('src.content')
local S={}
function S.has(ids,id) for _,v in ipairs(ids) do if v==id then return true end end return false end
function S.toggle(ids,id) for i,v in ipairs(ids) do if v==id then table.remove(ids,i);return end end;ids[#ids+1]=id;table.sort(ids) end
function S.groups(app)
 local groups,index={},{}
 for _,id in ipairs(app.selected) do local e=app:entity(id);if e and e.alive then
  if not index[e.kind] then local group={kind=e.kind,ids={}};index[e.kind]=group;groups[#groups+1]=group end
  local a=index[e.kind].ids;a[#a+1]=id
 end end
 table.sort(groups,function(a,b) return a.kind<b.kind end);return groups
end
-- Which single unit the command card, the stat card and the order inspector describe.
-- Warcraft 3 shows the card of the active subgroup, and when the player has not chosen
-- one it picks the most interesting member: a hero over a soldier, a soldier over a
-- worker, a unit over a building. Lowest id breaks ties so the card never flickers
-- between two equals as they move.
local RANK={hero=0,combat=1,worker=2,building=3,other=4}
function S.rank(e)
 if not e then return RANK.other end
 if e.category=='building' then return RANK.building end
 if e.category~='unit' then return RANK.other end
 local d=Content.units[e.kind]
 if d and d.hero then return RANK.hero end
 if d and d.worker then return RANK.worker end
 return RANK.combat
end
function S.primary(app)
 -- The active subgroup is remembered by kind, not by index, so it survives units
 -- dying or being added to the selection.
 if app.subgroupKind then
  for _,id in ipairs(app.selected) do
   local e=app:entity(id)
   if e and e.alive and e.kind==app.subgroupKind then return id end
  end
  app.subgroupKind=nil
 end
 local best,bestRank
 for _,id in ipairs(app.selected) do
  local e=app:entity(id)
  if e then
   local rank=S.rank(e)
   if not best or rank<bestRank or (rank==bestRank and id<best) then best,bestRank=id,rank end
  end
 end
 return best
end
-- Tab moves the card to the next unit type in the selection and leaves the selection
-- itself alone. The old behaviour replaced the selection with one subgroup, which meant
-- a player who pressed Tab to look at their casters lost the rest of the army and could
-- not get it back without reselecting.
function S.cycle(app)
 local groups=S.groups(app)
 if #groups==0 then app.subgroupKind=nil;return nil end
 local index=0
 if app.subgroupKind then for i,group in ipairs(groups) do if group.kind==app.subgroupKind then index=i;break end end end
 app.subgroupKind=groups[index%#groups+1].kind
 return app.subgroupKind
end
return S
