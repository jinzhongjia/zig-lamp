-- this file is just to store module infos

local cmd = require("zig-lamp.cmd")
local config = require("zig-lamp.config")
local job = require("plenary.job")
local util = require("zig-lamp.util")
local zig = require("zig-lamp.module.zig")
local zls = require("zig-lamp.module.zls")

local M = {}

local function cb_info()
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

local function cb_build()
    local zig_ffi = require("zig-lamp.ffi")
    local is_loaded = zig_ffi.is_loaded()
    if is_loaded then
        -- stylua: ignore
        util.Warn("sorry, lamp lib has been loaded, could not update it! please restart neovim and run command again!")
        return
    end
    local plugin_path = zig_ffi.get_plugin_path()
    --- @param code integer
    local _callback = function(_, code, signal)
        vim.schedule(function()
            if code ~= 0 then
                util.Error("build lamp lib failed, code is " .. code)
                return
            end
            util.Info("build lamp lib success!")
            zig_ffi.lazy_load()
        end)
    end

    ---@diagnostic disable-next-line: missing-fields
    local _j = job:new({
        cwd = plugin_path,
        command = "zig",
        args = { "build", "-Doptimize=ReleaseFast" },
        on_exit = _callback,
    })
    _j:start()
end

function M.setup()
    cmd.set_command(cb_info, nil, "info")
    cmd.set_command(cb_build, nil, "build")
end

return {
    lamp = M,
    zig = require("zig-lamp.module.zig"),
    zls = require("zig-lamp.module.zls"),
}
