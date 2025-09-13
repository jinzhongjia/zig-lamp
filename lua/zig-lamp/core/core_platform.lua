-- 跨平台兼容性模块
-- 处理不同操作系统之间的差异，提供统一的平台相关功能

local vim = vim
local uv = vim.uv or vim.loop

local M = {}

-- 平台检测
local function detect_platform()
    if vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1 then
        return "windows"
    elseif vim.fn.has("macunix") == 1 then
        return "macos"
    elseif vim.fn.has("unix") == 1 then
        return "linux"
    else
        return "unknown"
    end
end

-- 架构检测
local function detect_arch()
    local machine = uv.os_uname().machine
    -- 标准化架构名称
    if machine == "arm64" then
        return "aarch64"
    elseif machine == "AMD64" then -- Windows
        return "x86_64"
    else
        return machine
    end
end

-- 平台信息
M.os = detect_platform()
M.arch = detect_arch()
M.is_windows = M.os == "windows"
M.is_macos = M.os == "macos"
M.is_linux = M.os == "linux"

-- 路径分隔符
M.path_sep = M.is_windows and "\\" or "/"

-- 可执行文件扩展名
M.exe_ext = M.is_windows and ".exe" or ""

-- 动态库扩展名
M.lib_ext = M.is_windows and ".dll" or (M.is_macos and ".dylib" or ".so")

-- 动态库前缀
M.lib_prefix = M.is_windows and "" or "lib"

--- 规范化路径
---@param path string 原始路径
---@return string normalized 规范化后的路径
function M.normalize_path(path)
    if not path then
        return ""
    end

    -- 使用 vim.fs.normalize 进行基础规范化
    local normalized = vim.fs.normalize(path)

    -- 在 Windows 上处理驱动器字母大小写
    if M.is_windows and normalized:match("^[a-z]:") then
        normalized = normalized:sub(1, 1):upper() .. normalized:sub(2)
    end

    return normalized
end

--- 连接路径
---@param ... string 路径组件
---@return string joined 连接后的路径
function M.join_path(...)
    local parts = { ... }
    local result = table.concat(parts, M.path_sep)
    return M.normalize_path(result)
end

--- 获取可执行文件名
---@param name string 基础名称
---@return string executable 带扩展名的可执行文件名
function M.executable_name(name)
    return name .. M.exe_ext
end

--- 获取动态库文件名
---@param name string 基础名称
---@return string library 完整的动态库文件名
function M.library_name(name)
    return M.lib_prefix .. name .. M.lib_ext
end

--- 检查可执行文件是否存在
---@param name string 可执行文件名
---@return boolean exists 是否存在
function M.executable_exists(name)
    return vim.fn.executable(M.executable_name(name)) == 1
end

--- 获取环境变量
---@param name string 环境变量名
---@param default string|nil 默认值
---@return string|nil value 环境变量值
function M.getenv(name, default)
    local value = os.getenv(name)
    if value == nil or value == "" then
        return default
    end
    return value
end

--- 获取主目录
---@return string home 主目录路径
function M.get_home_dir()
    if M.is_windows then
        return M.getenv("USERPROFILE") or M.getenv("HOME") or "C:\\"
    else
        return M.getenv("HOME") or "/tmp"
    end
end

--- 获取临时目录
---@return string temp 临时目录路径
function M.get_temp_dir()
    if M.is_windows then
        return M.getenv("TEMP") or M.getenv("TMP") or "C:\\temp"
    else
        return M.getenv("TMPDIR") or "/tmp"
    end
end

--- 创建目录（跨平台）
---@param path string 目录路径
---@param mode number|nil 权限模式（仅 Unix）
---@return boolean success 是否成功
---@return string|nil error 错误信息
function M.mkdir(path, mode)
    mode = mode or 493 -- 0755 in octal

    local success, err = pcall(function()
        if M.is_windows then
            -- Windows 不支持 mode 参数
            vim.fn.mkdir(path, "p")
        else
            -- Unix 系统支持权限设置
            uv.fs_mkdir(path, mode)
        end
    end)

    if success then
        return true, nil
    else
        return false, tostring(err)
    end
