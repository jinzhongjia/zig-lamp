# zig-lamp

A Neovim plugin and Zig library that streamlines Zig development with ZLS management, build.zig.zon parsing/formatting, and convenient build integration.

## Highlights
- ZLS management: one‑command install/uninstall, auto match with the current Zig version, local cache, and system ZLS fallback
- Info panel: display plugin version, data path, Zig/ZLS status, and locally available ZLS versions
- Package manager panel: visual view/edit of `build.zig.zon` (paths, dependencies, hash, lazy), with automatic URL hash retrieval (requires the optional native library; see below)
- Build integration: project build/test/clean commands and one‑command build for the plugin’s native library
- Native library (FFI): ZON → JSON, ZON formatting, checksum verification (when FFI is available)

## Requirements
- Neovim 0.10+
- Zig 0.15.1+
- Optional: `nvim-lspconfig` (only required when using Neovim without the built-in LSP config API; 0.11+ users can rely on `vim.lsp.config`/`vim.lsp.enable`)
- System tools:
  - Windows: `curl`, `unzip` (or `powershell` for extraction)
  - Non‑Windows: `curl`, `tar`

## Installation (lazy.nvim)
```lua
{
  "jinzhongjia/zig-lamp",
  event = "VeryLazy",
  -- Optional but recommended: build the local FFI lib to enable faster/safer verification & formatting
  build = ":ZigLampBuild async",
  dependencies = {
    -- For Neovim < 0.11 you’ll likely want lspconfig
    "neovim/nvim-lspconfig",
  },
  init = function()
    -- Backward-compatible global vars (all optional)
    -- Auto-install ZLS: timeout in milliseconds; set to nil to disable
    vim.g.zig_lamp_zls_auto_install = nil
    -- Fallback to system zls when no local match is found
    vim.g.zig_lamp_fall_back_sys_zls = nil
    -- Extra LSP options merged into defaults
    vim.g.zig_lamp_zls_lsp_opt = {}
    -- ZLS server settings (overrides built-in recommendations)
    vim.g.zig_lamp_zls_settings = {}
    -- Help text color for the package panel
    vim.g.zig_lamp_pkg_help_fg = "#CF5C00"
    -- Timeout (ms) used by `zig fetch` when retrieving url hashes
    vim.g.zig_lamp_zig_fetch_timeout = 5000
    -- Zig executable configuration
    vim.g.zig_lamp_zig_cmd = "zig"       -- path to zig binary when not in PATH
    vim.g.zig_lamp_zig_timeout = 15000   -- timeout (ms) for `zig version` checks
  end,
}
```

> Tip: Do not set up ZLS in lspconfig yourself. zig-lamp will auto‑match and start ZLS as you open Zig buffers (on Neovim 0.11+ it prefers the built‑in LSP APIs).

## Commands
All commands are rooted at `:ZigLamp` (hierarchical subcommands with completion) plus one standalone command `:ZigLampBuild`.

- `:ZigLamp info` — open the info panel
- `:ZigLamp health` — run health checks (zig/curl/unzip|tar/lspconfig/native lib)
- `:ZigLamp build [--args…]` — run `zig build` in the current Zig project (arguments are forwarded as‑is)
- `:ZigLamp test [--args…]` — run `zig build test` in the current Zig project
- `:ZigLamp clean` — remove `zig-out` and `zig-cache` in the current project
- `:ZigLamp zls install` — download and install the ZLS version compatible with the current `zig version`
- `:ZigLamp zls uninstall <version>` — uninstall a local ZLS version (with completion)
- `:ZigLamp zls status` — show ZLS status (local versions, system zls availability, current LSP version, etc.)
- `:ZigLamp pkg` — open the package manager panel (view/edit `build.zig.zon`)

Standalone:
- `:ZigLampBuild [async|sync] [timeout_ms]` — build the plugin’s native library in the plugin root (ReleaseFast by default).
  - Note: if the library is already loaded in the current Neovim process, you’ll be prompted to restart before building.

### Package manager panel keymaps
> Editing requires the optional native library. Run `:ZigLampBuild` first; otherwise the panel will prompt you to build it.
- `q` — quit
- `r` — reload from file
- `s` — save back to `build.zig.zon` (formatted automatically)
- `e` — edit package metadata (name/version/minimum Zig)
- `p` — edit paths (comma-separated)
- `a` — add or update a dependency (supports url/path and lazy flag; url auto-fetches hash)
- `d` — delete a dependency
- `h` — re-fetch hash for a URL dependency

