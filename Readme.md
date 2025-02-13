# zig-lamp

This is a plugin for neovim and a library for zig.

For neovim, you can install zls easily through this plugin.

For zig, you can use this plugin to parse zig build dependency from `build.zig.zon`(developing!!).

## Install

For neovim user, please use neovim `0.10`!

this plugin's dependecy is [nui.nvim](https://github.com/MunifTanjim/nui.nvim) and [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)!

If you are using `lazy.nvim`, just add this to your configuration file:

```lua
-- no need to call any setup
{
    "jinzhongjia/zig-lamp",
    event = "VeryLazy",
    build = ":ZigLamp build sync"
    -- or ":ZigLamp build" for async build, the build job will return immediately
    -- or ":ZigLamp build sync 20000" for sync build with specified timeout 20000ms
    dependencies = {
        "nvim-lua/plenary.nvim",
        "MunifTanjim/nui.nvim",
    },
    init = function()
        -- this is setting for zls with lspconfig, the opts you need to see document of zls and lspconfig
        vim.g.zls_lsp_opt = {}
    end,
}
```

for windows user: you need `curl` and `unzip`

for unix-like user: you need `curl` and `tar`

Oh, of course, recommend to install `zig` to build lamp lib for shasum and more features.(_hhh, this sentence seems be meaningless_)

## Command

- `ZigLamp info`: display infos
- `ZigLamp zls install`: automatically install zls matching the current system zig version
- `ZigLamp zls uninstall`: uninstall the specified zls
- `ZigLamp build`: you can add param `sync` + timeout(ms optional) or `async` to select build mode
- `ZigLamp pkg info`: you can see current pkg info(such as package name, version, dependencies..)
