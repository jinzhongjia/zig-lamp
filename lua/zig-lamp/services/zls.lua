local Config = require("zig-lamp.config")
local Log = require("zig-lamp.log")
local System = require("zig-lamp.system")
local Zig = require("zig-lamp.services.zig")
local FFI = require("zig-lamp.services.ffi")

local META_URL = "https://releases.zigtools.org/v1/zls/select-version"

local Zls = {}

local state = {
    initialized = false,
    lsp_initialized = false,
    using_system = false,
    current_version = nil,
    db = { version_map = {} },
    paths = nil,
}

local meta_errors = {
    [0] = "当前 Zig 版本暂不支持 ZLS",
    [1] = "ZLS 版本仍在构建，稍后再试",
    [2] = "当前开发版本不兼容",
    [3] = "标签版本不兼容",
}

local function ensure_paths()
    if state.paths then
        return state.paths
    end
    local paths = Config.paths()
    local data_dir = vim.fs.joinpath(paths.data, "zls")
    local tmp_dir = paths.tmp
    local db_file = vim.fs.joinpath(paths.data, "zlsdb.json")
    System.ensure_dir(data_dir)
    System.ensure_dir(tmp_dir)
    state.paths = {
        store = data_dir,
        tmp = tmp_dir,
        db = db_file,
    }
    return state.paths
end

local function read_file(path)
    return System.read_file(path)
end

local function write_file(path, content)
    local ok, err = System.write_file(path, content)
    if not ok then
        Log.error("写入文件失败", { path = path, error = err })
    end
    return ok
end

local function load_db()
    local paths = ensure_paths()
    local content = read_file(paths.db)
    if not content or content == "" then
        state.db = { version_map = {} }
        return
    end
    local ok, decoded = pcall(vim.fn.json_decode, content)
    if not ok or type(decoded) ~= "table" then
        state.db = { version_map = {} }
        return
    end
    state.db = decoded
    state.db.version_map = state.db.version_map or {}
end

local function save_db()
    local paths = ensure_paths()
    local ok, encoded = pcall(vim.fn.json_encode, state.db)
    if not ok then
        Log.error("保存 zls 数据库失败", { error = encoded })
        return false
    end
    return write_file(paths.db, encoded)
end

local function store_for_version(version)
    local paths = ensure_paths()
    return vim.fs.joinpath(paths.store, version)
end

local function executable_for_version(version)
    local dir = store_for_version(version)
    return vim.fs.joinpath(dir, System.executable_name("zls"))
end

local function mapping_for_zig(zig_version)
    if not zig_version then
        return nil
    end
    return state.db.version_map[zig_version]
end

local function set_mapping(zig_version, zls_version)
    state.db.version_map[zig_version] = zls_version
    save_db()
end

local function remove_mapping_for_version(zls_version)
    for zig_version, mapped in pairs(state.db.version_map) do
        if mapped == zls_version then
            state.db.version_map[zig_version] = nil
        end
    end
    save_db()
end

local function verify_local_version(version)
    local exec_path = executable_for_version(version)
    if not System.is_file(exec_path) then
        return false
    end
    local result = System.run(exec_path, { "--version" }, { timeout = 5000 })
    if result.code ~= 0 then
        return false
    end
    return vim.trim(result.stdout or "") == version
end

local function list_local_versions()
    local paths = ensure_paths()
    if not System.is_dir(paths.store) then
        return {}
    end
    local entries = System.list_dir(paths.store)
    local versions = {}
    for _, entry in ipairs(entries) do
        if entry.type == "directory" then
            table.insert(versions, entry.name)
        end
    end
    table.sort(versions)
    return versions
end

local function arch_key()
    local info = System.info()
    return string.format("%s-%s", info.arch, info.os)
end

local function default_zls_settings()
    return {
        zls = {
            enable_snippets = true,
            enable_argument_placeholders = true,
            completion_label_details = true,
            semantic_tokens = "full",
            prefer_ast_check_as_child_process = true,
            warn_style = true,
            highlight_global_var_declarations = true,
            enable_build_on_save = true,
            build_on_save_args = {},
            inlay_hints_show_variable_type_hints = true,
            inlay_hints_show_struct_literal_field_type = true,
            inlay_hints_show_parameter_name = true,
            inlay_hints_show_builtin = true,
            inlay_hints_exclude_single_argument = true,
            inlay_hints_hide_redundant_param_names = false,
            inlay_hints_hide_redundant_param_names_last_token = false,
            skip_std_references = false,
        },
    }
end

