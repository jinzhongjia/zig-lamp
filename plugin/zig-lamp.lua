---@diagnostic disable-next-line: undefined-global
local vim = vim

local function truthy(value)
    if value == nil then
        return nil
    end
    if type(value) == "number" then
        return value ~= 0
    end
    if type(value) == "string" then
        return value ~= "" and value ~= "0"
    end
    return value == true
end

local config = {
    zls = {},
    ui = {},
}

if vim.g.zig_lamp_zls_auto_install ~= nil then
    config.zls.auto_install = tonumber(vim.g.zig_lamp_zls_auto_install) or vim.g.zig_lamp_zls_auto_install
end

if vim.g.zig_lamp_fall_back_sys_zls ~= nil then
    config.zls.fall_back_sys = truthy(vim.g.zig_lamp_fall_back_sys_zls)
end

if vim.g.zig_lamp_zls_lsp_opt ~= nil then
    config.zls.lsp_opt = vim.g.zig_lamp_zls_lsp_opt
end

if vim.g.zig_lamp_zls_settings ~= nil then
    config.zls.settings = vim.g.zig_lamp_zls_settings
end

if vim.g.zig_lamp_zig_fetch_timeout ~= nil then
    config.zls.fetch_timeout = vim.g.zig_lamp_zig_fetch_timeout
end

if vim.g.zig_lamp_pkg_help_fg ~= nil then
    config.ui.pkg_help_fg = vim.g.zig_lamp_pkg_help_fg
end

if vim.g.zig_lamp_zig_cmd ~= nil then
    config.zig = config.zig or {}
    config.zig.cmd = vim.g.zig_lamp_zig_cmd
end

if vim.g.zig_lamp_zig_timeout ~= nil then
    config.zig = config.zig or {}
    config.zig.timeout = vim.g.zig_lamp_zig_timeout
end

require("zig-lamp").setup(config)

