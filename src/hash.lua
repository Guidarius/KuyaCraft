local M={}
function M.bytes(bytes) return love.data.encode('string','hex',love.data.hash('sha256',bytes)) end
function M.value(value) return M.bytes(require('src.sim.codec').encode(value)) end
return M
