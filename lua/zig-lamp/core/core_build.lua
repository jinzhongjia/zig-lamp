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

--- Run `zig build` in current project, forwarding user args as-is
---@param user_args string[] list of args passed after `build`
---@param callback function|nil completion callback (success:boolean, stdout:string, stderr:string)
---@return boolean success started
function M.build_project(user_args, callback)
    user_args = user_args or {}
    if #user_args > 0 then
        table.remove(user_args, 1) -- Remove first arg if it's "build"
    end

    local zig_available = select(1, check_zig())
    if not zig_available then
        util.Error("Zig is not available", { suggestion = "Please ensure Zig is installed and in PATH" })
        if callback then
            callback(false, "", "zig not available")
        end
        return false
    end

    local project_root = find_project_root()
    if not project_root then
        util.Error("build.zig not found", { suggestion = "Please run inside a Zig project directory" })
        if callback then
            callback(false, "", "build.zig not found")
        end
        return false
    end

    local job = require("plenary.job")

    local args = { "build" }
    for _, a in ipairs(user_args) do
        table.insert(args, a)
    end

    util.Info("Running build command: zig " .. table.concat(args, " "))

    job:new({
        command = "zig",
        args = args,
        cwd = project_root,
        on_exit = function(j, return_val)
            local stdout = table.concat(j:result(), "\n")
            local stderr = table.concat(j:stderr_result(), "\n")
            if return_val == 0 then
                require("zig-lamp.core.core_error").notify_always("Project build succeeded", vim.log.levels.INFO)
                if callback then
                    callback(true, stdout, stderr)
                end
            else
                util.Error("Project build failed", { error = stderr or stdout })
                if callback then
                    callback(false, stdout, stderr)
                end
            end
        end,
    }):start()

    return true
end

--- Run `zig build test` in current project, forwarding user args as-is
---@param user_args string[] list of args passed after `test`
---@param callback function|nil completion callback (success:boolean, stdout:string, stderr:string)
---@return boolean success started
function M.test_project(user_args, callback)
    user_args = user_args or {}

    local zig_available = select(1, check_zig())
    if not zig_available then
        util.Error("Zig is not available", { suggestion = "Please ensure Zig is installed and in PATH" })
        if callback then
            callback(false, "", "zig not available")
        end
        return false
    end

    local project_root = find_project_root()
    if not project_root then
        util.Error("build.zig not found", { suggestion = "Please run inside a Zig project directory" })
        if callback then
            callback(false, "", "build.zig not found")
        end
        return false
    end

    local job = require("plenary.job")

    local args = { "build", "test" }
    for _, a in ipairs(user_args) do
        table.insert(args, a)
    end

    util.Info("Running test command: zig " .. table.concat(args, " "))

    job:new({
        command = "zig",
        args = args,
        cwd = project_root,
        on_exit = function(j, return_val)
            local stdout = table.concat(j:result(), "\n")
            local stderr = table.concat(j:stderr_result(), "\n")
            if return_val == 0 then
                require("zig-lamp.core.core_error").notify_always("Project tests passed", vim.log.levels.INFO)
                if callback then
                    callback(true, stdout, stderr)
                end
            else
                util.Error("Project tests failed", { error = stderr or stdout })
                if callback then
                    callback(false, stdout, stderr)
                end
            end
        end,
    }):start()

    return true
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

    -- Find project root
    local project_root = find_project_root()
    if not project_root then
        util.Error("build.zig not found", {
            suggestion = "Please run the build command inside a Zig project directory",
        })
        return false
    end

    util.Info("Project root: " .. project_root)

    -- Clean before build (if requested)
    if options.clean then
        util.Info("Cleaning build outputs...")
        if not clean_build(project_root) then
            util.Warn("Errors occurred during clean step, continuing build...")
        end
    end

    -- Prepare build command
    local args = { "build" }

    -- Add optimization option
    if options.optimization then
        table.insert(args, "-Doptimize=" .. options.optimization)
    end

    -- Add target platform option
    if options.target then
        table.insert(args, "-Dtarget=" .. options.target)
    end

    -- Add verbose flag
    if options.verbose then
        table.insert(args, "--verbose")
    end

    local cmd_str = "zig " .. table.concat(args, " ")
    util.Info("Running build command: " .. cmd_str)

    -- 执行构建
    if options.mode == "sync" then
        -- 同步构建
        local result = platform.execute("zig", args, {
            cwd = project_root,
            timeout = options.timeout,
        })

        if result.code == 0 then
            util.Info("Build succeeded")
            if callback then
                callback(true, result.stdout)
            end
            return true
        else
            util.Error("Build failed", {
                error = result.stderr or result.stdout,
                suggestion = "Please check build errors and fix them",
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
                    util.Info("Build succeeded")
                    if callback then
                        callback(true, stdout)
                    end
                else
                    util.Error("Build failed", {
                        error = stderr or stdout,
                        suggestion = "Please check build errors and fix them",
                    })
                    if callback then
                        callback(false, stderr or stdout)
                    end
                end
            end,
            on_stdout = function(_, data)
                if options.verbose and data then
                    print("[build] " .. data)
                end
            end,
            on_stderr = function(_, data)
                if options.verbose and data then
                    print("[build:error] " .. data)
                end
            end,
        }):start()

        util.Info("Async build started...")
        return true
    end
