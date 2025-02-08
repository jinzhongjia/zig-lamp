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

--- @param path string
--- @return string
function M.read_file(path)
    local err, fd = a.uv.fs_open(path, "r", 438)
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

function M.write_file(path, content)
    local err, fd = a.uv.fs_open(path, "w", 438)
    assert(not err, err)

    ---@diagnostic disable-next-line: redefined-local
    local err, stat = a.uv.fs_fstat(fd)
    assert(not err, err)

    ---@diagnostic disable-next-line: redefined-local
    local err, stat = a.uv.fs_write(fd, content)
    assert(not err, err)

    ---@diagnostic disable-next-line: redefined-local
    local err = a.uv.fs_close(fd)
    assert(not err, err)
end

function M.display(content)
    local bufnr = vim.api.nvim_create_buf(false, true)
    ---@diagnostic disable-next-line: param-type-mismatch
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, content)

    local popup = Popup({
        enter = true,
        focusable = true,
        border = {
            style = "rounded",
        },
        position = "0%",
        size = {
            width = "100%",
            height = "100%",
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

return M
