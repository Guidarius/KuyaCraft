local C=require('src.asset_catalog')
local F=require('src.asset_frames')
local T={}
local function eq(a,b) assert(a==b,tostring(a)..' ~= '..tostring(b)) end
local function bad(fn) assert(not pcall(fn),'expected rejection') end
local function fixture(id)
    local m={version=2,unitId=id or 'shieldguard',buildId='test',profileId='bastion_overhead_v1',directions=C.directions,bodyHeightPixels=32,
        pages={{color='assets/generated/builds/test/a.png',mask='assets/generated/builds/test/m.png',width=128,height=128},{color='assets/generated/builds/test/b.png',mask='assets/generated/builds/test/n.png',width=128,height=128}},frames={},clips={},referenceStride={distance=1,units='navigationCells'}}
    for i=1,6 do m.frames[i]={page=i%2+1,x=0,y=0,width=64,height=64,anchorX=32,anchorY=40} end
    for _,name in ipairs({'idle','move','attack','death','work'}) do
        local c={durationMs=600,loop=name=='idle' or name=='move' or name=='work',frames={}};m.clips[name]=c
        for _,d in ipairs(C.directions) do c.frames[d]={1,2,3,4,5,6} end
    end
    m.clips.idle.frames={};for _,d in ipairs(C.directions) do m.clips.idle.frames[d]={1,2} end
    m.clips.attack.contactFrame=3
    return m
