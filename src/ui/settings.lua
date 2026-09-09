local S={defaults={version=1,scale=100,edgeScroll=false,master=70,ui=65,effects=70,ambience=35,bindings={attack='a',stop='s',hold='h',hero='f1',alert='space',build='b',tower='t'}}}
local Codec=require('src.sim.codec')
function S.load()
 local value=Codec.copy(S.defaults)
 local ok,data=pcall(function() return Codec.decode(require('src.ui.storage').read('settings.dat')) end)
 if ok and type(data)=='table' and data.version==1 then
  for _,key in ipairs({'scale','master','ui','effects','ambience'}) do if type(data[key])=='number' then value[key]=math.max(key=='scale' and 80 or 0,math.min(key=='scale' and 125 or 100,data[key])) end end
  value.edgeScroll=data.edgeScroll==true
  if type(data.bindings)=='table' then for k in pairs(value.bindings) do if type(data.bindings[k])=='string' then value.bindings[k]=data.bindings[k] end end end
 end
 return value
end
function S.save(value) return require('src.ui.storage').write('settings.dat',Codec.encode(value)) end
return S
