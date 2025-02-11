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
    dependencies = {
        "nvim-lua/plenary.nvim",
        "MunifTanjim/nui.nvim",
    },
}
```

for windows user: you need `curl` and `unzip`

for unix-like user: you need `curl` and `tar`

## Command

- `ZigLamp info`: display infos
- `ZigLamp zls install`: automatically install zls matching the current system zig version
- `ZigLamp zls uninstall`: uninstall the specified zls
