-- zls/init.lua
-- Migrated from module/zls.lua, maintains interface compatibility, depends on core layer

local cmd = require("zig-lamp.core.core_cmd")
local config = require("zig-lamp.core.core_config")
local util = require("zig-lamp.core.core_util")
-- Optional FFI dependency for checksum verification
local zig_ffi = nil
local ffi_available = pcall(function()
    zig_ffi = require("zig-lamp.core.core_ffi")
end)
local vim = vim

-- Check plenary dependency
local ok_path, path = pcall(require, "plenary.path")
if not ok_path then
    util.Error("[zig-lamp.zls] Failed to require('plenary.path'), please ensure plenary.nvim is installed")
    return {}
end

local ok_curl, curl = pcall(require, "plenary.curl")
local ok_job, job = pcall(require, "plenary.job")
local ok_scan, scan = pcall(require, "plenary.scandir")

if not (ok_curl and ok_job and ok_scan) then
    util.Error("[zig-lamp.zls] Failed to load plenary modules")
    return {}
end

local zig = require("zig-lamp.zig")

local M = {}

-- Constants
local ZLS_META_URL = "https://releases.zigtools.org/v1/zls/select-version"
local ZLS_STORE_PATH = vim.fs.joinpath(config.data_path, "zls")
local ZLS_DB_PATH = path:new(config.data_path, "zlsdb.json")

-- Global state
local lsp_is_initialized = false
local if_using_sys_zls = false
local current_lsp_zls_version = nil
local _db = nil

-- Helper functions

--- Get the appropriate ZLS executable filename for the current system
--- @return string filename ZLS executable name (with .exe on Windows)
local function get_filename()
    local platform = require("zig-lamp.core.core_platform")
    return platform.executable_name("zls")
end

--- Ensure a directory exists, create if it doesn't
--- @param dir_path string Directory path to ensure exists
local function ensure_directory(dir_path)
    if not path:new(dir_path):exists() then
        util.mkdir(dir_path)
    end
end

--- Safely decode JSON content with error handling
--- @param content string JSON content to decode
--- @return table|nil Decoded table or nil if decoding fails
local function safe_json_decode(content)
    local ok, result = pcall(vim.fn.json_decode, content)
    return ok and result or nil
end

--- Safely encode data to JSON with error handling
--- @param data table Data to encode
--- @return string JSON string or empty object if encoding fails
local function safe_json_encode(data)
    local ok, result = pcall(vim.fn.json_encode, data)
    return ok and result or "{}"
end

-- Database operations

--- Get or initialize the ZLS version database
--- @return table Database object with version_map
local function get_db()
    if _db then
        return _db
    end

    if not ZLS_DB_PATH:exists() then
        ensure_directory(ZLS_DB_PATH:parent():absolute())
        ZLS_DB_PATH:touch()
        _db = { version_map = {} }
    else
        local content = ZLS_DB_PATH:read()
        if content and content ~= "" then
            _db = safe_json_decode(content) or { version_map = {} }
        else
            _db = { version_map = {} }
        end
    end
    return _db
end

--- Save the database to disk
--- @return boolean Success status
local function save_db()
    if not _db then
        return false
    end

    local ok, err = pcall(function()
        ensure_directory(ZLS_DB_PATH:parent():absolute())
        ZLS_DB_PATH:write(safe_json_encode(_db), "w", 438)
    end)

    if not ok then
        util.Error("Failed to save ZLS database: " .. tostring(err))
        return false
    end
    return true
end

--- Store ZLS version mapping for a specific Zig version
--- @param zig_version string Zig version
--- @param zls_version string ZLS version to associate
local function set_zls_version_to_db(zig_version, zls_version)
    local db = get_db()
    db.version_map[zig_version] = zls_version
end

--- Remove ZLS version mapping for a specific Zig version
--- @param zig_version string Zig version to remove mapping for
local function db_delete_with_zig_version(zig_version)
    local db = get_db()
    db.version_map[zig_version] = nil
