local a = require("plenary.async")
local cmd = require("zig-lamp.cmd")
local config = require("zig-lamp.config")
local curl = require("plenary.curl")
local job = require("plenary.job")
local path = require("plenary.path")
local scan = require("plenary.scandir")
local util = require("zig-lamp.util")
local zig = require("zig-lamp.module.zig")

-- decompress zig and get specific file from zip with powershell 5
-- [[Add-Type -AssemblyName System.IO.Compression.FileSystem; $zip = [System.IO.Compression.ZipFile]::OpenRead("C:\Users\jin\Downloads\zlsl.zip"); $entry = $zip.Entries | Where-Object { $_.FullName -eq "zls.exe" }; if ($entry) { $stream = $entry.Open(); $fileStream = [System.IO.File]::OpenWrite("C:\Users\jin\Downloads\zls.exe"); $stream.CopyTo($fileStream); $fileStream.Close(); $stream.Close() }; $zip.Dispose()]]

local M = {}

-- zls meta info url
local zls_meta_url = "https://releases.zigtools.org/v1/zls/select-version"
local zls_store_path = vim.fs.joinpath(config.data_path, "zls")
local zls_db_path = path:new(config.data_path, "zlsdb.json")

--- @type { version_map: table }
local _db = nil

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
local function get_zls_verion_from_db(zig_version)
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
        args = { "-j", src_loc, "zls.exe", "-d", dest_loc },
        on_exit = function(...)
            -- TODO: handle this when error
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
    local _p = path:new(zls_store_path, zls_version, "zls.exe")
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
--- @field code number
--- @field message string

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
--- @param callback fun(result: boolean)
local function download_zls(zls_version, arch_info, callback)
    -- check tmp path whether exist
    local _p = path:new(config.tmp_path)
    if not _p:exists() then
        util.mkdir(config.tmp_path)
    end

    local loc = vim.fs.joinpath(config.tmp_path, zls_version)
    local _tmp = function(out)
        callback(out.status == 200)
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

-- callback for zls install
--- @param params string[]
local function cb_zls_install(params)
    local zig_version = zig.version()
    local db_zls_version = get_zls_verion_from_db(zig_version)
    if not db_zls_version then
        goto l1
    end
    if not verify_local_zls_version(db_zls_version) then
        -- when zls version is not correct
        db_delete_with_zig_version(zig_version)
        remove_zls(db_zls_version)
        goto l1
    end
    -- TODO: we need to not use print
    util.Info(string.format("zls version %s is already installed", db_zls_version))

    ::l1::
    -- run after extract zls, check zls version
    --- @param info zlsMeta
    local function cb_3(info)
        return function()
            if verify_local_zls_version(info.version) then
                print("success to install zls")
            else
                util.Error("failed to install zls")
            end
        end
    end

    -- run after download zls, extract zls
    --- @param info zlsMeta
    local cb_2 = function(info)
        return function(result)
            if result then
                vim.schedule(function()
                    extract_zls_for_win(info.version, cb_3)
                end)
            else
                -- TODO: handle this when result is false
            end
        end
    end

    -- run aftet get meta json
    --- @param info zlsMeta|zlsMetaErr|nil
    local cb_1 = function(info)
        -- TODO: handle this when err or nil
        --
        if info and not info.code then
            ---@diagnostic disable-next-line: param-type-mismatch
            local archinfo = get_arch_info(info)

            -- download zls
            ---@diagnostic disable-next-line: param-type-mismatch
            download_zls(info.version, archinfo, cb_2(info))
        end
    end

    get_meta_json(zig_version, cb_1)
end

local function set_command()
    cmd.set_command(cb_zls_install, nil, "zls", "install")
end

function M.setup()
    set_command()
end

return M
