-- info.lua
-- Migrated from module/init.lua, provides info panel and build command functionality

local cmd = require("zig-lamp.core.core_cmd")
local config = require("zig-lamp.core.core_config")
local job = require("plenary.job")
local util = require("zig-lamp.core.core_util")
local zig = require("zig-lamp.zig")
local zls = require("zig-lamp.zls")

local M = {}

-- Setup syntax highlighting for ZigLamp info window
local function setup_syntax_highlighting()
    vim.api.nvim_create_autocmd("FileType", {
        pattern = "ZigLamp_info",
        callback = function()
            -- Define syntax patterns
            local syntax_patterns = {
                { "ZigLampTitle", [["^Zig Lamp$"]] },
                { "ZigLampSection", [["^Zig info:$\|^ZLS info:$"]] },
                {
                    "ZigLampKey",
                    [["^\s\+version:\|^\s\+data path:\|^\s\+system version:\|^\s\+lsp using version:\|^\s\+local versions:$"]],
                },
                { "ZigLampValue", [[":\s*\zs.*$"]] },
                { "ZigLampListItem", [["^\s\+- .*$"]] },
            }

            -- Apply syntax patterns
            for _, pattern in ipairs(syntax_patterns) do
                vim.cmd(
                    string.format(
                        [[syntax match %s %s]],
                        pattern[1],
                        pattern[2]
                    )
                )
            end

            -- Define highlight links
            local highlights = {
                { "ZigLampTitle", "Title" },
                { "ZigLampSection", "Statement" },
                { "ZigLampKey", "Identifier" },
                { "ZigLampValue", "String" },
                { "ZigLampListItem", "Special" },
            }

            for _, hl in ipairs(highlights) do
                vim.cmd(
                    string.format(
                        [[highlight default link %s %s]],
                        hl[1],
                        hl[2]
                    )
                )
            end
        end,
    })
end

-- Create content for the info panel
local function create_info_content()
    local zig_version = zig.version()
    local sys_zls_version = zls.sys_version()
    local local_zls_list = zls.local_zls_lists()
    local current_lsp_zls = zls.get_current_lsp_zls_version()

    -- Build basic info content
    local content = {
        "Zig Lamp",
        "  version: " .. config.version,
        "  data path: " .. config.data_path,
        "",
        "Zig info:",
        "  version: " .. (zig_version or "not found"),
        "",
    }

    -- Add ZLS info if available
    if sys_zls_version or current_lsp_zls or #local_zls_list > 0 then
        table.insert(content, "ZLS info:")

        -- System ZLS version
        if sys_zls_version then
            table.insert(content, "  system version: " .. sys_zls_version)
        end

        -- Currently used ZLS version
        if current_lsp_zls then
            table.insert(content, "  lsp using version: " .. current_lsp_zls)
        elseif zls.if_using_sys_zls() and sys_zls_version then
            table.insert(
                content,
                "  lsp using version: sys " .. sys_zls_version
            )
        end

        -- Local ZLS versions
        if #local_zls_list > 0 then
            table.insert(content, "  local versions:")
            for _, version in ipairs(local_zls_list) do
                table.insert(content, "  - " .. version)
            end
        end
    end

    return content
end

-- Show info panel in a new window
local function show_info_panel()
    -- Create new buffer with info content
    local buf = vim.api.nvim_create_buf(false, true)
    local content = create_info_content()

    vim.api.nvim_buf_set_lines(buf, 0, -1, true, content)
    vim.api.nvim_buf_set_option(buf, "filetype", "ZigLamp_info")
    vim.api.nvim_buf_set_option(buf, "bufhidden", "delete")
    vim.api.nvim_buf_set_option(buf, "modifiable", false)

    -- Open window
    local win = vim.api.nvim_open_win(buf, true, {
        split = "right",
        style = "minimal",
        width = 50,
    })

    -- Set up quit keybinding
    vim.keymap.set("n", "q", function()
        vim.api.nvim_win_close(win, true)
    end, {
        buffer = buf,
        desc = "Close ZigLamp info panel",
    })
end

-- Create a build job with callbacks
local function create_build_job(args, on_success, on_failure)
    return job:new({
        cwd = require("zig-lamp.core.core_ffi").get_plugin_path(),
        command = "zig",
        args = args,
        on_exit = function(j, code, signal)
            if code == 0 then
                on_success()
            else
                on_failure(code, signal)
            end
        end,
    })
end

-- Handle build command with different modes
local function handle_build_command(args)
    local zig_ffi = require("zig-lamp.core.core_ffi")

    -- Check if lamp lib is already loaded
    if zig_ffi.is_loaded() then
        util.Warn(
            "Lamp library is already loaded! Please restart Neovim and run the command again."
        )
        return
    end

    local build_args = { "build", "-Doptimize=ReleaseFast" }
    local mode = args[1] or "async"

    if mode == "async" then
        -- Asynchronous build
        local build_job = create_build_job(
            build_args,
            vim.schedule_wrap(function()
                util.Info("Build lamp library successfully!")
                zig_ffi.lazy_load()
            end),
            vim.schedule_wrap(function(code, signal)
                util.Error(
                    string.format(
                        "Build lamp library failed! Exit code: %d, Signal: %d",
                        code,
                        signal
                    )
                )
            end)
        )
        build_job:start()
    elseif mode == "sync" then
        -- Synchronous build
        local build_job = create_build_job(
            build_args,
            vim.schedule_wrap(function()
                util.Info("Build lamp library successfully!")
            end),
            vim.schedule_wrap(function(code, _)
                util.Error("Build lamp library failed! Exit code: " .. code)
            end)
        )

        local timeout = args[2]
                and tonumber(args[2])
                and math.floor(tonumber(args[2]))
            or 15000
        build_job:sync(timeout)
    else
        util.Warn("Invalid parameter: " .. mode .. ". Use 'async' or 'sync'.")
    end
end

-- Setup commands and autocmds
function M.setup()
    setup_syntax_highlighting()
    cmd.set_command(show_info_panel, nil, "info")
    cmd.set_command(handle_build_command, { "async", "sync" }, "build")
end

return M
