local cmd = require("zig-lamp.cmd")
local config = require("zig-lamp.config")
local curl = require("plenary.curl")
local job = require("plenary.job")
local path = require("plenary.path")
local scan = require("plenary.scandir")
local util = require("zig-lamp.util")
local zig = require("zig-lamp.module.zig")
local zig_ffi = require("zig-lamp.ffi")
local M = {}

local lsp_is_initialized = false

local if_using_sys_zls = false

function M.if_using_sys_zls()
    return if_using_sys_zls
end

--- @type string|nil
local current_lsp_zls_version = nil

--- @param zls_version string|nil
function M.set_current_lsp_zls_version(zls_version)
    current_lsp_zls_version = zls_version
end

--- @return string|nil
function M.get_current_lsp_zls_version()
    return current_lsp_zls_version
end

--- @return boolean
function M.lsp_if_inited()
    return lsp_is_initialized
end

function M.lsp_inited()
    lsp_is_initialized = true
end

-- zls meta info url
local zls_meta_url = "https://releases.zigtools.org/v1/zls/select-version"
local zls_store_path = vim.fs.joinpath(config.data_path, "zls")
local zls_db_path = path:new(config.data_path, "zlsdb.json")

--- @type { version_map: table }
local _db = nil

-- get zls file name
local function get_filename()
    if util.sys == "windows" then
        return "zls.exe"
    else
        return "zls"
    end
end

-- get db
local function get_db()
    -- when db is already loaded, return it
    if _db then
        return _db
    end
    -- when db is not loaded, load it from disk
    if not zls_db_path:exists() then
        -- when db is not exist, create it
        util.mkdir(zls_db_path:parent():absolute())
        zls_db_path:touch()
        _db = {
            version_map = {},
        }
    else
        -- when db is exist, load it
        local content = zls_db_path:read()
        if content ~= "" then
            -- when content is not empty, decode it
            _db = vim.fn.json_decode(content)
        else
            -- when content is empty, create db
            _db = {
                version_map = {},
            }
        end
    end
    return _db
end

-- Note: this is not load db from disk
-- save db
local function save_db()
    -- stylua: ignore
    if not _db then return end

    if not zls_db_path:exists() then
        util.mkdir(zls_db_path:parent():absolute())
    end

    zls_db_path:write(vim.fn.json_encode(_db), "w", 438)
end

--- @param zig_version string
--- @return string|nil
function M.get_zls_version_from_db(zig_version)
    local db = get_db()
    return db.version_map[zig_version]
end

-- please call save db after using this function
--- @param zig_version string
--- @param zls_version string
local function set_zls_version_to_db(zig_version, zls_version)
    local db = get_db()
    db.version_map[zig_version] = zls_version
end

-- please call save db after using this function
--- @param zig_version string
local function db_delete_with_zig_version(zig_version)
    local db = get_db()
    db.version_map[zig_version] = nil
end

-- please call save db after using this function
--- @param zls_version string
local function db_delete_with_zls_version(zls_version)
    local db = get_db()
    for _zig, _zls in pairs(db.version_map) do
        if _zls == zls_version then
            db.version_map[_zig] = nil
        end
    end
end

-- generate src and dest path for extract zls
--- @param zls_version string
--- @return string, string
local function generate_src_and_dest(zls_version)
    local src_loc = vim.fs.joinpath(config.tmp_path, zls_version)
    local _p = path:new(zls_store_path, zls_version)
    -- stylua: ignore
    if _p:exists() then _p:rm({ recursive = true }) end
    util.mkdir(_p:absolute())

    local dest_loc = vim.fs.normalize(_p:absolute())
    return src_loc, dest_loc
end

-- extract zls for unix, like linux, macos
--- @param zls_version string
--- @param callback? fun()
local function extract_zls_for_unix(zls_version, callback)
    local src_loc, dest_loc = generate_src_and_dest(zls_version)

    ---@diagnostic disable-next-line: missing-fields
    local _j = job:new({
        command = "tar",
        args = { "-xvf", src_loc, "-C", dest_loc, get_filename() },
    })
    -- stylua: ignore
    _j:after_success(function() if callback then callback() end end)
    _j:after_failure(vim.schedule_wrap(function(_, code, signal)
        util.error("failed to extract zls", code, signal)
    end))
    _j:start()