end
function T.run()
    local pod=fixture('drop_pod');pod.profileId='prop_overhead_v1';pod.fixedFacing='S'
    pod.clips={idle=pod.clips.idle,deploy=pod.clips.death};C.validate(pod,'drop_pod')
    eq(F.sample(pod,'deploy','S',9999),6)
    pod.clips.deploy.frames.N={1};bad(function() C.validate(pod,'drop_pod') end)
    pod.clips.deploy.frames.N={1,2,3,4,5,6};pod.fixedFacing='N';bad(function() C.validate(pod,'drop_pod') end)
    pod.fixedFacing='S';pod.clips.deploy=nil;bad(function() C.validate(pod,'drop_pod') end)
    local building=fixture('orbital_command')
    building.profileId='building_overhead_v1';building.fixedFacing='S';building.footprintCells=4
    building.clips={idle=building.clips.idle};C.validate(building,'orbital_command')
    eq(F.assetId({kind='orbital_command',category='building'}),'orbital_command')
    eq(F.assetId({kind='keep',category='building'}),'keep')
    local _,_,bc,bd=F.select(building,{x=100,y=200,alive=true,attackTick=2}, {x=0,y=0},3,{})
    eq(bc,'idle');eq(bd,'S')
    building.clips.idle.frames.N={2,1};bad(function() C.validate(building,'orbital_command') end)
    building.clips.idle.frames.N={1,2};building.footprintCells=0
    bad(function() C.validate(building,'orbital_command') end)
    eq(F.assetId({kind='command_blimp'}),'command_blimp')
    eq(F.assetId({kind='battleship'}),'battleship')
    for _,kind in ipairs({'associate','medic','enforcer'}) do eq(F.assetId({kind=kind}),kind) end
    local m=fixture();C.validate(m,'shieldguard')
    eq(F.sample(m,'idle','N',599),2);eq(F.sample(m,'idle','N',600),1)
    eq(F.sample(m,'death','SE',60000),6);eq(F.sample(m,'attack','S',0,true),3)
    eq(F.sample(m,'attack','S',100,true),4);eq(F.sample(m,'attack','S',5000,true),6)
    eq(m.frames[F.sample(m,'move','N',100)].page,1)
    for _,sample in ipairs({{0,-1,'N'},{1,-1,'NE'},{1,0,'E'},{1,1,'SE'},{0,1,'S'},{-1,1,'SW'},{-1,0,'W'},{-1,-1,'NW'}}) do eq(F.direction(sample[1],sample[2]),sample[3]) end
    eq(F.direction(0,0,'NW'),'NW')
    local e={id=1,kind='worker',x=128,y=0,alive=true,order={kind='move'}}
    eq(F.assetId(e),'worker');local state={};local a=F.select(m,e,{x=0,y=0},5,state)
    e.carrying=8;eq(F.assetId(e),'worker_loaded');e.carrying=nil;local b=F.select(m,e,{x=0,y=0},5,state);eq(a,b)
    eq(state.moveMs,300);eq(state.direction,'E')
    e.attackTick=6;e.order={kind='attack',target=2}
    local attack,_,clip,d=F.select(m,e,nil,6,state,{entities={{id=3,x=-100,y=-100,alive=true}}})
    eq(attack,3);eq(clip,'attack');eq(d,'E')
    local _,_,_,visibleD=F.select(m,e,nil,6,state,{entities={{id=2,x=128,y=-100,alive=true}}});eq(visibleD,'N')
    e.alive=false;e.deathTick=6;eq(F.select(m,e,nil,600,state),6)
    bad(function() local v=fixture();v.version=99;C.validate(v,'shieldguard') end)
    bad(function() local v=fixture();v.frames[1].x=120;C.validate(v,'shieldguard') end)
    bad(function() local v=fixture();v.clips.move.frames.N={500};C.validate(v,'shieldguard') end)
    bad(function() local v=fixture();v.pages[1].mask='../outside.png';C.validate(v,'shieldguard') end)
    bad(function() local v=fixture();v.clips.attack.contactFrame=7;C.validate(v,'shieldguard') end)
    for _,p in ipairs({'assets/generated/../x','assets/generated/a\\b','C:/x','assets/generated//x'}) do assert(not C.safePath(p)) end
    local old={version=1,frameSize=128,framesPerClip=4,directions=8,anchorX=64,anchorY=91}
    local legacy=C.adaptV1(old);eq(#legacy.frames,128);eq(F.sample(legacy,'death','NW',900),128)
    local files={['assets/generated/catalog.lua']={version=2,units={shieldguard='assets/generated/test.lua'}},['assets/generated/test.lua']=m}
    local function read(path) assert(files[path],'missing');return files[path] end
    local function exists(path) return files[path]~=nil end
    local loaded=C.load(read,exists);eq(loaded.units.shieldguard,m)
    files['assets/generated/test.lua']=fixture('wrong');loaded=C.load(read,exists);eq(loaded.units.shieldguard,nil);eq(#loaded.diagnostics,1)
    files['assets/generated/catalog.lua']={version=17};loaded=C.load(read,exists);eq(#loaded.diagnostics,1)
    files['assets/generated/catalog.lua']=nil;files['assets/generated/shieldguard.lua']=old
    loaded=C.load(read,exists);assert(loaded.legacy);eq(loaded.units.shieldguard.profileId,'legacy_v1')
    loaded=C.load(read,exists,'assets/generated/woodland/catalog.lua');eq(next(loaded.units),nil);eq(loaded.legacy,nil)
    local pilot=fixture('mouse_builder_48');pilot.profileId='woodland_pixel_v1'
    pilot.clips.attack=nil;pilot.clips.death=nil
    bad(function() C.validate(pilot,'mouse_builder_48') end)
    pilot.pixelStyle={palette={'#292323','#233c62','#315b89','#497eac','#71a4c7','#a8cedb'},teamStart=1,teamRamps={{'#233c62','#315b89','#497eac','#71a4c7','#a8cedb'}}}
    pilot.sourceRevision='test';C.validate(pilot,'mouse_builder_48')
    pilot.pixelStyle.teamRamps[1][1]='broken';bad(function() C.validate(pilot,'mouse_builder_48') end)
    local Sprites=require('src.sprites')
    local renderer=setmetatable({states={[1]={direction='E',moveMs=300}}},{__index=Sprites})
    local attacker={id=1,kind='worker',x=0,y=0,alive=true,attackTick=20,order={kind='attack_move'}}
    local corpse={id=2,x=0,y=-100,alive=false}
    local attackEvents={{kind='attack',source=1,target=2,tick=20}}
    renderer:observe(attackEvents,{entities={attacker,corpse}},20)
    eq(renderer.states[1].attackHeading,'N');eq(renderer.states[1].attackFacingTick,20)
    eq(renderer.states[1].moveMs,300)
    local _,_,observedClip,observedDirection=F.select(m,attacker,nil,20,renderer.states[1])
    eq(observedClip,'attack');eq(observedDirection,'N')
    corpse.x=100;corpse.y=0
    renderer:observe(attackEvents,{entities={attacker,corpse}},20)
    eq(renderer.states[1].attackHeading,'N') -- duplicate consumption cannot change the recorded direction
    eq(F.assetId({kind='worker',carrying=8}),'worker_loaded');eq(renderer.states[1].moveMs,300)
    attacker.attackTick=21
    renderer:observe({{kind='attack',source=1,target=2,tick=21}},{entities={attacker}},21)
    local _,_,_,hiddenDirection=F.select(m,attacker,nil,21,renderer.states[1]);eq(hiddenDirection,'N')
    eq(renderer.states[1].attackFacingTick,20) -- hidden target does not create a new heading
    renderer:observe({{kind='attack',source=3,target=2,tick=22}},{entities={corpse}},22)
    eq(renderer.states[3],nil) -- hidden source does not acquire presentation state
    renderer:observe({{kind='attack',source=1,target=2,tick=20}},{entities={attacker,corpse}},23)
    eq(renderer.states[1].attackFacingTick,20) -- stale events do not relabel a later tick
    renderer:reset();eq(renderer.observedTick,nil);eq(next(renderer.states),nil)
    local _,_,_,noEventDirection=F.select(m,attacker,nil,21,{direction='W'});eq(noEventDirection,'W')
    -- Hysteresis: a heading is kept until the motion is clearly past the boundary between two,
    -- so a unit moving close to that line stops flickering between them.
    eq(F.direction(256,0,nil),'E')
    local thirty=math.floor(256*math.tan(math.rad(30)))
    eq(F.direction(256,thirty,nil),'SE') -- with nothing to keep, 30 degrees is already south-east
    eq(F.direction(256,thirty,'E'),'E') -- but a unit already facing east keeps facing east
    eq(F.direction(256,math.floor(256*math.tan(math.rad(40))),'E'),'SE') -- until it is clearly past
    eq(F.direction(-256,0,'E'),'W') -- and a real reversal still turns
    print('PASS asset runtime: metadata, paths, v1 migration, multi-page frames, timing, world headings, cargo phase, visibility')
end
return T
