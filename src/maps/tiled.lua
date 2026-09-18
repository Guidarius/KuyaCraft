-- Converts a map exported by Tiled's Lua format into the table Sim.create reads, plus a
-- `terrain` string for presentation. Pure Lua with no engine calls: it runs inside the
-- fingerprinted simulation sources, so every peer derives the same map from the same export.
--
-- The map is authored in maps/<id>.tmx and exported with scripts/map.ps1. Layers:
--   ground    tile layer, one tile per cell, each tile carrying a `terrain` property
--   gameplay  object layer: start, gold, camp, unit_start, anchor and control objects
-- The simulation still reads only `blocked` and `unbuildable`; both are derived from terrain
-- here, so nothing downstream changes when a map moves to Tiled.
local M={}
-- Object classes that place a resource node; the class name is the resource.
M.RESOURCES={gold=true,substrate=true,charge=true}
-- Terrain types. `code` is the character used for the type in map.terrain.
M.TERRAIN={
    grass={code='g'},
    road={code='r',unbuildable=true},
    rock={code='k',blocked=true},
    forest={code='f',blocked=true},
}
-- Tiled stores flips and rotations in the top four bits of a tile id.
local FLAG_BITS=0x10000000
local function fail(id,message) error('map '..tostring(id)..': '..message,0) end
local function integer(id,value,what,min,max)
    if type(value)~='number' or value~=math.floor(value) or value<min or value>max then fail(id,what..' must be an integer from '..min..' to '..max..', got '..tostring(value)) end
    return value
end
function M.convert(data)
    local id=data.properties and data.properties.id
    if type(id)~='string' or id=='' then fail(nil,'the map needs a string property named id') end
    if data.orientation~='orthogonal' then fail(id,'only orthogonal maps are supported') end
    if data.tilewidth~=data.tileheight then fail(id,'tiles must be square') end
    local width=integer(id,data.width,'width',8,256);local height=integer(id,data.height,'height',8,256)
    local cell=data.tilewidth
    local types={}
    for _,tileset in ipairs(data.tilesets or {}) do
        if not tileset.tiles then fail(id,'tileset '..tostring(tileset.name or tileset.filename)..' is external or has no tile properties; embed it in the map') end
        for _,tile in ipairs(tileset.tiles) do
            local name=tile.properties and tile.properties.terrain
            if name~=nil then
                if not M.TERRAIN[name] then fail(id,'tile '..tile.id..' of '..tostring(tileset.name)..' has unknown terrain '..tostring(name)) end
                types[tileset.firstgid+tile.id]=name
            end
        end
    end
    local ground,gameplay
    for _,layer in ipairs(data.layers or {}) do
        if layer.name=='ground' then ground=layer
        elseif layer.name=='gameplay' then gameplay=layer
        elseif layer.name~='doodads' then fail(id,'unknown layer '..tostring(layer.name)) end
    end
    if not ground or ground.type~='tilelayer' then fail(id,'no tile layer named ground') end
    if ground.encoding~='lua' then fail(id,'ground must be exported with lua encoding') end
    if ground.width~=width or ground.height~=height or #ground.data~=width*height then fail(id,'ground layer does not cover the map') end
    if not gameplay or gameplay.type~='objectgroup' then fail(id,'no object layer named gameplay') end

    local m={id=id,width=width,height=height,blocked={},unbuildable={},resources={},camps={},starts={},unitStarts={},
        anchors={naturals={},forward={},contested={}},controlPoints={}}
    -- Row-major from the top-left, which is exactly the simulation's cell key y*width+x+1.
    local codes={}
    for i=1,width*height do
        local gid=ground.data[i]%FLAG_BITS
        if gid==0 then fail(id,'empty ground cell at '..(i-1)%width..','..math.floor((i-1)/width)) end
        local name=types[gid]
        if not name then fail(id,'ground cell at '..(i-1)%width..','..math.floor((i-1)/width)..' uses tile '..gid..', which has no terrain property') end
        local terrain=M.TERRAIN[name]
        codes[i]=terrain.code
        if terrain.blocked then m.blocked[i]=true end
        if terrain.unbuildable then m.unbuildable[i]=true end
    end
    m.terrain=table.concat(codes)

    -- Objects in id order: Tiled keeps ids stable and hands new objects higher ones, so lists
    -- keep their order when the map is edited, and entity ids in the simulation with them.
    local objects={}
    for i,o in ipairs(gameplay.objects or {}) do objects[i]=o end
    table.sort(objects,function(a,b) return a.id<b.id end)
    local function property(o,name,kind)
        local value=o.properties and o.properties[name]
        if kind=='int' then return integer(id,value,(o.type or '?')..' '..o.id..' property '..name,0,1000000) end
        if type(value)~='string' or value=='' then fail(id,(o.type or '?')..' '..o.id..' needs a string property '..name) end
        return value
    end
    local function place(o)
        local x,y=math.floor(o.x/cell),math.floor(o.y/cell)
        integer(id,x,o.type..' '..o.id..' x',0,width-1);integer(id,y,o.type..' '..o.id..' y',0,height-1)
        return x,y
    end
    for _,o in ipairs(objects) do
        local class=o.type
        if class=='start' then
            local x,y=place(o);local player=property(o,'player','int')
            if m.starts[player] then fail(id,'two starts for player '..player) end
            m.starts[player]={x=x,y=y}
        elseif M.RESOURCES[class] then
            local x,y=place(o)
            m.resources[#m.resources+1]={x=x,y=y,resource=class,amount=property(o,'amount','int'),size=integer(id,o.width/cell,class..' '..o.id..' size',1,8)}
        elseif class=='camp' then
            local x,y=place(o)
            m.camps[#m.camps+1]={x=x,y=y,kind=property(o,'kind'),tier=property(o,'tier')}
        elseif class=='unit_start' then
            local x,y=place(o);local player,slot=property(o,'player','int'),property(o,'slot','int')
            m.unitStarts[player]=m.unitStarts[player] or {}
            m.unitStarts[player][slot]={x=x,y=y}
        elseif class=='anchor' then
            local x,y=place(o);local kind=property(o,'kind')
            if not m.anchors[kind] then fail(id,'anchor '..o.id..' has unknown kind '..kind) end
            m.anchors[kind][property(o,'player','int')]={x=x,y=y}
        elseif class=='control' then
            local x,y=place(o)
            m.controlPoints[#m.controlPoints+1]={x=x,y=y}
        else
            fail(id,'object '..o.id..' has unknown class '..tostring(class))
        end
    end
    for p=1,#m.starts do if not m.starts[p] then fail(id,'no start for player '..p) end end
    if #m.starts<2 then fail(id,'a map needs at least two starts') end
    for p,list in pairs(m.unitStarts) do for slot=1,#list do if not list[slot] then fail(id,'player '..p..' unit start '..slot..' is missing') end end end
    if #m.controlPoints==0 then m.controlPoints=nil end
    return m
end
return M