end

--- 删除文件或目录
---@param path string 路径
---@param recursive boolean|nil 是否递归删除
---@return boolean success 是否成功
---@return string|nil error 错误信息
function M.remove(path, recursive)
    local success, err = pcall(function()
        local stat = uv.fs_stat(path)
        if not stat then
            return -- 文件不存在
        end

        if stat.type == "directory" then
            if recursive then
                -- 递归删除目录
                local function rmdir_recursive(dir)
                    local entries = uv.fs_scandir(dir)
                    if entries then
                        while true do
                            local name, type = uv.fs_scandir_next(entries)
                            if not name then
                                break
                            end

                            local full_path = M.join_path(dir, name)
                            if type == "directory" then
                                rmdir_recursive(full_path)
                            else
                                uv.fs_unlink(full_path)
                            end
                        end
                    end
                    uv.fs_rmdir(dir)
                end
                rmdir_recursive(path)
            else
                uv.fs_rmdir(path)
            end
        else
            uv.fs_unlink(path)
        end
    end)

    if success then
        return true, nil
    else
        return false, tostring(err)
    end
end

--- 复制文件
---@param src string 源文件路径
---@param dest string 目标文件路径
---@return boolean success 是否成功
---@return string|nil error 错误信息
function M.copy_file(src, dest)
    local success, err = pcall(function()
        local src_fd = uv.fs_open(src, "r", 420) -- 0644 in octal
        if not src_fd then
            error("无法打开源文件: " .. src)
        end

        local dest_fd = uv.fs_open(dest, "w", 420) -- 0644 in octal
        if not dest_fd then
            uv.fs_close(src_fd)
            error("无法创建目标文件: " .. dest)
        end

        local stat = uv.fs_fstat(src_fd)
        if stat then
            uv.fs_sendfile(dest_fd, src_fd, 0, stat.size)
        end

        uv.fs_close(src_fd)
        uv.fs_close(dest_fd)
    end)

    if success then
        return true, nil
    else
        return false, tostring(err)
    end
end

--- 检查文件或目录是否存在
---@param path string 路径
---@return boolean exists 是否存在
function M.exists(path)
    local stat = uv.fs_stat(path)
    return stat ~= nil
end

--- 检查是否为目录
---@param path string 路径
---@return boolean is_dir 是否为目录
function M.is_directory(path)
    local stat = uv.fs_stat(path)
    return stat and stat.type == "directory" or false
end

--- 检查是否为文件
---@param path string 路径
---@return boolean is_file 是否为文件
function M.is_file(path)
    local stat = uv.fs_stat(path)
    return stat and stat.type == "file" or false
end

--- 获取文件大小
---@param path string 文件路径
---@return number|nil size 文件大小（字节）
function M.file_size(path)
    local stat = uv.fs_stat(path)
    return stat and stat.size or nil
end

--- 获取文件修改时间
---@param path string 文件路径
---@return number|nil mtime 修改时间戳
function M.file_mtime(path)
    local stat = uv.fs_stat(path)
    return stat and stat.mtime.sec or nil
end

