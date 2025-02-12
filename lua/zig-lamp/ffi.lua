local ffi = require("ffi")
local path = require("plenary.path")
local util = require("zig-lamp.util")

local M = {}

ffi.cdef([[
    bool check_shasum(const char* file_path, const char* shasum);
]])

-- stylua: ignore
local plugin_path = vim.fs.normalize(string.sub(debug.getinfo(1).source, 2, #"/ffi.lua" * -1) .. "../../")

local library_path = vim.fs.normalize((function()
    if package.config:sub(1, 1) == "\\" then
        return vim.fs.joinpath(plugin_path, "zig-out/bin/zig-lamp.dll")
    else
        return vim.fs.joinpath(plugin_path, "zig-out/lib/libzig-lamp.so")
    end
end)())

--- @type ffi.namespace*|nil|true
local _zig_lamp = nil

--- @return ffi.namespace*|nil
function M.get_lamp()
    -- when true, zig_lamp is not found
    if _zig_lamp == true then
        return nil
    end
    if _zig_lamp then
        return _zig_lamp
    end
    local _p = path:new(library_path)
    if _p:exists() then
        _zig_lamp = ffi.load(library_path)
        return _zig_lamp
    end
    _zig_lamp = true
    return nil
end

-- whether zig-lamp is loaded
--- @return boolean
function M.is_loaded()
    if _zig_lamp == nil or _zig_lamp == true then
        return false
    end
    return true
end

-- if zig-lamp is true, load it
function M.lazy_load()
    if _zig_lamp ~= true then
        return
    end
    local _p = path:new(library_path)
    if _p:exists() then
        _zig_lamp = ffi.load(library_path)
    end
end

--- @return string
function M.get_plugin_path()
    return plugin_path
end

-- check sha256 digest
--- @param file_path string
--- @param shasum string
--- @return boolean
function M.check_shasum(file_path, shasum)
    local zig_lamp = M.get_lamp()
    if not zig_lamp then
        util.Info("not found zig dynamic library, skip shasum check")
        return true
    end
    util.Info("try to check shasum")
    return zig_lamp.check_shasum(file_path, shasum)
end

return M
