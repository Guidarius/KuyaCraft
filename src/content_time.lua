-- Content authors use seconds/cells; the simulation receives exact integers only.
local T={}
function T.ticks(seconds)
    local n=seconds*20;assert(n==math.floor(n) and n>=0,'time must be a multiple of 0.05 seconds');return n
end
function T.cells(cells)
    local n=cells*256;assert(n==math.floor(n) and n>=0,'range must resolve to whole subunits');return n
end
return T
