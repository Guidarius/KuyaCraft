-- Backwards-compatible static entry point; the actual proof is the interactive viewer.
local P={}
function P.draw(sprites)
    if not P.viewer or P.viewer.sprites~=sprites then P.viewer=require('src.asset_viewer').create(sprites) end
    P.viewer:draw()
end
return P
