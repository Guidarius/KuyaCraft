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
return S
