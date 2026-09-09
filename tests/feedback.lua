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
end
return T
