-- Presentation-only metadata reader. No require cache: a reload sees the active catalog.
local C={directions={'N','NE','E','SE','S','SW','W','NW'}}
local function integer(v,min) return type(v)=='number' and v==math.floor(v) and v>=(min or 0) and v<100000000 end
function C.safePath(path)
    if type(path)~='string' or not path:match('^assets/generated/') or path:find('\\',1,true) or path:find(':',1,true) then return false end
    for part in path:gmatch('[^/]+') do if part=='.' or part=='..' then return false end end
    return not path:find('//',1,true)
end
function C.validate(m,expected)
    assert(type(m)=='table' and m.version==2,'unsupported asset version')
    assert(type(m.unitId)=='string' and m.unitId==expected,'unit identity mismatch')
    assert(type(m.buildId)=='string' and #m.buildId>0,'missing build identity')
    assert(m.profileId=='bastion_overhead_v1' or m.profileId=='legacy_v1' or m.profileId=='woodland_pixel_v1' or m.profileId=='building_overhead_v1' or m.profileId=='prop_overhead_v1','unsupported render profile')
    if m.profileId=='building_overhead_v1' then
        assert(m.fixedFacing=='S' and integer(m.footprintCells,1) and m.footprintCells<=4,'invalid building footprint/facing')
    end
    if m.profileId=='prop_overhead_v1' then assert(m.fixedFacing=='S','invalid prop facing') end
    if m.profileId=='woodland_pixel_v1' then
        local s=m.pixelStyle
        assert(type(s)=='table' and type(s.palette)=='table' and #s.palette<=32 and integer(s.teamStart,1) and s.teamStart+5==#s.palette,'invalid pixel palette')
        local function color(c) return type(c)=='string' and c:match('^#%x%x%x%x%x%x$') end
        for _,c in ipairs(s.palette) do assert(color(c),'invalid palette color') end
        assert(type(s.teamRamps)=='table' and #s.teamRamps>0,'missing team ramps')
        for _,r in ipairs(s.teamRamps) do
            assert(type(r)=='table' and #r==5,'invalid team ramp')
            for _,c in ipairs(r) do assert(color(c),'invalid team shade') end
        end
        assert(type(m.sourceRevision)=='string' and #m.sourceRevision>0,'missing source revision')
    end
    assert(type(m.directions)=='table' and #m.directions==8,'eight directions required')
    for i,d in ipairs(C.directions) do assert(m.directions[i]==d,'direction order mismatch') end
    assert(type(m.pages)=='table' and #m.pages>0,'missing atlas pages')
    for _,p in ipairs(m.pages) do
        assert(C.safePath(p.color) and C.safePath(p.mask),'unsafe page path')
        assert(integer(p.width,1) and integer(p.height,1) and p.width<=2048 and p.height<=2048,'invalid page dimensions')
    end
    assert(type(m.frames)=='table' and #m.frames>0,'missing frames')
    for _,f in ipairs(m.frames) do
        assert(integer(f.page,1) and m.pages[f.page],'invalid frame page')
        local p=m.pages[f.page]
        assert(integer(f.x) and integer(f.y) and integer(f.width,1) and integer(f.height,1),'invalid frame rectangle')
        assert(f.x+f.width<=p.width and f.y+f.height<=p.height,'frame outside page')
        assert(integer(f.anchorX) and integer(f.anchorY) and f.anchorX<=f.width and f.anchorY<=f.height,'invalid anchor')
    end
    assert(type(m.clips)=='table','missing clips')
    for _,name in ipairs(m.profileId=='prop_overhead_v1' and {'idle','deploy'} or m.profileId=='building_overhead_v1' and {'idle'} or m.profileId=='woodland_pixel_v1' and {'idle','move','work'} or {'idle','move','attack','death'}) do assert(m.clips[name],'missing clip '..name) end
    if expected=='worker' or expected=='worker_loaded' then assert(m.clips.work,'missing worker work clip') end
    for name,c in pairs(m.clips) do
        assert(type(name)=='string' and type(c)=='table' and integer(c.durationMs,1) and type(c.loop)=='boolean','invalid clip')
        assert(type(c.frames)=='table','missing directional frames')
        local count
        for _,d in ipairs(C.directions) do
            local ids=c.frames[d];assert(type(ids)=='table' and #ids>0,'missing direction '..d)
            count=count or #ids;assert(#ids==count,'direction sample counts differ')
            for _,id in ipairs(ids) do assert(integer(id,1) and m.frames[id],'invalid frame reference') end
            if m.profileId=='building_overhead_v1' or m.profileId=='prop_overhead_v1' then
                for i,id in ipairs(ids) do assert(id==c.frames.S[i],'building directions must alias the fixed view') end
            end
        end
        if c.contactFrame then assert(integer(c.contactFrame,1) and c.contactFrame<=count,'invalid contact sample') end
    end
    assert(type(m.bodyHeightPixels)=='number' and m.bodyHeightPixels>0,'invalid body height')
    if m.referenceStride then assert(type(m.referenceStride.distance)=='number' and m.referenceStride.distance>0 and m.referenceStride.units=='navigationCells','invalid stride') end
    return m
end
function C.adaptV1(old)
    assert(old.version==1 and old.frameSize==128 and old.framesPerClip==4 and old.directions==8,'unsupported legacy proof')
    local m={version=2,unitId='shieldguard',buildId='legacy-proof',profileId='legacy_v1',directions=C.directions,
        bodyHeightPixels=64,drawScale=0.65,pages={{color='assets/generated/shieldguard.png',mask='assets/generated/shieldguard-mask.png',width=1024,height=2048}},frames={},clips={}}
    for i=0,127 do m.frames[i+1]={page=1,x=i%8*128,y=math.floor(i/8)*128,width=128,height=128,anchorX=old.anchorX,anchorY=old.anchorY} end
    for ci,name in ipairs({'idle','move','attack','death'}) do
        local c={durationMs=500,loop=ci<3,frames={},contactFrame=name=='attack' and 1 or nil};m.clips[name]=c
        for di,d in ipairs(C.directions) do c.frames[d]={};for n=1,4 do c.frames[d][n]=(ci-1)*32+(di-1)*4+n end end
    end
    return C.validate(m,'shieldguard')
end
local function defaultRead(path)
    local chunk,err=love.filesystem.load(path);assert(chunk,err)
    if setfenv then setfenv(chunk,{}) end
    return chunk()
end
function C.load(read,exists,catalogPath)
    catalogPath=catalogPath or 'assets/generated/catalog.lua'
    assert(C.safePath(catalogPath),'unsafe catalog path')
    read=read or defaultRead;exists=exists or function(p) return love.filesystem.getInfo(p)~=nil end
    local result={units={},diagnostics={},version=2}
    local function report(id,err) result.diagnostics[#result.diagnostics+1]=id..': '..tostring(err) end
    if not exists(catalogPath) then
        if catalogPath=='assets/generated/catalog.lua' and exists('assets/generated/shieldguard.lua') then
            local ok,m=pcall(function() return C.adaptV1(read('assets/generated/shieldguard.lua')) end)
            if ok then result.units.shieldguard=m;result.legacy=true else report('shieldguard',m) end
        end
        return result
    end
    local ok,catalog=pcall(read,catalogPath)
    if not ok or type(catalog)~='table' or catalog.version~=2 or type(catalog.units)~='table' then report('catalog',ok and 'invalid version/units' or catalog);return result end
    local ids={};for id in pairs(catalog.units) do if type(id)=='string' then ids[#ids+1]=id else report('catalog','invalid unit key') end end;table.sort(ids)
    for _,id in ipairs(ids) do
        local success,m=pcall(function() local path=catalog.units[id];assert(C.safePath(path),'unsafe metadata path');return C.validate(read(path),id) end)
        if success then result.units[id]=m else report(id,m) end
    end
    return result
end
return C
