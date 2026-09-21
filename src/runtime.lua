-- Host configuration only. Cache capacity affects execution cost, not rules.
local R={}
function R.configure()
    -- The pinned LÖVE/LuaJIT build supports these documented parameters.
    -- A fresh shipping battle exceeded 4,000 traces and repeatedly flushed the whole
    -- cache. Keep enough compiled routes for both simulation and presentation. These
    -- are capacity limits, not preallocated memory. Arithmetic options stay unchanged.
    require('jit.opt').start('maxtrace=16000','maxmcode=16384')
end
return R
