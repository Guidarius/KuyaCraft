local Sim=require('src.sim')
local C=require('src.content')
local Maps=require('src.maps')
local S=require('tests.control_scenarios')
local F=require('src.sim.fixed')
local P=require('src.sim.path')
local M={}
local function write(name,text) local f=assert(io.open('artifacts/'..name,'wb'));f:write(text);f:close();print(text) end
-- Every shipping map but the default, which has its own longer matches below: the march
-- between the bases and to the natural at Footman speed, then six minutes of Orders against
-- Megacorp to prove both bots can live on the layout (production up, an economy running).
-- The numbers are reported for comparing layouts; only survival is asserted.
function M.mapReport(id)
 local map=Maps.create(id);local w=Sim.create({seed=725,players={{faction='orders'},{faction='megacorp'}}},C,map);local Bot=require('src.bot')
 local probe=Sim.create({seed=1,players={{faction='orders'},{faction='orders'}}},C,Maps.create(id))
 local a,b=map.unitStarts[1][1],map.unitStarts[2][1];local e=S.unit(probe,'footman',1,a.x,a.y)
 local function route(ax,ay,bx,by)
  e.x=F.center(ax);e.y=F.center(ay);e.path={};e.goal=nil;probe.metrics.directChecks=0;assert(P.request(probe,e,bx,by),'blocked route endpoint')
  for _=1,2000 do probe.metrics.pathExpansions=0;P.step(probe);if not probe.searches[e.id] then break end end
  assert(not probe.searches[e.id] and not e.blockedReason,'unreachable route on '..id)
  local ticks=0;local x,y=ax,ay
  for _,p in ipairs(e.path) do local distance=F.isqrt((p.x-x)^2*65536+(p.y-y)^2*65536);ticks=ticks+math.ceil(distance/C.units.footman.speed);x,y=p.x,p.y end
  return ticks/20
 end
 local natural=map.anchors.naturals[1]
 local main,toNatural=route(a.x,a.y,b.x,b.y),route(a.x,a.y,natural.x,natural.y)
 local firstContact;local built={{},{}}
 for tick=1,7200 do
  local commands={}
  if w.tick%20==0 then for p=1,2 do local sequence=w.players[p].sequence;for _,c in ipairs(Bot.commands(Sim.view(w,p),C)) do sequence=sequence+1;c.tick=tick;c.player=p;c.sequence=sequence;commands[#commands+1]=c end end end
  Sim.step(w,commands)
  for _,ev in ipairs(w.events) do
   if ev.kind=='constructed' then local entity=w.entities[ev.entity];built[entity.owner][entity.kind]=(built[entity.owner][entity.kind] or 0)+1
   elseif ev.kind=='attack' and not firstContact then local s,t=w.entities[ev.source],w.entities[ev.target];if s and t and s.owner>0 and t.owner>0 and s.owner~=t.owner then firstContact=tick end end
  end
  if w.result then break end
 end
 local open=0;for k=1,map.width*map.height do if not map.blocked[k] then open=open+1 end end
 write('balance-map-'..id..'.txt',string.format('%s (%dx%d, %d%% walkable): base to base %.1fs, to the natural %.1fs at Footman speed; after %ds of Orders vs Megacorp: Orders food %d with %d barracks and %d keeps, Megacorp food %d with %d rigs and %d relays; first contact %s; %s\n',
  id,map.width,map.height,math.floor(open*100/(map.width*map.height)),main,toNatural,w.tick/20,Sim.population(w,1),built[1].barracks or 0,1+(built[1].keep or 0),Sim.population(w,2),(built[2].substrate_rig or 0)+(built[2].charge_rig or 0),built[2].orbital_relay or 0,
  firstContact and string.format('%.0fs',firstContact/20) or 'none',w.result and ('won by player '..w.result.winner) or 'undecided'))
 assert(built[1].barracks,'the Orders bot built no barracks on '..id);assert(built[2].mc_barracks,'the Megacorp bot landed no barracks on '..id)
 assert((built[2].substrate_rig or 0)>=4,'the Megacorp bot rigged fewer than four patches on '..id)
 assert(Sim.population(w,1)>=12 or w.result,'the Orders bot did not grow on '..id)
end
function M.routes()
 local w=Sim.create({seed=1,players={{faction='orders'},{faction='orders'}}},C,Maps.create())
 local e=S.unit(w,'footman',1,28,18)
 local function route(ax,ay,bx,by)
  e.x=F.center(ax);e.y=F.center(ay);e.path={};e.goal=nil;w.metrics.directChecks=0;assert(P.request(w,e,bx,by),'blocked route endpoint')
  for _=1,1000 do w.metrics.pathExpansions=0;P.step(w);if not w.searches[e.id] then break end end
  assert(not w.searches[e.id] and not e.blockedReason,'unreachable route')
  local ticks=0;local x,y=ax,ay
  for _,p in ipairs(e.path) do local distance=F.isqrt((p.x-x)^2*65536+(p.y-y)^2*65536);ticks=ticks+math.ceil(distance/C.units.footman.speed);x,y=p.x,p.y end
  return ticks/20
 end
 -- The strategic targets are the 128x112 map's scaled by 1.5 with the map's width: the
 -- 192x192 map was made larger on purpose, so a longer march is the change, not a regression.
 local main=route(28,18,163,173);local natural=route(28,18,54,26);local easy=route(28,18,48,29);local center=route(96,96,28,18)
 local corner=route(28,18,22,160)+route(22,160,163,173)
 local report=string.format('Twin Marches infantry route estimates (actual A* cell paths, footman speed, rounded step ticks; no crowd waits):\nRally (28,18) to enemy rally (163,173): %.2fs [target 60–83]\nNatural approach (54,26): %.2fs [target 10–15]\nEasy camp (48,29): %.2fs [target 8–12]\nCenter to rally: %.2fs [target 30–42]\nVia the south-west corner (22,160): %.2fs (+%.1f%%) [reported only: a detour, not a flank]\n',main,natural,easy,center,corner,100*(corner/main-1))
 write('balance-routes.txt',report);assert(main>=60 and main<=83 and center>=30 and center<=42,'strategic route time outside target')
end
function M.match(mirror,ticks)
 local config={seed=725,players={{faction='orders'},{faction=mirror and 'orders' or 'megacorp'}}}
 local map=Maps.create();local w=Sim.create(config,C,map);local Bot=require('src.bot');local Replay=require('src.replay');local replay=Replay.create(config,C,map)
 local milestones={{},{}};local lines={};local label=mirror and 'mirror' or 'asymmetric'
 local firstContact;local peakFood,peakFoodTick={},{}
 for tick=1,ticks or 30000 do
  local commands={}
  if w.tick%20==0 then for p=1,2 do local sequence=w.players[p].sequence;for _,c in ipairs(Bot.commands(Sim.view(w,p),C)) do sequence=sequence+1;c.tick=tick;c.player=p;c.sequence=sequence;commands[#commands+1]=c end end end
  Sim.step(w,commands);Replay.record(replay,w,commands)
  for _,ev in ipairs(w.events) do
   if ev.kind=='constructed' or ev.kind=='recruited' or ev.kind=='researched' then
    local entity=w.entities[ev.entity];local p=entity.owner;local key=ev.kind..':'..entity.kind;if not milestones[p][key] then milestones[p][key]=tick;lines[#lines+1]=string.format('P%d %s at %.2fs',p,key,tick/20) end
   elseif ev.kind=='attack' and not firstContact then
    -- Time to first contact: the first blow struck between two players, ignoring the
    -- neutral camps, which both sides clear early and which say nothing about the
    -- pace of the match itself.
    local source,target=w.entities[ev.source],w.entities[ev.target]
    if source and target and source.owner>0 and target.owner>0 and source.owner~=target.owner then firstContact=tick end
   end
  end
  for p=1,2 do
   local food=Sim.population(w,p)
   if food>(peakFood[p] or 0) then peakFood[p]=food;peakFoodTick[p]=tick end
  end
  if tick%1200==0 then
   local line=string.format('%ds: P1 food=%d units=%d substrate=%d charge=%d | P2 food=%d units=%d substrate=%d charge=%d',tick/20,Sim.population(w,1),Sim.unitCount(w,1),w.players[1].resources.substrate,w.players[1].resources.charge or 0,Sim.population(w,2),Sim.unitCount(w,2),w.players[2].resources.substrate,w.players[2].resources.charge or 0)
   lines[#lines+1]=line;print(line)
  end
  if w.result then break end
 end
 lines[#lines+1]='Outcome: '..(w.result and tostring(w.result.winner) or 'unfinished')..' at '..(w.tick/20)..'s'..(w.result and ' by '..(w.result.reason or 'headquarters') or '')
 M.pacing(label,w,milestones,firstContact,peakFood,peakFoodTick,true)
 write('balance-'..label..'.txt',table.concat(lines,'\n')..'\n');Replay.write('artifacts/balance-'..label..'.replay',replay);if mirror then Replay.write('artifacts/sample.replay',replay) end
 local file=assert(io.open('artifacts/balance-'..label..'.state','wb'));file:write(Sim.serializeCanonical(w));file:close()
 local clone=Sim.create(config,C,map)
 for _,frame in ipairs(replay.frames) do Sim.step(clone,frame.commands) end
 assert(Sim.serializeCanonical(w)==Sim.serializeCanonical(clone),'new-profile replay diverged')
 assert(milestones[1]['constructed:barracks'],'the Orders bot did not establish production')
 assert(milestones[2]['constructed:barracks'] or milestones[2]['constructed:mc_barracks'],'the second bot did not establish production')
 return w
end
-- Match pacing measured rather than assumed. docs/BALANCE_AND_PACING.md sets a 15-25
-- minute target; the opening milestones are close to where they should be and the match
-- ends far too early, so this writes both to artifacts on every balance run. The bounds
-- asserted below are sanity rails around the current shape, wide enough not to fail on
-- ordinary variation and tight enough to catch a change that guts the opening. The
-- duration target is deliberately reported and not asserted: it is a design goal that
-- the content does not meet yet, and turning it into a failing test would only mean a
-- permanently red suite.
M.TARGET_MINUTES={15,25}
local function seconds(tick) return tick and tick/20 or nil end
local function clock(tick)
    if not tick then return '     -' end
    return string.format('%3d:%02d',math.floor(tick/1200),math.floor(tick/20)%60)
end
function M.pacing(label,w,milestones,firstContact,peakFood,peakFoodTick,rails)
    local duration=w.tick
    local rows={
        {'first extra worker',milestones[1]['recruited:worker']},
        {'war hall',milestones[1]['constructed:barracks']},
        {'first combat unit',milestones[1]['recruited:footman']},
        {'first depot',milestones[1]['constructed:depot']},
        {'first gryphon knight',milestones[1]['recruited:gryphon']},
        {'second keep',milestones[1]['constructed:keep']},
        {'first contact between players',firstContact},
        {'peak army, player 1',peakFoodTick[1]},
        {'peak army, player 2',peakFoodTick[2]},
        {'match end',duration},
    }
    local out={string.format('Match pacing: %s. Target %d-%d minutes (docs/BALANCE_AND_PACING.md).',label,M.TARGET_MINUTES[1],M.TARGET_MINUTES[2])}
    out[#out+1]='Milestones are player 1 unless stated. Times are mm:ss of simulated match time.'
    for _,row in ipairs(rows) do out[#out+1]=string.format('  %-32s %s',row[1],clock(row[2])) end
    out[#out+1]=string.format('  peak food                        P1 %d, P2 %d of caps %d, %d',peakFood[1] or 0,peakFood[2] or 0,Sim.supplyCap(w,1),Sim.supplyCap(w,2))
    -- The economy is workers on patches, so the report says how many each side kept and
    -- how much of the map's substrate is left.
    local workers,patches={0,0},0
    for _,id in ipairs(w.order) do
        local e=w.entities[id]
        if e.alive and e.owner>0 and C.units[e.kind] and C.units[e.kind].worker then workers[e.owner]=workers[e.owner]+1
        elseif e.alive and e.category=='node' and e.resource=='substrate' then patches=patches+1 end
    end
    out[#out+1]=string.format('  workers at the end               P1 %d, P2 %d',workers[1],workers[2])
    out[#out+1]=string.format('  substrate patches left           %d',patches)
    local minutes=duration/1200
    local verdict
    if minutes<M.TARGET_MINUTES[1] then verdict=string.format('%.1f minutes SHORT of the %d minute floor',M.TARGET_MINUTES[1]-minutes,M.TARGET_MINUTES[1])
    elseif minutes>M.TARGET_MINUTES[2] then verdict=string.format('%.1f minutes OVER the %d minute ceiling',minutes-M.TARGET_MINUTES[2],M.TARGET_MINUTES[2])
    else verdict='within target' end
    out[#out+1]=string.format('Duration %.2f minutes: %s',minutes,verdict)
    out[#out+1]='Two bot matches on one seed. This measures the shape of a match, not balance between the factions.'
    write('balance-pacing-'..label..'.txt',table.concat(out,'\n')..'\n')
    -- Sanity rails on the opening. These hold today and exist to catch a change that
    -- breaks the early game, not to enforce the duration target. The Orders against the
    -- Megacorp is report-only until the Megacorp has a ground army to send.
    if rails==false then return end
    local hall=seconds(milestones[1]['constructed:barracks'])
    assert(hall and hall>=20 and hall<=180,'war hall arrived at '..tostring(hall)..'s, outside 20-180s')
    assert(firstContact,'the players never fought each other')
    local contact=seconds(firstContact)
    assert(contact>=60 and contact<=900,'first contact at '..string.format('%.1f',contact)..'s, outside 60-900s')
    assert((peakFood[1] or 0)>=20 and (peakFood[2] or 0)>=20,'neither bot built a real army')
end
function M.stressWorld(perSide,opponent)
 perSide=perSide or 120
 local w=Sim.create({seed=1,players={{faction='orders'},{faction=opponent or 'orders'}}},C,Maps.create())
 for _,id in ipairs(w.order) do local e=w.entities[id];if e.category=='unit' then e.alive=false end end
 -- Two adjacent blocks in the center clearing; keep casualties from reducing the workload.
 local units={};for p=1,2 do for i=1,perSide do local x=(p==1 and 84 or 99)+(i-1)%10;local y=90+math.floor((i-1)/10)
  for cy=y-1,y+1 do for cx=x-1,x+1 do w.blocked[P.key(w.map,cx,cy)]=nil;w.map.blocked[P.key(w.map,cx,cy)]=nil end end
  local kind=opponent=='megacorp' and p==2 and (i%12==0 and 'battleship' or i%8==0 and 'enforcer' or i%6==0 and 'medic' or 'associate') or (i%3==0 and 'crossbow' or 'footman');local e=S.unit(w,kind,p,x,y);e.hp=1000000;e.maxHp=e.hp;units[#units+1]=e
 end end
 return w,units
end
function M.performance()
 local w,units=M.stressWorld()
 local stopProfile=S.profile and require('tests.sim_profile').start(S.profile)
 local times={};local attacks=0;local moved=0
 for tick=1,2000 do local commands={}
  if tick%400==1 or tick%400==301 then local seq={w.players[1].sequence,w.players[2].sequence};local attack=tick%400==1
   for _,e in ipairs(units) do seq[e.owner]=seq[e.owner]+1;commands[#commands+1]=S.command(w,e,attack and 'attack_move' or 'move',{x=F.center(attack and (e.owner==1 and 98 or 94) or (e.owner==1 and 87 or 102)),y=F.center(96),group=tick},seq[e.owner]) end
  end
  local old=units[1].x;local start=love.timer.getTime();Sim.step(w,commands);times[#times+1]=(love.timer.getTime()-start)*1000
  if old~=units[1].x then moved=moved+1 end
  for _,ev in ipairs(w.events) do if ev.kind=='attack' then attacks=attacks+1 end end
  assert(w.metrics.pathExpansions<=C.rules.pathBudget)
 end
 if stopProfile then stopProfile() end
 table.sort(times);write('balance-performance.txt',string.format('192x192 map, 240 live mobiles, 2000 active ticks, new combat/sight profile. Clearings widened for fixture deployment.\nSim.step p95 %.3fms; max %.3fms; attacks %d; lead moving ticks %d. Excludes bot/replay/rendering.\nDIST step_ms p50 %.6f p95 %.6f p99 %.6f max %.6f\nCHECKPOINT %d %s\n',times[1900],times[2000],attacks,moved,times[1000],times[1900],times[1980],times[2000],w.tick,require('src.hash').bytes(Sim.serializeAuthoritative(w))))
 assert(attacks>100 and moved>100)
 local budget=M.perfBudget or 10
 assert(times[1900]<budget,string.format('new-profile simulation exceeds %g ms p95 (%.3f ms)',budget,times[1900]))
end
return M


