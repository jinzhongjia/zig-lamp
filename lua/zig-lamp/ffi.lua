local ffi = require("ffi")
local path = require("plenary.path")
local util = require("zig-lamp.util")

local M = {}

ffi.cdef([[
    bool check_shasum(const char* file_path, const char* shasum);
    const char* get_build_zon_info(const char* file_path);
    void free_build_zon_info();
    const char* fmt_zon(const char* source_code);
    void free_fmt_zon();
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

--- @class ZigDependency
--- @field url? string
--- @field hash? string
--- @field path? string
--- @field lazy? boolean
---
--- @class ZigBuildZon
--- @field name string
--- @field version string
--- @field fingerprint string
--- @field minimum_zig_version string|nil
--- @field dependencies { [string] : ZigDependency }
--- @field paths string[]

-- get build.zig.zon info
-- this will parse as a table
--- @param file_path string
--- @return ZigBuildZon|nil
function M.get_build_zon_info(file_path)
    local zig_lamp = M.get_lamp()
    -- stylua: ignore
    if not zig_lamp then return nil end

    local _p = path:new(file_path)
    -- stylua: ignore
    if not _p:exists() then return nil end

    local res = ffi.string(zig_lamp.get_build_zon_info(file_path))
    if res == "" then
        return nil
    end
    zig_lamp.free_build_zon_info()
    local _tmp = vim.fn.json_decode(res)
    return _tmp
end

--- @deprecated not use this
function M.free_build_zon_info()
    local zig_lamp = M.get_lamp()
    -- stylua: ignore
    if not zig_lamp then return end
    zig_lamp.free_build_zon_info()
end

-- format zon code
--- @param source_code string
--- @return string|nil
function M.fmt_zon(source_code)
    local zig_lamp = M.get_lamp()
    -- stylua: ignore
    if not zig_lamp then return nil end
    local res = ffi.string(zig_lamp.fmt_zon(source_code))
    if res == "" then
        return nil
    end
    zig_lamp.free_fmt_zon()
    return res
end

--- @deprecated not use this
function M.free_fmt_zon()
    local zig_lamp = M.get_lamp()
    -- stylua: ignore
    if not zig_lamp then return end
    zig_lamp.free_fmt_zon()
end

return M
