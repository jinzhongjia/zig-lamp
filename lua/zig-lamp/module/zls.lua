local cmd = require("zig-lamp.cmd")
local config = require("zig-lamp.config")
local curl = require("plenary.curl")
local job = require("plenary.job")
local path = require("plenary.path")
local scan = require("plenary.scandir")
local util = require("zig-lamp.util")
local zig = require("zig-lamp.module.zig")
local M = {}

local lsp_is_initialized = false

local current_lsp_zls_version = nil

--- @param zls_version string
function M.set_current_lsp_zls_version(zls_version)
    current_lsp_zls_version = zls_version
end

function M.get_current_lsp_zls_version()
    return current_lsp_zls_version
end

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
function M.get_zls_verion_from_db(zig_version)
    local db = get_db()
    return db.version_map[zig_version]
end

-- please call save db after using this function
--- @param zig_version string
--- @param zls_version string
local function set_zls_verion_to_db(zig_version, zls_version)
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

-- this function must call in main loop
--- @param zls_version string
--- @param callback? fun(zls_version:string|nil,err_msg:string|nil)
local function extract_zls_for_win(zls_version, callback)
    local src_loc = vim.fs.joinpath(config.tmp_path, zls_version)

    local _p = path:new(zls_store_path, zls_version)
    if not _p:exists() then
        util.mkdir(_p:absolute())
    end

    local dest_loc = vim.fs.normalize(_p:absolute())

    ---@diagnostic disable-next-line: missing-fields
    local _j = job:new({
        command = "unzip",
        args = { "-j", src_loc, get_filename(), "-d", dest_loc },
        on_exit = function(_, code, signal)
            if code ~= 0 then
                util.error("failed to extract zls", code, signal)
                return
            end
            if callback then
                callback()
            end
        end,
    })
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
    _j:sync()
    local _result = _j:result()
    if _result[1] and _result[1] == zls_version then
        return true
    end

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
    local zls_version = M.get_zls_verion_from_db(zig_version)
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

-- get zls version
--- @return string
function M.version()
    --- @diagnostic disable-next-line: missing-fields
    local _tmp = job:new({ command = "zls", args = { "--version" } })
    _tmp:sync()
    return _tmp:result()[1]
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
            set_zls_verion_to_db(zig_version, info.version)
            save_db()
        end
        callback(info)
    end

    local query = { zig_version = zig_version, compatibility = "only-runtime" }

    -- stylua: ignore
    curl.get(zls_meta_url, { query = query, callback = vim.schedule_wrap(__tmp) })
end

-- TODO: add minisign identify support
--
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
    local _tmp = function(out)
        callback(out.status == 200, out)
    end
    -- asynchronously download
    curl.get(arch_info.tarball, { output = loc, callback = _tmp })
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
    local _key = util.arch .. "-" .. util.sys
    return meta[_key]
end

--- @param zls_version string
local function remove_zls_tmp(zls_version)
    local _p = path:new(config.tmp_path, zls_version)
    if _p:exists() then
        _p:rm()
    end
end

--- @param zls_version string
--- @param zls_path string
function M.setup_lspconfig(zls_version, zls_path)
    local lspconfig = require("lspconfig")
    -- TODO: zls lsp opts
    lspconfig.zls.setup({ cmd = { zls_path } })

    M.set_current_lsp_zls_version(zls_version)

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
--- @param params string[]
--- @diagnostic disable-next-line: unused-local
local function cb_zls_install(params)
    local zig_version = zig.version()
    if not zig_version then
        util.Warn("not found zig")
        return
    end
    util.Info("get zig version: " .. zig_version)
    local db_zls_version = M.get_zls_verion_from_db(zig_version)
    if not db_zls_version then
        util.Info("not found zls version in db, try to get meta json")
        goto l1
    end
    util.Info("found zls version in db: " .. db_zls_version)
    if not verify_local_zls_version(db_zls_version) then
        -- when zls version is not correct
        db_delete_with_zig_version(zig_version)
        remove_zls(db_zls_version)
        util.Info("zls version verify failed, try to get meta json")
        goto l1
    end

    util.Info(
        string.format("zls version %s is already installed", db_zls_version)
    )

    ::l1::

    --- @param zls_version string
    local function after_install(zls_version)
        -- stylua: ignore
        if M.lsp_if_inited() then return end

        -- get zls path
        local _p = path:new(zls_store_path, zls_version, get_filename())
        local zls_path = vim.fs.normalize(_p:absolute())

        M.setup_lspconfig(zls_version, zls_path)

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
        --- @param result boolean
        --- @param ctx { exit: number, status: number, headers: table, body: string}
        return function(result, ctx)
            if result then
                vim.schedule(function()
                    util.Info("try to extract zls")
                    if util.sys == "windows" then
                        extract_zls_for_win(info.version, after_extract(info))
                    else
                        util.Error("other platform is not support")
                    end
                end)
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
        util.Warn("please restart neovim to prevent lspconfig still autostart!")
    end
end

local function complete_zls_uninstall()
    return M.local_zls_lists()
end

-- now, we have two commands
-- zls install
-- zls uninstall
local function set_command()
    cmd.set_command(cb_zls_install, nil, "zls", "install")
    -- stylua: ignore
    cmd.set_command(cb_zls_uninstall, complete_zls_uninstall, "zls", "uninstall")
end

function M.setup()
    set_command()
end

return M
