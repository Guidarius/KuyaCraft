-- Tiled map conversion (src/maps/tiled.lua): what the converter accepts, what it refuses, and
-- that the shipped Twin Marches export agrees with the flags the simulation reads.
local Tiled=require('src.maps.tiled')
local M={}
local function eq(a,b,message) assert(a==b,(message or 'values differ')..': '..tostring(a)..' != '..tostring(b)) end
-- A minimal export in the shape Tiled's Lua format produces: 8x8, tiles 1-4 are grass, road,
-- rock and forest.
local function export()
    local data={}
    for i=1,64 do data[i]=1 end
    data[1]=3;data[2]=2+0x80000000;data[10]=4+0x40000000+0x20000000;data[64]=2
    return {
        orientation='orthogonal',width=8,height=8,tilewidth=32,tileheight=32,properties={id='fixture'},
        tilesets={{name='terrain',firstgid=1,tiles={
            {id=0,properties={terrain='grass'}},{id=1,properties={terrain='road'}},
            {id=2,properties={terrain='rock'}},{id=3,properties={terrain='forest'}}}}},
        layers={
            {type='tilelayer',name='ground',width=8,height=8,encoding='lua',data=data},
            {type='objectgroup',name='gameplay',objects={
                {id=7,type='gold',shape='rectangle',x=96,y=96,width=96,height=96,properties={amount=900}},
                {id=2,type='start',shape='rectangle',x=32,y=32,width=160,height=160,properties={player=2}},
                {id=1,type='start',shape='rectangle',x=0,y=160,width=160,height=160,properties={player=1}},
                {id=5,type='gold',shape='rectangle',x=160,y=0,width=96,height=96,properties={amount=500}},
                {id=9,type='camp',shape='point',x=48,y=80,properties={kind='scout',tier='easy'}},
                {id=4,type='control',shape='point',x=112,y=112,properties={}},
                {id=11,type='substrate',shape='rectangle',x=0,y=0,width=32,height=32,properties={amount=1500}},
                {id=12,type='charge',shape='rectangle',x=192,y=192,width=64,height=64,properties={amount=5000}},
            }},
        },
    }
end
local function refuses(mutate,needle)
    local data=export();mutate(data)
    local ok,err=pcall(Tiled.convert,data)
    assert(not ok,'accepted a map that should be refused ('..needle..')')
    assert(tostring(err):find(needle,1,true),'wrong refusal: '..tostring(err))
end
function M.register(test)
    test('unit','maps: a Tiled export converts to cells, flags, terrain and ordered objects',function()
        local m=Tiled.convert(export())
        eq(m.id,'fixture');eq(m.width,8);eq(m.height,8)
        -- Row-major from the top-left, with flip and rotation bits cleared.
        eq(m.terrain:sub(1,1),'k');eq(m.terrain:sub(2,2),'r');eq(m.terrain:sub(10,10),'f');eq(m.terrain:sub(64,64),'r');eq(#m.terrain,64)
        assert(m.blocked[1] and m.blocked[10] and not m.blocked[2],'blocked flags wrong')
        assert(m.unbuildable[2] and m.unbuildable[64] and not m.unbuildable[1],'unbuildable flags wrong')
        -- Objects in id order, whatever order the layer lists them in.
        eq(m.resources[1].amount,500,'gold not in id order');eq(m.resources[2].amount,900);eq(m.resources[1].size,3)
        -- The object class names the resource; substrate and charge are nodes like gold.
        eq(m.resources[3].resource,'substrate');eq(m.resources[3].size,1);eq(m.resources[3].amount,1500)
        eq(m.resources[4].resource,'charge');eq(m.resources[4].size,2);eq(m.resources[4].x,6);eq(m.resources[4].y,6)
        eq(m.starts[1].x,0);eq(m.starts[1].y,5);eq(m.starts[2].x,1);eq(m.starts[2].y,1)
        eq(m.camps[1].x,1);eq(m.camps[1].y,2);eq(m.camps[1].kind,'scout')
        eq(#m.controlPoints,1);eq(m.controlPoints[1].x,3);eq(m.controlPoints[1].y,3)
    end)
    test('unit','maps: the converter refuses what it cannot represent',function()
        refuses(function(d) d.layers[1].data[5]=99 end,'no terrain property')
        refuses(function(d) d.layers[1].data[5]=0 end,'empty ground cell')
        refuses(function(d) d.layers[2].objects[1].type='tower' end,'unknown class')
        refuses(function(d) d.tilesets[1].tiles=nil end,'external')
        refuses(function(d) d.tilesets[1].tiles[1].properties.terrain='lava' end,'unknown terrain')
        refuses(function(d) d.properties=nil end,'property named id')
        refuses(function(d) d.layers[3]={type='tilelayer',name='decals'} end,'unknown layer')
        refuses(function(d) table.remove(d.layers[2].objects,3) end,'no start for player 1')
    end)
    test('unit','maps: Twin Marches terrain agrees with the flags the simulation reads',function()
        local m=require('src.maps').create();local W,H=m.width,m.height
        eq(#m.terrain,W*H)
        local counts={}
        for k=1,W*H do
            local code=m.terrain:sub(k,k);counts[code]=(counts[code] or 0)+1
            eq(m.blocked[k]==true,code=='k' or code=='f','blocked flag at cell '..k)
            eq(m.unbuildable[k]==true,code=='r','unbuildable flag at cell '..k)
            eq(code,m.terrain:sub(W*H+1-k,W*H+1-k),'terrain is not symmetric at cell '..k)
        end
        assert((counts.f or 0)>0 and (counts.k or 0)>0 and (counts.r or 0)>0 and (counts.g or 0)>0,'a terrain type is missing')
    end)
end
return M
