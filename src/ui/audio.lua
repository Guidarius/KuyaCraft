-- Original synthesized nonverbal cues. No files or audio device are required.
local A={manifest={
 select={frequency=430,endFrequency=600,duration=.08,gain=.14,priority=3,cooldown=.16,bus='ui'},
 menu={frequency=620,endFrequency=820,duration=.06,gain=.13,priority=3,cooldown=.08,bus='ui'},
 cancel={frequency=440,endFrequency=300,duration=.07,gain=.12,priority=3,cooldown=.1,bus='ui'},
 move={frequency=480,endFrequency=650,duration=.08,gain=.14,priority=3,cooldown=.16,bus='ui'},
 attack_order={frequency=320,endFrequency=430,duration=.1,gain=.17,priority=3,cooldown=.16,bus='ui'},
 build_order={frequency=580,endFrequency=760,duration=.1,gain=.15,priority=3,cooldown=.16,bus='ui'},
 stance={frequency=380,endFrequency=570,duration=.12,gain=.17,priority=3,cooldown=.2,bus='ui'},
 levelup={frequency=650,endFrequency=1100,duration=.3,gain=.22,priority=5,cooldown=.5,bus='ui'},
 research={frequency=500,endFrequency=900,duration=.25,gain=.2,priority=4,cooldown=.5,bus='ui'},
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
 -- The order acknowledgement. In Warcraft 3 this is a voice line, and it is what makes
 -- a command feel instant while the simulation has not run yet. A:ack picks the most
 -- specific entry that exists, so dropping `ack-shield-attack`, then `ack-shield`, into
 -- this manifest makes them play with no code change.
 ack={frequency=600,duration=.06,gain=.16,priority=3,cooldown=.05,bus='ui'},
 windup={frequency=300,duration=.05,gain=.07,priority=0,cooldown=.12,bus='effects'},
 victory={frequency=1040,duration=.4,gain=.25,priority=6,cooldown=2,bus='ui'}}}
function A.create(settings)
 local self=setmetatable({settings=settings,pool={},last={},clock=0,templates={},variation=0}, {__index=A})
 if love.audio and love.sound then
  for name,d in pairs(A.manifest) do
   -- A cue may opt into a bundled file with `path`; a missing file keeps the synthesized fallback.
   local loaded,source=false,nil
   if d.path then loaded,source=pcall(love.audio.newSource,d.path,'static') end
   if loaded then self.templates[name]=source else pcall(function()
    local samples=math.floor(22050*d.duration);local data=love.sound.newSoundData(samples,22050,16,1)
    for i=0,samples-1 do local t=i/22050;local envelope=math.min(1,i/100)*(1-i/samples)^2
     local phase=t*d.frequency+.5*((d.endFrequency or d.frequency)-d.frequency)*t*t/d.duration
     data:setSample(i,math.sin(phase*6.2831853)*envelope*.5)
    end
    self.templates[name]=love.audio.newSource(data,'static')
   end) end
  end
 end
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
  slot.source:setRelative(true);slot.source:setPosition(0,0,-1)
  local gain=d.gain*self.settings.master/100*self.settings[d.bus]/100
  if app and x then local sx,sy=app:screen(x,y);local w,h=love.graphics.getDimensions();local pan=(sx-w/2)/(w/2);gain=gain/(1+math.abs(pan));slot.source:setPosition(math.max(-1,math.min(1,pan)),0,-1) end
  self.variation=self.variation%3+1;slot.source:setPitch(({.96,1,1.04})[self.variation]);slot.source:setVolume(gain);slot.source:play();self.last[name]=self.clock
 end)
end
-- Most specific acknowledgement that exists: per unit kind and order, then per unit
-- kind, then the generic cue. Faction voice lines slot in by naming alone.
function A:ack(kind,order,app,x,y)
 local names={}
 if kind and order then names[#names+1]='ack-'..kind..'-'..order end
 if kind then names[#names+1]='ack-'..kind end
 names[#names+1]='ack'
 for _,name in ipairs(names) do
  if self.templates[name] then return self:play(name,app,x,y) end
 end
end
function A:clear() for _,v in ipairs(self.pool) do v.source:stop() end end
return A
