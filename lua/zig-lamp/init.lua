local command = require("zig-lamp.command")
local module = require("zig-lamp.module")

local M = {}

M.setup = function()
    command.setup_command()

    for _, _e in pairs(module) do
        if _e.setup then
            _e.setup()
        end
    end
end

return M
