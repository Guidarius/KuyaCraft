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
function S.rank(e,app)
 if not e then return RANK.other end
 if e.category=='building' then return RANK.building end
 if e.category~='unit' then return RANK.other end
 local d=app and app.content.units[e.kind]
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
   local rank=S.rank(e,app)
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
-- Inspection. An enemy, a neutral camp creature, a foreign building or a gold mine can be
-- selected to read it -- what it is, its health, the statistics anyone could look up --
-- and never to command it. Warcraft 3 and StarCraft both show one foreign thing at a time,
-- so it is only ever selected alone.
function S.foreign(app,e) return e~=nil and e.owner~=app.player end
function S.inspecting(app)
 if #app.selected~=1 then return nil end
 local e=app:entity(app.selected[1])
 if S.foreign(app,e) then return e end
 return nil
end
-- Every click and box selection goes through here, so the rule holds whatever picked the
-- ids. A foreign id replaces the selection outright, and adding your own units to an
-- inspected enemy replaces the enemy rather than mixing the two.
function S.apply(app,ids,additive)
 for _,id in ipairs(ids) do
  if S.foreign(app,app:entity(id)) then app.selected={id};app.subgroupKind=nil;return end
 end
 if not additive or S.inspecting(app) then app.selected={} end
 for _,id in ipairs(ids) do
  if additive then S.toggle(app.selected,id) else app.selected[#app.selected+1]=id end
 end
end
-- A foreign thing is only known while it is seen. When it walks into fog it drops out of
-- the view, and when it dies it stops being alive; either way the selection lets go
-- rather than describing a ghost. Your own units are always in your own view.
function S.prune(app)
 if #app.selected~=1 then return end
 local e=app:entity(app.selected[1])
 if not e or (e.owner~=app.player and not e.alive) then app.selected={} end
end
return S
