local health = vim.health
local System = require("zig-lamp.system")
local FFI = require("zig-lamp.services.ffi")

local M = {}

local function check_tool(name)
    health.start(string.format("检查工具: %s", name))
    if System.which(name) then
        health.ok(string.format("已安装 %s", name))
    else
        health.error(string.format("未找到 %s", name))
    end
end

local function check_lspconfig()
    health.start("检查 lspconfig (可选)")
    local ok = pcall(require, "lspconfig")
    if ok then
        health.ok("已找到 lspconfig")
    else
        health.warn("未找到 lspconfig (Neovim 0.11+ 可使用内置 LSP)")
    end
end

local function check_extract_tools()
    local info = System.info()
    if info.is_windows then
        health.start("检查 unzip / powershell")
        if System.which("unzip") or System.which("powershell") then
            health.ok("已找到解压工具")
        else
            health.error("未找到 unzip 或 powershell，无法解压 ZLS 压缩包")
        end
    else
        check_tool("tar")
    end
end

local function check_native_lib()
    health.start("检查 zig-lamp 本地库 (可选)")
    if FFI.available() then
        health.ok("已加载本地库，可启用更快的校验与格式化")
    else
        health.warn('未构建本地库，可执行 ":ZigLampBuild" 以启用校验与格式化加速')
    end
end

function M.check()
    check_tool("zig")
    check_tool("curl")
    check_extract_tools()
    check_lspconfig()
    check_native_lib()
end

return M