end

-- this function must call in main loop
--- @param zls_version string
--- @param callback? fun()
local function extract_zls_for_win(zls_version, callback)
    local src_loc, dest_loc = generate_src_and_dest(zls_version)

    ---@diagnostic disable-next-line: missing-fields
    local _j = job:new({
        command = "unzip",
        args = { "-j", src_loc, get_filename(), "-d", dest_loc },
    })
    -- stylua: ignore
    _j:after_success(function() if callback then callback() end end)
    _j:after_failure(vim.schedule_wrap(function(_, code, signal)
        util.error("failed to extract zls", code, signal)
    end))
    _j:start()
end

-- verify zls version
--- @param zls_version string
--- @return boolean|nil
local function verify_local_zls_version(zls_version)
    local _p = path:new(zls_store_path, zls_version, get_filename())
    if not _p:exists() then
        return nil
    end
    ---@diagnostic disable-next-line: missing-fields
    local _j = job:new({
        command = _p:absolute(),
        args = { "--version" },
    })
    local _result, _ = _j:sync()

    -- stylua: ignore
    if not _result then return false end
    -- stylua: ignore
    if _result[1] == zls_version then return true end

    return false
end

--- @return string|nil
function M.get_zls_version()
    -- get zig version
    local zig_version = zig.version()
    if not zig_version then
        return nil
    end

    -- get zls version from db
    local zls_version = M.get_zls_version_from_db(zig_version)
    if not zls_version then
        return nil
    end

    return zls_version
end

--- @param zls_version string|nil
function M.get_zls_path(zls_version)
    if not zls_version then
        return nil
    end
    -- detect zls whether exist
    local zls_path = path:new(zls_store_path, zls_version, get_filename())
    if not zls_path:exists() then
        return nil
    end

    return vim.fs.normalize(zls_path:absolute())
end

-- whether exist system zls
function M.if_sys_zls()
    return vim.fn.executable("zls") == 1
end

-- get zls version
--- @return string|nil
function M.sys_version()
    if not M.if_sys_zls() then
        return nil
    end
    --- @diagnostic disable-next-line: missing-fields
    local _tmp = job:new({ command = "zls", args = { "--version" } })
    _tmp:after_failure(vim.schedule_wrap(function(_, code, signal)
        util.error("failed to get sys zls version", code, signal)
    end))
    local _result, _ = _tmp:sync()
    if not _result then
        return nil
    end

    return _result[1]
end

--- @class zlsMetaArchInfo
--- @field tarball string
--- @field shasum string
--- @field size string this is litter number

--- @class zlsMeta
--- @field date string
--- @field version string
--- @field ["aarch64-linux"] zlsMetaArchInfo
--- @field ["aarch64-macos"] zlsMetaArchInfo
--- @field ["wasm32-wasi"] zlsMetaArchInfo
--- @field ["x86-linux"] zlsMetaArchInfo
--- @field ["x86-windows"] zlsMetaArchInfo
--- @field ["x86_64-linux"] zlsMetaArchInfo
--- @field ["x86_64-macos"] zlsMetaArchInfo
--- @field ["x86_64-windows"] zlsMetaArchInfo

--- @class zlsMetaErr
--- @field code 0|1|2|3
--- @field message string

-- this function api is here:
-- https://github.com/zigtools/release-worker#unsupported-release-cycle
--- @param zig_version string
--- @param callback fun(json:zlsMeta|zlsMetaErr|nil)
local function get_meta_json(zig_version, callback)
    --- @param response { exit: number, status: number, headers: table, body: string }
    local function __tmp(response)
        -- stylua: ignore
        if response.status ~= 200 then callback() return end

        --- @type zlsMeta|zlsMetaErr
        local info = vim.fn.json_decode(response.body)
        if not info.code then
            set_zls_version_to_db(zig_version, info.version)
            save_db()
        end
        callback(info)
    end

    local query = { zig_version = zig_version, compatibility = "only-runtime" }

    -- stylua: ignore
    curl.get(zls_meta_url, { query = query, callback = vim.schedule_wrap(__tmp) })
