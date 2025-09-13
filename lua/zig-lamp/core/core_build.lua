-- Cross-platform build module
-- Handles Zig project build process with support for different platforms

local vim = vim
local platform = require("zig-lamp.core.core_platform")
local util = require("zig-lamp.core.core_util")

local M = {}

--- Build options
---@class BuildOptions
---@field mode string Build mode ("sync" | "async")
---@field timeout number|nil Timeout in milliseconds
---@field optimization string Optimization level
---@field target string|nil Target platform
---@field verbose boolean Whether to show verbose output
---@field clean boolean Whether to clean first

--- Default build options
local default_options = {
    mode = "async",
    timeout = 30000,
    optimization = "ReleaseFast",
    target = nil,
    verbose = false,
    clean = false,
}

--- 检查 Zig 是否可用
---@return boolean available Zig 是否可用
---@return string|nil version Zig 版本
local function check_zig()
    if not platform.executable_exists("zig") then
        return false, nil
    end

    local result = platform.execute("zig", { "version" })
    if result.code == 0 then
        local version = result.stdout:gsub("%s+", "")
        return true, version
    end

    return false, nil
end

--- 获取项目根目录
---@return string|nil root 项目根目录路径
local function find_project_root()
    local current_dir = vim.fn.getcwd()

    -- 查找 build.zig 文件
    while current_dir do
        local build_zig = platform.join_path(current_dir, "build.zig")
        if platform.is_file(build_zig) then
            return current_dir
        end

        local parent = vim.fs.dirname(current_dir)
        if parent == current_dir then
            break
        end
        current_dir = parent
    end

    return nil
end

--- 清理构建输出
---@param project_root string 项目根目录
---@return boolean success 是否成功
local function clean_build(project_root)
    local zig_out = platform.join_path(project_root, "zig-out")
    local zig_cache = platform.join_path(project_root, "zig-cache")

    local success = true

    if platform.exists(zig_out) then
        local ok, err = platform.remove(zig_out, true)
        if not ok then
            util.Error("Failed to clean zig-out", { error = err })
            success = false
        end
    end

    if platform.exists(zig_cache) then
        local ok, err = platform.remove(zig_cache, true)
        if not ok then
            util.Error("Failed to clean zig-cache", { error = err })
            success = false
        end
    end

    return success
end

--- 构建 Zig 项目
---@param options BuildOptions|nil 构建选项
---@param callback function|nil 完成回调
---@return boolean success 是否开始构建成功
function M.build(options, callback)
    options = vim.tbl_extend("force", default_options, options or {})

    -- 检查 Zig
    local zig_available, zig_version = check_zig()
    if not zig_available then
        util.Error("Zig is not available", {
            suggestion = "Please ensure Zig is installed and in PATH",
        })
        return false
    end

    util.Info("Using Zig version: " .. (zig_version or "unknown"))

    -- 查找项目根目录
    local project_root = find_project_root()
    if not project_root then
        util.Error("未找到 build.zig 文件", {
            suggestion = "请确保在 Zig 项目目录中运行构建命令",
        })
        return false
    end

    util.Info("项目根目录: " .. project_root)

    -- 清理构建（如果需要）
    if options.clean then
        util.Info("清理构建输出...")
        if not clean_build(project_root) then
            util.Warn("清理过程中出现错误，继续构建...")
        end
    end

    -- 准备构建命令
    local args = { "build" }

    -- 添加优化选项
    if options.optimization then
        table.insert(args, "-Doptimize=" .. options.optimization)
    end

    -- 添加目标平台
    if options.target then
        table.insert(args, "-Dtarget=" .. options.target)
    end

    -- 添加详细输出
    if options.verbose then
        table.insert(args, "--verbose")
    end

    local cmd_str = "zig " .. table.concat(args, " ")
    util.Info("执行构建命令: " .. cmd_str)

    -- 执行构建
    if options.mode == "sync" then
        -- 同步构建
        local result = platform.execute("zig", args, {
            cwd = project_root,
            timeout = options.timeout,
        })

        if result.code == 0 then
            util.Info("构建成功")
            if callback then
                callback(true, result.stdout)
            end
            return true
        else
            util.Error("构建失败", {
                error = result.stderr or result.stdout,
                suggestion = "请检查构建错误并修复",
            })
            if callback then
                callback(false, result.stderr or result.stdout)
            end
            return false
        end
    else
        -- 异步构建
        local job = require("plenary.job")

        job:new({
            command = "zig",
            args = args,
            cwd = project_root,
            on_exit = function(j, return_val)
                local stdout = table.concat(j:result(), "\n")
                local stderr = table.concat(j:stderr_result(), "\n")

                if return_val == 0 then
                    util.Info("构建成功")
                    if callback then
                        callback(true, stdout)
                    end
                else
                    util.Error("构建失败", {
                        error = stderr or stdout,
                        suggestion = "请检查构建错误并修复",
                    })
                    if callback then
                        callback(false, stderr or stdout)
                    end
                end
            end,
            on_stdout = function(_, data)
                if options.verbose and data then
                    print("[构建] " .. data)
                end
            end,
            on_stderr = function(_, data)
                if options.verbose and data then
                    print("[构建错误] " .. data)
                end
            end,
        }):start()

        util.Info("异步构建已启动...")
        return true
    end
