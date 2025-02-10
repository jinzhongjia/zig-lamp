-- this file will run when enter zig.lua

local util = require("zig-lamp.util")
local zls = require("zig-lamp.module.zls")

-- config zls for lsp
do
    if not zls.lsp_if_inited() then
        local zls_version = zls.get_zls_version()
        local zls_path = zls.get_zls_path(zls_version)

        if not zls_path or not zls_version then
        -- stylua: ignore
        util.Info("Not found valid zls, please run \"ZigLamp zls install\" to install it.")
            return
        end

        zls.setup_lspconfig(zls_version)
    end
    if zls.get_current_lsp_zls_version() then
        zls.launch_zls()
    end
end
