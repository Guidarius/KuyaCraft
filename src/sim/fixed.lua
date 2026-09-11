local M = { SCALE = 256, MAX_EXACT = 9007199254740991 }
function M.integer(n, min, max)
    return type(n) == 'number' and n == math.floor(n) and n >= (min or -M.MAX_EXACT) and n <= (max or M.MAX_EXACT)
end
function M.check(n, min, max)
    assert(M.integer(n, min, max), 'integer outside supported bounds')
    return n
end
function M.mulDiv(a, b, divisor)
    M.check(a); M.check(b); M.check(divisor, 1)
    assert(a == 0 or math.abs(b) <= math.floor(M.MAX_EXACT / math.abs(a)), 'integer product overflow')
    return math.floor(a * b / divisor)
end
-- Squaring via x*x rather than x^2 keeps the whole simulation inside integer
-- multiplication. pow() is exact here on every IEEE-754 platform we target, but
-- it is a libm call whose rounding is not architecturally pinned, and it is
-- slower. Taking an argument (rather than repeating the expression) keeps
-- function calls in the operand from being evaluated twice.
function M.sq(n) return n*n end
function M.cell(value) return math.floor(value / M.SCALE) end
function M.center(cell) return cell * M.SCALE + M.SCALE / 2 end
function M.isqrt(n)
    M.check(n,0,M.MAX_EXACT)
    local hi=n<=65536 and 256 or n<=1048576 and 1024 or n<=16777216 and 4096 or 94906265
    local lo=0;hi=math.min(n,hi)
    while lo<hi do local mid=math.floor((lo+hi+1)/2);if mid*mid<=n then lo=mid else hi=mid-1 end end
    return lo
end
function M.vector(dx,dy,speed)
    local square=dx*dx+dy*dy
    if square<=speed*speed then return dx,dy end
    local length=M.isqrt(square);if length*length<square then length=length+1 end
    local x=math.floor(math.abs(dx)*speed/length);local y=math.floor(math.abs(dy)*speed/length)
    return dx<0 and -x or x,dy<0 and -y or y
end
-- Internal hot path for positions already constrained to the <=256-cell map.
-- |delta| <= 65536, so the sum of squares is exact in binary64.
function M.distance2Bounded(ax,ay,bx,by)
    local dx,dy=ax-bx,ay-by;return dx*dx+dy*dy
end
function M.distance2(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    M.check(dx, -1048576, 1048576); M.check(dy, -1048576, 1048576)
    return dx * dx + dy * dy
end
function M.approach(x, y, tx, ty, speed)
    local dx, dy = tx - x, ty - y
    local largest = math.max(math.abs(dx), math.abs(dy))
    if largest <= speed then return tx, ty end
    local step = speed
    if dx ~= 0 and dy ~= 0 then step = M.mulDiv(speed, 181, 256) end
    local function delta(d)
        local magnitude = math.floor(math.abs(d) * step / largest)
        return d < 0 and -magnitude or magnitude
    end
    return x + delta(dx), y + delta(dy)
end
return M
