-- FFI bindings for zig-lamp native library
-- Provides interface to Zig compiled functions for file operations and parsing

local vim = vim
local ffi = require("ffi")
local path = require("plenary.path")
local util = require("zig-lamp.core.core_util")

local M = {}

-- Define C function signatures
ffi.cdef([[
    bool check_shasum(const char* file_path, const char* shasum);
    const char* get_build_zon_info(const char* file_path);
    void free_build_zon_info();
    const char* fmt_zon(const char* source_code);
    void free_fmt_zon();
]])

-- Find plugin root directory by traversing up from current file
local function find_plugin_path()
    local current_dir = vim.fs.dirname(debug.getinfo(1).source:sub(2))

    while current_dir do
        -- Check for expected plugin structure
        local marker_file = vim.fs.joinpath(
            current_dir,
            "lua",
            "zig-lamp",
            "core",
            "core_ffi.lua"
        )
        if vim.loop.fs_stat(marker_file) then
            return current_dir
        end

        local parent = vim.fs.dirname(current_dir)
        if parent == current_dir then
            break
        end
        current_dir = parent
    end

    return nil
end

local plugin_path = vim.fs.normalize(find_plugin_path() or ".")

-- Get platform-specific library path
local function get_library_path()
    local is_windows = package.config:sub(1, 1) == "\\"

    if is_windows then
        return vim.fs.joinpath(plugin_path, "zig-out", "bin", "zig-lamp.dll")
    elseif vim.fn.has("macunix") == 1 then
        return vim.fs.joinpath(
            plugin_path,
            "zig-out",
            "lib",
            "libzig-lamp.dylib"
        )
    else
        return vim.fs.joinpath(plugin_path, "zig-out", "lib", "libzig-lamp.so")
    end
end

local library_path = vim.fs.normalize(get_library_path())
local _zig_lamp = nil

-- Get FFI library instance (lazy loaded)
function M.get_lamp()
    -- Return nil if library is known to be missing
    if _zig_lamp == true then
        return nil
    end

    -- Return cached instance
    if _zig_lamp then
        return _zig_lamp
    end

    -- Try to load library
    if path:new(library_path):exists() then
        _zig_lamp = ffi.load(library_path)
        return _zig_lamp
    end

    -- Mark as missing to avoid repeated attempts
    _zig_lamp = true
    return nil
end

-- Check if library is successfully loaded
function M.is_loaded()
    return _zig_lamp ~= nil and _zig_lamp ~= true
end

-- Attempt to load library if previously failed
function M.lazy_load()
    if _zig_lamp ~= true then
        return
    end

    if path:new(library_path):exists() then
        _zig_lamp = ffi.load(library_path)
    end
end

-- Get plugin root directory path
function M.get_plugin_path()
    return plugin_path
end

-- Verify file checksum using native implementation
function M.check_shasum(file_path, shasum)
    local zig_lamp = M.get_lamp()
    if not zig_lamp then
        util.Info("Native library not found, skipping shasum check")
        return true
    end

    util.Info("Checking file shasum")
    return zig_lamp.check_shasum(file_path, shasum)
end

-- Parse build.zon file and return structured data
function M.get_build_zon_info(file_path)
    local zig_lamp = M.get_lamp()
    if not zig_lamp then
        return nil
    end

    if not path:new(file_path):exists() then
        return nil
    end

    local result = ffi.string(zig_lamp.get_build_zon_info(file_path))
    if result == "" then
        return nil
    end

    zig_lamp.free_build_zon_info()
    return vim.fn.json_decode(result)
end

-- Free memory allocated for build.zon info
function M.free_build_zon_info()
    local zig_lamp = M.get_lamp()
    if zig_lamp then
        zig_lamp.free_build_zon_info()
    end
end

-- Format ZON source code using native formatter
function M.fmt_zon(source_code)
    local zig_lamp = M.get_lamp()
    if not zig_lamp then
        return nil
    end

    local result = ffi.string(zig_lamp.fmt_zon(source_code))
    if result == "" then
        return nil
    end

    zig_lamp.free_fmt_zon()
    return result
end

-- Free memory allocated for ZON formatting
function M.free_fmt_zon()
    local zig_lamp = M.get_lamp()
    if zig_lamp then
        zig_lamp.free_fmt_zon()
    end
end

return M
