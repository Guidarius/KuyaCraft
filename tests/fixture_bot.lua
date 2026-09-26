-- A bot receives only the same filtered view available to a player.
local M={}
function M.commands(view,content)
    local commands={}
    if view.tick%20~=0 or view.result then return commands end
    local player,worker,hq,hero,barracks,enemy
    local nodes={}
    for _,e in ipairs(view.entities) do
        if e.owner>0 and e.id==view.player.hq then player=e.owner;hq=e end
    end
    if not player then return commands end
    local function add(kind,e,args)
        args=args or {};args.entity=e.id
        commands[#commands+1]={kind=kind,args=args}
    end
    for _,e in ipairs(view.entities) do
        if e.alive then
            if e.category=='node' then nodes[#nodes+1]=e
            elseif e.owner==player then
                if e.kind=='worker' then worker=worker or e end
                if e.kind=='barracks' then barracks=barracks or e end
                if content.units[e.kind] and content.units[e.kind].hero then hero=e end
            else enemy=enemy or e end
        end
    end
    local builderId
    if worker and not barracks and view.player.resources.gold>=content.buildings.barracks.cost.gold then
        local ox,oy=math.floor(hq.x/256),math.floor(hq.y/256)
        local placed=false
        for radius=3,7 do
            if placed then break end
            for y=math.max(0,oy-radius),math.min(view.map.height-2,oy+radius) do
                if placed then break end
                for x=math.max(0,ox-radius),math.min(view.map.width-2,ox+radius) do
                    local ok=true
                    for cy=y,y+1 do for cx=x,x+1 do
                        local key=cy*view.map.width+cx+1
                        if not view.player.visible[key] or view.map.blocked[key] then ok=false end
                        for _,obstacle in ipairs(view.entities) do
                            local ex,ey=math.floor(obstacle.x/256),math.floor(obstacle.y/256)
                            if obstacle.alive and cx>=ex and cy>=ey and cx<ex+(obstacle.size or 1) and cy<ey+(obstacle.size or 1) then ok=false end
                        end
                    end end
                    if ok then add('build',worker,{building='barracks',x=x,y=y});builderId=worker.id;placed=true;break end
                end
            end
        end
    end
    -- Every idle worker but the builder harvests the nearest gold node.
    for _,e in ipairs(view.entities) do
        if e.alive and e.owner==player and e.kind=='worker' and e.order.kind=='stop' and e.id~=builderId then
            local best,dist
            for _,n in ipairs(nodes) do if n.resource=='gold' and (n.amount or 1)>0 then local d=(e.x-n.x)^2+(e.y-n.y)^2;if not best or d<dist then best=n;dist=d end end end
            if best then add('harvest',e,{target=best.id}) end
        end
    end
    if barracks and barracks.remaining==0 and #barracks.queue<2 then
        local roster=content.factions[view.player.faction].roster
        add('recruit',barracks,{unit=roster[1+math.floor(view.tick/100)%#roster]})
    end
    if not hero then
        for _,e in ipairs(view.entities) do if e.id==view.player.hero and not e.alive and not e.reviveRemaining then add('revive',e) end end
    else
        for i,threshold in ipairs(content.rules.xpThresholds) do
            if hero.xp>=threshold and not hero.upgrades[i] then add('upgrade',hero,{milestone=i,choice=1+(player+i)%2}) end
        end
    end
    if view.tick>=300 then
        local x,y
        if enemy then x=enemy.x;y=enemy.y
        else
            -- Scout public map coordinates; never read unseen entity positions.
            x=player%2==0 and 4*256 or (view.map.width-5)*256
            y=player%2==0 and 4*256 or (view.map.height-5)*256
        end
        for _,e in ipairs(view.entities) do
            if e.alive and e.owner==player and e.category=='unit' and e.kind~='worker' and (e.order.kind=='stop' or view.tick%200==0) then add('attack_move',e,{x=x,y=y}) end
        end
    end
    return commands
end
return M
