local ffi = require("ffi")
local path = require("plenary.path")

local M = {}

ffi.cdef([[
    bool sha256_digest(const char* file_path, const char* shasum);
]])

local library_path = vim.fs.normalize((function()
    local dirname = string.sub(debug.getinfo(1).source, 2, #"/ffi.lua" * -1)
    if package.config:sub(1, 1) == "\\" then
        return dirname .. "../../zig-out/bin/zig-lamp.dll"
    else
        return dirname .. "../../zig-out/bin/zig-lamp.so"
    end
end)())

local _p = path:new(library_path)

local zig_lamp = ffi.load(library_path)

function M.sha256_digest(file_path, shasum)
    if not _p:exists() then
        return true
    end
    return zig_lamp.sha256_digest(file_path, shasum)
end

return M