end

--- Remove all Zig version mappings for a specific ZLS version
--- @param zls_version string ZLS version to remove all mappings for
local function db_delete_with_zls_version(zls_version)
    local db = get_db()
    for _zig, _zls in pairs(db.version_map) do
        if _zls == zls_version then
            db.version_map[_zig] = nil
        end
    end
end

-- File operations

--- Safely remove a path with error handling
--- @param target_path string Path to remove
--- @param recursive boolean Whether to remove recursively
--- @return boolean Success status
local function remove_path_safe(target_path, recursive)
    local ok, err = pcall(function()
        local p = path:new(target_path)
        if p:exists() then
            p:rm(recursive and { recursive = true } or nil)
        end
    end)

    if not ok then
        util.Error("Failed to remove path: " .. target_path .. " - " .. tostring(err))
        return false
    end
    return true
end

--- Generate source and destination paths for ZLS installation
--- @param zls_version string ZLS version being installed
--- @return string, string Source archive path and destination directory
local function generate_src_and_dest(zls_version)
    local src_loc = vim.fs.joinpath(config.tmp_path, zls_version)
    local dest_path = path:new(ZLS_STORE_PATH, zls_version)

    -- Clean existing destination
    if dest_path:exists() then
        remove_path_safe(dest_path:absolute(), true)
    end

    ensure_directory(dest_path:absolute())
    return src_loc, vim.fs.normalize(dest_path:absolute())
end

-- Archive extraction

--- Extract ZLS archive (supports both tar and zip)
--- @param zls_version string ZLS version being extracted
--- @param callback function|nil Callback to execute after extraction
local function extract_zls_archive(zls_version, callback)
    local src_loc, dest_loc = generate_src_and_dest(zls_version)
    local filename = get_filename()

    local extract_cmd, extract_args
    local platform = require("zig-lamp.core.core_platform")
    if platform.is_windows then
        extract_cmd = "unzip"
        extract_args = { "-j", src_loc, filename, "-d", dest_loc }
    else
        extract_cmd = "tar"
        extract_args = { "-xvf", src_loc, "-C", dest_loc, filename }
    end

    local _j = job:new({
        command = extract_cmd,
        args = extract_args,
        on_exit = vim.schedule_wrap(function(_, code, signal)
            if code == 0 then
                if callback then
                    callback(true)
                end
            else
                util.Error("Failed to extract ZLS archive: " .. extract_cmd .. " exited with code " .. tostring(code))
                if callback then
                    callback(false)
                end
            end
        end),
    })

    _j:start()
end

-- Version verification

--- Verify that a locally installed ZLS version matches the expected version
--- @param zls_version string Expected ZLS version
--- @return boolean|nil true if verified, false if mismatch, nil if not found
local function verify_local_zls_version(zls_version)
    local zls_path = path:new(ZLS_STORE_PATH, zls_version, get_filename())
    if not zls_path:exists() then
        return nil
    end

    local _j = job:new({
        command = zls_path:absolute(),
        args = { "--version" },
        enable_recording = true,
    })

    local ok, result = pcall(_j.sync, _j)
    if not ok or not result then
        return false
    end

    return result[1] == zls_version
end

-- Public API functions

--- Check if currently using system-installed ZLS
--- @return boolean True if using system ZLS
function M.if_using_sys_zls()
    return if_using_sys_zls
end

--- Set the current LSP ZLS version
--- @param zls_version string|nil ZLS version or nil for system ZLS
function M.set_current_lsp_zls_version(zls_version)
    current_lsp_zls_version = zls_version
end

--- Get the current LSP ZLS version
--- @return string|nil Current ZLS version or nil
function M.get_current_lsp_zls_version()
    return current_lsp_zls_version
end

--- Check if LSP has been initialized
--- @return boolean True if LSP is initialized
function M.lsp_if_inited()
    return lsp_is_initialized
