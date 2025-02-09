local cmd = require("zig-lamp.cmd")
local job = require("plenary.job")

local M = {}

-- get zig version
--- @return string
function M.version()
    --- @diagnostic disable-next-line: missing-fields
    local _tmp = job:new({ command = "zig", args = { "version" } })
    _tmp:sync()
    return _tmp:result()[1]
end

function M.setup()
    cmd.set_command(function(param)
        -- TODO: not use print
        print(M.version())
    end, nil, "zig", "version")
end

return M
