# zig-lamp

This is a plugin for neovim and a library for zig.

For neovim, you can install zls easily through this plugin.

For zig, you can use this plugin to parse zig build dependency from `build.zig.zon`.

## Install(neovim)

For neovim user, please use neovim `0.10`!

this plugin's dependency is [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) and [lspconfig](https://github.com/neovim/nvim-lspconfig)!

If you are using `lazy.nvim`, just add this to your configuration file:

```lua
-- no need to call any setup
{
    "jinzhongjia/zig-lamp",
    event = "VeryLazy",
    build = ":ZigLamp build sync",
    -- or ":ZigLamp build" for async build, the build job will return immediately
    -- or ":ZigLamp build sync 20000" for sync build with specified timeout 20000ms
    dependencies = {
        "neovim/nvim-lspconfig",
        "nvim-lua/plenary.nvim",
    },
    -- Here is default config, in general you no need to set these options
    init = function()
        -- if set this Non-negative value, zig-lamp will automatically install zls when open zig file.
        vim.g.zig_lamp_zls_auto_install = nil
        -- if set this Non-negative value, zig-lamp will fallback system zls when not found downloaded zls.
        vim.g.zig_lamp_fall_back_sys_zls = nil
        -- this is setting for zls with lspconfig, the opts you need to see document of zls and lspconfig.
        vim.g.zig_lamp_zls_lsp_opt = {}
        vim.g.zig_lamp_pkg_help_fg = "#CF5C00"
        vim.g.zig_lamp_zig_fetch_timeout = 5000
    end,
}
```

**Do not set zls through lspconfig, `zig-lamp` will do this!**

for windows user: you need `curl` and `unzip`

for unix-like user: you need `curl` and `tar`

Oh, of course, you need to install `zig` to build lamp lib for shasum and more features.(_hhh, this sentence seems be meaningless_)

### Notice

Since external libraries are introduced, if the zig compiled libraries appear panic or do not conform to the c API, then neovim will crash. Please open the issue report

## Install(zig)

1. Add to `build.zig.zon`

```sh
# It is recommended to replace the following branch with commit id
zig fetch --save https://github.com/jinzhongjia/zig-lamp/archive/main.tar.gz
# Of course, you can also use git+https to fetch this package!
```

2. Config to `build.zig`

```zig
// To standardize development, maybe you should use `lazyDependency()` instead of `dependency()`
// more info to see: https://ziglang.org/download/0.12.0/release-notes.html#toc-Lazy-Dependencies
const zig_lamp = b.dependency("zig-lamp", .{
    .target = target,
    .optimize = optimize,
});

// add module
exe.root_module.addImport("zigLamp", zig_lamp.module("zigLamp"));
```

## Command

- `ZigLamp info`: display infos
- `ZigLamp zls install`: automatically install zls matching the current system zig version
- `ZigLamp zls uninstall`: uninstall the specified zls
- `ZigLamp build`: you can add param `sync` + timeout(ms optional) or `async` to select build mode
- `ZigLamp pkg`: package manager panel

## ScreenShot

![pkg_panel](https://github.com/user-attachments/assets/01324e66-5912-4532-beeb-ac82c3ca84d0)
![info](https://github.com/user-attachments/assets/c5c988b5-d0b4-453e-8967-2b00b2bd3a11)