## ZLS behavior & version matching
- On entering a Zig buffer when LSP isn’t initialized:
  - It looks up a ZLS version for the current `zig version` from a local DB
  - If not found and fallback is disabled: auto‑install will kick in when configured; otherwise a notice is shown
  - Once resolved, the plugin configures and starts `zls` via the built‑in LSP (Neovim 0.11+) or `lspconfig` fallback
- Windows uses `unzip`, non‑Windows uses `tar`
- If the native library is available, downloads are verified via checksum
- If `zls.json` exists at project root, it is passed to ZLS automatically

## ZLS Configuration

### Built-in Recommended Settings
zig-lamp now automatically applies recommended ZLS settings without requiring a `zls.json` file. Built-in settings include:

- **Core features**: Snippet completions, argument placeholders, full semantic highlighting
- **Code quality**: Style warnings, global variable highlighting  
- **Build features**: Build-on-save diagnostics
- **Inlay hints**: Smart type and parameter hints

### Custom Configuration
Override defaults via `vim.g.zig_lamp_zls_settings`:

```lua
-- Example: Performance optimization (large projects)
vim.g.zig_lamp_zls_settings = {
    zls = {
        skip_std_references = true,  -- Skip standard library references
        semantic_tokens = "partial",  -- Reduce semantic analysis
    }
}

-- Example: Minimal UI (reduce distractions)
vim.g.zig_lamp_zls_settings = {
    zls = {
        warn_style = false,  -- Disable style warnings
        inlay_hints_show_variable_type_hints = false,  -- Hide variable type hints
    }
}
```

### Configuration Priority
1. Project `zls.json` (highest priority)
2. `vim.g.zig_lamp_zls_settings` user configuration
3. zig-lamp built-in recommendations (default)

## Using zig-lamp as a Zig library
The repo also provides a Zig module for ZON parsing/formatting.

### Add dependency in build.zig.zon
```bash
# Recommended: pin a specific commit or archived artifact
zig fetch --save https://github.com/jinzhongjia/zig-lamp/archive/main.tar.gz

# Alternative: Git URL (requires git)
zig fetch --save git+https://github.com/jinzhongjia/zig-lamp
```

### Configure build.zig
```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zig_lamp = b.dependency("zig-lamp", .{ .target = target, .optimize = optimize });

    const exe = b.addExecutable(.{
        .name = "your-app",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("zigLamp", zig_lamp.module("zigLamp"));
    b.installArtifact(exe);
}
```

### Zig API examples
```zig
const std = @import("std");
const zigLamp = @import("zigLamp");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    // Parse build.zig.zon to JSON
    const file = try std.fs.cwd().openFile("build.zig.zon", .{}); defer file.close();
    var out = std.ArrayList(u8).init(alloc); defer out.deinit();
    try zigLamp.zig2json(alloc, file.reader().any(), out.writer(), void{}, .{ .file_name = "build.zig.zon" });
    std.log.info("JSON: {s}", .{out.items});

    // Format ZON
    const source = ".{ .name = .zig_lamp }";
    const formatted = try zigLamp.fmtZon(source, alloc); defer alloc.free(formatted);
    std.log.info("Formatted: {s}", .{formatted});
}
```

Note: checksum verification is exposed to Neovim via FFI (`check_shasum`) and is not currently part of the public Zig API.

## Compatibility
- Plugin version: `0.1.0`
- Requires Zig: `0.15.1+`
- Neovim: `0.10+` (on 0.11+ the built‑in LSP API is used)

## Troubleshooting
- ZLS not found: run `:ZigLamp zls install`, or set `vim.g.zig_lamp_fall_back_sys_zls = 1` to allow falling back to system zls
- Native library not loaded: run `:ZigLampBuild sync`, then restart Neovim; on Windows the lib resides in `zig-out/bin`, on Unix‑like systems in `zig-out/lib`
- Build failures: ensure `curl` and the appropriate extractor are installed (`unzip` on Windows, `tar` on non‑Windows)
- Health check: run `:ZigLamp health`

## Development
```bash
# Build the plugin library (native)
zig build -Doptimize=ReleaseFast

# Run tests
zig build test
```

## License & Support
- Please use Issues/Discussions in the repository
- PRs are welcome
