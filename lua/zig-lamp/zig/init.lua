-- zig/init.lua
-- 迁移自 module/zig.lua，接口与原始保持一致

local job = require("plenary.job")
local M = {}

--- @return string|nil
function M.version()
    local _tmp = job:new({ command = "zig", args = { "version" } })
    local _result, _ = _tmp:sync()
    if _result and #_result > 0 then
        return _result[1]
    end
    return nil
end

function M.setup() end

return M
