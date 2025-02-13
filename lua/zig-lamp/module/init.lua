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
    local current_lsp_zls = zls.get_current_lsp_zls_version()

    local content = {
        { { "Zig Lamp", "DiagnosticInfo" } },
        "  version: " .. config.version,
        "  data path: " .. config.data_path,
        "",
        { { "Zig info:", "DiagnosticOk" } },
        "  version: " .. (zig_version or "not found"),
        "",
    }
    if sys_zls_version or current_lsp_zls or #list > 0 then
        table.insert(content, { { "ZLS info:", "DiagnosticOk" } })
    end
    if sys_zls_version then
        table.insert(content, "  system version: " .. sys_zls_version)
    end

    if current_lsp_zls then
        -- stylua: ignore
        table.insert(content, "  lsp using version: " .. zls.get_current_lsp_zls_version())
    end
    -- stylua: ignore
    if #list > 0 then table.insert(content, "  local versions:") end

    -- stylua: ignore
    for _, val in pairs(list) do table.insert(content, "  - " .. val) end

    util.display(content, "60%", "60%")
end

--- @param params string[]
local function cb_build(params)
    local zig_ffi = require("zig-lamp.ffi")
    local is_loaded = zig_ffi.is_loaded()
    if is_loaded then
        -- stylua: ignore
        util.Warn("sorry, lamp lib has been loaded, could not update it! please restart neovim and run command again!")
        return
    end
    local plugin_path = zig_ffi.get_plugin_path()
    if #params == 0 or params[1] == "async" then
        -- async build

        ---@diagnostic disable-next-line: missing-fields
        local _j = job:new({
            cwd = plugin_path,
            command = "zig",
            args = { "build", "-Doptimize=ReleaseFast" },
            -- on_exit = _callback,
        })
        _j:after_success(vim.schedule_wrap(function()
            util.Info("build lamp lib success!")
            zig_ffi.lazy_load()
        end))
        _j:after_failure(vim.schedule_wrap(function(_, code, signal)
            -- stylua: ignore
            util.Error(string.format("build lamp lib failed, code is %d, signal is %d", code, signal))
        end))
        _j:start()
    elseif params[1] == "sync" then
        -- sync build
        ---@diagnostic disable-next-line: missing-fields
        local _j = job:new({
            cwd = plugin_path,
            command = "zig",
            args = { "build", "-Doptimize=ReleaseFast" },
        })
        _j:after_success(vim.schedule_wrap(function()
            util.Info("build lamp lib success!")
        end))
        _j:after_failure(vim.schedule_wrap(function(_, code, _)
            util.Error("build lamp lib failed, code is " .. code)
        end))

        -- default wait 1500 ms
        local wait_time = 15000
        if params[2] then
            local num = tonumber(params[2])
            if num then
                wait_time = math.floor(num)
            end
        end
        -- wait 1500 ms
        _j:sync(wait_time)
    else
        util.Warn("error param: " .. params[1])
    end
end

function M.setup()
    cmd.set_command(cb_info, nil, "info")
    cmd.set_command(cb_build, { "async", "sync" }, "build")
end

return {
    lamp = M,
    zig = zig,
    zls = zls,
    pkg = require("zig-lamp.module.pkg"),
}
