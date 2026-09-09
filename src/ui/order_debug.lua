local D={}
function D.draw(app,w,h)
    local e=app:entity(app.selected[1]);if not e or e.owner~=app.player then return end
    local g=love.graphics;local lines={'Order inspector [F3]  Unit '..e.id,
        'Order: '..e.order.kind..' | queued: '..#e.orders,
        'Combat target: '..tostring(e.combatTarget),
        'Phase: '..(e.attack and (app.world.tick<e.attack.impact and 'windup' or 'recovery') or 'none')..' | next commit: '..tostring(e.nextCommitTick),
        'Requested: '..tostring(e.order.requestX)..','..tostring(e.order.requestY)..' | slot: '..tostring(e.order.x)..','..tostring(e.order.y),
        'Waypoint: '..e.pathIndex..'/'..#e.path..' | '..(e.navigation or 'idle'),
        'Wait: '..(e.waitTicks or 0)..' | reason: '..(e.blockedReason or e.lastOrderFailure or 'none')}
    if app.lastCommandTiming then lines[#lines+1]='Last acknowledgement: '..app.lastCommandTiming.ticks..' ticks / '..app.lastCommandTiming.milliseconds..' ms' end
    local x,y=math.max(10,w-580),90
    g.setColor(.025,.04,.05,.94);g.rectangle('fill',x,y,570,175)
    g.setColor(.8,.95,.88);for i,line in ipairs(lines) do g.print(line,x+10,y+8+(i-1)*20) end
end
return D
