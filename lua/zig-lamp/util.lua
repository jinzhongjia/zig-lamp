local NuiLine = require("nui.line")
local NuiText = require("nui.text")
local Popup = require("nui.popup")
local event = require("nui.utils.autocmd").event
local a = require("plenary.async")

local M = {}

-- TODO: this need to test on linux and macos
M.arch = vim.uv.os_uname().machine

if vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1 then
    M.sys = "windows"
elseif vim.fn.has("macunix") == 1 then
    M.sys = "macos"
elseif vim.fn.has("unix") == 1 then
    M.sys = "linux"
end

function M.mkdir(_path)
    vim.fn.mkdir(_path, "p")
end

--- read file through path
--- @param _path string
--- @return string
function M.read_file(_path)
    local err, fd = a.uv.fs_open(_path, "r", 438)
    assert(not err, err)

    ---@diagnostic disable-next-line: redefined-local
    local err, stat = a.uv.fs_fstat(fd)
    assert(not err, err)

    ---@diagnostic disable-next-line: redefined-local
    local err, data = a.uv.fs_read(fd, stat.size, 0)
    assert(not err, err)

    ---@diagnostic disable-next-line: redefined-local
    local err = a.uv.fs_close(fd)
    assert(not err, err)

    return data
end

-- write file through path
--- @param _path string
---@param content string
function M.write_file(_path, content)
    local err, fd = a.uv.fs_open(_path, "w", 438)
    assert(not err, err)

    ---@diagnostic disable-next-line: redefined-local, unused-local
    local err, stat = a.uv.fs_fstat(fd)
    assert(not err, err)

    ---@diagnostic disable-next-line: redefined-local, unused-local
    local err, stat = a.uv.fs_write(fd, content)
    assert(not err, err)

    ---@diagnostic disable-next-line: redefined-local
    local err = a.uv.fs_close(fd)
    assert(not err, err)
end

-- display something with nui
--- @param content (string[]|string)[]
--- @param width string|nil
--- @param height string|nil
function M.display(content, width, height)
    local bufnr = vim.api.nvim_create_buf(false, true)

    for _index, _tmp in pairs(content) do
        local line = NuiLine()
        if type(_tmp) == "string" then
            line:append(_tmp)
        else
            line:append(_tmp[1], _tmp[2] or nil)
        end
        line:render(bufnr, -1, _index)
    end

    local popup = Popup({
        enter = true,
        focusable = true,
        border = {
            style = "rounded",
        },
        position = "50%",
        size = {
            width = width or "100%",
            height = height or "100%",
        },
        bufnr = bufnr,
    })

    vim.api.nvim_buf_set_keymap(bufnr, "n", "q", "", {
        noremap = true,
        callback = function()
            popup:_close_window()
        end,
    })

    -- mount/open the component
    popup:mount()

    -- unmount component when cursor leaves buffer
    popup:on(event.BufLeave, function()
        popup:unmount()
    end)
end

-- this is public notify message prefix
local _notify_public_message = "[ZigLamp]: "

-- Error notify
--- @param message string
M.Error = function(message)
    -- stylua: ignore
    vim.api.nvim_notify(_notify_public_message .. message, vim.log.levels.ERROR, {})
end

-- Info notify
--- @param message string
M.Info = function(message)
    -- stylua: ignore
    vim.api.nvim_notify(_notify_public_message .. message, vim.log.levels.INFO, {})
end

-- Warn notify
--- @param message string
M.Warn = function(message)
    -- stylua: ignore
    vim.api.nvim_notify(_notify_public_message .. message, vim.log.levels.WARN, {})
end

return M
