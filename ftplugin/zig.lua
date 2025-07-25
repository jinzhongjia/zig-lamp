-- this file will run when enter zig.lua

local util = require("zig-lamp.core.core_util")
local zls = require("zig-lamp.zls")

-- config zls for lsp
do
    if not zls.lsp_if_inited() then
        local zls_version = zls.get_zls_version()
        local zls_path = zls.get_zls_path(zls_version)

        local is_there_zls = zls_path and zls_version

        if (not is_there_zls) and not vim.g.zig_lamp_fall_back_sys_zls then
            if vim.g.zig_lamp_zls_auto_install then
                zls.zls_install({})
                return
            end
            util.Warn(
                'Not found valid zls, please run "ZigLamp zls install" to install it.'
            )
            return
        end

        zls.setup_lspconfig(zls_version)
    end
    if zls.get_current_lsp_zls_version() or zls.if_using_sys_zls() then
        zls.launch_zls()
    end
end
