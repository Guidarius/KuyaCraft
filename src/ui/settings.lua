-- healthBars: 'always' | 'selected' | 'damaged'. screenShake and dayNight are cosmetic
-- toggles. gameSpeed only affects offline play; network play always runs at 1x.
-- The idle-worker key defaults to F9 rather than the more traditional F8 because F5-F8
-- are camera bookmarks here; it is rebindable like the others.
local S={defaults={version=2,scale=100,edgeScroll=false,master=70,ui=65,effects=70,ambience=35,
 healthBars='damaged',screenShake=true,dayNight=false,gameSpeed=2,
 bindings={attack='a',stop='s',hold='h',hero='f1',alert='space',build='b',tower='t',idle='f9'}}}
local Codec=require('src.sim.codec')
-- Offline pacing multipliers. These scale how fast wall-clock time is fed to the fixed
-- 20 Hz accumulator; they never change the tick rate itself, so the simulation, its
-- hashes and its replays are identical at every speed.
S.SPEEDS={1,2,3}
S.SPEED_LABELS={'Slower','Normal','Faster'}
S.SPEED_SCALE={0.5,1,1.5}
function S.load()
 local value=Codec.copy(S.defaults)
 local ok,data=pcall(function() return Codec.decode(require('src.ui.storage').read('settings.dat')) end)
 -- Version 1 files are still read: the new keys simply keep their defaults, so an
 -- existing settings file does not have to be thrown away to gain them.
 if ok and type(data)=='table' and (data.version==1 or data.version==2) then
  for _,key in ipairs({'scale','master','ui','effects','ambience'}) do if type(data[key])=='number' then value[key]=math.max(key=='scale' and 80 or 0,math.min(key=='scale' and 125 or 100,data[key])) end end
  value.edgeScroll=data.edgeScroll==true
  if data.version==2 then
   if data.healthBars=='always' or data.healthBars=='selected' or data.healthBars=='damaged' then value.healthBars=data.healthBars end
   value.screenShake=data.screenShake~=false
   value.dayNight=data.dayNight==true
   for _,speed in ipairs(S.SPEEDS) do if data.gameSpeed==speed then value.gameSpeed=speed end end
  end
  if type(data.bindings)=='table' then for k in pairs(value.bindings) do if type(data.bindings[k])=='string' then value.bindings[k]=data.bindings[k] end end end
 end
 return value
end
function S.save(value) return require('src.ui.storage').write('settings.dat',Codec.encode(value)) end
return S