local function apply_builtin_lsp_config(cmd)
    local user_opt = Config.get("zls.lsp_opt") or {}
    local user_settings = Config.get("zls.settings") or {}
    local settings = vim.tbl_deep_extend("force", default_zls_settings(), user_settings)
    local config = vim.tbl_deep_extend("force", {
        cmd = { cmd },
        filetypes = { "zig" },
        root_markers = { { "zls.json", "build.zig" }, ".git" },
        on_new_config = function(new_config, new_root_dir)
            local cfg_cmd = cmd
            local config_path = vim.fs.joinpath(new_root_dir, "zls.json")
            if vim.fn.filereadable(config_path) == 1 then
                new_config.cmd = { cfg_cmd, "--config-path", "zls.json" }
            else
                new_config.cmd = { cfg_cmd }
            end
        end,
        settings = settings,
    }, user_opt)

    if vim.lsp and vim.lsp.config then
        if type(vim.lsp.config) == "function" then
            vim.lsp.config("zls", config)
        else
            vim.lsp.config.zls = config
        end
        local ok, err = pcall(vim.lsp.enable, "zls")
        if not ok then
            Log.error("启用内置 LSP 失败", { error = err })
            return false
        end
        return true
    end
    return false
end

local function apply_lspconfig(cmd)
    local ok, lspconfig = pcall(require, "lspconfig")
    if not ok then
        Log.error("未找到 lspconfig", { error = lspconfig })
        return false
    end
    local user_opt = Config.get("zls.lsp_opt") or {}
    local user_settings = Config.get("zls.settings") or {}
    local settings = vim.tbl_deep_extend("force", default_zls_settings(), user_settings)
    local config = vim.tbl_deep_extend("force", {
        autostart = false,
        cmd = { cmd },
        filetypes = { "zig" },
        on_new_config = function(new_config, new_root_dir)
            local config_path = vim.fs.joinpath(new_root_dir, "zls.json")
            if vim.fn.filereadable(config_path) == 1 then
                new_config.cmd = { cmd, "--config-path", "zls.json" }
            else
                new_config.cmd = { cmd }
            end
        end,
        settings = settings,
    }, user_opt)
    lspconfig.zls.setup(config)
    return true
end

local function setup_lsp(cmd, source_version)
    if apply_builtin_lsp_config(cmd) or apply_lspconfig(cmd) then
        state.current_version = source_version
        state.using_system = not source_version
        state.lsp_initialized = true
        Log.info("ZLS 已配置", { version = source_version or "system" })
    end
end

function Zls.launch(bufnr)
    if vim.lsp and vim.lsp.enable then
        local ok, err = pcall(vim.lsp.enable, "zls")
        if not ok then
            Log.error("启动内置 LSP 失败", { error = err })
        end
        return
    end
    local ok, configs = pcall(require, "lspconfig.configs")
    if ok and configs.zls and configs.zls.launch then
        configs.zls.launch(bufnr)
    end
end

local function download_destination(version, url)
    local ext = url:match("(%.[%w%.]+)$") or ".tar.gz"
    ext = ext:gsub("^%.", "")
    return vim.fs.joinpath(ensure_paths().tmp, string.format("%s.%s", version, ext))
end

local function download_archive(version, arch_info, callback)
    local dest = download_destination(version, arch_info.tarball)
    System.remove(dest)

    local function handle_exit(code, _, stderr)
        if code ~= 0 then
            callback(false, dest, stderr)
            return
        end
        if arch_info.shasum and FFI.available() then
            if not FFI.check_shasum(dest, arch_info.shasum) then
                System.remove(dest)
                callback(false, dest, "checksum mismatch")
                return
            end
        end
        callback(true, dest)
    end

    if System.which("curl") then
        System.spawn("curl", {
            "-L",
            "--fail",
            "--silent",
            "--show-error",
            "-o",
            dest,
            arch_info.tarball,
        }, {
            on_exit = handle_exit,
        })
    elseif System.info().is_windows then
        local ps_cmd = string.format('Invoke-WebRequest -Uri "%s" -OutFile "%s"', arch_info.tarball, dest)
        System.spawn("powershell", { "-Command", ps_cmd }, { on_exit = handle_exit })
    else
        callback(false, dest, "curl not available")
    end
end

local function find_executable(root)
    local exec_name = System.executable_name("zls")
    local direct = vim.fs.joinpath(root, exec_name)
    if System.is_file(direct) then
        return direct
    end
    local matches = vim.fs.find(exec_name, { path = root, type = "file", limit = 1 })
    if matches and matches[1] then
        return matches[1]
    end
    return nil
end

local function move_into_store(store, path)
    local target = vim.fs.joinpath(store, System.executable_name("zls"))
    if path == target then
        return true
    end
    local ok, err = os.rename(path, target)
    if not ok then
        Log.error("移动 ZLS 可执行文件失败", { error = err })
        return false
    end
    return true
end

local function extract_archive(version, archive_path, callback)
    local store = store_for_version(version)
    System.remove(store, true)
    System.ensure_dir(store)
    local info = System.info()
    local exec_name = System.executable_name("zls")
    local cmd
    local args

    if archive_path:lower():match("%.zip$") then
        if System.which("unzip") then
            cmd = "unzip"
            args = { "-o", archive_path, exec_name, "-d", store }
        elseif info.is_windows then
            cmd = "powershell"
            args = {
                "-Command",
                string.format('Expand-Archive -LiteralPath "%s" -DestinationPath "%s" -Force', archive_path, store),
            }
        else
            callback(false, "missing unzip tool")
            return
        end
    else
        cmd = "tar"
        args = { "-xf", archive_path, "-C", store, exec_name }
    end

    System.spawn(cmd, args, {
        on_exit = function(code, _, stderr)
            if code ~= 0 then
                callback(false, stderr)
                return
            end
            local exec_path = find_executable(store)
            if not exec_path then
                callback(false, "无法定位 zls 可执行文件")
                return
            end
            if not move_into_store(store, exec_path) then
                callback(false, "无法移动 zls 可执行文件")
                return
            end
            callback(true)
        end,
    })
