local command = require("zig-lamp.command")

local M = {}

M.setup = function()

command.create_command()
end

return M
