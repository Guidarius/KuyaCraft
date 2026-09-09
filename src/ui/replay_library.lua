local Codec=require('src.sim.codec')
local L={}
local function load()
 local ok,data=pcall(function() return Codec.decode(require('src.ui.storage').read('replay-index.dat')) end)
 if not ok or type(data)~='table' then return {} end
 local out={};for _,path in ipairs(data) do if type(path)=='string' and #path<4096 then out[#out+1]=path end end;return out
end
function L.remember(path)
 if not path:match('^%a:[/\\]') and path:sub(1,1)~='/' then path=love.filesystem.getWorkingDirectory()..'/'..path end
 path=path:gsub('\\','/')
 local paths=load();local out={path}
 for _,old in ipairs(paths) do if old~=path and #out<200 then out[#out+1]=old end end
 require('src.ui.storage').write('replay-index.dat',Codec.encode(out))
end
function L.list()
 local paths=load();local source=love.filesystem.getSource()
 if not source:match('%.love$') then for _,name in ipairs(love.filesystem.getDirectoryItems('artifacts')) do if name:match('%.replay$') then paths[#paths+1]=source..'/artifacts/'..name end end end
 local found,result={},{}
 for _,path in ipairs(paths) do
  path=path:gsub('\\','/')
  if not found[path] then local file=io.open(path,'rb');if file then file:close();found[path]=true;result[#result+1]={name=path:match('([^/]+)$'),path=path} end end
 end
 table.sort(result,function(a,b) if a.name~=b.name then return a.name>b.name end return a.path<b.path end);return result
end
return L
