local M = {}
function M.parse(args)
    local out = {}
    local i = 1
    while i <= #args do
        local key = args[i]
        if key:sub(1, 2) == '--' then
            local value = args[i + 1]
            if value and value:sub(1, 2) ~= '--' then out[key:sub(3)] = value; i = i + 1
            else out[key:sub(3)] = true end
        end
        i = i + 1
    end
    return out
end
return M
