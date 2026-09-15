-- Control points: capture, contest, the two-minute hold, and state that survives a snapshot.
local Sim=require('src.sim')
local F=require('src.sim.fixed')
local Codec=require('src.sim.codec')
local Content=require('tests.fixture_content')
local Maps=require('src.maps')
local Control=require('src.sim.control')
local M={}
local function eq(a,b,message) assert(a==b,(message or 'values differ')..': '..tostring(a)..' != '..tostring(b)) end
local function step(w,n)
    local events={}
    for _=1,n do for _,ev in ipairs(Sim.step(w,{})) do events[#events+1]=ev end end
    return events
end
-- A 32-cell field with the given points, the two headquarters and the two heroes. Every
-- other unit is removed, and the heroes are parked in opposite corners, out of reach of
-- each other, the points and both headquarters, so a test moves exactly what it means to.
local function world(points)
    local m=Maps.create('control',32);m.resources={};m.camps={};m.controlPoints=points
    local w=Sim.create({seed=7,players={{faction='bastion'},{faction='wild'}}},Content,m)
    for _,id in ipairs(w.order) do local e=w.entities[id]
        if e.category=='unit' and id~=w.players[1].hero and id~=w.players[2].hero then e.alive=false end
    end
    local a,b=w.entities[w.players[1].hero],w.entities[w.players[2].hero]
    a.x=F.center(3);a.y=F.center(28);b.x=F.center(28);b.y=F.center(3)
    return w,a,b
end
function M.capture()
    local w,a=world({{x=16,y=16}});local rules=Control.rules(w);local point=w.control.points[1]
    a.x=point.x;a.y=point.y
    step(w,rules.captureTicks-1)
    eq(point.owner,0,'captured early');eq(point.capturer,1);eq(point.progress,rules.captureTicks-1)
    local captured
    for _,ev in ipairs(step(w,1)) do if ev.kind=='captured' then captured=ev end end
    eq(point.owner,1,'not captured on time');assert(captured and captured.capturedBy==1,'no capture event')
    -- Public: both players are told, and both views show the new owner.
    for p=1,2 do
        local told=false
        for _,ev in ipairs(Sim.eventsFor(w,p)) do if ev.kind=='captured' then told=true end end
        assert(told,'player '..p..' was not told of the capture');eq(Sim.view(w,p).control.points[1].owner,1)
    end
    -- Walking away does not give it up.
    a.x=F.center(3);a.y=F.center(28);step(w,rules.captureTicks*2);eq(point.owner,1,'an empty point changed hands')
end
function M.contest()
    local w,a,b=world({{x=16,y=16}});local point=w.control.points[1]
    a.x=point.x;a.y=point.y;step(w,50);eq(point.progress,50)
    -- An enemy inside freezes the capture, whatever the two of them then do to each other.
    b.x=point.x+256;b.y=point.y;step(w,20);eq(point.progress,50,'a contested capture moved');eq(point.owner,0)
    -- Alone on it, player two first unwinds player one's progress, then starts its own.
    a.alive=false;step(w,50);eq(point.progress,0);eq(point.capturer,1)
    step(w,1);eq(point.capturer,2);eq(point.progress,1)
end
function M.hold()
    local w=world({{x=10,y=16},{x=22,y=16}});local rules=Control.rules(w)
    -- Owned outright, as if captured earlier; the countdown starts on the next tick.
    w.control.points[1].owner=1;w.control.points[2].owner=1
    local started
    for _,ev in ipairs(step(w,1)) do if ev.kind=='control_started' then started=ev end end
    eq(w.control.holder,1);assert(started and started.deadline==w.tick+rules.holdTicks,'no countdown event')
    local since=w.control.since
    step(w,rules.holdTicks-1);assert(not w.result,'won a tick early')
    step(w,1);assert(w.result,'did not win on time')
    eq(w.result.winner,1);eq(w.result.reason,'control');eq(w.tick-since,rules.holdTicks)
end
function M.broken()
    local w,a,b=world({{x=10,y=16},{x=22,y=16}});local rules=Control.rules(w)
    local second=w.control.points[2]
    w.control.points[1].owner=1;second.owner=1
    step(w,rules.holdTicks-rules.captureTicks-10)
    -- Player two takes one back with seconds to spare, which cancels the countdown outright.
    b.x=second.x;b.y=second.y;local broken=false
    for _,ev in ipairs(step(w,rules.captureTicks)) do if ev.kind=='control_broken' then broken=true end end
    eq(second.owner,2);assert(broken,'no broken event');eq(w.control.holder,0)
    step(w,40);assert(not w.result,'a broken hold still won')
    -- Winning it back starts the countdown again from nothing.
    b.x=F.center(28);b.y=F.center(3);a.x=second.x;a.y=second.y
    step(w,rules.captureTicks);eq(second.owner,1);eq(w.control.holder,1);eq(w.control.since,w.tick)
    step(w,rules.holdTicks-1);assert(not w.result,'the old hold carried over')
    step(w,1);eq(w.result and w.result.winner,1)
end
function M.snapshot()
    local w,a=world({{x=16,y=16}});local point=w.control.points[1]
    a.x=point.x;a.y=point.y;step(w,120)
    local clone=Sim.restore(Codec.decode(Codec.encode(Sim.snapshot(w))))
    for _=1,120 do Sim.step(w,{});Sim.step(clone,{}) end
    eq(Sim.serializeCanonical(w),Sim.serializeCanonical(clone));eq(clone.control.points[1].owner,1)
    -- The checkpoint peers compare must cover the mode, or a divergence in it would go unseen.
    local other=Sim.restore(Sim.snapshot(w));other.control.points[1].progress=other.control.points[1].progress+1
    assert(Sim.serializeAuthoritative(w)~=Sim.serializeAuthoritative(other),'checkpoint ignores control state')
end
-- Edge cases. Each is a way the wrong player could win, or a point could be taken by nobody.

-- A holder that loses its headquarters loses the match, and its hold is worth nothing.
function M.defeatedHolder()
    local w=world({{x=10,y=16},{x=22,y=16}})
    w.control.points[1].owner=1;w.control.points[2].owner=1
    step(w,100);assert(not w.result,'the match ended early')
    w.entities[w.players[1].hq].hp=0;step(w,1)
    assert(w.result,'no result after the holder lost its headquarters')
    eq(w.result.winner,2);eq(w.result.reason,nil,'a defeated holder won by control')
end
-- A hold that would complete on the very tick its owner's headquarters falls: headquarters are
-- decided first, so the owner loses rather than winning by control on its way out.
function M.sameTick()
    local w=world({{x=10,y=16},{x=22,y=16}});local rules=Control.rules(w)
    w.control.points[1].owner=1;w.control.points[2].owner=1
    step(w,1);local since=w.control.since
    step(w,rules.holdTicks-1);assert(not w.result,'won a tick early')
    w.entities[w.players[1].hq].hp=0;step(w,1)
    eq(w.tick-since,rules.holdTicks,'the hold was not due on this tick')
    eq(w.result and w.result.winner,2,'the player whose headquarters fell still won')
    eq(w.result.reason,nil,'a hold completing on the losing tick counted as a control win')
end
-- The only unit capturing a point dies: nobody is capturing any more, so progress fades and the
-- point stays unowned.
function M.capturerDies()
    local w,a=world({{x=16,y=16}});local point=w.control.points[1]
    a.x=point.x;a.y=point.y;step(w,100);eq(point.progress,100)
    a.alive=false;a.hp=0;step(w,20)
    eq(point.owner,0,'a dead unit captured the point')
    assert(point.progress<100 and point.progress>=90,'progress did not fade at half rate after the capturer died: '..point.progress)
end
-- A three-player world with every unit removed and nothing else in the way.
local function threePlayers(points)
    local m=Maps.create('control',32);m.resources={};m.camps={};m.controlPoints=points
    local w=Sim.create({seed=7,players={{faction='bastion'},{faction='wild'},{faction='bastion'}}},Content,m)
    for _,id in ipairs(w.order) do local e=w.entities[id];if e.category=='unit' then e.alive=false end end
    return w
end
-- Control is not a two-player rule: a third player who holds every point wins.
function M.thirdPlayer()
    local w=threePlayers({{x=10,y=16},{x=22,y=16}});local rules=Control.rules(w)
    w.control.points[1].owner=3;w.control.points[2].owner=3
    step(w,rules.holdTicks+1)
    assert(w.result,'a third player holding every point did not win')
    eq(w.result.winner,3);eq(w.result.reason,'control')
end
-- A defeated player's surviving unit standing in the circle does not contest anyone's capture.
function M.defeatedDoesNotContest()
    local w=threePlayers({{x=16,y=16}});local rules=Control.rules(w);local point=w.control.points[1]
    w.entities[w.players[2].hq].hp=0;step(w,1);assert(w.players[2].defeated,'player two was not defeated')
    local mine,theirs=w.entities[w.players[1].hero],w.entities[w.players[2].hero]
    for _,e in ipairs({mine,theirs}) do e.alive=true;e.hp=e.maxHp;e.x=point.x;e.y=point.y end
    theirs.x=point.x+256
    step(w,rules.captureTicks)
    eq(point.owner,1,'a defeated player\'s unit stopped a capture')
end
return M
