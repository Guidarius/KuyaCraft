local T={}
function T.run()
    local f=require('src.feedback').create()
    local hq={id=9,owner=1,category='building'}
    local a={id=1,kind='crossbow',owner=1,category='unit',alive=true,x=0,y=0}
    local b={id=2,kind='shield',owner=2,category='unit',alive=true,x=256,y=0}
    local v={player={hq=9},entities={hq,a,b}}
    f:observe({},v,0);assert(#f.items==0)
    local events={{kind='attack',source=1,target=2,tick=1}}
    f:observe(events,v,1);assert(#f.items==1 and f.items[1].kind=='tracer')
    f:observe(events,v,1);assert(#f.items==1,'duplicate effects')
    f:observe(events,{player={hq=9},entities={hq,a}},2);assert(#f.items==0,'fog must remove effects')
    f:observe({{kind='attack',source=1,target=2,tick=3}},v,3);assert(#f.items==1)
    f:observe({},v,6);assert(#f.items==0,'expired effects')
    local c={id=3,owner=1,category='unit',alive=true,x=10,y=10};v.entities[4]=c
    f:observe({},v,7);assert(#f.items==1 and f.items[1].kind=='ready')
    f:observe({},v,0);assert(#f.items==0,'rewind reset')
    T.unobserved();T.flash();T.floatingText();T.shake();T.windup();T.selectionCue()
end
-- A selection reply is chosen per unit kind when the manifest has one, and falls back to the
-- generic cue otherwise, including for a selection with no unit to name.
function T.selectionCue()
    local Audio=require('src.ui.audio')
    local a=Audio.create({})
    local heard={}
    a.templates={select=true,['select-shield']=true}
    a.play=function(_,name) heard[#heard+1]=name end
    a:selected('shield');a:selected('crossbow');a:selected(nil)
    assert(heard[1]=='select-shield','a unit with its own selection cue did not use it: '..tostring(heard[1]))
    assert(heard[2]=='select' and heard[3]=='select','a unit without its own cue did not fall back to the generic one')
end
-- A swing in progress is reported as how far it has got, and forgotten once it has landed or the
-- swinging unit is out of sight. The body leans into the blow from this.
function T.windup()
    local f=require('src.feedback').create()
    local hq={id=9,owner=1,category='building'}
    local a={id=1,kind='shield',owner=1,category='unit',alive=true,x=0,y=0}
    local v={player={hq=9},entities={hq,a}}
    f:observe({},v,0)
    assert(f:windup(1,0)==nil,'a unit that is not swinging reported a windup')
    f:observe({{kind='windup',source=1,tick=1}},v,1)
    assert(f:windup(1,1)==0,'a swing did not start at zero')
    f:observe({},v,3)
    assert(f:windup(1,3)==0.5,'a swing is not halfway two ticks in: '..tostring(f:windup(1,3)))
    f:observe({},v,6)
    assert(f:windup(1,6)==nil,'a landed swing was still reported')
    f:observe({{kind='windup',source=1,tick=7}},v,7)
    f:observe({},{player={hq=9},entities={hq}},8)
    assert(f:windup(1,8)==nil,'a swing out of sight was still reported')
end
-- An event naming an entity the player cannot see produces nothing, even though the
-- event itself was delivered (an impact can be heard without revealing its source).
function T.unobserved()
    local f=require('src.feedback').create()
    local hq={id=9,owner=1,category='building'}
    local a={id=1,kind='crossbow',owner=1,category='unit',alive=true,x=0,y=0}
    local v={player={hq=9},entities={hq,a}}
    f:observe({},v,0)
    f:observe({{kind='attack',source=1,target=7,tick=1}},v,1)
    assert(#f.items==0,'effect drawn for an unobserved target')
    assert(not f:flashing(7,1),'flash on an unobserved target')
end
-- The damage flash lasts a fixed, small number of ticks and is dropped as soon as the
-- unit leaves the view, so it cannot outlive what the player is allowed to see.
function T.flash()
    local f=require('src.feedback').create()
    local hq={id=9,owner=1,category='building'}
    local a={id=1,kind='shield',owner=1,category='unit',alive=true,x=0,y=0}
    local b={id=2,kind='shield',owner=2,category='unit',alive=true,x=256,y=0}
    local v={player={hq=9},entities={hq,a,b}}
    f:observe({},v,0)
    f:observe({{kind='attack',source=1,target=2,tick=1}},v,1)
    assert(f:flashing(2,1),'target did not flash on impact')
    assert(not f:flashing(1,1),'attacker must not flash')
    assert(f:flashing(2,3),'flash ended too early')
    assert(not f:flashing(2,4),'flash outlived its window')
    f:observe({},{player={hq=9},entities={hq,a}},5)
    assert(not f:flashing(2,5),'flash survived the target leaving view')
end
-- Floating text is capped like the effect list, ages in wall-clock, and only ever shows
-- one centre-screen rejection at a time.
function T.floatingText()
    local f=require('src.feedback').create()
    for i=1,400 do f:text('income','+1 gold',0,0) end
    assert(#f.texts==256,'floating text ignored its cap: '..#f.texts)
    f:reset();assert(#f.texts==0)
    f:text('income','+10 gold',0,0,nil,1.0)
    f:update(0.5);assert(#f.texts==1,'text expired early')
    f:update(0.6);assert(#f.texts==0,'text outlived its life')
    f:error('Insufficient resources')
    f:error('Population limit')
    assert(#f.texts==1,'centre-screen errors stacked')
    assert(f.texts[1].label=='Population limit','the newest rejection must win')
    assert(f.texts[1].kind=='error')
end
-- Shake decays to rest and is bounded, so a long fight cannot accumulate it.
function T.shake()
    local f=require('src.feedback').create()
    for _=1,20 do f:shakeBy(4) end
    assert(f.shake<=8,'shake exceeded its bound: '..f.shake)
    for _=1,30 do f:update(1/60) end
    assert(f.shake==0 and f.shakeX==0 and f.shakeY==0,'shake did not settle within half a second')
end
return T
