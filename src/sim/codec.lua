-- Canonical, non-executable, length-prefixed encoding for bounded primitive state.
local Fixed = require('src.sim.fixed')
local M = {}
function M.byteLess(a,b)
    for i=1,math.min(#a,#b) do
        local ac,bc=a:byte(i),b:byte(i)
        if ac~=bc then return ac<bc end
    end
    return #a<#b
end
function M.keys(t)
    local keys = {}
    for key in pairs(t) do
        assert(type(key) == 'string' or Fixed.integer(key), 'unsupported state key')
        keys[#keys + 1] = key
    end
    table.sort(keys, function(a, b)
        if type(a) ~= type(b) then return type(a) == 'number' end
        if type(a) == 'number' then return a < b end
        -- Lua string ordering can be locale-sensitive. Compare byte values explicitly.
        for i = 1, math.min(#a, #b) do
            local ac, bc = a:byte(i), b:byte(i)
            if ac ~= bc then return ac < bc end
        end
        return #a < #b
    end)
    return keys
end
function M.encode(value)
    local out, active = {}, {}
    local function write(v, depth)
        assert(depth <= 64, 'state too deep')
        local kind = type(v)
        if kind == 'nil' then out[#out + 1] = 'z'
        elseif kind == 'boolean' then out[#out + 1] = v and 't' or 'f'
        elseif kind == 'number' then Fixed.check(v); out[#out + 1] = 'n' .. string.format('%.0f', v) .. ':'
        elseif kind == 'string' then out[#out + 1] = 's' .. #v .. ':' .. v
        elseif kind == 'table' then
            assert(not active[v], 'cyclic state')
            active[v] = true
            local keys = M.keys(v)
            out[#out + 1] = 'd' .. #keys .. ':'
            for i = 1, #keys do write(keys[i], depth + 1); write(v[keys[i]], depth + 1) end
            active[v] = nil
        else error('unsupported state value: ' .. kind) end
    end
    write(value, 0)
    return table.concat(out)
end
function M.decode(bytes)
    assert(type(bytes) == 'string' and #bytes <= 32 * 1024 * 1024, 'invalid or oversized payload')
    local pos, nodes = 1, 0
    local function numberToken()
        local stop = assert(bytes:find(':', pos, true), 'truncated numeric token')
        assert(stop - pos <= 17, 'oversized numeric token')
        local token = bytes:sub(pos, stop - 1)
        assert(token:match('^-?%d+$'), 'invalid numeric token')
        local n = tonumber(token)
        Fixed.check(n)
        assert(string.format('%.0f', n) == token, 'noncanonical number')
        pos = stop + 1
        return n
    end
    local read
    read = function(depth)
        nodes = nodes + 1
        assert(depth <= 64 and nodes <= 1000000, 'payload complexity exceeded')
        local tag = bytes:sub(pos, pos); pos = pos + 1
        if tag == 'z' then return nil
        elseif tag == 't' then return true
        elseif tag == 'f' then return false
        elseif tag == 'n' then return numberToken()
        elseif tag == 's' then
            local size = numberToken()
            assert(size >= 0 and pos + size - 1 <= #bytes, 'truncated string')
            local s = bytes:sub(pos, pos + size - 1); pos = pos + size
            return s
        elseif tag == 'd' then
            local count, result = numberToken(), {}
            assert(count >= 0 and count <= 500000, 'invalid table size')
            for _ = 1, count do
                local key, value = read(depth + 1), read(depth + 1)
                assert(type(key) == 'string' or Fixed.integer(key), 'invalid key')
                assert(value ~= nil and result[key] == nil, 'nil value or duplicate key')
                result[key] = value
            end
            return result
        end
        error('unknown codec tag')
    end
    local result = read(0)
    assert(pos == #bytes + 1, 'trailing bytes')
    return result
end
-- Preserve canonical insertion order and validation without formatting/parsing a
-- complete byte stream on every filtered view. Shared children copy independently,
-- exactly like an encode/decode round trip; cycles remain invalid.
function M.copy(value)
    local active={}
    local function clone(v,depth)
        assert(depth<=64,'state too deep')
        local kind=type(v)
        if kind=='number' then Fixed.check(v);return v end
        if kind=='nil' or kind=='boolean' or kind=='string' then return v end
        assert(kind=='table','unsupported state value: '..kind)
        assert(not active[v],'cyclic state');active[v]=true
        local out={}
        for _,key in ipairs(M.keys(v)) do out[clone(key,depth+1)]=clone(v[key],depth+1) end
        active[v]=nil;return out
    end
    return clone(value,0)
end
return M
