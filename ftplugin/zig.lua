-- this file will run when enter zig.lua

local zls = require("zig-lamp.module.zls")

-- config zls for lsp
do
    -- stylua: ignore
    if zls.lsp_if_inited() then return end

    -- get zls path
    local zls_path = zls.get_zls_path()

    if not zls_path then
        local util = require("zig-lamp.util")
        -- stylua: ignore
        util.Info("Not found valid zls, please run [ZigLamp zls install] to install it.")
        return
    end

    local lspconfig = require("lspconfig")
    -- TODO: zls lsp opts
    lspconfig.zls.setup({ cmd = { zls_path } })

    local lspconfig_configs = require("lspconfig.configs")
    local zls_config = lspconfig_configs.zls

    zls_config.launch()

    zls.lsp_inited()
end
