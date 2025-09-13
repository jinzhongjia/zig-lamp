-- zig-lamp main module entry point
-- Provides unified plugin initialization and configuration interface

local M = {}

-- Lazy load core modules
local _core = nil
local _config = nil

--- Get core module instance
---@return table core Core module
local function get_core()
    if not _core then
        _core = require("zig-lamp.core")
    end
    return _core
end

--- Get configuration module instance
---@return table config Configuration module
local function get_config()
    if not _config then
        _config = require("zig-lamp.core.core_config")
    end
    return _config
end

--- Plugin setup options
---@class ZigLampConfig
---@field zls_auto_install number|nil ZLS auto-install timeout in milliseconds, nil to disable
---@field fall_back_sys_zls number|nil Whether to fallback to system ZLS, non-negative to enable
---@field zls_lsp_opt table LSP configuration options
---@field pkg_help_fg string Package manager help text color
---@field zig_fetch_timeout number Zig fetch timeout in milliseconds

--- Default configuration
---@type ZigLampConfig
local default_config = {
    zls_auto_install = nil,
    fall_back_sys_zls = nil,
    zls_lsp_opt = {},
    pkg_help_fg = "#CF5C00",
    zig_fetch_timeout = 5000,
}

--- Current configuration
---@type ZigLampConfig
local current_config = vim.deepcopy(default_config)

--- Setup plugin configuration
---@param config ZigLampConfig|nil Configuration options
function M.setup(config)
    if config then
        current_config = vim.tbl_deep_extend("force", current_config, config)
    end

    -- Apply global variable configuration (backward compatibility)
    if vim.g.zig_lamp_zls_auto_install ~= nil then
        current_config.zls_auto_install = vim.g.zig_lamp_zls_auto_install
    end
    if vim.g.zig_lamp_fall_back_sys_zls ~= nil then
        current_config.fall_back_sys_zls = vim.g.zig_lamp_fall_back_sys_zls
    end
    if vim.g.zig_lamp_zls_lsp_opt ~= nil then
        current_config.zls_lsp_opt = vim.g.zig_lamp_zls_lsp_opt
    end
    if vim.g.zig_lamp_pkg_help_fg ~= nil then
        current_config.pkg_help_fg = vim.g.zig_lamp_pkg_help_fg
    end
    if vim.g.zig_lamp_zig_fetch_timeout ~= nil then
        current_config.zig_fetch_timeout = vim.g.zig_lamp_zig_fetch_timeout
    end

    -- Initialize core modules
    get_core().setup(current_config)
end

--- Get current configuration
---@return ZigLampConfig
function M.get_config()
    return vim.deepcopy(current_config)
end

--- Get plugin version information
---@return string version Version number
function M.version()
    return get_config().version
end

--- Check plugin health status
function M.health()
    require("zig-lamp.health").check()
end

--- Get project information
function M.info()
    require("zig-lamp.info").show()
end

--- Open package manager
function M.pkg()
    require("zig-lamp.pkg").open()
end

--- ZLS management interface
M.zls = {
    --- Install ZLS
    install = function()
        require("zig-lamp.zls").install()
    end,

    --- Uninstall ZLS
    uninstall = function()
        require("zig-lamp.zls").uninstall()
    end,

    --- Get ZLS status
    status = function()
        return require("zig-lamp.zls").status()
    end,
}

--- Zig tools interface
M.zig = {
    --- Get Zig version
    version = function()
        return require("zig-lamp.zig").version()
    end,

    --- Build project
    build = function(mode, timeout)
        require("zig-lamp.zig").build(mode, timeout)
    end,
}

return M
