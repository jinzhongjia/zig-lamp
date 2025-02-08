-- this file is just to store module infos

local cmd = require("zig-lamp.cmd")
local config = require("zig-lamp.config")
local util = require("zig-lamp.util")
local zig = require("zig-lamp.module.zig")
local zls = require("zig-lamp.module.zls")

local M = {}

local function info_cb()
    local zig_version = zig.version()
    local zls_version = zls.version()

    local content = {
        { "Zig Lamp", "DiagnosticInfo" },
        "data path: " .. config.data_path,
        "version: " .. config.version,
        "",
        { "Zig info:", "DiagnosticOk" },
        "version: " .. zig_version,
        "",
        { "Zls info:", "DiagnosticOk" },
        "version: " .. zls_version,
    }

    util.display(content, "60%", "60%")
end

function M.setup()
    cmd.set_command(info_cb, "info")
end

return {
    lamp = M,
    zig = require("zig-lamp.module.zig"),
    zls = require("zig-lamp.module.zls"),
}