end

--- Mark LSP as initialized
function M.lsp_inited()
    lsp_is_initialized = true
end

--- Get ZLS version for a specific Zig version from database
--- @param zig_version string Zig version to look up
--- @return string|nil ZLS version or nil if not found
function M.get_zls_version_from_db(zig_version)
    if not zig_version then
        return nil
    end
    local db = get_db()
    return db.version_map[zig_version]
end

--- Get ZLS version for the current Zig installation
--- @return string|nil ZLS version or nil if not found
function M.get_zls_version()
    local zig_version = zig.version()
    if not zig_version then
        return nil
    end
    return M.get_zls_version_from_db(zig_version)
end

--- Get the full path to a specific ZLS version executable
--- @param zls_version string ZLS version
--- @return string|nil Full path to ZLS executable or nil if not found
function M.get_zls_path(zls_version)
    if not zls_version then
        return nil
    end
    local zls_path = path:new(ZLS_STORE_PATH, zls_version, get_filename())
    if not zls_path:exists() then
        return nil
    end
    return vim.fs.normalize(zls_path:absolute())
end

--- Check if system ZLS is available
--- @return boolean True if system ZLS is executable
function M.if_sys_zls()
    return vim.fn.executable("zls") == 1
end

--- Get the version of system-installed ZLS
--- @return string|nil System ZLS version or nil if not available
function M.sys_version()
    if not M.if_sys_zls() then
        return nil
    end

    local _tmp = job:new({
        command = "zls",
        args = { "--version" },
        enable_recording = true,
    })

    local ok, result = pcall(_tmp.sync, _tmp)
    if not ok or not result or #result == 0 then
        util.Error("Failed to get system ZLS version")
        return nil
    end

    return result[1]
end

--- Get list of locally installed ZLS versions
--- @return table List of installed ZLS version strings
function M.local_zls_lists()
    local res = {}
    local store_path = path:new(ZLS_STORE_PATH)

    if not store_path:exists() then
        return res
    end

    local ok, directories = pcall(scan.scan_dir, ZLS_STORE_PATH, { only_dirs = true })
    if not ok then
        util.Error("Failed to scan ZLS store directory")
        return res
    end

    for _, value in pairs(directories) do
        local version = vim.fn.fnamemodify(value, ":t")
        table.insert(res, version)
    end

    return res
end

-- Network and installation

--- Extract architecture-specific download information from metadata
--- @param meta table ZLS metadata containing architecture info
--- @return table|nil Architecture-specific download info or nil if not found
local function get_arch_info(meta)
    local platform = require("zig-lamp.core.core_platform")
    local key = platform.arch .. "-" .. platform.os
    return meta[key]
end

--- Remove temporary ZLS download file
--- @param zls_version string ZLS version to clean up
local function remove_zls_tmp(zls_version)
    remove_path_safe(vim.fs.joinpath(config.tmp_path, zls_version))
end

--- Remove installed ZLS version
--- @param zls_version string ZLS version to remove
local function remove_zls(zls_version)
    remove_path_safe(vim.fs.joinpath(ZLS_STORE_PATH, zls_version), true)
end

-- LSP configuration

--- Configure LSP on new config creation
--- @param new_config table LSP configuration object
--- @param new_root_dir string Project root directory
local function lsp_on_new_config(new_config, new_root_dir)
    local zls_cmd = "zls"

    if not if_using_sys_zls then
        local zls_version = M.get_zls_version()
        local zls_path = M.get_zls_path(zls_version)
        if zls_path then
            zls_cmd = zls_path
        end
    end

    new_config.cmd = { zls_cmd }

    -- Check for zls.json config file
    local config_path = vim.fs.joinpath(new_root_dir, "zls.json")
    if vim.fn.filereadable(config_path) ~= 0 then
        new_config.cmd = { zls_cmd, "--config-path", "zls.json" }
    end
