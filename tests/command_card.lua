local T={}
local C=require('src.content');local Sim=require('src.sim');local Actions=require('src.ui.actions')
local function fixture()
 local w=Sim.create({seed=12345,players={{faction='bastion'},{faction='wild'}}},C,require('src.maps').create('open_fields'))
 -- The audio stub records what played, so tests can hear what a player would hear.
 local audio={played={},acks={}}
 function audio:play(name) self.played[#self.played+1]=name end
 function audio:ack(kind,order) self.acks[#self.acks+1]=order end
 function audio:selected(kind) self.played[#self.played+1]='select' end
 local app={world=w,view=Sim.view(w,1),player=1,selected={},settings={bindings={attack='a',stop='s',hold='h',build='b'}},clock=0,queue={},audio=audio}
 function app:entity(id) for _,e in ipairs(self.view.entities) do if e.id==id then return e end end end
 function app:command(kind,id,args) self.queue[#self.queue+1]={kind=kind,id=id,args=args} end
 return app
end
local function index(app) local result={};for _,a in ipairs(Actions.list(app)) do result[a.id]=a end;return result end
local function workers(app) local ids={};for _,e in ipairs(app.view.entities) do if e.owner==1 and e.kind=='worker' then ids[#ids+1]=e.id end end;return ids end
function T.context()
 local app=fixture();local ids=workers(app);local hero=app.view.player.hero;local before=Sim.serializeCanonical(app.world)
 app.selected={hero};local a=index(app);assert(a.abilities and a.stance and not a['build-menu'])
 app.selected={ids[1],ids[2]};a=index(app);assert(a['build-menu'] and not a.harvest and not a.abilities)
 Actions.activate(app,a['build-menu']);assert(app.cardPage=='build');a=index(app);assert(a.barracks and a.tower and a.extractor and a.outpost and not a.move)
 app.selected={hero,ids[1]};a=index(app);assert(not app.cardPage and a.move and a.stance and not a['build-menu'] and a.abilities)
 app.selected={ids[1],hero};local b=index(app);assert(b.move and not b['build-menu'],'selection order altered capabilities')
 Actions.activate(app,b.stop);assert(#app.queue==2)
 -- Warcraft 3 answers an order once, on the click, whatever issued it. Stop from the card or its
 -- hotkey must flash the ordered units and play the acknowledgement, not a generic UI click.
 assert(#app.audio.acks==1 and app.audio.acks[1]=='stop','Stop was not acknowledged like a right-click order')
 assert(app.ackFlash and app.ackFlash[ids[1]] and app.ackFlash[hero],'Stop did not flash the ordered units')
 for _,name in ipairs(app.audio.played) do assert(name~='click','Stop played a generic click on top of its acknowledgement') end
 -- And never a second time when the simulation accepts it: that cue would make the input delay audible.
 local Feedback=require('src.ui.command_feedback');app.audio.played={}
 Feedback.resolve(app,{kind='accepted'},{kind='move',group=1});Feedback.resolve(app,{kind='accepted'},{kind='toggle',group=2})
 assert(#app.audio.played==0,'an accepted order was confirmed again when it executed: '..table.concat(app.audio.played,','))
 app.subgroupKind='worker';a=index(app);assert(a['build-menu'] and not a.stance);Actions.activate(app,a['build-menu']);assert(index(app).extractor,'worker subgroup lost build menu');app.subgroupKind=nil
 app.selected={hero};a=index(app);local slots={};local keys={};for _,action in pairs(a) do assert(action.slot<=9 and not slots[action.slot],'overlapping command slot');slots[action.slot]=true;if action.key~='' then assert(not keys[action.key],'duplicate hotkey');keys[action.key]=true end end
 for _,id in ipairs(C.units[app:entity(hero).kind].abilities) do assert(a['ability-'..id].slot==C.abilities[id].slot,'spell slot moved') end
 app.selected={app.view.player.hq};assert(index(app)['recruit-worker'])
 app.selected={};assert(not next(index(app)))
 assert(Sim.serializeCanonical(app.world)==before,'UI changed simulation state')
end
function T.availability()
 local app=fixture();app.selected={app.view.player.hq};local hq=app:entity(app.selected[1]);hq.kind='barracks'
 local a=index(app);assert(a['recruit-medic'].reason=='Requires HQ advancement')
 app.view.player.tech=true;app.view.player.resources.gold=0
 a=index(app);local unit=a['recruit-medic'];assert(unit.reason=='Insufficient gold' and unit.costs[1].short and not unit.costs[2].short)
 Actions.activate(app,unit);assert(#app.queue==0 and app.uiNotice.kind=='rejected' and app.costFlash.keys.gold)
 local costs=Actions.costs(app,{mana=30},{mana=10});assert(costs[1].short and costs[1].key=='mana')
 app.view.player.resources.gold=1000;hq.remaining=10;assert(index(app)['recruit-medic'].reason=='Building unfinished');hq.remaining=0
 local realHQ=app.world.entities[app.view.player.hq];for i=1,20 do realHQ.queue[i]={kind='siege',remaining=10} end
 assert(index(app)['recruit-medic'].reason=='Insufficient food');realHQ.queue={}
 for i=1,5 do hq.queue[i]={kind='worker',remaining=10} end;assert(index(app)['recruit-medic'].reason=='Production queue full')
 app.selected={app.view.player.hero};local hero=app:entity(app.selected[1]);hero.xp=1000;Actions.context(app);app.cardPage='abilities'
 a=index(app);assert(a['ability-2-1'].slot==4 and a['back-card'].slot==9)
 assert(not a['ability-1-1'].reason and a['ability-2-1'].reason=='Learn the previous tier first')
 hero.upgrades[1]=1;a=index(app);assert(a['ability-1-1'].reason=='Learned' and a['ability-1-2'].reason=='Other choice learned' and not a['ability-2-1'].reason)
 hero.xp=0;assert(index(app)['ability-2-1'].costs[1].short)
 app.playback={};assert(index(app)['ability-2-1'].reason=='Replay is read-only')
end
function T.rendered()
 local app=require('src.app').create({map='open_fields'});app.noAutoSave=true
 local function click(id)
  app:draw();for _,b in ipairs(app.widgets.items) do if b.id==id then local s=app.widgets.scale;app:mousepressed((b.x+b.w/2)*s,(b.y+b.h/2)*s,1);return b end end;error('missing '..id)
 end
 local ids=workers(app);app.selected={ids[1],ids[2]};click('build-menu');assert(app.cardPage=='build')
 app.world.players[1].resources.gold=0;app.view=Sim.view(app.world,1)
 for _,scale in ipairs({80,100,125}) do app.settings.scale=scale;app:draw();for _,b in ipairs(app.widgets.items) do if b.details then assert(b.x>=0 and (b.y+b.h)*scale/100<=love.graphics.getHeight(),'card outside viewport') end end end;app.settings.scale=100
 local before=#app.queue;local button=click('barracks');assert(button.reason=='Insufficient gold' and #app.queue==before and not app.building and app.uiNotice.kind=='rejected')
 app:keypressed('q');assert(#app.queue==before and not app.building,'hotkey bypassed cost')
 app.world.players[1].resources.gold=1000;app.view=Sim.view(app.world,1);app:keypressed('q');assert(app.building=='barracks')
 app:keypressed('escape');assert(not app.building and app.cardPage=='build');app:keypressed('escape');assert(not app.cardPage and not app.overlay)
 app.selected={app.view.player.hero,ids[1]};app:draw();app:keypressed('b');assert(not app.cardPage and not app.building)
 app:keypressed('f1');app:keypressed('u');assert(app.cardPage=='abilities');before=#app.queue;click('ability-1-1');assert(#app.queue==before and not app.overlay)
 local hero=app.world.entities[app.view.player.hero];hero.xp=C.rules.xpThresholds[1];app.view=Sim.view(app.world,1)
 click('ability-1-1');assert(app.overlay=='upgrade' and not hero.upgrades[1]);click('commit');app:update(.05);assert(hero.upgrades[1]==1 and app.cardPage=='abilities')
 assert(app.uiNotice.kind=='levelup')
 app.network={ready=false};local queued=#app.queue;require('src.ui.input').intent(app,0,0,nil,'move');assert(#app.queue==queued and app.uiNotice.kind=='rejected' and app.uiNotice.text=='Waiting for match to start' and app.message=='Waiting for match to start','blocked order reported issued');app.network=nil
 local state=Sim.serializeCanonical(app.world);app:draw();app:draw();assert(Sim.serializeCanonical(app.world)==state)
 local feedback=require('src.ui.command_feedback');app.orderMarker={group=8,time=0,x=0,y=0};feedback.resolve(app,{kind='rejected',reason='invalid position'},{kind='move',group=7,x=0,y=0});assert(not app.orderMarker.kind,'late rejection altered newer marker')
 feedback.resolve(app,{kind='rejected',reason='invalid position'},{kind='move',group=8,x=0,y=0});assert(app.orderMarker.kind=='rejected')
 for i=1,100 do feedback.notify(app,'rejected','Blocked',nil,nil,0,0) end;assert(#app.commandMarks<=16 and #app.audio.pool<=32)
 local audio=require('src.ui.audio');audio.manifest.menu.path='assets/audio/missing-test-cue.ogg';local fallback=audio.create(app.settings);audio.manifest.menu.path=nil;assert(fallback.templates.menu,'missing audio file disabled cue fallback');fallback:clear()
 -- Both drawing a disabled tooltip and feedback must leave canonical gameplay untouched.
 app:draw();app.widgets.hover={instant=true,label='Cost proof',tip='Requirements',reason='Insufficient mana',details={costs=Actions.costs(app,{mana=30},{mana=10})}};app.widgets:tooltip(1280,720);assert(app.widgets.shownTip,'the cost proof tooltip was not drawn')
 assert(Sim.serializeCanonical(app.world)==state);app:close()
 print('PASS command card: selection context, build submenu, costs, keyboard parity, hero choices, late acknowledgements, bounded feedback')
end
function T.captures(app,capture)
 local ids=workers(app);local hero=app.world.entities[app.view.player.hero];local player=app.world.players[1]
 local gold,xp=player.resources.gold,hero.xp
 app.overlay=nil;app.selected={ids[1],ids[2]};Actions.context(app);app.cardPage='build';player.resources.gold=100;app.view=Sim.view(app.world,1)
 capture('build-card',function() app:draw();for _,b in ipairs(app.widgets.items) do if b.id=='barracks' then app.widgets.hover=b end end;app.widgets:tooltip(love.graphics.getWidth(),love.graphics.getHeight()) end)
 app.selected={hero.id};Actions.context(app);app.cardPage='abilities';hero.xp=500;app.view=Sim.view(app.world,1)
 capture('ability-card',function() app:draw() end)
 app.selected={hero.id,ids[1]};capture('mixed-card',function() app:draw() end)
 player.resources.gold=gold;hero.xp=xp;app.view=Sim.view(app.world,1);app.selected={hero.id};Actions.context(app)
end
return T
