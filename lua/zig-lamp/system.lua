local vim = vim
local uv = vim.uv or vim.loop

local System = {}

local function detect_os()
    if vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1 then
        return "windows"
    elseif vim.fn.has("macunix") == 1 then
        return "macos"
    elseif vim.fn.has("unix") == 1 then
        return "linux"
    end
    return "unknown"
end

local function detect_arch()
    local machine = uv.os_uname().machine
    if machine == "arm64" then
        return "aarch64"
    elseif machine == "AMD64" then
        return "x86_64"
    end
    return machine
end

local os_name = detect_os()
local arch_name = detect_arch()
local path_sep = (os_name == "windows") and "\\" or "/"
local exe_ext = (os_name == "windows") and ".exe" or ""
local lib_ext = (os_name == "windows") and ".dll" or (os_name == "macos" and ".dylib" or ".so")
local lib_prefix = (os_name == "windows") and "" or "lib"

function System.info()
    local uname = uv.os_uname()
    return {
        os = os_name,
        arch = arch_name,
        sysname = uname.sysname,
        release = uname.release,
        version = uname.version,
        machine = uname.machine,
        path_sep = path_sep,
        exe_ext = exe_ext,
        lib_ext = lib_ext,
        lib_prefix = lib_prefix,
        is_windows = os_name == "windows",
        is_macos = os_name == "macos",
        is_linux = os_name == "linux",
    }
end

function System.normalize(path)
    return path and vim.fs.normalize(path) or path
end

function System.join(...)
    return System.normalize(table.concat({ ... }, path_sep))
end

function System.executable_name(name)
    return string.format("%s%s", name, exe_ext)
end

function System.library_name(name)
    return string.format("%s%s%s", lib_prefix, name, lib_ext)
end

function System.ensure_dir(path)
    if not path or path == "" then
        return true
    end
    local ok, err = pcall(vim.fn.mkdir, path, "p")
    return ok, ok and nil or err
end

function System.exists(path)
    return path and uv.fs_stat(path) ~= nil
end

function System.is_file(path)
    local stat = path and uv.fs_stat(path)
    return stat and stat.type == "file" or false
end

function System.is_dir(path)
    local stat = path and uv.fs_stat(path)
    return stat and stat.type == "directory" or false
end

function System.remove(path, recursive)
    if not path or path == "" then
        return true
    end
    if recursive and System.is_dir(path) then
        local handle = uv.fs_scandir(path)
        if handle then
            while true do
                local name, type = uv.fs_scandir_next(handle)
                if not name then
                    break
                end
                local target = System.join(path, name)
                if type == "directory" then
                    System.remove(target, true)
                else
                    uv.fs_unlink(target)
                end
            end
        end
        uv.fs_rmdir(path)
        return true
    end
    if System.is_dir(path) then
        return uv.fs_rmdir(path) == 0
    end
    return uv.fs_unlink(path) == 0
end

function System.which(binary)
    return vim.fn.executable(binary) == 1
end

function System.home_dir()
    if os_name == "windows" then
        return os.getenv("USERPROFILE") or os.getenv("HOME") or "C:\\"
    end
    return os.getenv("HOME") or "/tmp"
end

function System.temp_dir()
    local env = os.getenv("TMPDIR") or os.getenv("TEMP") or os.getenv("TMP")
    if env and env ~= "" then
        return env
    end
    return os_name == "windows" and "C:\\temp" or "/tmp"
end

local function build_command(cmd, args)
    if type(cmd) == "table" then
        return cmd
    end
    local command_line = { cmd }
    if args and #args > 0 then
        for _, value in ipairs(args) do
            table.insert(command_line, value)
        end
    end
    return command_line
end

local function system_opts(opts)
    opts = opts or {}
    return {
        cwd = opts.cwd,
        env = opts.env,
        text = opts.text ~= false,
        stdout = true,
        stderr = true,
    }
end

function System.run(cmd, args, opts)
    opts = opts or {}
    local command_line = build_command(cmd, args)
    local handle = vim.system(command_line, system_opts(opts))
    local timeout = opts.timeout and math.floor(opts.timeout / 1000) or nil
    local result = handle:wait(timeout)
    return {
        code = result.code or -1,
        stdout = result.stdout or "",
        stderr = result.stderr or "",
    }
end

function System.spawn(cmd, args, opts)
    opts = opts or {}
    local command_line = build_command(cmd, args)
    return vim.system(command_line, system_opts(opts), function(res)
        if opts.on_exit then
            opts.on_exit(res.code or -1, res.stdout or "", res.stderr or "")
        end
    end)
end

function System.read_file(path)
    local fd = uv.fs_open(path, "r", 420)
    if not fd then
        return nil
    end
    local stat = uv.fs_fstat(fd)
    if not stat then
        uv.fs_close(fd)
        return nil
    end
    local data = uv.fs_read(fd, stat.size, 0)
    uv.fs_close(fd)
    return data
end

function System.write_file(path, content)
    local fd, err = uv.fs_open(path, "w", 420)
    if not fd then
        return false, err
    end
    uv.fs_write(fd, content, 0)
    uv.fs_close(fd)
    return true
end

function System.find_upwards(filename, start_dir)
    local results = vim.fs.find(filename, {
        path = start_dir or uv.cwd(),
        upward = true,
        limit = 1,
    })
    if results and results[1] then
        return System.normalize(results[1])
    end
    return nil
end

function System.list_dir(path)
    local handle = uv.fs_scandir(path)
    if not handle then
        return {}
    end
    local entries = {}
    while true do
        local name, type = uv.fs_scandir_next(handle)
        if not name then
            break
        end
        table.insert(entries, { name = name, type = type })
    end
    table.sort(entries, function(a, b)
        return a.name < b.name
    end)
    return entries
end

function System.http_get(url, opts)
    opts = opts or {}
    if not System.which("curl") then
        return { code = -1, stderr = "curl not available" }
    end
    local args = { "-L", "--fail", "--silent", "--show-error", url }
    if opts.headers then
        for _, header in ipairs(opts.headers) do
            table.insert(args, 1, "-H")
            table.insert(args, 2, header)
        end
    end
    if opts.query and next(opts.query) then
        local query = {}
        for key, value in pairs(opts.query) do
            table.insert(query, string.format("%s=%s", key, value))
        end
        local suffix = table.concat(query, "&")
        local separator = url:find("?", 1, true) and "&" or "?"
        args[#args] = url .. separator .. suffix
    end
    return System.run("curl", args, { timeout = opts.timeout })
end

return System