end

--- 构建共享库
---@param options BuildOptions|nil 构建选项
---@param callback function|nil 完成回调
---@return boolean success 是否开始构建成功
function M.build_library(options, callback)
    options = options or {}
    options.verbose = true -- 库构建通常需要详细输出

    return M.build(options, function(success, output)
        if success then
            -- 检查库文件是否生成
            local project_root = find_project_root()
            if project_root then
                local lib_name = platform.library_name("zig-lamp")
                local lib_paths = {
                    platform.join_path(project_root, "zig-out", "lib", lib_name),
                    platform.join_path(project_root, "zig-out", "bin", lib_name),
                }

                local lib_found = false
                for _, lib_path in ipairs(lib_paths) do
                    if platform.is_file(lib_path) then
                        util.Info("库文件已生成: " .. lib_path)
                        lib_found = true
                        break
                    end
                end

                if not lib_found then
                    util.Warn("构建成功但未找到库文件", {
                        suggestion = "请检查 build.zig 配置",
                    })
                end
            end
        end

        if callback then
            callback(success, output)
        end
    end)
end

--- 运行测试
---@param options BuildOptions|nil 构建选项
---@param callback function|nil 完成回调
---@return boolean success 是否开始测试成功
function M.test(options, callback)
    options = vim.tbl_extend("force", default_options, options or {})

    local project_root = find_project_root()
    if not project_root then
        util.Error("未找到项目根目录")
        return false
    end

    local args = { "build", "test" }

    if options.verbose then
        table.insert(args, "--verbose")
    end

    util.Info("运行测试...")

    if options.mode == "sync" then
        local result = platform.execute("zig", args, {
            cwd = project_root,
            timeout = options.timeout,
        })

        local success = result.code == 0
        if success then
            util.Info("测试通过")
        else
            util.Error("测试失败", { error = result.stderr })
        end

        if callback then
            callback(success, result.stdout, result.stderr)
        end

        return success
    else
        local job = require("plenary.job")

        job:new({
            command = "zig",
            args = args,
            cwd = project_root,
            on_exit = function(j, return_val)
                local stdout = table.concat(j:result(), "\n")
                local stderr = table.concat(j:stderr_result(), "\n")

                if return_val == 0 then
                    util.Info("测试通过")
                else
                    util.Error("测试失败", { error = stderr })
                end

                if callback then
                    callback(return_val == 0, stdout, stderr)
                end
            end,
        }):start()

        return true
    end
end

--- 获取构建信息
---@return table info 构建信息
function M.get_build_info()
    local project_root = find_project_root()
    local zig_available, zig_version = check_zig()

    return {
        project_root = project_root,
        zig_available = zig_available,
        zig_version = zig_version,
        platform = platform.get_system_info(),
        has_build_zig = project_root and platform.is_file(platform.join_path(project_root, "build.zig")) or false,
    }
end

return M
