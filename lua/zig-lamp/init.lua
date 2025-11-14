local Config = require("zig-lamp.config")
local Log = require("zig-lamp.log")
local CommandRegistry = require("zig-lamp.commands")
local Build = require("zig-lamp.services.build")
local Zls = require("zig-lamp.services.zls")
local ZigSvc = require("zig-lamp.services.zig")
local PkgUI = require("zig-lamp.ui.pkg")
local InfoUI = require("zig-lamp.ui.info")
local Health = require("zig-lamp.health")

local M = {}

local registry = nil
local commands_installed = false

local function render_status()
    local status = Zls.status()
    local lines = {
        "ZLS 状态:",
        string.format("  Zig: %s", status.zig_version or "unknown"),
        string.format("  当前版本: %s", status.current_zls_version or "未运行"),
        string.format("  使用系统 ZLS: %s", status.using_system_zls and "是" or "否"),
        string.format("  是否已初始化: %s", status.lsp_initialized and "是" or "否"),
        string.format("  系统 ZLS: %s", status.system_zls_available and (status.system_zls_version or "可用") or "不可用"),
    }
    if status.available_local_versions and #status.available_local_versions > 0 then
        table.insert(lines, "  本地版本:")
        for _, version in ipairs(status.available_local_versions) do
            table.insert(lines, "    - " .. version)
        end
    end
    vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO, { title = "ZigLamp" })
end

local function register_commands()
    if commands_installed then
        return
    end
    registry = registry or CommandRegistry.new("ZigLamp")

    registry:register({
        path = { "info" },
        handler = InfoUI.open,
        desc = "显示插件信息",
    })

    registry:register({
        path = { "health" },
        handler = Health.check,
        desc = "运行健康检查",
    })

    registry:register({
        path = { "pkg" },
        handler = PkgUI.open,
        desc = "打开包管理面板",
    })

    registry:register({
        path = { "build" },
        handler = function(args)
            Build.project(args)
        end,
        desc = "执行 zig build",
    })

    registry:register({
        path = { "test" },
        handler = function(args)
            Build.test(args)
        end,
        desc = "执行 zig build test",
    })

    registry:register({
        path = { "clean" },
        handler = Build.clean,
        desc = "清理 zig-out 与 zig-cache",
    })

    registry:register({
        path = { "zls", "install" },
        handler = Zls.install,
        desc = "安装匹配当前 Zig 的 ZLS",
    })

    registry:register({
        path = { "zls", "uninstall" },
        handler = Zls.uninstall,
        complete = function()
            return Zls.local_versions()
        end,
        desc = "卸载指定 ZLS 版本",
    })

    registry:register({
        path = { "zls", "status" },
        handler = render_status,
        desc = "显示 ZLS 状态",
    })

    registry:install()
    commands_installed = true
end

local function register_build_command()
    local ok = pcall(vim.api.nvim_create_user_command, "ZigLampBuild", function(info)
        local opts = {
            optimization = info.args ~= "" and info.args or "ReleaseFast",
        }
        Build.plugin_library(opts)
    end, {
        desc = "构建 zig-lamp FFI 动态库",
        nargs = "?",
        complete = function()
            return { "Debug", "ReleaseSafe", "ReleaseFast", "ReleaseSmall" }
        end,
    })

    if not ok then
        -- command already exists; ignore to keep configuration idempotent
        return
    end
end

function M.setup(opts)
    Config.bootstrap(opts or {})
    Log.setup(Config.get("logging"))
    Zls.bootstrap()

    register_commands()
    register_build_command()
end

function M.health()
    Health.check()
end

function M.info()
    InfoUI.open()
end

function M.pkg()
    PkgUI.open()
end

M.zls = {
    install = Zls.install,
    uninstall = Zls.uninstall,
    status = Zls.status,
    ensure_started = Zls.ensure_started,
}

M.build = {
    project = Build.project,
    test = Build.test,
    clean = Build.clean,
    plugin = Build.plugin_library,
}

M.zig = ZigSvc

return M
