-- info.lua
-- 迁移自 module/init.lua，提供 info 面板和 build 命令

local cmd = require("zig-lamp.core.core_cmd")
local config = require("zig-lamp.core.core_config")
local job = require("plenary.job")
local util = require("zig-lamp.core.core_util")
local zig = require("zig-lamp.zig")
local zls = require("zig-lamp.zls")

local M = {}

local function setup_syntax_highlighting()
    vim.api.nvim_create_autocmd("FileType", {
        pattern = "ZigLamp_info",
        callback = function()
            local buf = vim.api.nvim_get_current_buf()
            vim.cmd([[syntax match ZigLampTitle "^Zig Lamp$"]])
            vim.cmd([[syntax match ZigLampSection "^Zig info:$\|^ZLS info:$"]])
            vim.cmd([[syntax match ZigLampKey "^\s\+version:\|^\s\+data path:\|^\s\+system version:\|^\s\+lsp using version:\|^\s\+local versions:$"]])
            vim.cmd([[syntax match ZigLampValue ":\s*\zs.*$"]])
            vim.cmd([[syntax match ZigLampListItem "^\s\+- .*$"]])
            vim.cmd([[highlight default link ZigLampTitle Title]])
            vim.cmd([[highlight default link ZigLampSection Statement]])
            vim.cmd([[highlight default link ZigLampKey Identifier]])
            vim.cmd([[highlight default link ZigLampValue String]])
            vim.cmd([[highlight default link ZigLampListItem Special]])
        end,
    })
end

local function create_info_content()
    local zig_version = zig.version()
    local sys_zls_version = zls.sys_version()
    local list = zls.local_zls_lists()
    local current_lsp_zls = zls.get_current_lsp_zls_version()
    local content = {
        "Zig Lamp",
        "  version: " .. config.version,
        "  data path: " .. config.data_path,
        "",
        "Zig info:",
        "  version: " .. (zig_version or "not found"),
        "",
    }
    if sys_zls_version or current_lsp_zls or #list > 0 then
        table.insert(content, "ZLS info:")
        if sys_zls_version then
            table.insert(content, "  system version: " .. sys_zls_version)
        end
        if current_lsp_zls then
            table.insert(content, "  lsp using version: " .. current_lsp_zls)
        elseif zls.if_using_sys_zls() and sys_zls_version then
            table.insert(content, "  lsp using version: sys " .. sys_zls_version)
        end
        if #list > 0 then
            table.insert(content, "  local versions:")
            for _, val in pairs(list) do
                table.insert(content, "  - " .. val)
            end
        end
    end
    return content
end

local function cb_info()
    local new_buf = vim.api.nvim_create_buf(false, true)
    local content = create_info_content()
    vim.api.nvim_buf_set_lines(new_buf, 0, -1, true, content)
    vim.api.nvim_buf_set_option(new_buf, "filetype", "ZigLamp_info")
    vim.api.nvim_buf_set_option(new_buf, "bufhidden", "delete")
    vim.api.nvim_buf_set_option(new_buf, "modifiable", false)
    local win = vim.api.nvim_open_win(new_buf, true, {
        split = "right",
        style = "minimal",
        width = 50,
    })
    vim.keymap.set("n", "q", function()
        vim.api.nvim_win_close(win, true)
    end, {
        buffer = new_buf,
        desc = "quit for ZigLamp info panel",
    })
end

local function build_job(args, callback_success, callback_failure)
    return job:new({
        cwd = require("zig-lamp.core.core_ffi").get_plugin_path(),
        command = "zig",
        args = args,
        on_exit = function(j, code, signal)
            if code == 0 then
                callback_success()
            else
                callback_failure(code, signal)
            end
        end,
    })
end

local function cb_build(params)
    local zig_ffi = require("zig-lamp.core.core_ffi")
    if zig_ffi.is_loaded() then
        util.Warn("sorry, lamp lib has been loaded, could not update it! please restart neovim and run command again!")
        return
    end
    local build_args = { "build", "-Doptimize=ReleaseFast" }
    local mode = params[1] or "async"
    if mode == "async" then
        local _j = build_job(
            build_args,
            vim.schedule_wrap(function()
                util.Info("build lamp lib success!")
                zig_ffi.lazy_load()
            end),
            vim.schedule_wrap(function(code, signal)
                util.Error(string.format("build lamp lib failed, code is %d, signal is %d", code, signal))
            end)
        )
        _j:start()
    elseif mode == "sync" then
        local _j = build_job(
            build_args,
            vim.schedule_wrap(function()
                util.Info("build lamp lib success!")
            end),
            vim.schedule_wrap(function(code, _)
                util.Error("build lamp lib failed, code is " .. code)
            end)
        )
        local wait_time = params[2] and tonumber(params[2]) and math.floor(tonumber(params[2])) or 15000
        _j:sync(wait_time)
    else
        util.Warn("error param: " .. mode)
    end
end

function M.setup()
    setup_syntax_highlighting()
    cmd.set_command(cb_info, nil, "info")
    cmd.set_command(cb_build, { "async", "sync" }, "build")
end

return M
