local job = require("plenary.job")

local M = {}

-- get zig version
--- @return string|nil
function M.version()
    --- @diagnostic disable-next-line: missing-fields
    local _tmp = job:new({ command = "zig", args = { "version" } })
    local _result, _ = _tmp:sync()

    if _result and #_result > 0 then
        return _result[1]
    end
    return nil
end

function M.setup() end

return M
