local Log = require("zig-lamp.log")
local System = require("zig-lamp.system")
local FFI = require("zig-lamp.services.ffi")

local Build = {}

local function has_zig()
    return vim.fn.executable("zig") == 1
end

local function find_project_root(start_dir)
    local current = start_dir or vim.fn.getcwd()
    while current and current ~= "" do
        if System.is_file(vim.fs.joinpath(current, "build.zig")) then
            return current
        end
        local parent = vim.fs.dirname(current)
        if parent == current then
            break
        end
        current = parent
    end
    return nil
end

function Build.project(user_args)
    if not has_zig() then
        Log.error("未检测到 zig 可执行文件")
        return false
    end
    local root = find_project_root()
    if not root then
        Log.error("未找到 build.zig，请在 Zig 项目中执行")
        return false
    end
    local args = { "build" }
    if user_args and #user_args > 0 then
        vim.list_extend(args, user_args)
    end
    System.spawn("zig", args, {
        cwd = root,
        on_exit = function(code, stdout, stderr)
            if code == 0 then
                Log.info("项目构建完成")
            else
                Log.error("项目构建失败", { stderr = stderr, stdout = stdout })
            end
        end,
    })
    return true
end

function Build.test(user_args)
    if not has_zig() then
        Log.error("未检测到 zig 可执行文件")
        return false
    end
    local root = find_project_root()
    if not root then
        Log.error("未找到 build.zig，请在 Zig 项目中执行")
        return false
    end
    local args = { "build", "test" }
    if user_args and #user_args > 0 then
        vim.list_extend(args, user_args)
    end
    System.spawn("zig", args, {
        cwd = root,
        on_exit = function(code, stdout, stderr)
            if code == 0 then
                Log.info("测试通过")
            else
                Log.error("测试失败", { stderr = stderr, stdout = stdout })
            end
        end,
    })
    return true
end

function Build.clean()
    local root = find_project_root()
    if not root then
        Log.error("未找到 build.zig，请在 Zig 项目中执行")
        return false
    end
    local out_dir = vim.fs.joinpath(root, "zig-out")
    local cache_dir = vim.fs.joinpath(root, "zig-cache")
    local removed = false
    if System.exists(out_dir) then
        System.remove(out_dir, true)
        removed = true
    end
    if System.exists(cache_dir) then
        System.remove(cache_dir, true)
        removed = true
    end
    if removed then
        Log.info("已清理 zig-out 与 zig-cache")
    else
        Log.info("无需清理")
    end
    return true
end

local function build_plugin(args)
    if not has_zig() then
        Log.error("未检测到 zig，可执行 zig build 失败")
        return
    end

    local plugin_root = FFI.plugin_path()
    if not plugin_root then
        Log.error("无法定位插件根目录")
        return
    end

    local command_args = { "build" }
    if args.optimization then
        table.insert(command_args, "-Doptimize=" .. args.optimization)
    end
    if args.target then
        table.insert(command_args, "-Dtarget=" .. args.target)
    end
    if args.verbose then
        table.insert(command_args, "--verbose")
    end

    System.spawn("zig", command_args, {
        cwd = plugin_root,
        on_exit = function(code, stdout, stderr)
            if code == 0 then
                Log.info("本地 FFI 库构建成功")
            else
                Log.error("本地 FFI 库构建失败", { stderr = stderr, stdout = stdout })
            end
        end,
    })
end

function Build.plugin_library(opts)
    opts = opts or {}
    build_plugin({
        optimization = opts.optimization or "ReleaseFast",
        target = opts.target,
        verbose = opts.verbose,
    })
end

return Build

