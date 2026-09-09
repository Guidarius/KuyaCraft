-- Prefer the portable build's artifacts directory; use the LÖVE save directory
-- when the working folder is read-only. Tests and installed builds share this path.
local S={}
function S.read(name)
 local file=io.open('artifacts/'..name,'rb')
 if file then local bytes=file:read('*a');file:close();return bytes end
 return love.filesystem.read(name)
end
function S.write(name,bytes)
 local file=io.open('artifacts/'..name,'wb')
 if file then file:write(bytes);file:close();return true end
 return love.filesystem.write(name,bytes)
end
return S