end

--- 构建共享库
---@param options BuildOptions|nil 构建选项
---@param callback function|nil 完成回调
---@return boolean success 是否开始构建成功
function M.build_library(options, callback)
    options = options or {}
    local mode = options.mode or "async"
    local timeout = options.timeout
    local verbose = options.verbose == true

    -- Detect plugin root (where zig-lamp build.zig resides)
    local ok_ffi, core_ffi = pcall(require, "zig-lamp.core.core_ffi")
    if not ok_ffi then
        util.Error("Failed to load core_ffi for plugin root detection")
        return false
    end
    local plugin_root = core_ffi.get_plugin_path()
    if not plugin_root or plugin_root == "" then
        util.Error("Failed to detect plugin root path")
        return false
    end

    local zig_available = select(1, check_zig())
    if not zig_available then
        util.Error("Zig is not available", { suggestion = "Please ensure Zig is installed and in PATH" })
        return false
    end

    -- Prepare args for plugin build
    local args = { "build" }
    if options.optimization then
        table.insert(args, "-Doptimize=" .. options.optimization)
    end
    if options.target then
        table.insert(args, "-Dtarget=" .. options.target)
    end
    if verbose then
        table.insert(args, "--verbose")
    end

    util.Info("Running plugin library build: zig " .. table.concat(args, " "))

    local function post_check(success, out)
        if success then
            local lib_name = platform.library_name("zig-lamp")
            local lib_paths = {
                platform.join_path(plugin_root, "zig-out", "lib", lib_name),
                platform.join_path(plugin_root, "zig-out", "bin", lib_name),
            }
            local lib_found = false
            for _, lib_path in ipairs(lib_paths) do
                if platform.is_file(lib_path) then
                    util.Info("Library file generated: " .. lib_path)
                    lib_found = true
                    break
                end
            end
            if not lib_found then
                util.Warn("Build succeeded but no library file was found", {
                    suggestion = "Please check your build.zig outputs/installation step",
                })
            end
        end
        if callback then
            callback(success, out)
        end
    end

    if mode == "sync" then
        local result = platform.execute("zig", args, { cwd = plugin_root, timeout = timeout })
        if result.code == 0 then
            require("zig-lamp.core.core_error").notify_always("Plugin library build succeeded", vim.log.levels.INFO)
            post_check(true, result.stdout)
            return true
        else
            util.Error("Plugin library build failed", { error = result.stderr or result.stdout })
            post_check(false, result.stderr or result.stdout)
            return false
        end
    else
        local job = require("plenary.job")
        job:new({
            command = "zig",
            args = args,
            cwd = plugin_root,
            on_exit = function(j, return_val)
                local stdout = table.concat(j:result(), "\n")
                local stderr = table.concat(j:stderr_result(), "\n")
                if return_val == 0 then
                    require("zig-lamp.core.core_error").notify_always(
                        "Plugin library build succeeded",
                        vim.log.levels.INFO
                    )
                    post_check(true, stdout)
                else
                    util.Error("Plugin library build failed", { error = stderr or stdout })
                    post_check(false, stderr or stdout)
                end
            end,
        }):start()
        return true
    end
end

--- Clean build artifacts only (zig-out, zig-cache)
---@param callback function|nil completion callback (success:boolean)
---@return boolean success
function M.clean(callback)
    local project_root = find_project_root()
    if not project_root then
        util.Error("build.zig not found", {
            suggestion = "Please run the clean command inside a Zig project directory",
        })
        if callback then
            callback(false)
        end
        return false
    end

    util.Info("Cleaning build outputs...")

    local zig_out = platform.join_path(project_root, "zig-out")
    local zig_cache = platform.join_path(project_root, "zig-cache")
    local had_any = platform.exists(zig_out) or platform.exists(zig_cache)

    local ok = clean_build(project_root)
    if ok then
        if had_any then
            require("zig-lamp.core.core_error").notify_always("Clean completed", vim.log.levels.INFO)
        else
            require("zig-lamp.core.core_error").notify_always("Nothing to clean", vim.log.levels.INFO)
        end
        if callback then
            callback(true)
        end
        return true
    else
        util.Warn("Errors occurred during clean step")
        if callback then
            callback(false)
        end
        return false
    end
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
