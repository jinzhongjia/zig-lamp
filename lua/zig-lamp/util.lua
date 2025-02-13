local NuiLine = require("nui.line")
local Popup = require("nui.popup")

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

-- display something with nui
--- @param content (string[][]|string)[]
--- @param width string|nil
--- @param height string|nil
function M.display(content, width, height)
    local bufnr = vim.api.nvim_create_buf(false, true)

    for _index, _tmp in pairs(content) do
        local line = NuiLine()
        if type(_tmp) == "string" then
            line:append(_tmp)
        else
            for _, _ele in pairs(_tmp) do
                line:append(_ele[1], _ele[2] or nil)
            end
        end
        line:render(bufnr, -1, _index)
    end

    local popup = Popup({
        enter = true,
        focusable = true,
        relative = "editor",
        border = {
            style = "rounded",
            text = { top = "Zig Lamp", top_align = "center" },
        },
        position = "50%",
        size = {
            width = width or "100%",
            height = height or "100%",
        },
        bufnr = bufnr,
        buf_options = { modifiable = false, readonly = true },
    })

    vim.api.nvim_buf_set_keymap(bufnr, "n", "q", "", {
        noremap = true,
        callback = function()
            popup:_close_window()
        end,
    })

    -- mount/open the component
    popup:mount()

    local event = require("nui.utils.autocmd").event
    -- unmount component when cursor leaves buffer
    popup:on(event.BufLeave, function()
        popup:unmount()
    end)
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
