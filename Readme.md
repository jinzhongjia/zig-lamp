# zig-lamp

A comprehensive Neovim plugin and Zig library for enhanced Zig development experience.

**zig-lamp** provides seamless ZLS (Zig Language Server) management for Neovim and powerful build.zig.zon parsing capabilities for Zig projects.

## Features

### For Neovim Users
- **Automatic ZLS Management**: Download, install, and manage ZLS versions automatically
- **Smart Version Matching**: Automatically matches ZLS versions with your Zig installation
- **Package Manager UI**: Visual interface for managing Zig dependencies in build.zig.zon
- **Build Integration**: Execute Zig build commands directly from Neovim
- **Project Info Panel**: Display comprehensive project and toolchain information
- **Zero Configuration**: Works out of the box with sensible defaults

### For Zig Developers
- **ZON Parser**: Parse build.zig.zon files into JSON format
- **Hash Verification**: SHA256 checksum validation for downloaded packages
- **ZON Formatter**: Format build.zig.zon files with proper structure
- **FFI Interface**: C-compatible API for integration with other tools

## Requirements

### Neovim Plugin
- **Neovim**: 0.10 or later
- **Zig**: 0.14.0 or later
- **Dependencies**: 
  - [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
  - [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig)

### System Tools
- **Windows**: `curl` and `unzip`
- **Unix-like systems**: `curl` and `tar`

## Installation

### Using lazy.nvim

```lua
{
    "jinzhongjia/zig-lamp",
    event = "VeryLazy",
    build = ":ZigLamp build sync",
    dependencies = {
        "neovim/nvim-lspconfig",
        "nvim-lua/plenary.nvim",
    },
    init = function()
        -- Configuration options (all optional)
        
        -- Timeout in milliseconds for automatic ZLS installation
        -- Set to nil to disable auto-install
        vim.g.zig_lamp_zls_auto_install = nil
        
        -- Fallback to system ZLS if local version not found
        -- Set to any non-negative value to enable
        vim.g.zig_lamp_fall_back_sys_zls = nil
        
        -- LSP configuration options passed to lspconfig
        vim.g.zig_lamp_zls_lsp_opt = {}
        
        -- UI customization
        vim.g.zig_lamp_pkg_help_fg = "#CF5C00"
        vim.g.zig_lamp_zig_fetch_timeout = 5000
    end,
}
```

> **Important**: Do not configure ZLS through lspconfig directly. zig-lamp handles ZLS setup automatically.

### Version Compatibility

| zig-lamp | Zig Version | Neovim |
|----------|-------------|---------|
| 0.0.1    | 0.13.0 and earlier | 0.10+ |
| latest   | 0.14.0+     | 0.10+ |

## Commands

### ZLS Management
- `:ZigLamp zls install` - Install ZLS matching current Zig version
- `:ZigLamp zls uninstall` - Remove installed ZLS version

### Project Management
- `:ZigLamp info` - Show project and toolchain information
- `:ZigLamp pkg` - Open package manager interface
- `:ZigLamp build [sync|async] [timeout]` - Build the zig-lamp library

### Build Command Options
- `async` (default) - Non-blocking build, returns immediately
- `sync [timeout]` - Blocking build with optional timeout in milliseconds
- `sync 20000` - Sync build with 20-second timeout

## Package Manager Interface

The package manager provides an intuitive interface for managing Zig dependencies:

### Key Bindings
- `q` - Quit the package manager
- `i` - Add or edit dependency
- `o` - Toggle between URL and local path dependencies
- `<leader>r` - Reload from build.zig.zon file
- `d` - Delete selected dependency or path
- `<leader>s` - Save changes to build.zig.zon file

### Features
- Visual dependency management
- Automatic hash generation for URL dependencies
- Support for both URL and local path dependencies
- Real-time file synchronization
- Syntax highlighting and help text

## Using zig-lamp as a Zig Library

### Installation

1. **Add to build.zig.zon**:
```bash
# Recommended: Use specific commit instead of branch
zig fetch --save https://github.com/jinzhongjia/zig-lamp/archive/main.tar.gz

# Alternative: Git URL (requires git)
zig fetch --save git+https://github.com/jinzhongjia/zig-lamp
```

2. **Configure build.zig**:
```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Add zig-lamp dependency
    const zig_lamp = b.dependency("zig-lamp", .{
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "your-app",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Import zig-lamp module
    exe.root_module.addImport("zigLamp", zig_lamp.module("zigLamp"));
    
    b.installArtifact(exe);
}
```

### API Usage

```zig
const std = @import("std");
const zigLamp = @import("zigLamp");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse build.zig.zon to JSON
    const file = try std.fs.cwd().openFile("build.zig.zon", .{});
    defer file.close();
    
    var output = std.ArrayList(u8).init(allocator);
    defer output.deinit();
    
    try zigLamp.zig2json(
        allocator,
        file.reader().any(),
        output.writer(),
        void{},
        .{ .file_name = "build.zig.zon" }
    );
    
    std.log.info("JSON output: {s}", .{output.items});

    // Verify file hash
    const digest = try zigLamp.sha256Digest(file);
    std.log.info("SHA256: {}", .{std.fmt.fmtSliceHexLower(&digest)});

    // Format ZON file
    const source = "@import(\"std\")";
    const formatted = try zigLamp.fmtZon(source, allocator);
    defer allocator.free(formatted);
    std.log.info("Formatted: {s}", .{formatted});
}
```

## Architecture

### Neovim Plugin Structure
```
lua/zig-lamp/
├── core/           # Core functionality
│   ├── core_cmd.lua    # Command system
│   ├── core_config.lua # Configuration management
│   ├── core_ffi.lua    # FFI interface to Zig library
│   └── core_util.lua   # Utility functions
├── info.lua        # Information display
├── pkg/            # Package manager
├── zig/            # Zig integration
└── zls/            # ZLS management
```

### Zig Library Structure
```
src/
├── zig-lamp.zig    # Main library interface
├── zon2json.zig    # ZON to JSON parser
└── fmtzon.zig      # ZON formatter
```

## Troubleshooting

### Common Issues

**ZLS Not Found**: Run `:ZigLamp zls install` to download the appropriate ZLS version.

**Build Failures**: Ensure you have the required system tools (curl, unzip/tar) installed.

**Library Crashes**: If the Zig library causes Neovim crashes, please file an issue with:
- Neovim version
- Zig version
- Error reproduction steps

**Permission Errors**: Make sure Neovim has write access to its data directory.

## Development

### Building from Source
```bash
# Clone the repository
git clone https://github.com/jinzhongjia/zig-lamp.git
cd zig-lamp

# Build the library
zig build -Doptimize=ReleaseFast

# Run tests
zig build test
```

### Contributing
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## Screenshots

### Package Manager Interface
![Package Manager](https://github.com/user-attachments/assets/01324e66-5912-4532-beeb-ac82c3ca84d0)

### Project Information Panel
![Info Panel](https://github.com/user-attachments/assets/c5c988b5-d0b4-453e-8967-2b00b2bd3a11)

## License

This project is open source. See the repository for license details.

## Support

- **Issues**: [GitHub Issues](https://github.com/jinzhongjia/zig-lamp/issues)
- **Discussions**: [GitHub Discussions](https://github.com/jinzhongjia/zig-lamp/discussions)

---

**Note**: Since this plugin integrates with external libraries via FFI, stability depends on the Zig compilation target and C API compatibility. Please report any crashes or unexpected behavior.
