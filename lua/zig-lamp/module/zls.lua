local a = require("plenary.async")
local cmd = require("zig-lamp.cmd")
local config = require("zig-lamp.config")
local curl = require("plenary.curl")
local job = require("plenary.job")
local path = require("plenary.path")
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
local _db = {
    version_map = {},
}

-- get db
local function get_db()
    if _db then
        return _db
    end
    if not zls_db_path:exists() then
        util.mkdir(zls_db_path:parent():absolute())
        zls_db_path:touch()
        _db = {}
    else
        local content = zls_db_path:read()
        if content ~= "" then
            _db = vim.fn.json_decode()
        end
    end
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

--- @param zig_version string
--- @param zls_version string
local function set_zls_verion_to_db(zig_version, zls_version)
    local db = get_db()
    db.version_map[zig_version] = zls_version
end

-- this function must call in main loop
--- @param zls_version string
--- @param callback fun()
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
            if callback then
                callback()
            end
        end,
    })
    _j:start()
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

--- @param meta zlsMeta
--- @return zlsMetaArchInfo
local function get_arch_info(meta)
    local _key = util.arch .. "-" .. util.sys
    return meta[_key]
end

-- TODO: this must be removed
--
--- @type { command: string[], cb: cmdCb }
local _commands = {
    {
        command = { "zls", "version" },
        cb = function(param)
            -- TODO: not use print
            print(M.version())
        end,
    },
    {
        command = { "zls", "json" },
        cb = function(param)
            get_meta_json(zig.version(), function(json)
                if json and not json.code then
                    ---@diagnostic disable-next-line: param-type-mismatch
                    print(vim.inspect(get_arch_info(json)))
                end
            end)
        end,
    },
    {
        command = { "zls", "debug" },
        cb = function()
            local zv = zig.version()
            local callback_2 = function(info)
                return function(result)
                    if result then
                        vim.schedule(function()
                            extract_zls_for_win(info.version)
                        end)
                    else
                        print("failed")
                    end
                end
            end
            local callback_1 = function(info)
                if info and not info.code then
                    ---@diagnostic disable-next-line: param-type-mismatch
                    local archinfo = get_arch_info(info)

                    download_zls(info.version, archinfo, callback_2(info))
                end
            end
            get_meta_json(zv, callback_1)
        end,
    },
}

function M.setup()
    -- init for commands
    for _, _ele in pairs(_commands) do
        cmd.set_command(_ele.cb, unpack(_ele.command))
    end
end

return M