end

local function after_install(version)
    local exec = executable_for_version(version)
    if not System.is_file(exec) then
        Log.error("未找到 ZLS 可执行文件", { path = exec })
        return
    end
    if Config.get("zls.auto_setup") == false then
        return
    end
    setup_lsp(exec, version)
end

local function fetch_metadata(zig_version)
    local timeout = Config.get("zls.fetch_timeout") or 30000
    local res = System.http_get(META_URL, {
        query = { zig_version = zig_version, compatibility = "only-runtime" },
        timeout = timeout,
    })
    if res.code ~= 0 then
        Log.error("获取 ZLS 元数据失败", { stderr = res.stderr })
        return nil
    end
    local ok, info = pcall(vim.fn.json_decode, res.stdout)
    if not ok then
        Log.error("解析 ZLS 元数据失败", { error = info })
        return nil
    end
    if info.code and meta_errors[info.code] then
        Log.warn(meta_errors[info.code])
        return nil
    end
    return info
end

local function install_flow(zig_version)
    local info = fetch_metadata(zig_version)
    if not info then
        return
    end
    local arch_info = info[arch_key()]
    if not arch_info then
        Log.error("不支持的体系结构", { arch = arch_key() })
        return
    end

    Log.info(string.format("开始下载 ZLS %s", info.version))
    download_archive(info.version, arch_info, function(ok, archive_path, err)
        if not ok then
            Log.error("下载 ZLS 失败", { error = err })
            return
        end
        extract_archive(info.version, archive_path, function(extracted, extract_err)
            System.remove(archive_path)
            if not extracted then
                Log.error("解压 ZLS 失败", { error = extract_err })
                return
            end
            if verify_local_version(info.version) then
                set_mapping(zig_version, info.version)
                Log.info("ZLS 安装完成", { version = info.version })
                after_install(info.version)
            else
                Log.error("ZLS 安装后校验失败")
            end
        end)
    end)
end

function Zls.bootstrap()
    if state.initialized then
        return
    end
    ensure_paths()
    load_db()
    state.initialized = true
end

function Zls.install()
    Zls.bootstrap()
    local zig_version = Zig.version()
    if not zig_version then
        Log.warn("无法获取 Zig 版本，终止安装")
        return
    end
    local mapped = mapping_for_zig(zig_version)
    if mapped and verify_local_version(mapped) then
        Log.info("ZLS 已存在，无需重复安装", { version = mapped, zig = zig_version })
        return
    end
    install_flow(zig_version)
end

function Zls.uninstall(args)
    Zls.bootstrap()
    local version = args and args[1]
    if not version then
        Log.warn("请提供要卸载的 ZLS 版本")
        return
    end
    local versions = list_local_versions()
    if not vim.tbl_contains(versions, version) then
        Log.warn("未找到指定版本", { version = version })
        return
    end
    System.remove(store_for_version(version), true)
    remove_mapping_for_version(version)
    if state.current_version == version then
        state.current_version = nil
        state.lsp_initialized = false
    end
    Log.info("已卸载 ZLS", { version = version })
end

function Zls.status()
    Zls.bootstrap()
    local zig_version = Zig.version()
    local sys_available = System.which("zls")
    local sys_version = nil
    if sys_available then
        local result = System.run("zls", { "--version" }, { timeout = 3000 })
        if result.code == 0 then
            sys_version = vim.trim(result.stdout or "")
        end
    end
    return {
        zig_version = zig_version,
        current_zls_version = state.current_version,
        using_system_zls = state.using_system,
        lsp_initialized = state.lsp_initialized,
        available_local_versions = list_local_versions(),
        system_zls_available = sys_available,
        system_zls_version = sys_version,
    }
end

function Zls.ensure_started()
    Zls.bootstrap()
    if state.lsp_initialized then
        Zls.launch()
        return
    end
    local zig_version = Zig.version()
    local mapped = mapping_for_zig(zig_version)
    if mapped and verify_local_version(mapped) then
        setup_lsp(executable_for_version(mapped), mapped)
        Zls.launch()
        return
    end

    if Config.get("zls.fall_back_sys") and System.which("zls") then
        setup_lsp("zls", nil)
        Zls.launch()
        return
    end

    local auto = Config.get("zls.auto_install")
    if auto then
        Zls.install()
    else
        Log.warn('未找到本地 ZLS，请执行 ":ZigLamp zls install"')
    end
end

function Zls.local_versions()
    return list_local_versions()
end

return Zls

