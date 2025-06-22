-- Core utility functions for zig-lamp plugin
-- Provides platform detection, notifications, and data conversion utilities

local vim = vim

local M = {}

-- Platform and architecture detection
local arch = vim.uv.os_uname().machine

-- Get normalized architecture string
function M.arch()
    return arch == "arm64" and "aarch64" or arch
end

-- Detect operating system
if vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1 then
    M.sys = "windows"
elseif vim.fn.has("macunix") == 1 then
    M.sys = "macos"
elseif vim.fn.has("unix") == 1 then
    M.sys = "linux"
end

-- File system utilities
function M.mkdir(path)
    vim.fn.mkdir(path, "p")
end

-- Notification system with consistent prefix
local NOTIFY_PREFIX = "[ZigLamp]: "

-- Show error notification
function M.Error(message)
    vim.api.nvim_notify(NOTIFY_PREFIX .. message, vim.log.levels.ERROR, {})
end

-- Show info notification
function M.Info(message)
    vim.api.nvim_notify(NOTIFY_PREFIX .. message, vim.log.levels.INFO, {})
end

-- Show warning notification
function M.Warn(message)
    vim.api.nvim_notify(NOTIFY_PREFIX .. message, vim.log.levels.WARN, {})
end

-- Check if table is an array (consecutive integer keys starting from 1)
local function is_array(t)
    local i = 0
    for _ in pairs(t) do
        i = i + 1
        if t[i] == nil then return false end
    end
    return true
end

-- Check if string is a valid Zig identifier
local function is_valid_identifier(str)
    local first_char = str:sub(1, 1)
    return not str:find("-") and first_char:match("[%a_]")
end

-- Convert Lua data to Zig Object Notation (ZON) format
function M.data2zon(obj)
    local obj_type = type(obj)
    
    if obj_type == "table" then
        local result = ".{"
        local is_arr = is_array(obj)
        
        for key, value in pairs(obj) do
            if not is_arr then
                if is_valid_identifier(key) then
                    result = result .. "." .. key .. "="
                else
                    result = result .. '.@"' .. key .. '"='
                end
            end
            result = result .. M.data2zon(value) .. ","
        end
        return result .. "}"
        
    elseif obj_type == "string" then
        return string.format('"%s"', obj)
    elseif obj_type == "boolean" then
        return obj and "true" or "false"
    elseif obj_type == "number" then
        return tostring(obj)
    end
    
    return ""
end

-- Convert build.zon info to ZON format
function M.wrap_j2zon(info)
    local components = {
        ".name = ." .. (info.name or ""),
        ".version = " .. M.data2zon(info.version or ""),
        ".fingerprint = " .. info.fingerprint,
    }
    
    if info.minimum_zig_version then
        table.insert(components, ".minimum_zig_version = " .. M.data2zon(info.minimum_zig_version))
    end
    
    table.insert(components, ".dependencies = " .. M.data2zon(info.dependencies or {}))
    table.insert(components, ".paths=" .. M.data2zon(info.paths or {}))
    
    return ".{" .. table.concat(components, ",") .. "}"
end

-- Adjust color brightness for UI theming
function M.adjust_brightness(color, amount)
    local r = tonumber(color:sub(2, 3), 16) or 0
    local g = tonumber(color:sub(4, 5), 16) or 0
    local b = tonumber(color:sub(6, 7), 16) or 0

    r = math.min(255, math.max(0, r + amount))
    g = math.min(255, math.max(0, g + amount))
    b = math.min(255, math.max(0, b + amount))

    return string.format("#%02X%02X%02X", r, g, b)
end

return M