end

--- @param zls_version string
--- @param arch_info zlsMetaArchInfo
--- @param callback fun(result: boolean, ctx: { exit: number, status: number, headers: table, body: string})
local function download_zls(zls_version, arch_info, callback)
    -- check tmp path whether exist
    local _p = path:new(config.tmp_path)
    if not _p:exists() then
        util.mkdir(config.tmp_path)
    end

    local loc = vim.fs.joinpath(config.tmp_path, zls_version)
    local _loc = path:new(loc)
    if _loc:exists() then
        _loc:rm()
    end
    --- @param out { exit: number, status: number, headers: table, body: string}
    local _tmp = function(out)
        if out.status ~= 200 then
            callback(false, out)
            return
        end
        local is_ok = zig_ffi.check_shasum(loc, arch_info.shasum)
        callback(is_ok, out)
    end
    -- asynchronously download
    curl.get(
        arch_info.tarball,
        { output = loc, callback = vim.schedule_wrap(_tmp) }
    )
end

-- delete specific zls version
--- @param zls_version string
local function remove_zls(zls_version)
    local _p = path:new(zls_store_path, zls_version)
    if _p:exists() then
        _p:rm({ recursive = true })
    end
end

-- get all local zls version
--- @return string[]
function M.local_zls_lists()
    local res = {}
    if not path:new(zls_store_path):exists() then
        return res
    end

    local _s = scan.scan_dir(zls_store_path, { only_dirs = true })
    for _, value in pairs(_s) do
        local _pp = vim.fn.fnamemodify(value, ":t")
        table.insert(res, _pp)
    end

    return res
end

--- @param meta zlsMeta
--- @return zlsMetaArchInfo
local function get_arch_info(meta)
    local _key = util.arch() .. "-" .. util.sys
    return meta[_key]
end

--- @param zls_version string
local function remove_zls_tmp(zls_version)
    local _p = path:new(config.tmp_path, zls_version)
    if _p:exists() then
        _p:rm()
    end
end

local function lsp_on_new_config(new_config, new_root_dir)
    local _zls_path = "zls"

    if not if_using_sys_zls then
        local _zls_version = M.get_zls_version()
        --- @type string
        ---@diagnostic disable-next-line: assign-type-mismatch
        _zls_path = M.get_zls_path(_zls_version)
        new_config.cmd = { _zls_path }
    end

    if vim.fn.filereadable(vim.fs.joinpath(new_root_dir, "zls.json")) ~= 0 then
        new_config.cmd = { _zls_path, "--config-path", "zls.json" }
    end
end

--- @param zls_version string|nil
function M.setup_lspconfig(zls_version)
    local lspconfig = require("lspconfig")

    -- support use user's config
    local lsp_opt = vim.g.zig_lamp_zls_lsp_opt or {}
    lsp_opt.autostart = false
    lsp_opt.on_new_config = lsp_on_new_config

    lspconfig.zls.setup(lsp_opt)
    M.set_current_lsp_zls_version(zls_version)
    if_using_sys_zls = zls_version == nil

    M.lsp_inited()
end

-- we need setup lspconfig first
--- @param bufnr integer|nil
function M.launch_zls(bufnr)
    local lspconfig_configs = require("lspconfig.configs")
    local zls_config = lspconfig_configs.zls

    zls_config.launch(bufnr)
end

