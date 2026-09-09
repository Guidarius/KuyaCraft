-- Original synthesized nonverbal cues. No files or audio device are required.
local A={manifest={
 heal={frequency=460,duration=.14,gain=.1,priority=1,cooldown=.7,bus='effects'},
 work={frequency=130,duration=.06,gain=.1,priority=1,cooldown=.8,bus='effects'},
 ambience={frequency=75,duration=.4,gain=.03,priority=0,cooldown=4,bus='ambience'},
 click={frequency=660,duration=.045,gain=.2,priority=3,cooldown=.06,bus='ui'},
 accepted={frequency=520,duration=.07,gain=.18,priority=3,cooldown=.12,bus='ui'},
 rejected={frequency=150,duration=.14,gain=.3,priority=4,cooldown=.3,bus='ui'},
 attack={frequency=210,duration=.075,gain=.22,priority=1,cooldown=.035,bus='effects'},
 death={frequency=95,duration=.2,gain=.25,priority=2,cooldown=.12,bus='effects'},
 alert={frequency=880,duration=.18,gain=.3,priority=5,cooldown=1,bus='ui'},
 ready={frequency=740,duration=.12,gain=.22,priority=3,cooldown=.25,bus='effects'},
 victory={frequency=1040,duration=.4,gain=.25,priority=6,cooldown=2,bus='ui'}}}
function A.create(settings)
 local self=setmetatable({settings=settings,pool={},last={},clock=0,templates={},variation=0}, {__index=A})
 if love.audio and love.sound then pcall(function()
  for name,d in pairs(A.manifest) do
   local samples=math.floor(22050*d.duration);local data=love.sound.newSoundData(samples,22050,16,1)
   for i=0,samples-1 do local t=i/22050;local envelope=math.min(1,i/100)*(1-i/samples)^2;data:setSample(i,math.sin(t*d.frequency*6.2831853)*envelope*.5) end
   self.templates[name]=love.audio.newSource(data,'static')
  end
 end) end
 return self
end
function A:update(dt) self.clock=self.clock+dt end
function A:play(name,app,x,y)
 local d=A.manifest[name];if not d or not self.templates[name] or self.clock-(self.last[name] or -10)<d.cooldown then return end
 local slot
 for _,v in ipairs(self.pool) do if not v.source:isPlaying() then slot=v;break end end
 if not slot and #self.pool<32 then slot={};self.pool[#self.pool+1]=slot end
 if not slot then for _,v in ipairs(self.pool) do if v.priority<d.priority then slot=v;break end end end
 if not slot then return end
 pcall(function()
  if slot.source then slot.source:stop() end
  if slot.name~=name then slot.source=self.templates[name]:clone();slot.name=name end;slot.priority=d.priority
  slot.source:setRelative(true)
  local gain=d.gain*self.settings.master/100*self.settings[d.bus]/100
  if app and x then local sx,sy=app:screen(x,y);local w,h=love.graphics.getDimensions();local pan=(sx-w/2)/(w/2);gain=gain/(1+math.abs(pan));slot.source:setPosition(math.max(-1,math.min(1,pan)),0,-1) end
  self.variation=self.variation%3+1;slot.source:setPitch(({.96,1,1.04})[self.variation]);slot.source:setVolume(gain);slot.source:play();self.last[name]=self.clock
 end)
end
function A:clear() for _,v in ipairs(self.pool) do v.source:stop() end end
return A
