local M = {}

-- TODO: this need to test on macos
M.arch = vim.uv.os_uname().machine

if vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1 then
    M.sys = "windows"
elseif vim.fn.has("macunix") == 1 then
    M.sys = "macos"
elseif vim.fn.has("unix") == 1 then
    M.sys = "linux"
end

--- @param _path string
function M.mkdir(_path)
    vim.fn.mkdir(_path, "p")
end

-- this is public notify message prefix
local _notify_public_message = "[ZigLamp]: "

-- Error notify
--- @param message string
function M.Error(message)
    -- stylua: ignore
    vim.api.nvim_notify(_notify_public_message .. message, vim.log.levels.ERROR, {})
end

-- Info notify
--- @param message string
function M.Info(message)
    -- stylua: ignore
    vim.api.nvim_notify(_notify_public_message .. message, vim.log.levels.INFO, {})
end

-- Warn notify
--- @param message string
function M.Warn(message)
    -- stylua: ignore
    vim.api.nvim_notify(_notify_public_message .. message, vim.log.levels.WARN, {})
end

local function is_array(t)
    local i = 0
    for _ in pairs(t) do
        i = i + 1
        if t[i] == nil then
            return false
        end
    end
    return true
end

--- @param info ZigBuildZon
--- @return string
function M.wrap_j2zon(info)
    local res = ""
    res = res .. ".{"
    res = res .. ".name = ." .. (info.name or "") .. ","
    res = res .. ".version = " .. M.data2zon(info.version or "") .. ","
    res = res .. ".fingerprint = " .. info.fingerprint .. ","
    if info.minimum_zig_version then
        -- stylua: ignore
        res = res .. ".minimum_zig_version = " .. M.data2zon(info.minimum_zig_version or "") .. ","
    end
    -- stylua: ignore
    res = res .. ".dependencies = ".. M.data2zon(info.dependencies or {}) .. ","
    res = res .. ".paths=" .. M.data2zon(info.paths or {}) .. ","
    res = res .. "}"
    return res
end

-- whether the str is legal for zig
--- @param str string
local function str_if_legal(str)
    local result = string.find(str, "-") == nil
    local first_char = string.sub(str, 1, 1)
    result = result and string.match(first_char, "[%a_]") ~= nil
    return result
end

-- convert lua type to a zon string, but now we can not format the string
function M.data2zon(obj)
    local res = ""
    if type(obj) == "table" then
        res = res .. ".{"
        local if_arr = is_array(obj)
        for key, value in pairs(obj) do
            if not if_arr then
                if str_if_legal(key) then
                    res = res .. "." .. key .. "="
                else
                    res = res .. '.@"' .. key .. '"='
                end
            end
            res = res .. M.data2zon(value)
            res = res .. ","
        end
        res = res .. "}"
    elseif type(obj) == "string" then
        res = string.format('"%s"', obj)
    elseif type(obj) == "boolean" then
        if obj then
            res = "true"
        else
            res = "false"
        end
    elseif type(obj) == "number" then
        res = tostring(obj)
    end
    return res
end

--- @param color string
--- @param amount number
function M.adjust_brightness(color, amount)
    local r = tonumber(color:sub(2, 3), 16)
    local g = tonumber(color:sub(4, 5), 16)
    local b = tonumber(color:sub(6, 7), 16)

    r = math.min(255, math.max(0, r + amount))
    g = math.min(255, math.max(0, g + amount))
    b = math.min(255, math.max(0, b + amount))

    return string.format("#%02X%02X%02X", r, g, b)
end
return M
