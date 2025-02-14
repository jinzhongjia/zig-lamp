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

-- convert lua type to a zon string, but now we can not format the string
function M.data2zon(obj)
    local res = ""
    if type(obj) == "table" then
        res = res .. ".{"
        local if_arr = is_array(obj)
        for key, value in pairs(obj) do
            if not if_arr then
                res = res .. "." .. key .. "="
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

return M
