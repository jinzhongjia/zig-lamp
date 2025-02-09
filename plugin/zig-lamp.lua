local cmd = require("zig-lamp.cmd")
local module = require("zig-lamp.module")

cmd.setup_command()

for _, _e in pairs(module) do
    if _e.setup then
        _e.setup()
    end
end
