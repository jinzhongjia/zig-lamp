local cmd = require("zig-lamp.cmd")
local path = require("plenary.path")
local util = require("zig-lamp.util")
local zig_ffi = require("zig-lamp.ffi")
local M = {}

local function cb_pkg_info()
    local cwd = vim.fn.getcwd()
    local _p = path:new(cwd)
    local _root = _p:find_upwards("build.zig.zon")
    if not _root then
        util.Warn("not found build.zig.zon")
        return
    end
    local zon_info = zig_ffi.get_build_zon_info(_root:absolute())
    if not zon_info then
        util.Warn("parse build.zig.zon failed!")
        return
    end

    local content = {
        { { "PKG INFO", "DiagnosticInfo" } },
    }
    if zon_info.name then
        table.insert(content, "  name: " .. zon_info.name)
    end
    if zon_info.version then
        table.insert(content, "  version: " .. zon_info.version)
    end
    if zon_info.minimum_zig_version then
        table.insert(
            content,
            "  minimum_zig_version: " .. zon_info.minimum_zig_version
        )
    end
    if zon_info.paths and #zon_info.paths > 0 then
        table.insert(content, "  paths:")
        for _, val in pairs(zon_info.paths) do
            table.insert(content, "    - " .. val)
        end
    end
    if zon_info.dependencies and #zon_info.dependencies > 0 then
        table.insert(content, "  dependencies:")
        for name, _info in pairs(zon_info.dependencies) do
            table.insert(content, "    - " .. name)
        end
    end

    util.display(content, "60%", "60%")
end

--- @param params string[]
local function cb_pkg(params)
    if #params == 0 then
    elseif params[1] == "info" then
        cb_pkg_info()
    end
end

function M.setup()
    cmd.set_command(cb_pkg, { "info" }, "pkg")
end

return M
