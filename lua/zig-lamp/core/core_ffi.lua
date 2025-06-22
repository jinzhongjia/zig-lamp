-- core_ffi.lua
-- ffi 相关，原 ffi.lua 内容迁移于此

local vim = vim
local ffi = require("ffi")
local path = require("plenary.path")
local util = require("zig-lamp.core.core_util")

local M = {}

ffi.cdef([[ 
    bool check_shasum(const char* file_path, const char* shasum);
    const char* get_build_zon_info(const char* file_path);
    void free_build_zon_info();
    const char* fmt_zon(const char* source_code);
    void free_fmt_zon();
]])

local function find_plugin_path()
    local dir = vim.fs.dirname(debug.getinfo(1).source:sub(2))
    while dir do
        -- 检查是否存在 lua/zig-lamp/core/core_ffi.lua 结构
        local candidate = vim.fs.joinpath(dir, "lua", "zig-lamp", "core", "core_ffi.lua")
        if vim.loop.fs_stat(candidate) then
            return dir
        end
        local parent = vim.fs.dirname(dir)
        if parent == dir then break end
        dir = parent
    end
    return nil
end
local plugin_path = vim.fs.normalize(find_plugin_path() or ".")

local library_path = (function()
    if package.config:sub(1, 1) == "\\" then
        -- Windows
        return vim.fs.normalize(vim.fs.joinpath(plugin_path, "zig-out", "bin", "zig-lamp.dll"))
    else
        -- Unix
        if vim.fn.has("macunix") == 1 then
            return vim.fs.normalize(vim.fs.joinpath(plugin_path, "zig-out", "lib", "libzig-lamp.dylib"))
        else
            return vim.fs.normalize(vim.fs.joinpath(plugin_path, "zig-out", "lib", "libzig-lamp.so"))
        end
    end
end)()

local _zig_lamp = nil

function M.get_lamp()
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

function M.is_loaded()
    if _zig_lamp == nil or _zig_lamp == true then
        return false
    end
    return true
end

function M.lazy_load()
    if _zig_lamp ~= true then
        return
    end
    local _p = path:new(library_path)
    if _p:exists() then
        _zig_lamp = ffi.load(library_path)
    end
end

function M.get_plugin_path()
    return plugin_path
end

function M.check_shasum(file_path, shasum)
    local zig_lamp = M.get_lamp()
    if not zig_lamp then
        util.Info("not found zig dynamic library, skip shasum check")
        return true
    end
    util.Info("try to check shasum")
    return zig_lamp.check_shasum(file_path, shasum)
end

function M.get_build_zon_info(file_path)
    local zig_lamp = M.get_lamp()
    if not zig_lamp then
        return nil
    end
    local _p = path:new(file_path)
    if not _p:exists() then
        return nil
    end
    local res = ffi.string(zig_lamp.get_build_zon_info(file_path))
    if res == "" then
        return nil
    end
    zig_lamp.free_build_zon_info()
    local _tmp = vim.fn.json_decode(res)
    return _tmp
end

function M.free_build_zon_info()
    local zig_lamp = M.get_lamp()
    if not zig_lamp then
        return
    end
    zig_lamp.free_build_zon_info()
end

function M.fmt_zon(source_code)
    local zig_lamp = M.get_lamp()
    if not zig_lamp then
        return nil
    end
    local res = ffi.string(zig_lamp.fmt_zon(source_code))
    if res == "" then
        return nil
    end
    zig_lamp.free_fmt_zon()
    return res
end

function M.free_fmt_zon()
    local zig_lamp = M.get_lamp()
    if not zig_lamp then
        return
    end
    zig_lamp.free_fmt_zon()
end

return M
