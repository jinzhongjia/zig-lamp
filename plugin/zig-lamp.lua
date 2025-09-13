-- Initialize zig-lamp plugin
-- Maintain backward compatibility while using new modular architecture

-- Check dependencies
local has_plenary, _ = pcall(require, "plenary.path")
if not has_plenary then
    vim.api.nvim_err_writeln("[zig-lamp] Error: plenary.nvim dependency required")
    return
end

-- Initialize core system
local core = require("zig-lamp.core")

-- Read configuration from global variables (backward compatibility)
local config = {}

if vim.g.zig_lamp_zls_auto_install ~= nil then
    config.zls_auto_install = vim.g.zig_lamp_zls_auto_install
end

if vim.g.zig_lamp_fall_back_sys_zls ~= nil then
    config.fall_back_sys_zls = vim.g.zig_lamp_fall_back_sys_zls ~= nil
end

if vim.g.zig_lamp_zls_lsp_opt ~= nil then
    config.zls_lsp_opt = vim.g.zig_lamp_zls_lsp_opt
end

if vim.g.zig_lamp_pkg_help_fg ~= nil then
    config.pkg_help_fg = vim.g.zig_lamp_pkg_help_fg
end

if vim.g.zig_lamp_zig_fetch_timeout ~= nil then
    config.zig_fetch_timeout = vim.g.zig_lamp_zig_fetch_timeout
end

-- Setup plugin
require("zig-lamp").setup(config)
