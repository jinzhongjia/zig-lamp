-- FFI bindings for zig-lamp native library
-- Provides interface to Zig compiled functions for file operations and parsing
-- Enhanced version with better memory management and error handling

local vim = vim
local ffi = require("ffi")
local path = require("plenary.path")
local util = require("zig-lamp.core.core_util")

local M = {}

-- FFI library status
local _ffi_initialized = false
local _ffi_error = nil

-- Initialize FFI definitions
local function init_ffi_definitions()
    if _ffi_initialized then
        return true
    end

    local success, err = pcall(function()
        ffi.cdef([[
            bool check_shasum(const char* file_path, const char* shasum);
            const char* get_build_zon_info(const char* file_path);
            void free_build_zon_info();
            const char* fmt_zon(const char* source_code);
            void free_fmt_zon();
        ]])
    end)

    if success then
        _ffi_initialized = true
        return true
    else
        _ffi_error = err
        util.Error("Failed to initialize FFI definitions", {
            operation = "ffi.cdef",
            error = tostring(err),
            suggestion = "Please check LuaJIT environment and FFI support",
        })
        return false
    end
end

-- Find plugin root directory by traversing up from current file
local function find_plugin_path()
    local current_dir = vim.fs.dirname(debug.getinfo(1).source:sub(2))

    while current_dir do
        -- Check for expected plugin structure
        local marker_file = vim.fs.joinpath(current_dir, "lua", "zig-lamp", "core", "core_ffi.lua")
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
    local platform = require("zig-lamp.core.core_platform")
    local lib_name = platform.library_name("zig-lamp")

    if platform.is_windows then
        -- Windows DLL 通常放在 bin 目录
        return vim.fs.joinpath(plugin_path, "zig-out", "bin", lib_name)
    else
        -- Unix 系统的共享库放在 lib 目录
        return vim.fs.joinpath(plugin_path, "zig-out", "lib", lib_name)
    end
end

local library_path = vim.fs.normalize(get_library_path())
local _zig_lamp = nil
local _load_attempts = 0
local _max_load_attempts = 3

-- Get FFI library instance (lazy loaded with enhanced error handling)
function M.get_lamp()
    -- Check if FFI is initialized
    if not init_ffi_definitions() then
        return nil
    end

    -- Return nil if library is known to be missing after max attempts
    if _zig_lamp == true then
        return nil
    end

    -- Return cached instance
    if _zig_lamp then
        return _zig_lamp
    end

    -- Check load attempt count
    if _load_attempts >= _max_load_attempts then
        util.Error("Failed to load FFI library", {
            operation = "ffi.load",
            file = library_path,
            error = "Exceeded maximum attempts",
            suggestion = "Please run ':ZigLamp build' to build the library",
        })
        _zig_lamp = true
        return nil
    end

    _load_attempts = _load_attempts + 1

    -- Try to load library
    if path:new(library_path):exists() then
        local success, result = util.safe_call(function()
            return ffi.load(library_path)
        end, {
            operation = "ffi.load",
            file = library_path,
        })

        if success then
            _zig_lamp = result
            util.Info("FFI library loaded successfully", { file = library_path })
            return _zig_lamp
        else
            util.Error("Failed to load FFI library", {
                operation = "ffi.load",
                file = library_path,
                error = tostring(result),
                suggestion = "Please rebuild the library or check file permissions",
            })
        end
    else
        util.Warn("FFI library file not found", {
            file = library_path,
            suggestion = "Please run ':ZigLamp build' to build the library",
        })
    end

    -- Mark as missing only after all attempts failed
    if _load_attempts >= _max_load_attempts then
        _zig_lamp = true
    end

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
        util.Info("Native library not found, skipping checksum verification")
        return true
    end

    util.Info("Verifying file checksum")
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
