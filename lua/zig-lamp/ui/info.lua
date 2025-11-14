local Config = require("zig-lamp.config")
local Zls = require("zig-lamp.services.zls")
local Zig = require("zig-lamp.services.zig")
local System = require("zig-lamp.system")

local Info = {}

local function build_lines()
    local cfg = Config.get()
    local status = Zls.status()
    local lines = {
        "Zig Lamp",
        string.format("  版本: %s", cfg.version or "0.0.0"),
        string.format("  数据目录: %s", Config.paths().data),
        "",
        "Zig:",
        string.format("  版本: %s", Zig.version() or "未检测到"),
        "",
        "ZLS:",
        string.format("  当前版本: %s", status.current_zls_version or "未运行"),
        string.format("  使用系统 ZLS: %s", status.using_system_zls and "是" or "否"),
        string.format("  已初始化: %s", status.lsp_initialized and "是" or "否"),
        string.format("  系统 ZLS: %s", status.system_zls_available and (status.system_zls_version or "可用") or "不可用"),
    }

    if status.available_local_versions and #status.available_local_versions > 0 then
        table.insert(lines, "  本地版本:")
        for _, version in ipairs(status.available_local_versions) do
            table.insert(lines, "    - " .. version)
        end
    end

    local sys = System.info()
    table.insert(lines, "")
    table.insert(lines, "系统:")
    table.insert(lines, string.format("  OS: %s", sys.os))
    table.insert(lines, string.format("  架构: %s", sys.arch))

    return lines
end

local function open_window(buf)
    local width = math.min(60, math.floor(vim.o.columns * 0.4))
    local height = math.min(20, math.floor(vim.o.lines * 0.5))
    return vim.api.nvim_open_win(buf, true, {
        relative = "editor",
        width = width,
        height = height,
        row = math.floor((vim.o.lines - height) / 2),
        col = math.floor((vim.o.columns - width) / 2),
        style = "minimal",
        border = "rounded",
        title = "ZigLamp Info",
        title_pos = "center",
    })
end

function Info.open()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_option(buf, "filetype", "ziglamp_info")
    vim.api.nvim_buf_set_option(buf, "modifiable", false)
    vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")

    local lines = build_lines()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

    local win = open_window(buf)

    vim.keymap.set("n", "q", function()
        if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
        end
    end, { buffer = buf, nowait = true, silent = true })
end

return Info