-- callback for zls install
--- @param _ string[]
function M.zls_install(_)
    local zig_version = zig.version()
    if not zig_version then
        util.Warn("not found zig")
        return
    end
    util.Info("get zig version: " .. zig_version)

    local is_local = true

    local db_zls_version = M.get_zls_version_from_db(zig_version)
    if not db_zls_version then
        util.Info("not found zls version in db, try to get meta json")
        is_local = false
        goto l1
    end
    util.Info("found zls version in db: " .. db_zls_version)

    if not verify_local_zls_version(db_zls_version) then
        -- when zls version is not correct
        db_delete_with_zig_version(zig_version)
        remove_zls(db_zls_version)
        util.Info("zls version verify failed, try to get meta json")
        is_local = false
        goto l1
    end

    -- stylua: ignore
    util.Info(string.format("zls version %s is already installed", db_zls_version))

    ::l1::
    if is_local then
        return
    end

    --- @param zls_version string
    local function after_install(zls_version)
        -- when inited, return
        if M.lsp_if_inited() then
            return
        end

        M.setup_lspconfig(zls_version)
        local buf_lists = vim.api.nvim_list_bufs()
        for _, bufnr in pairs(buf_lists) do
            -- stylua: ignore
            local filetype = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
            if filetype == "zig" then
                M.launch_zls(bufnr)
            end
        end
    end

    -- run after extract zls, check zls version
    --- @param info zlsMeta
    local function after_extract(info)
        return vim.schedule_wrap(function()
            remove_zls_tmp(info.version)
            if verify_local_zls_version(info.version) then
                util.Info("success to install zls version " .. info.version)
                after_install(info.version)
            else
                util.Error("failed to install zls")
            end
        end)
    end

    -- run after download zls, extract zls
    --- @param info zlsMeta
    local function after_download(info)
        local function _tmp()
            util.Info("try to extract zls")
            if util.sys == "windows" then
                extract_zls_for_win(info.version, after_extract(info))
            else
                -- for unix, like linux, macos
                extract_zls_for_unix(info.version, after_extract(info))
            end
        end

        --- @param result boolean
        --- @param ctx { exit: number, status: number, headers: table, body: string}
        return function(result, ctx)
            if result then
                vim.schedule(_tmp)
            else
                util.Error("failed to download zls, status: " .. ctx.status)
            end
        end
    end

    -- run aftet get meta json
    --- @param info zlsMeta|zlsMetaErr|nil
    local function after_meta(info)
        -- when info is nil, network error
        -- when info.code is 0, Unsupported
        -- when info.code is 1, Unsupported Release Cycle
        -- when info.code is 2, Incompatible development build
        -- when info.code is 3, Incompatible tagged release
        if info == nil then
            util.Error("failed to get zls meta json, please check your network")
            return
        elseif info.code == 0 then
            util.Warn("current zig version is not supported by zls")
            return
        elseif info.code == 1 then
            util.Warn("Unsupported Release Cycle, zls hasn't updated yet")
            return
        elseif info.code == 2 then
            util.Warn("Incompatible development build, non-zls compatible")
            return
        elseif info.code == 3 then
            util.Warn("Incompatible tagged release, non-zls compatible")
            return
        end

        ---@diagnostic disable-next-line: param-type-mismatch
        local archinfo = get_arch_info(info)

        util.Info("try to download zls")
        -- download zls
        ---@diagnostic disable-next-line: param-type-mismatch
        download_zls(info.version, archinfo, after_download(info))
    end

    util.Info("try to get zls meta json")
    -- get meta json
    get_meta_json(zig_version, after_meta)
end

--- @param params string[]
--- @diagnostic disable-next-line: unused-local
local function cb_zls_uninstall(params)
    if #params == 0 then
        util.Info("please input zls version")
        return
    end

    local lists = M.local_zls_lists()
    if not vim.tbl_contains(lists, params[1]) then
        util.Info("please input correct zls version")
        return
    end

    local zls_version = params[1]

    if zls_version == M.get_current_lsp_zls_version() then
        local zls_clients = vim.lsp.get_clients({ name = "zls" })
        if #zls_clients > 0 then
            -- stylua: ignore
            util.Warn("the zls which you want to uninstall is running, please stop it first")
            return
        end
    end

    db_delete_with_zls_version(zls_version)
    remove_zls(zls_version)
    save_db()

    util.Info("success to uninstall zls version " .. zls_version)
    if zls_version == M.get_current_lsp_zls_version() then
        M.set_current_lsp_zls_version(nil)
    end
end

local function complete_zls_uninstall()
    return M.local_zls_lists()
end

-- now, we have two commands
-- zls install
-- zls uninstall
local function set_command()
    cmd.set_command(M.zls_install, nil, "zls", "install")
    -- stylua: ignore
    cmd.set_command(cb_zls_uninstall, complete_zls_uninstall, "zls", "uninstall")
end

function M.setup()
    set_command()
end

return M
