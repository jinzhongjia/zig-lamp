local a = require("plenary.async")
local command = require("zig-lamp.command")
local curl = require("plenary.curl")
local job = require("plenary.job")
local util = require("zig-lamp.util")
local zig = require("zig-lamp.module.zig")

-- decompress zig and get specific file from zip with powershell 5
-- [[Add-Type -AssemblyName System.IO.Compression.FileSystem; $zip = [System.IO.Compression.ZipFile]::OpenRead("C:\Users\jin\Downloads\zlsl.zip"); $entry = $zip.Entries | Where-Object { $_.FullName -eq "zls.exe" }; if ($entry) { $stream = $entry.Open(); $fileStream = [System.IO.File]::OpenWrite("C:\Users\jin\Downloads\zls.exe"); $stream.CopyTo($fileStream); $fileStream.Close(); $stream.Close() }; $zip.Dispose()]]

local M = {}

local zls_meta_url = "https://releases.zigtools.org/v1/zls/select-version"

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
--- @param callback fun(json:table|nil)
local function get_meta_json(zig_version, callback)
    --- @param response { exit: number, status: number, headers: table, body: string }
    local function __tmp(response)
        if response.status == 200 then
            callback(vim.fn.json_decode(response.body))
        else
            callback()
        end
    end

    local query = { zig_version = zig_version, compatibility = "only-runtime" }

    curl.get(zls_meta_url, {
        query = query,
        callback = vim.schedule_wrap(__tmp),
    })
end

--- @param meta zlsMeta
--- @return zlsMetaArchInfo
local function get_arch_info(meta)
    local _key = util.arch .. "-" .. util.sys
    return meta[_key]
end

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
            local res = get_meta_json(zig.version(), function(json)
                if json then
                    print(vim.inspect(get_arch_info(json)))
                end
            end)
        end,
    },
    {
        command = { "zls", "info" },
        cb = function()
            a.run(function()
                -- util.write_file("C://Users/jin/Downloads/new.txt","okokok")
                local data = util.read_file("C://Users/jin/Downloads/new.txt")
                print(data)
            end)
        end,
    },
}

function M.setup()
    -- init for commands
    for _, _ele in pairs(_commands) do
        command.set_command(_ele.cb, unpack(_ele.command))
    end
end

return M
