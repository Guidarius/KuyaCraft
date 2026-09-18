-- Game juice (src/ui/juice.lua): reactions are produced once per event, bounded, forgotten
-- on a rewind, harmless when the place they name cannot be seen, and complete: every event
-- the simulation emits is answered somewhere or silent for a stated reason.
local T={}
local function eq(a,b,message) assert(a==b,(message or 'values differ')..': '..tostring(a)..' != '..tostring(b)) end
local function app(tick)
    local heard={}
    local self={world={tick=tick or 1},content=require('src.content'),camera={zoom=1},accumulator=0,heard=heard,
        view={byId={[9]={id=9,x=5120,y=5120,category='building'},[2]={id=2,x=2560,y=2560,kind='battleship'}},player={hq=9}},
        feedback=require('src.feedback').create(),audio={play=function(_,name) heard[#heard+1]=name end}}
    function self:screen(x,y) return x/16,y/16 end
    return self
end
function T.run()
    local Juice=require('src.ui.juice');local Audio=require('src.ui.audio')
    local j=Juice.create();local a=app(1)
    -- One burst: a ring, its sparks, a number, the cue, a shake. Observing the tick again adds nothing.
    local burst={{kind='stack_burst',entity=5,x=1000,y=1000,damage=45,tick=1}}
    j:observe(burst,a)
    eq(#j.rings,1);eq(#j.particles,12);eq(#a.feedback.texts,1);eq(a.feedback.texts[1].label,'-45');eq(a.heard[1],'burst');assert(a.feedback.shake>0,'a burst was not felt')
    j:observe(burst,a);eq(#j.particles,12,'a tick was observed twice')
    -- A place that cannot be seen produces a cue at most, never an effect, and never an error.
    a.world.tick=2;j:observe({{kind='garrisoned',entity=5,target=77,x=0,y=0,tick=2}},a);eq(#j.rings,1,'a ring for a building out of sight')
    -- A splash weapon marks the ground it covers; the source's definition says so.
    a.world.tick=3;j:observe({{kind='attack',source=2,target=5,x=3000,y=3000,tick=3}},a)
    eq(#j.rings,2);assert(j.rings[2].filled and j.rings[2].radius==require('src.content').units.battleship.splash,'the splash ring is not the weapon\'s radius')
    -- A building's death leaves scorch; a unit's does not. The event names what died.
    a.world.tick=4;j:observe({{kind='death',entity=6,unitKind='depot',x=4000,y=4000,tick=4},{kind='death',entity=7,unitKind='footman',x=4100,y=4000,tick=4}},a)
    eq(#j.decals,1)
    -- Bounded: a hundred buildings falling on one tick cannot grow the pool past its cap.
    local many={};for i=1,100 do many[i]={kind='death',entity=100+i,unitKind='keep',x=i*10,y=0,tick=5} end
    a.world.tick=5;j:observe(many,a);assert(#j.particles<=384,'the particle pool outgrew its cap: '..#j.particles);assert(#j.decals<=48,'the decal list outgrew its cap')
    -- Everything ages out: particles and rings inside a second and a half, scorch in under half a minute.
    for _=1,30 do j:update(.05) end;eq(#j.particles,0);eq(#j.rings,0);assert(#j.decals>0,'scorch vanished at once')
    for _=1,500 do j:update(.05) end;eq(#j.decals,0)
    -- A rewind (replay seek) forgets everything.
    a.world.tick=6;j:observe(burst,a);a.world.tick=2;j:observe({},a);eq(#j.particles,0,'a rewind kept effects')
    -- Every cue a reaction names exists in the manifest, so a recording can be dropped in by name.
    for kind,reaction in pairs(Juice.REACTIONS) do if reaction.cue then assert(Audio.manifest[reaction.cue],'the reaction to '..kind..' names the unknown cue '..reaction.cue) end end
    for _,name in ipairs({'splash','cast'}) do assert(Audio.manifest[name],'missing cue '..name) end
    -- Completeness: every event kind in the simulation's sources is answered or silent on purpose.
    local kinds={}
    for _,file in ipairs(love.filesystem.getDirectoryItems('src/sim')) do
        if file:match('%.lua$') then for kind in love.filesystem.read('src/sim/'..file):gmatch("emit%(w,'([a-z_]+)'") do kinds[kind]=true end end
    end
    local count=0
    for kind in pairs(kinds) do
        count=count+1
        assert(Juice.REACTIONS[kind] or Juice.ELSEWHERE[kind] or Juice.SILENT[kind],'the simulation emits "'..kind..'" and nothing in the interface answers it: add a row to REACTIONS in src/ui/juice.lua, or to SILENT with the reason')
    end
    assert(count>=40,'the event scan found only '..count..' kinds; the pattern no longer matches the sources')
end
return T