end

--- Setup LSP configuration for ZLS
--- @param zls_version string|nil ZLS version to use (nil for system ZLS)
--- @return boolean Success status
function M.setup_lspconfig(zls_version)
    -- Prefer Neovim builtin LSP config API (Neovim 0.11+)
    local has_builtin = vim.lsp and vim.lsp.enable and vim.lsp.config ~= nil

    local lsp_opt = vim.g.zig_lamp_zls_lsp_opt or {}

    -- Resolve ZLS command (system or managed version)
    local zls_cmd = "zls"
    if zls_version ~= nil then
        local managed_path = M.get_zls_path(zls_version)
        if managed_path then
            zls_cmd = managed_path
        end
    end

    if has_builtin then
        -- Build config compatible with builtin API
        local conf = vim.tbl_deep_extend("force", {
            cmd = { zls_cmd },
            filetypes = { "zig" },
            -- Prefer project-local zls.json if present
            root_markers = { { "zls.json", "build.zig" }, ".git" },
            on_new_config = lsp_on_new_config,
        }, lsp_opt)

        local ok_define = pcall(function()
            if type(vim.lsp.config) == "function" then
                vim.lsp.config("zls", conf)
            else
                -- Table-style API
                vim.lsp.config["zls"] = conf
            end
        end)

        if not ok_define then
            util.Error("Failed to define builtin LSP config for zls")
            return false
        end

        -- Enable zls for matching buffers
        pcall(vim.lsp.enable, "zls")

        M.set_current_lsp_zls_version(zls_version)
        if_using_sys_zls = zls_version == nil
        M.lsp_inited()
        return true
    end

    -- Fallback to nvim-lspconfig for older Neovim
    local ok, lspconfig = pcall(require, "lspconfig")
    if not ok then
        util.Error("Failed to load lspconfig")
        return false
    end

    local cfg = vim.tbl_deep_extend("force", {
        autostart = false,
        on_new_config = lsp_on_new_config,
        cmd = { zls_cmd },
        filetypes = { "zig" },
    }, lsp_opt)

    lspconfig.zls.setup(cfg)
    M.set_current_lsp_zls_version(zls_version)
    if_using_sys_zls = zls_version == nil
    M.lsp_inited()
    return true
end

--- Launch ZLS for a specific buffer
--- @param bufnr number Buffer number to launch ZLS for
--- @return boolean Success status
function M.launch_zls(bufnr)
    -- Prefer builtin enable which will attach to open zig buffers
    if vim.lsp and vim.lsp.enable then
        local ok_enable = pcall(vim.lsp.enable, "zls")
        return ok_enable
    end

    -- Fallback to lspconfig
    local ok, lspconfig_configs = pcall(require, "lspconfig.configs")
    if not ok then
        util.Error("Failed to load lspconfig.configs")
        return false
    end

    local zls_config = lspconfig_configs.zls
    if zls_config and zls_config.launch then
        zls_config.launch(bufnr)
        return true
    end

    return false
end

-- Installation workflow

