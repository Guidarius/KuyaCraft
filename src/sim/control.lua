-- Control points: a second way to win.
--
-- A map may name points. A player captures one by keeping units inside its circle with no
-- other player's units there, and it stays theirs after they leave, until someone else
-- captures it. Owning every point at once starts a countdown; a player who still owns
-- them all when it runs out wins. Losing any one point cancels the countdown, and a new
-- hold starts it again from the beginning.
--
-- All state is integer ticks on w.control and public to every player. Points are processed
-- in map order and units in w.order, so nothing here depends on table traversal.
local F=require('src.sim.fixed')
local M={}
-- Used when content does not configure the mode, so a map with points still works under
-- the frozen test fixtures.
M.DEFAULT={radius=1024,captureTicks=200,holdTicks=2400}
function M.rules(w) return w.content.rules.control or M.DEFAULT end
function M.create(w,map)
    local list=map.controlPoints
    if not list or #list==0 then return end
    local points={}
    for i,p in ipairs(list) do
        F.check(p.x,0,map.width-1);F.check(p.y,0,map.height-1)
        assert(not map.blocked[p.y*map.width+p.x+1],'control point on impassable terrain')
        points[i]={x=F.center(p.x),y=F.center(p.y),owner=0,capturer=0,progress=0}
    end
    w.control={points=points,holder=0,since=0}
end
local present={}
-- Advances every point one tick and returns the player who has just won by holding them
-- all, if anyone has. Runs after combat, so a unit that died this tick holds nothing.
function M.step(w,emit)
    local control=w.control
    if not control then return nil end
    local rules=M.rules(w)
    local reach=rules.radius*rules.radius
    for i,point in ipairs(control.points) do
        for p=1,#w.players do present[p]=false end
        for _,id in ipairs(w.order) do
            local e=w.entities[id]
            if e.alive and e.category=='unit' and e.owner>0 and F.distance2Bounded(e.x,e.y,point.x,point.y)<=reach then present[e.owner]=true end
        end
        local count,only=0,0
        for p=1,#w.players do if present[p] and not w.players[p].defeated then count=count+1;only=p end end
        if count==1 and only~=point.owner then
            if point.capturer~=only and point.progress>0 then
                -- Someone else's half-finished capture unwinds before this one begins.
                point.progress=point.progress-1
            else
                point.capturer=only;point.progress=point.progress+1
                if point.progress>=rules.captureTicks then
                    local previous=point.owner
                    point.owner=only;point.capturer=0;point.progress=0
                    emit(w,'captured',{point=i,capturedBy=only,previous=previous,x=point.x,y=point.y})
                end
            end
        elseif count<=1 then
            -- Empty, or occupied only by its owner: a partial capture fades. It fades at half
            -- speed when the point is empty, so stepping out for a moment does not lose it all.
            if point.progress>0 and (count==1 or w.tick%2==0) then
                point.progress=point.progress-1
                if point.progress==0 then point.capturer=0 end
            end
        end
        -- Two or more players inside: contested, and nothing moves.
    end
    local holder=control.points[1].owner
    for i=2,#control.points do if control.points[i].owner~=holder then holder=0 end end
    if holder~=control.holder then
        if control.holder>0 then emit(w,'control_broken',{holder=control.holder}) end
        control.holder=holder;control.since=w.tick
        if holder>0 then emit(w,'control_started',{holder=holder,deadline=w.tick+rules.holdTicks}) end
    end
    if holder>0 and not w.players[holder].defeated and w.tick-control.since>=rules.holdTicks then return holder end
    return nil
end
return M
