local command = require("zig-lamp.command")
local job = require("plenary.job")

local M = {}

-- get zig version
--- @return string
function M.version()
    --- @diagnostic disable-next-line: missing-fields
    local _tmp = job:new({
        command = "zig",
        args = { "version" },
    })

    _tmp:sync()

    local _result = _tmp:result()
    return _result[1]
end

function M.setup()
    command.set_command(function(param)
        -- TODO: not use print
        print(M.version())
    end, "zig", "version")
end

return M
