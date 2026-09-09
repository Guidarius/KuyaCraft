-- Exact authoritative source fingerprint; presentation assets are deliberately excluded.
local Codec=require('src.sim.codec')
local Hash=require('src.hash')
local B={}
local cached
function B.fingerprint()
    if cached then return cached end
    local files={'src/content.lua','src/content_time.lua','src/maps.lua','src/net/lockstep.lua','src/net/session.lua','src/build.lua'}
    local function visit(directory)
        local names=love.filesystem.getDirectoryItems(directory)
        table.sort(names,Codec.byteLess)
        for _,name in ipairs(names) do
            local path=directory..'/'..name
            local info=assert(love.filesystem.getInfo(path))
            if info.type=='directory' then visit(path)
            elseif name:sub(-4)=='.lua' then files[#files+1]=path end
        end
    end
    visit('src/sim');visit('src/maps')
    table.sort(files,Codec.byteLess)
    local contents={}
    for _,path in ipairs(files) do contents[#contents+1]={path=path,bytes=assert(love.filesystem.read(path))} end
    cached=Hash.value(contents)
    return cached
end
return B