--- Install ZLS for the current Zig version
--- @param _ any Unused parameter (for command compatibility)
function M.zls_install(_)
    local zig_version = zig.version()
    if not zig_version then
        util.Warn("Zig not found")
        return
    end

    -- Check if ZLS is already installed locally
    local db_zls_version = M.get_zls_version_from_db(zig_version)
    if db_zls_version then
        if verify_local_zls_version(db_zls_version) then
            local already_installed_msg =
                string.format("✅ ZLS %s is already installed for Zig %s", db_zls_version, zig_version)
            util.Info(already_installed_msg)
            vim.notify(already_installed_msg, vim.log.levels.INFO, { title = "ZLS Status" })
            return
        else
            util.Info("Reinstalling ZLS due to verification failure...")
            db_delete_with_zig_version(zig_version)
            remove_zls(db_zls_version)
        end
    end

    util.Info("Installing ZLS for Zig " .. zig_version .. "...")

    -- Installation completion callback
    local function after_install(zls_version)
        if M.lsp_if_inited() then
            util.Info("🔄 ZLS LSP restarted with version " .. zls_version)
            return
        end

        M.setup_lspconfig(zls_version)

        -- Launch ZLS for existing Zig buffers
        local buf_lists = vim.api.nvim_list_bufs()
        local zig_buffers = 0
        for _, bufnr in pairs(buf_lists) do
            local ok, filetype = pcall(vim.api.nvim_get_option_value, "filetype", { buf = bufnr })
            if ok and filetype == "zig" then
                M.launch_zls(bufnr)
                zig_buffers = zig_buffers + 1
            end
        end

        if zig_buffers > 0 then
            util.Info("🚀 ZLS LSP started for " .. zig_buffers .. " Zig buffer(s)")
        else
            util.Info("🎯 ZLS is ready! Open a .zig file to start the language server")
        end
    end

    -- Extraction completion callback
    local function after_extract(zls_version)
        return vim.schedule_wrap(function()
            remove_zls_tmp(zls_version)

            if verify_local_zls_version(zls_version) then
                -- Show installation success message
                local success_msg =
                    string.format("✅ ZLS %s successfully installed and ready for Zig %s", zls_version, zig.version())
                util.Info(success_msg)

                -- Force immediate notification
                vim.notify(success_msg, vim.log.levels.INFO, { title = "ZLS Installation" })

                after_install(zls_version)
            else
                local error_msg = "❌ ZLS installation failed - executable not found after extraction"
                util.Error(error_msg)
                vim.notify(error_msg, vim.log.levels.ERROR, { title = "ZLS Installation" })
            end
        end)
    end

    -- Download completion callback
    local function after_download(zls_version)
        return function(success, ctx)
            if success then
                util.Info("📦 Extracting ZLS...")
                extract_zls_archive(zls_version, after_extract(zls_version))
            else
                util.Error("❌ Failed to download ZLS (HTTP " .. tostring(ctx.status) .. ")")
            end
        end
    end

    -- Metadata fetch completion callback
    local function after_meta(info)
        if not info then
            util.Error("Failed to get ZLS metadata, please check your network connection")
            return
        end

        -- Handle error codes
        local error_messages = {
            [0] = "Current Zig version is not supported by ZLS",
            [1] = "Unsupported release cycle, ZLS hasn't been updated yet",
            [2] = "Incompatible development build, non-ZLS compatible",
            [3] = "Incompatible tagged release, non-ZLS compatible",
        }

        if info.code and error_messages[info.code] then
            util.Warn(error_messages[info.code])
            return
        end

        local arch_info = get_arch_info(info)
        if not arch_info then
            util.Error("Unsupported architecture: " .. platform.arch .. "-" .. platform.os)
            return
        end

        util.Info("⬇️  Downloading ZLS " .. info.version .. "...")
        M.download_zls(info.version, arch_info, after_download(info.version))
    end

    M.get_meta_json(zig_version, after_meta)
end

-- Uninstallation

--- Uninstall a specific ZLS version
--- @param params table Command parameters containing ZLS version
local function cb_zls_uninstall(params)
    if #params == 0 then
        util.Info("Please specify ZLS version to uninstall")
        return
    end

    local zls_version = params[1]
    local available_versions = M.local_zls_lists()

    if not vim.tbl_contains(available_versions, zls_version) then
        util.Info("Invalid ZLS version. Available versions: " .. table.concat(available_versions, ", "))
        return
    end

    -- Check if the version is currently in use
    if zls_version == M.get_current_lsp_zls_version() then
        local zls_clients = vim.lsp.get_clients({ name = "zls" })
        if #zls_clients > 0 then
            util.Warn("Cannot uninstall ZLS version that is currently running. Please stop ZLS first.")
            return
        end
    end

    -- Perform uninstallation
    db_delete_with_zls_version(zls_version)
    remove_zls(zls_version)

    if not save_db() then
        util.Error("Failed to update database after uninstallation")
        return
    end

    util.Info("Successfully uninstalled ZLS version " .. zls_version)

    if zls_version == M.get_current_lsp_zls_version() then
        M.set_current_lsp_zls_version(nil)
    end
