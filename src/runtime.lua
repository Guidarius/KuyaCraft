-- Host configuration only. Cache capacity affects execution cost, not rules.
local R={}
function R.configure()
    -- The pinned LÖVE/LuaJIT build supports these documented parameters.
    -- Keep arithmetic optimizations (including FMA being off) at their defaults.
    require('jit.opt').start('maxtrace=4000','maxmcode=4096')
end
return R
