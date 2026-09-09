local Codec=require('src.sim.codec')
local D={}
function D.diff(left,right)
    local changes={}
    local function walk(a,b,path,depth)
        if #changes>=100 then return end
        if type(a)~=type(b) or type(a)~='table' then
            if a~=b then changes[#changes+1]={path=path,left=a,right=b} end
            return
        end
        assert(depth<=64,'state too deep')
        local keys={}
        for _,key in ipairs(Codec.keys(a)) do keys[key]=true end
        for _,key in ipairs(Codec.keys(b)) do keys[key]=true end
        for _,key in ipairs(Codec.keys(keys)) do walk(a[key],b[key],path..'/'..tostring(key),depth+1) end
    end
    walk(left,right,'',0)
    return changes
end
function D.compareFiles(leftPath,rightPath,outputPath)
    local function read(path)
        local file=assert(io.open(path,'rb'));local data=file:read(32*1024*1024+1);file:close();return Codec.decode(data)
    end
    local left,right=read(leftPath),read(rightPath)
    assert(left.tick==right.tick,'compare snapshots from the same tick')
    local differences=D.diff(left,right)
    local file=assert(io.open(outputPath,'wb'))
    file:write('Compared checkpoint tick '..left.tick..'\n')
    for _,change in ipairs(differences) do file:write(change.path..' left='..Codec.encode(change.left)..' right='..Codec.encode(change.right)..'\n') end
    file:write(#differences..' differences (maximum 100)\n');file:close()
    print('State comparison: '..outputPath)
    return 0
end
return D
