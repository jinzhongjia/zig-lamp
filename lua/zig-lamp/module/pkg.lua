local cmd = require("zig-lamp.cmd")
local path = require("plenary.path")
local util = require("zig-lamp.util")
local zig_ffi = require("zig-lamp.ffi")
local M = {}

--- @param params string[]
local function cb_pkg(params)
    -- get cwd
    local cwd = vim.fn.getcwd()
    local _p = path:new(cwd)
    -- try find build.zig.zon
    local _root = _p:find_upwards("build.zig.zon")
    if not _root then
        util.Warn("not found build.zig.zon")
        return
    end
    -- try parse build.zig.zon
    local zon_info = zig_ffi.get_build_zon_info(_root:absolute())
    if not zon_info then
        util.Warn("parse build.zig.zon failed!")
        return
    end

    local content = {
        "Package info",
    }
    if zon_info.name then
        table.insert(content, "  Name: " .. zon_info.name)
    end
    if zon_info.version then
        table.insert(content, "  Version: " .. zon_info.version)
    end
    if zon_info.minimum_zig_version then
        table.insert(
            content,
            "  Minimum zig version: " .. zon_info.minimum_zig_version
        )
    end
    if zon_info.paths and #zon_info.paths > 0 then
        table.insert(content, "  Paths:")
        for _, val in pairs(zon_info.paths) do
            table.insert(content, "    - " .. val)
        end
    end
    if zon_info.dependencies and not vim.tbl_isempty(zon_info.dependencies) then
        table.insert(content, "  Dependencies:")
        for name, _info in pairs(zon_info.dependencies) do
            table.insert(content, "    - " .. name)
            table.insert(content, "      version: " .. _info.url)
            table.insert(content, "      hash: " .. _info.hash)
        end
    end

    local new_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_option_value("modifiable", true, { buf = new_buf })
    vim.api.nvim_buf_set_lines(new_buf, 0, -1, true, content)
    vim.api.nvim_set_option_value("filetype", "ZigLamp_info", { buf = new_buf })
    vim.api.nvim_set_option_value("bufhidden", "delete", { buf = new_buf })
    vim.api.nvim_set_option_value("modifiable", false, { buf = new_buf })
    local win = vim.api.nvim_open_win(
        new_buf,
        true,
        { split = "right", style = "minimal", width = 50 }
    )
    vim.api.nvim_buf_set_keymap(new_buf, "n", "q", "", {
        desc = "quit for ZigLamp info panel",
        callback = function()
            vim.api.nvim_win_close(win, true)
        end,
    })
end

function M.setup()
    cmd.set_command(cb_pkg, { "info" }, "pkg")
end

return M
