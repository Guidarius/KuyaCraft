local C=require('src.content')
local S={}
-- The next faction in the menu's cycle: content order by id, so a new faction appears
-- without the menu knowing its name.
function S.nextFaction(current)
 local ids={};for id in pairs(C.factions) do ids[#ids+1]=id end;table.sort(ids)
 for i,id in ipairs(ids) do if id==current then return ids[i%#ids+1] end end
 return ids[1]
end
function S.create(options)
 local self=setmetatable({options=options,screen='main',settings=require('src.ui.settings').load(),widgets=require('src.ui.widgets').create(),faction=options.faction or S.nextFaction(nil),opponent=options.opponent or S.nextFaction(S.nextFaction(nil)),map=options.map or 'twin_marches',address='127.0.0.1:22122',message='',fonts={small=love.graphics.newFont(14),title=love.graphics.newFont(36)}},{__index=S})
 if options.replay then self:start({replay=options.replay}) elseif options.host or options.join then
  local config={seed=12345,players={{faction=self.faction},{faction=self.opponent}}};local opts={host=options.host,join=options.join,manualLobby=true}
  local ok,n=pcall(require('src.net.session').create,opts,config,C,require('src.maps').create(self.map));self.screen='multiplayer';self.address=options.host or options.join;if ok then self.lobby=n else self.message=tostring(n) end
 end;return self
end
function S:start(extra)
 local options={map=self.map,faction=self.faction,opponent=self.opponent,settings=self.settings};for k,v in pairs(extra or {}) do options[k]=v end
 local ok,a=pcall(require('src.app').create,options);if not ok then self.message=tostring(a);return end
 self.match=a;self.screen='match';self.focus=nil
end
function S:leave()
 if self.match then self.match:close();self.match=nil end;if self.lobby then self.lobby:close();self.lobby=nil end;self.screen='skirmish';self.focus=nil
end
function S:update(dt)
 if self.lobby then
  self.lobby:poll();self.message=self.lobby.status
  if self.lobby.ready then local n=self.lobby;self.lobby=nil;self:start({faction=n.config.players[1].faction,opponent=n.config.players[2].faction})
   if self.match then self.match.network=n;self.match.player=n.player;self.match.started=false end
  end
 end
 if self.match then self.match:update(dt)
  if self.match.leaveRequested then self:leave()
  elseif self.match.world.result and not self.match.playback and self.screen~='results' then self.screen='results';self.match.audio:play('victory') end
 end
end
function S:draw()
 if self.screen=='match' then return self.match:draw() end
 local g=love.graphics;local scale=self.settings.scale/100;local width,height=g.getDimensions();local w,h=width/scale,height/scale
 g.clear(.035,.058,.075);g.push('all');g.scale(scale);g.setFont(self.fonts.small);self.widgets:begin(scale);self.widgets.context=self.screen
 local x,y=w/2-230,math.max(105,h/2-210)
 g.setColor(.13,.2,.22);g.polygon('fill',0,h,w*.48,h*.1,w,h);g.setColor(.045,.07,.09,.92);g.rectangle('fill',x-30,y-30,520,490,8)
 g.setFont(self.fonts.title);g.setColor(.91,.83,.59);g.printf('LoveRTS',0,32,w,'center');g.setFont(self.fonts.small)
 local function button(id,label,row,fn,reason,tip) self.widgets:button(id,label,x,y+row*48,460,38,fn,reason,tip) end
 local function label(t,yy) g.setColor(.8,.85,.82);g.printf(t,x,yy,460) end
 if self.screen=='main' then
  label('Small armies. Distinct factions. Every order matters.',y)
  for i,item in ipairs({{'Skirmish','skirmish'},{'Multiplayer','multiplayer'},{'Replays','replays'},{'Settings','settings'},{'Quit','quit'}}) do
   button(item[2],item[1],i,function() if item[2]=='quit' then love.event.quit() else self.screen=item[2];self.message='';if self.screen=='replays' then self:replays() end end end)
  end
 elseif self.screen=='skirmish' then
  label('SKIRMISH',y)
  button('map','Map: '..self.map,1,function() self.map=({twin_marches='river_pass',river_pass='open_fields',open_fields='movement_lab',movement_lab='twin_marches'})[self.map] or 'river_pass' end)
  button('faction','Your faction: '..C.factions[self.faction].label,2,function() self.faction=S.nextFaction(self.faction) end)
  button('opponent','Bot: '..C.factions[self.opponent].label,3,function() self.opponent=S.nextFaction(self.opponent) end)
  label(C.factions[self.faction].blurb or '',y+194)
  local map=require('src.maps').create(self.map);local cell=math.min(170/map.width,65/map.height);local mx=x+145;local my=y+240
  for cy=0,map.height-1 do for cx=0,map.width-1 do local key=cy*map.width+cx+1;if map.blocked[key] then g.setColor(.2,.35,.45) elseif map.unbuildable and map.unbuildable[key] then g.setColor(.42,.36,.25) else g.setColor(.22,.35,.27) end;g.rectangle('fill',mx+cx*cell,my+cy*cell,cell,cell) end end
  button('start','Start skirmish',7,function() self:start() end);button('back','Back',8,function() self.screen='main' end)
 elseif self.screen=='multiplayer' then
  label('PRIVATE MULTIPLAYER | direct IP',y)
  button('address',(self.focus=='address' and '> ' or '')..self.address,1,function() self.focus='address' end,nil,'Click to edit host:port. Enter finishes.')
  button('faction','Your faction: '..C.factions[self.faction].label,2,function()
   self.faction=S.nextFaction(self.faction);if self.lobby then self.lobby:setLobby(self.faction,false) end
  end,self.lobby and not self.lobby.compatible and 'Compatibility pending' or nil)
  if not self.lobby then
   for i,kind in ipairs({'host','join'}) do button(kind,kind=='host' and 'Host game' or 'Join game',2+i,function()
    local options={manualLobby=true};options[kind]=self.address
    local config={seed=12345,players={{faction=self.faction},{faction='wild'}}}
    local ok,n=pcall(require('src.net.session').create,options,config,C,require('src.maps').create(self.map));if ok then self.lobby=n;self.focus=nil else self.message=tostring(n) end
   end) end
  else local n=self.lobby
   label('Compatibility: '..(n.compatible and 'Verified' or 'Checking')..'\nPlayer 1: '..n.config.players[1].faction..' / '..(n.lobbyReady[1] and 'Ready' or 'Not ready')..'\nPlayer 2: '..n.config.players[2].faction..' / '..(n.lobbyReady[2] and 'Ready' or 'Not ready'),y+150)
   button('ready',n.lobbyReady[n.player] and 'Not ready' or 'Ready',5,function() n:setLobby(self.faction,not n.lobbyReady[n.player]) end,not n.compatible and 'Compatibility pending' or n.error)
   if n.player==1 then button('start','Start match',6,function() n:startMatch() end,not(n.lobbyReady[1] and n.lobbyReady[2]) and 'Both players must be ready' or n.error) end
  end
  button('back','Back',8,function() if self.lobby then self.lobby:close();self.lobby=nil end;self.screen='main';self.focus=nil end)
 elseif self.screen=='replays' then
  label('REPLAYS | current version only',y)
  for i=1,6 do local name=self.replayFiles and self.replayFiles[(self.replayPage or 0)*6+i];if name then button('replay-'..i,name.name,i,function() self:start({replay=name.path}) end) end end
  if not self.replayFiles or #self.replayFiles==0 then label('No recorded replays in artifacts.',y+70) end
  self.widgets:button('next-page','Next page',x,y+7*48,225,38,function() self.replayPage=((self.replayPage or 0)+1)%math.max(1,math.ceil(#self.replayFiles/6)) end)
  self.widgets:button('back','Back',x+235,y+7*48,225,38,function() self.screen='main' end)
 elseif self.screen=='settings' then require('src.ui.screens').settings(self,w,h,function() self.screen='main' end)
 elseif self.screen=='results' then
  local a=self.match;local r=a.world.result;label(r.winner==0 and 'DRAW' or r.winner==a.player and 'VICTORY' or 'DEFEAT',y)
  local living,lost=0,0;for _,e in ipairs(a.view.entities) do if e.owner==a.player and e.category=='unit' then if e.alive then living=living+1 else lost=lost+1 end end end
  label(string.format('Duration: %d:%02d\nSurviving units: %d\nUnits lost: %d\nGold: %d',math.floor(r.tick/1200),math.floor(r.tick/20)%60,living,lost,a.view.player.resources.gold),y+65)
  button('save','Save Replay',5,function() a:save();self.message=a.message end);button('setup','Return to Setup',6,function() self:leave() end)
 end
 if self.message~='' then g.setColor(.95,.72,.44);g.printf(self.message,20,h-55,w-40,'center') end
 self.widgets:tooltip(w,h);g.pop()
end
function S:replays()
 self.replayFiles=require('src.ui.replay_library').list();self.replayPage=0
end

function S:mousepressed(x,y,b,...) if self.screen=='match' then return self.match:mousepressed(x,y,b,...) end;if b==1 and self.widgets.context==self.screen then self.widgets:click(x,y) end end
function S:mousereleased(...) if self.screen=='match' then self.match:mousereleased(...) end end
function S:mousemoved(...) if self.screen=='match' then self.match:mousemoved(...) end end
function S:wheelmoved(...) if self.screen=='match' then self.match:wheelmoved(...) end end
function S:keypressed(key)
 if self.screen=='match' then return self.match:keypressed(key) end
 if self.rebind then return require('src.ui.input').keypressed(self,key) end
 if self.focus=='address' then if key=='backspace' then self.address=self.address:sub(1,-2) elseif key=='return' or key=='escape' then self.focus=nil end;return end
 if key=='escape' and self.screen~='results' then if self.lobby then self.lobby:close();self.lobby=nil end;self.screen='main' end
end
function S:textinput(text) if self.focus=='address' then self.address=(self.address..text:gsub('[^%w%.:%-_*]','')):sub(1,128) end end
function S:close() if self.match then self.match:close() end;if self.lobby then self.lobby:close() end end
return S
