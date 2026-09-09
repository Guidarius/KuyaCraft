local Fixed = require('src.sim.fixed')
local M = { VERSION = 1, MODULUS = 2147483647 }
function M.create(seed)
    Fixed.check(seed, 1, M.MODULUS - 1)
    return { state = seed, version = M.VERSION }
end
function M.next(rng)
    assert(rng.version == M.VERSION, 'unsupported PRNG version')
    rng.state = (rng.state * 16807) % M.MODULUS
    return rng.state
end
function M.range(rng, lo, hi)
    Fixed.check(lo); Fixed.check(hi)
    local span = hi - lo + 1
    Fixed.check(span, 1, M.MODULUS - 1)
    local limit = (M.MODULUS - 1) - ((M.MODULUS - 1) % span)
    local value
    repeat value = M.next(rng) - 1 until value < limit
    return lo + value % span
end
return M
