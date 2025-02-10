-- this file is just to store module infos

local cmd = require("zig-lamp.cmd")
local config = require("zig-lamp.config")
local util = require("zig-lamp.util")
local zig = require("zig-lamp.module.zig")
local zls = require("zig-lamp.module.zls")

local M = {}

local function info_cb()
    local zig_version = zig.version()
    local sys_zls_version = zls.sys_version()

    local list = zls.local_zls_lists()

    -- TODO: this table should reflect
    local content = {
        { "Zig Lamp", "DiagnosticInfo" },
        "data path: " .. config.data_path,
        "version: " .. config.version,
        "",
        { "Zig info:", "DiagnosticOk" },
        "version: " .. (zig_version or "not found"),
        "",
        { "Zls info:", "DiagnosticOk" },
    }
    if sys_zls_version then
        table.insert(content, "system version: " .. sys_zls_version)
    end

    if zls.get_current_lsp_zls_version() then
        -- stylua: ignore
        table.insert(content, "embed lsp using version: " .. zls.get_current_lsp_zls_version())
    end
    if #list > 0 then
        table.insert(content, "local versions:")
    end
    for _, val in pairs(list) do
        table.insert(content, "  - " .. val)
    end

    util.display(content, "60%", "60%")
end

function M.setup()
    cmd.set_command(info_cb, nil, "info")
end

return {
    lamp = M,
    zig = require("zig-lamp.module.zig"),
    zls = require("zig-lamp.module.zls"),
}