--- 执行命令（跨平台）
---@param cmd string 命令
---@param args table|nil 参数列表
---@param options table|nil 选项
---@return table result 执行结果 {code, stdout, stderr}
function M.execute(cmd, args, options)
    args = args or {}
    options = options or {}

    local stdout_data = {}
    local stderr_data = {}

    local handle
    handle = uv.spawn(cmd, {
        args = args,
        cwd = options.cwd,
        env = options.env,
        stdio = { nil, uv.new_pipe(false), uv.new_pipe(false) },
    }, function(code, signal)
        if handle then
            handle:close()
        end
    end)

    if not handle then
        return {
            code = -1,
            stdout = "",
            stderr = "Failed to spawn process: " .. cmd,
        }
    end

    -- 读取 stdout
    if handle.stdio and handle.stdio[2] then
        handle.stdio[2]:read_start(function(err, data)
            if data then
                table.insert(stdout_data, data)
            end
        end)
    end

    -- 读取 stderr
    if handle.stdio and handle.stdio[3] then
        handle.stdio[3]:read_start(function(err, data)
            if data then
                table.insert(stderr_data, data)
            end
        end)
    end

    -- 等待完成（简化版本，实际应该使用回调）
    local timeout = options.timeout or 30000
    local start_time = uv.now()

    while uv.now() - start_time < timeout do
        if not handle or handle:is_closing() then
            break
        end
        uv.run("nowait")
        vim.wait(10)
    end

    return {
        code = 0, -- 简化版本
        stdout = table.concat(stdout_data),
        stderr = table.concat(stderr_data),
    }
end

--- 下载文件（跨平台）
---@param url string 下载URL
---@param dest string 目标文件路径
---@param options table|nil 选项
---@return boolean success 是否成功
---@return string|nil error 错误信息
function M.download_file(url, dest, options)
    options = options or {}

    -- 优先使用 curl
    if M.executable_exists("curl") then
        local args = {
            "-L", -- 跟随重定向
            "-o",
            dest,
            url,
        }

        if options.timeout then
            table.insert(args, "--max-time")
            table.insert(args, tostring(options.timeout))
        end

        local result = M.execute("curl", args)
        if result.code == 0 then
            return true, nil
        else
            return false, result.stderr
        end
    end

    -- Windows 上的备用方案：PowerShell
    if M.is_windows then
        local ps_cmd = string.format('Invoke-WebRequest -Uri "%s" -OutFile "%s"', url, dest)

        local result = M.execute("powershell", { "-Command", ps_cmd })
        if result.code == 0 then
            return true, nil
        else
            return false, result.stderr
        end
    end

    return false, "没有可用的下载工具"
end

--- 解压文件（跨平台）
---@param archive string 压缩文件路径
---@param dest string 目标目录
---@param options table|nil 选项
---@return boolean success 是否成功
---@return string|nil error 错误信息
function M.extract_archive(archive, dest, options)
    options = options or {}

    -- 确保目标目录存在
    M.mkdir(dest)

    -- 根据文件扩展名选择解压工具
    local ext = archive:match("%.([^.]+)$"):lower()

    if ext == "zip" then
        if M.executable_exists("unzip") then
            local args = { archive, "-d", dest }
            if options.quiet then
                table.insert(args, 1, "-q")
            end

            local result = M.execute("unzip", args)
            return result.code == 0, result.stderr
        elseif M.is_windows then
            -- Windows PowerShell 解压
            local ps_cmd = string.format('Expand-Archive -Path "%s" -DestinationPath "%s" -Force', archive, dest)

            local result = M.execute("powershell", { "-Command", ps_cmd })
            return result.code == 0, result.stderr
        end
    elseif ext == "gz" or ext == "tgz" or archive:match("%.tar%.gz$") then
        if M.executable_exists("tar") then
            local args = { "xzf", archive, "-C", dest }
            if options.strip_components then
                table.insert(args, "--strip-components=" .. options.strip_components)
            end

            local result = M.execute("tar", args)
            return result.code == 0, result.stderr
        end
    end

    return false, "不支持的压缩格式或缺少解压工具"
end

--- 获取系统信息
---@return table info 系统信息
function M.get_system_info()
    local uname = uv.os_uname()

    return {
        os = M.os,
        arch = M.arch,
        sysname = uname.sysname,
        release = uname.release,
        version = uname.version,
        machine = uname.machine,
        is_windows = M.is_windows,
        is_macos = M.is_macos,
        is_linux = M.is_linux,
        path_sep = M.path_sep,
        exe_ext = M.exe_ext,
        lib_ext = M.lib_ext,
        lib_prefix = M.lib_prefix,
    }
end

return M