end

--- Complete ZLS version names for uninstall command
--- @return table List of available ZLS versions for completion
local function complete_zls_uninstall()
    return M.local_zls_lists()
end

-- Network operations

--- Fetch ZLS metadata for a specific Zig version
--- @param zig_version string Zig version to get ZLS metadata for
--- @param callback function Callback to execute with metadata (receives info table or nil)
function M.get_meta_json(zig_version, callback)
    if not zig_version or not callback then
        util.Error("Invalid parameters for get_meta_json")
        return
    end

    local function handle_response(response)
        if response.status ~= 200 then
            util.Error("Failed to fetch ZLS metadata: HTTP " .. tostring(response.status))
            callback(nil)
            return
        end

        local info = safe_json_decode(response.body)
        if not info then
            util.Error("Failed to parse ZLS metadata JSON")
            callback(nil)
            return
        end

        -- Save successful metadata to database
        if not info.code then
            set_zls_version_to_db(zig_version, info.version)
            save_db()
        end

        callback(info)
    end

    local query = {
        zig_version = zig_version,
        compatibility = "only-runtime",
    }

    curl.get(ZLS_META_URL, {
        query = query,
        callback = vim.schedule_wrap(handle_response),
        timeout = 30000, -- 30 second timeout
    })
end

--- Download ZLS archive for a specific version
--- @param zls_version string ZLS version to download
--- @param arch_info table Architecture-specific download information
--- @param callback function Callback to execute after download (receives success boolean and response)
function M.download_zls(zls_version, arch_info, callback)
    if not zls_version or not arch_info or not callback then
        util.Error("Invalid parameters for download_zls")
        return
    end

    -- Ensure tmp directory exists
    ensure_directory(config.tmp_path)

    local download_path = vim.fs.joinpath(config.tmp_path, zls_version)

    -- Remove existing download if present
    remove_path_safe(download_path)

    local function handle_download(response)
        if response.status ~= 200 then
            callback(false, response)
            return
        end

        -- Verify checksum if available and FFI is loaded
        local checksum_valid = true
        if arch_info.shasum then
            if ffi_available and zig_ffi and zig_ffi.get_lamp() then
                checksum_valid = zig_ffi.check_shasum(download_path, arch_info.shasum)
                if not checksum_valid then
                    util.Error("❌ Checksum verification failed")
                    remove_path_safe(download_path)
                    return
                end
                -- Don't spam with checksum success message
            else
                -- Silently skip checksum verification when FFI not available
                -- util.Warn("FFI library not available, skipping checksum verification")
            end
        end

        callback(checksum_valid, response)
    end

    -- Download ZLS archive
    curl.get(arch_info.tarball, {
        output = download_path,
        callback = vim.schedule_wrap(handle_download),
        timeout = 300000, -- 5 minute timeout for large files
    })
end

--- Get ZLS status information
---@return table status ZLS status information
function M.status()
    local zig_version = require("zig-lamp.zig").version()
    local current_zls = M.get_current_lsp_zls_version()
    local using_sys_zls = M.if_using_sys_zls()
    local lsp_initialized = M.lsp_if_inited()
    local local_zls_list = M.local_zls_lists()

    return {
        zig_version = zig_version,
        current_zls_version = current_zls,
        using_system_zls = using_sys_zls,
        lsp_initialized = lsp_initialized,
        available_local_versions = local_zls_list,
        system_zls_available = M.if_sys_zls(),
        system_zls_version = using_sys_zls and M.sys_version() or nil,
    }
end

return M
