local ffi = require("ffi")
local path = require("plenary.path")
local util = require("zig-lamp.util")

local M = {}

ffi.cdef([[
    bool sha256_digest(const char* file_path, const char* shasum);
]])

local library_path = vim.fs.normalize((function()
    local dirname = string.sub(debug.getinfo(1).source, 2, #"/ffi.lua" * -1)
    if package.config:sub(1, 1) == "\\" then
        return dirname .. "../../zig-out/bin/zig-lamp.dll"
    else
        return dirname .. "../../zig-out/lib/libzig-lamp.so"
    end
end)())

local _p = path:new(library_path)

--- @type ffi.namespace*|nil|true
local _zig_lamp = nil

--- @return ffi.namespace*|nil
local function get_lamp()
    -- when true, zig_lamp is not found
    if _zig_lamp == true then
        return nil
    end
    if _zig_lamp then
        return _zig_lamp
    end
    if _p:exists() then
        _zig_lamp = ffi.load(library_path)
        return _zig_lamp
    end
    _zig_lamp = true
    return nil
end

-- check sha256 digest
--- @param file_path string
--- @param shasum string
--- @return boolean
function M.sha256_digest(file_path, shasum)
    local zig_lamp = get_lamp()
    if not zig_lamp then
        util.Info("not found zig dynamic library, skip shasum check")
        return true
    end
    util.Info("try to check shasum")
    return zig_lamp.sha256_digest(file_path, shasum)
end

return M
