-- The Megacorp's orbital logistics as the interface shows them. `O.model` is a pure function
-- of the player's view and the content: the sidebar draws it and the Orbital Command's card
-- reads it, so the two can never disagree, and it can be tested with no window.
--
-- What it answers at a glance: which requisitions are producing (and how far along), which
-- are READY to land, which are waiting and whether a ready one is blocking them; how many
-- orbit slots and queue places there are; who sits in the open pod; how many pods exist,
-- are away, or are still locked; and whether a pod can launch now, and if not, why and when.
--
-- The sidebar is a strip down the right edge of the battlefield (src/ui/camera.lua narrows
-- the battlefield to make room), always on screen for a faction with orbital logistics,
-- because there is no building on the map to click for something produced off it. Glyphs
-- are monograms from the content labels; the kind ids are the hooks icon art replaces.
local O={}
O.WIDTH=136
function O.active(view,content)
    local faction=content.factions[view.player.faction]
    return faction~=nil and faction.coverage==true and view.player.orbit~=nil
end
local function seconds(ticks) return math.max(0,math.ceil(ticks/20)) end
function O.model(view,content)
    local p=view.player;local orbit=p.orbit
    if not orbit then return nil end
    local tick=view.tick;local queue=p.callDown or {}
    local m={slots=orbit.slots,queueMax=orbit.queueMax,count=#queue,ready=0,producing=0,waiting=0,frames={},
        landings={},flights={},seats={},pips={},capacity=orbit.podCapacity}
    -- An item in one of the first `slots` places is produced; a finished one stays in its
    -- place until it is landed, and until then nothing behind it moves up into production.
    local readyInSlot=false
    for i=1,orbit.queueMax do
        local item=queue[i]
        if not item then m.frames[i]={index=i,state='empty'}
        else
            local d=content.buildings[item.kind];local total=math.max(1,d.buildTicks or 1)
            local state=item.remaining==0 and 'ready' or i<=orbit.slots and 'producing' or 'waiting'
            if state=='ready' and i<=orbit.slots then readyInSlot=true end
            m[state]=m[state]+1
            m.frames[i]={index=i,state=state,kind=item.kind,label=d.label,progress=1-item.remaining/total,seconds=seconds(item.remaining),position=i}
        end
    end
    -- Waiting behind a finished building that has not been landed is the one stall the
    -- player causes themselves, so it is named.
    m.blocked=readyInSlot and m.waiting>0
    for _,frame in ipairs(m.frames) do if frame.state=='waiting' then frame.blocked=m.blocked end end
    for i,landing in ipairs(p.landings or {}) do
        local d=content.buildings[landing.kind];local half=(d and d.size or 1)*128
        m.landings[i]={kind=landing.kind,label=d and d.label or landing.kind,seconds=seconds(landing.at-tick),x=landing.x*256+half,y=landing.y*256+half}
    end
    local pods=p.pods or {open={kinds={}},inFlight={},cooldownUntil=0}
    for i=1,orbit.podCapacity do
        local kind=pods.open.kinds[i];local d=kind and content.units[kind]
        m.seats[i]=kind and {index=i,kind=kind,label=d.label,heavy=(d.garrisonSlots or 1)>1,cost=d.cost} or {index=i,empty=true}
    end
    m.loaded=#pods.open.kinds
    local soonest
    for i,pod in ipairs(pods.inFlight) do
        local left=pod.at-tick;soonest=math.min(soonest or left,left)
        m.flights[i]={seconds=seconds(left),count=#pod.kinds,x=pod.x*256+128,y=pod.y*256+128}
    end
    m.inFlight=#pods.inFlight;m.unlocked=orbit.podsUnlocked;m.free=math.max(0,orbit.podsUnlocked-m.inFlight)
    for i=1,orbit.podsMax do m.pips[i]=i<=m.inFlight and 'flight' or i<=orbit.podsUnlocked and 'free' or 'locked' end
    -- The launch dial. The cooldown is always reported, because "how long until the next pod"
    -- is worth knowing while the pod is still being loaded; the state is what stops a launch now.
    local cooling=math.max(0,(pods.cooldownUntil or 0)-tick)
    local launch={cooldown=cooling,cooldownSeconds=seconds(cooling),progress=1-cooling/math.max(1,orbit.podCooldown)}
    if m.free==0 then launch.state='away';launch.seconds=seconds(soonest or 0);launch.reason='Every pod is away; the next lands in '..launch.seconds..'s'
    elseif cooling>0 then launch.state='cooling';launch.seconds=launch.cooldownSeconds;launch.reason='Next pod in '..launch.seconds..'s'
    elseif m.loaded==0 then launch.state='empty';launch.reason='Load a unit first'
    else launch.state='ready' end
    m.launch=launch
    return m
end
-- The queue index of the next building ready to land after `after`, wrapping; nil when none.
function O.nextReady(model,after)
    if not model or model.ready==0 then return nil end
    local n=model.queueMax
    for step=1,n do
        local i=((after or 0)+step-1)%n+1
        if model.frames[i].state=='ready' then return i end
    end
end
-- Two letters for a thing with no icon yet: the initials of a two-word label, or the first
-- two letters of a one-word one.
function O.monogram(label)
    local a,b=label:match('^(%a)%a*%s+(%a)')
    if a then return (a..b):upper() end
    return label:sub(1,2):upper()
end
-- Actions, shared by the sidebar, the global keys and the alerts.
function O.arm(app,index)
    local item=(app.view.player.callDown or {})[index]
    if not item or item.remaining>0 then return false end
    app.targeting=nil;app.building=item.kind;app.landing=index;app.audio:play('build_order');return true
end
function O.armNext(app)
    local model=O.model(app.view,app.content);local index=O.nextReady(model,app.landing or 0)
    if not index then require('src.ui.command_feedback').notify(app,'rejected','Nothing is ready to land','orbit-next');return false end
    return O.arm(app,index)
end
function O.openPage(app,page)
    local hq=app.view.player.hq;if not hq then return end
    app.selected={hq};require('src.ui.actions').context(app);app.cardPage=page;app.building=nil;app.landing=nil;app.targeting=nil;app.audio:play('menu')
end
function O.launch(app) app.building=nil;app.landing=nil;app.targeting={command='pod_launch'} end
-- Drawing ------------------------------------------------------------------------
local function colour(g,c,a) g.setColor(c[1],c[2],c[3],a or 1) end
local function dial(g,cx,cy,r,progress,theme)
    -- A clock wipe: the dark wedge is what is left, unwinding clockwise from twelve.
    g.setColor(0,0,0,.55);g.circle('fill',cx,cy,r)
    colour(g,theme.meter,.9)
    if progress>0 then g.arc('fill','pie',cx,cy,r,-math.pi/2,-math.pi/2+math.pi*2*math.min(1,progress),24) end
    g.setColor(0,0,0,.5);g.circle('fill',cx,cy,r*.62)
    colour(g,theme.line,.9);g.setLineWidth(1);g.circle('line',cx,cy,r)
end
-- A label cut to one line: a name that wraps would run into the state word under it.
local function fit(g,text,width)
    local font=g.getFont()
    if font:getWidth(text)<=width then return text end
    while #text>1 and font:getWidth(text..'.')>width do text=text:sub(1,-2) end
    return text..'.'
end
-- Called from the HUD inside its scaled coordinate space: `w`,`h` are the window in HUD units.
function O.draw(app,w,h)
    local model=O.model(app.view,app.content);if not model then return end
    local g=love.graphics;local theme=require('src.ui.theme').of(app.view.player.faction);local widgets=app.widgets
    local Camera=require('src.ui.camera')
    local x,top,width,height=w-O.WIDTH,40,O.WIDTH,h-220
    local compact=height<430;local row=compact and 24 or 32;local pad=6;local inner=width-pad*2
    colour(g,theme.panel,.98);g.rectangle('fill',x,top,width,height);colour(g,theme.line);g.line(x,top,x,top+height)
    local y=top+6;local pulse=.55+.45*math.sin((app.clock or 0)*6)
    -- ORBIT: the header says how full the queue is and how many items are produced at once.
    colour(g,theme.accent);g.print('ORBIT',x+pad,y);colour(g,theme.text);g.printf(model.count..' / '..model.queueMax,x+pad,y,inner,'right')
    widgets:region('orbit-header',x,y-2,width,compact and 16 or 30,{title='Requisitions in orbit',stats={model.count..' of '..model.queueMax..' places used',model.slots..' produced at once'},
        lines={'Buildings are produced in orbit, then wait until you choose where they land.',model.slots<2 and 'A second Requisition Office produces two at once.' or 'Two Offices: two are produced at once.'}})
    y=y+14
    if not compact then colour(g,theme.dim);g.print(model.slots==1 and '1 production slot' or model.slots..' production slots',x+pad,y);y=y+16 end
    for _,frame in ipairs(model.frames) do
        local fy=y;local id='orbit-frame-'..frame.index
        if frame.state=='empty' then
            colour(g,theme.line,frame.index<=model.slots and .45 or .2);g.rectangle('line',x+pad,fy,inner,row-4,theme.radius)
            if frame.index<=model.slots then colour(g,theme.dim,.7);g.printf('slot',x+pad,fy+(row-4)/2-7,inner,'center') end
        else
            local tip={title=frame.label,subtitle=frame.state=='ready' and 'Ready to land' or frame.state=='producing' and ('In production, '..frame.seconds..'s left') or ('Waiting, place '..frame.position..' in the queue'),
                subtitleColor=frame.state=='ready' and {.55,1,.7} or nil,
                reason=frame.blocked and 'Blocked: land the ready building to free its production slot' or nil,
                lines={frame.state=='ready' and 'Click, then click covered ground. Right-click the ground to keep it in orbit.' or 'Produced in orbit; it lands complete.',{'Right-click here to cancel it for a 75% refund.',theme.dim}}}
            widgets:button(id,'',x+pad,fy,inner,row-4,function() if frame.state=='ready' then O.arm(app,frame.index) end end,nil,tip)
            widgets.items[#widgets.items].alt=function() app:command('cancel',app.view.player.hq,{callDown=frame.index});app.audio:play('cancel') end
            local cy=fy+(row-4)/2;local r=(row-4)/2-3
            if frame.state=='ready' then
                colour(g,theme.accent,pulse);g.setLineWidth(2);g.rectangle('line',x+pad,fy,inner,row-4,theme.radius);g.setLineWidth(1)
                colour(g,theme.accent,.18*pulse);g.rectangle('fill',x+pad,fy,inner,row-4,theme.radius)
            end
            if app.landing==frame.index then colour(g,theme.text);g.rectangle('line',x+pad+2,fy+2,inner-4,row-8,theme.radius) end
            dial(g,x+pad+r+4,cy,r,frame.state=='waiting' and 0 or frame.progress,theme)
            colour(g,frame.state=='waiting' and theme.dim or theme.text);g.printf(O.monogram(frame.label),x+pad+4,cy-7,r*2,'center')
            local tx=x+pad+r*2+10;local tw=inner-r*2-14
            colour(g,frame.state=='waiting' and theme.dim or theme.text);g.print(fit(g,frame.label,tw-(compact and 40 or 0)),tx,compact and cy-7 or fy+2)
            local word=frame.state=='ready' and 'READY' or frame.state=='producing' and (frame.seconds..'s') or (frame.blocked and 'blocked' or ('#'..frame.position))
            if frame.state=='ready' then colour(g,theme.accent) elseif frame.blocked then g.setColor(1,.5,.35) else colour(g,theme.dim) end
            if compact then g.printf(word,tx,cy-7,tw,'right') else g.printf(word,tx,fy+14,tw,'left') end
        end
        y=y+row
    end
    -- Descents, each with its countdown; a click looks at the site.
    for i,landing in ipairs(model.landings) do
        if i>2 then break end
        widgets:button('orbit-landing-'..i,'v '..landing.seconds..'s  '..landing.label,x+pad,y,inner,16,function() Camera.glide(app,landing.x,landing.y) end,nil,{title=landing.label..' landing',lines={'Touches down in '..landing.seconds..' seconds. Click to look at the site.'}})
        y=y+18
    end
    widgets:button('orbit-requisition','+ Requisition',x+pad,y,inner,compact and 20 or 24,function() O.openPage(app,'requisition') end,model.count>=model.queueMax and 'The queue is full' or nil,
        {title='Requisition',key='b',lines={'Order a building from orbit. It is paid for now.'}})
    y=y+(compact and 24 or 30)
    colour(g,theme.line,.6);g.line(x+pad,y,x+width-pad,y);y=y+5
    -- PODS: a pip per pod that could ever fly. Filled is away, hollow is free, a dot is locked.
    colour(g,theme.accent);g.print('PODS',x+pad,y)
    for i,pip in ipairs(model.pips) do
        local px=x+width-pad-(#model.pips-i)*14-6;local py=y+7
        if pip=='flight' then colour(g,theme.meter);g.circle('fill',px,py,5)
        elseif pip=='free' then colour(g,theme.accent);g.setLineWidth(1.5);g.circle('line',px,py,5);g.setLineWidth(1)
        else colour(g,theme.dim,.6);g.circle('fill',px,py,1.5) end
    end
    widgets:region('orbit-pods',x,y-2,width,16,{title='Drop pods',stats={model.free..' free',model.inFlight..' away',(#model.pips-model.unlocked)..' locked'},
        lines={'One pod, and one more for every Requisition Office, up to '..#model.pips..'.'}})
    y=y+18
    -- Seats, in the order the troops will step out. A heavy unit is marked; a click refunds that seat.
    local cell=math.floor((inner-(model.capacity-1)*3)/model.capacity);local seatH=compact and 22 or 28
    for i,seat in ipairs(model.seats) do
        local sx=x+pad+(i-1)*(cell+3)
        if seat.empty then colour(g,theme.line,.3);g.rectangle('line',sx,y,cell,seatH,theme.radius)
        else
            widgets:button('orbit-seat-'..i,O.monogram(seat.label),sx,y,cell,seatH,function() app:command('cancel',app.view.player.hq,{pod=true,seat=i});app.audio:play('cancel') end,nil,
                {title=seat.label,subtitle='Seat '..i..' of '..model.capacity,lines={'Click to take it out of the pod for a full refund.'},costs=require('src.ui.actions').costs(app,seat.cost)})
            if seat.heavy then colour(g,theme.meter);g.rectangle('fill',sx+2,y+seatH-4,cell-4,2) end
        end
    end
    y=y+seatH+6
    -- The launch dial: four states that differ in shape as well as colour.
    local launch=model.launch;local r=compact and 18 or 26;local cx,cy=x+width/2,y+r
    local reason=launch.state~='ready' and launch.reason or nil
    widgets:button('orbit-launch','',x+pad,y,inner,r*2,function() O.launch(app) end,reason,
        {title='Launch the pod',key='t',subtitle=model.loaded..' of '..model.capacity..' seats filled',lines={'Click covered ground. The pod lands there ten seconds later and the troops step out around it.'}})
    if launch.state=='ready' then colour(g,theme.accent,.25+.2*pulse);g.circle('fill',cx,cy,r-2);colour(g,theme.accent);g.setLineWidth(2);g.circle('line',cx,cy,r-2);g.setLineWidth(1)
    elseif launch.state=='cooling' then dial(g,cx,cy,r-2,launch.progress,theme)
    elseif launch.state=='away' then colour(g,theme.meter,.5+.4*pulse);g.setLineWidth(2);g.circle('line',cx,cy,r-2);g.circle('line',cx,cy,r-8);g.setLineWidth(1)
    else colour(g,theme.dim,.7);g.circle('line',cx,cy,r-2) end
    local word=launch.state=='ready' and 'LAUNCH' or launch.state=='empty' and 'LOAD' or (launch.seconds..'s')
    if launch.state=='ready' then colour(g,theme.text) elseif launch.state=='empty' then colour(g,theme.dim) else colour(g,theme.text) end
    g.printf(word,x+pad,cy-7,inner,'center')
    -- The cooldown is worth seeing even while something else stops the launch.
    if launch.state~='cooling' and launch.cooldown>0 then colour(g,theme.dim);g.printf('pod '..launch.cooldownSeconds..'s',x+pad,cy+r-14,inner,'center') end
    y=y+r*2+4
    for i,flight in ipairs(model.flights) do
        if i>2 then break end
        widgets:button('orbit-flight-'..i,'v '..flight.seconds..'s  pod of '..flight.count,x+pad,y,inner,16,function() Camera.glide(app,flight.x,flight.y) end,nil,{title='Pod in flight',lines={'Lands in '..flight.seconds..' seconds. Click to look at the landing point.'}})
        y=y+18
    end
    widgets:button('orbit-load','+ Load pod',x+pad,y,inner,compact and 20 or 24,function() O.openPage(app,'pod') end,model.loaded>=model.capacity and 'The pod is full' or nil,
        {title='Load the pod',key='p',lines={'Choose troops for the open pod. Each is paid for as it is loaded.'}})
    -- The dial finishing with troops aboard is worth a sound; it is the interface's own event.
    if app.podCooling and launch.cooldown==0 and model.loaded>0 then app.audio:play('pod_ready') end
    app.podCooling=launch.cooldown>0
    app.orbitalModel=model
end
return O
