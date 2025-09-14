# zig-lamp

一个为 Zig 打造的 Neovim 插件 + Zig 原生库，提供 ZLS 管理、build.zig.zon 解析/格式化与便捷的构建集成。

## 功能亮点
- ZLS 管理：一键安装/卸载、自动匹配当前 Zig 版本、本地版本缓存、系统 ZLS 回退
- 信息面板：显示插件版本、数据目录、Zig/ZLS 状态与本地可用 ZLS 版本
- 包管理面板：可视化查看与编辑 `build.zig.zon`（路径、依赖、hash、lazy 等），支持从 URL 自动获取 hash
- 构建集成：提供项目构建/测试/清理命令以及插件本身动态库的一键构建
- 原生库能力（FFI）：ZON → JSON 解析、ZON 格式化、下载校验（当启用 FFI 时）

## 需求
- Neovim 0.10+
- Zig 0.15.1+
- 依赖：`plenary.nvim`（必需），`nvim-lspconfig`（在旧版 Neovim 无内置 LSP 时需要；0.11+ 优先使用内置 `vim.lsp.config`/`vim.lsp.enable`）
- 系统工具：
  - Windows：`curl`、`unzip`
  - 非 Windows：`curl`、`tar`

## 安装（lazy.nvim）
```lua
{
  "jinzhongjia/zig-lamp",
  event = "VeryLazy",
  -- 可选：构建本地 FFI 库，启用更快/更稳的校验与格式化
  build = ":ZigLampBuild async",
  dependencies = {
    "nvim-lua/plenary.nvim",
    -- 对于 Neovim < 0.11 建议加上 lspconfig
    "neovim/nvim-lspconfig",
  },
  init = function()
    -- 兼容的全局变量（可不设置，默认即可）
    -- 自动安装 ZLS：毫秒为单位的超时；设为 nil 关闭
    vim.g.zig_lamp_zls_auto_install = nil
    -- 当未找到本地 ZLS 时，是否回退到系统 zls
    vim.g.zig_lamp_fall_back_sys_zls = nil
    -- 传给 LSP 的可选配置（将与默认合并）
    vim.g.zig_lamp_zls_lsp_opt = {}
    -- ZLS 服务器设置（覆盖内置推荐配置）
    vim.g.zig_lamp_zls_settings = {}
    -- 包管理面板帮助文本颜色
    vim.g.zig_lamp_pkg_help_fg = "#CF5C00"
    -- zig fetch 获取 hash 的超时（毫秒）
    vim.g.zig_lamp_zig_fetch_timeout = 5000
  end,
}
```

> 提示：无需手动配置 zls 的 lspconfig。zig-lamp 会在进入 Zig 缓冲区时自动匹配并启动 ZLS（Neovim 0.11+ 优先使用内置 LSP API）。

## 命令
所有命令入口为 `:ZigLamp`（带有分层子命令与补全），以及一个独立命令 `:ZigLampBuild`。

- `:ZigLamp info`：打开信息面板
- `:ZigLamp health`：健康检查（zig/curl/unzip|tar/lspconfig/动态库）
- `:ZigLamp build [--args…]`：在当前 Zig 项目运行 `zig build`（参数原样透传）
- `:ZigLamp test [--args…]`：在当前 Zig 项目运行 `zig build test`
- `:ZigLamp clean`：清理项目的 `zig-out` 与 `zig-cache`
- `:ZigLamp zls install`：为当前 Zig 版本下载并安装匹配的 ZLS 版本
- `:ZigLamp zls uninstall <version>`：卸载指定本地 ZLS 版本（带版本补全）
- `:ZigLamp zls status`：显示 ZLS 状态（本地版本列表、系统 zls 可用性、当前 LSP 使用版本等）
- `:ZigLamp pkg`：打开包管理面板（查看/编辑 `build.zig.zon`）

独立命令：
- `:ZigLampBuild [async|sync] [timeout_ms]`：在插件根目录构建本插件的动态库（默认 ReleaseFast）。
  - 注意：如库已被当前 Neovim 进程加载，将提示重启后再构建。

### 包管理面板键位
- `q` 退出
- `i` 添加/编辑
- `o` 切换依赖类型（url/path）
- `<leader>r` 从文件重载
- `d` 删除路径或依赖
- `<leader>s` 保存回写到 `build.zig.zon`（自动 ZON 格式化）

## ZLS 行为与版本匹配
- 进入 Zig 文件时，若未初始化 LSP：
  - 从本地数据库匹配当前 `zig version` 对应的 ZLS 版本
  - 找不到且未允许回退：若设置了自动安装超时，将自动拉取；否则给出提示
  - 解析后按 Neovim 版本选择内置 LSP 或 `lspconfig` 进行 `zls` 配置与启动
- Windows 使用 `unzip` 解压，非 Windows 使用 `tar`
- 启用本地 FFI 库时，下载会进行校验（checksum）
- 若项目根存在 `zls.json`，将自动传给 ZLS

## ZLS 配置

### 内置推荐配置
zig-lamp 现在会自动应用推荐的 ZLS 配置，无需手动创建 `zls.json` 文件。内置配置包括：

- **基础功能**：代码片段补全、参数占位符、完整语义高亮
- **代码质量**：风格警告、全局变量高亮
- **构建功能**：保存时自动构建
- **Inlay Hints**：智能的类型和参数提示

### 自定义配置
可通过 `vim.g.zig_lamp_zls_settings` 覆盖默认配置：

```lua
-- 示例：性能优化配置（大项目）
vim.g.zig_lamp_zls_settings = {
    zls = {
        skip_std_references = true,  -- 跳过标准库引用搜索
        semantic_tokens = "partial",  -- 减少语义分析
    }
}

-- 示例：精简配置（减少干扰）
vim.g.zig_lamp_zls_settings = {
    zls = {
        warn_style = false,  -- 关闭风格警告
        inlay_hints_show_variable_type_hints = false,  -- 关闭变量类型提示
    }
}
```

### 配置优先级
1. 项目根目录的 `zls.json`（最高优先级）
2. `vim.g.zig_lamp_zls_settings` 用户配置
3. zig-lamp 内置推荐配置（默认）

## 作为 Zig 库使用
本仓库同时提供 Zig 模块用于 ZON 解析/格式化。

### 在 build.zig.zon 中添加依赖
```bash
# 推荐：固定具体提交或归档
zig fetch --save https://github.com/jinzhongjia/zig-lamp/archive/main.tar.gz

# 备选：Git URL（需要本机有 git）
zig fetch --save git+https://github.com/jinzhongjia/zig-lamp
```

### 配置 build.zig
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

### Zig API 示例
```zig
const std = @import("std");
const zigLamp = @import("zigLamp");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    // 解析 build.zig.zon 为 JSON
    const file = try std.fs.cwd().openFile("build.zig.zon", .{}); defer file.close();
    var out = std.ArrayList(u8).init(alloc); defer out.deinit();
    try zigLamp.zig2json(alloc, file.reader().any(), out.writer(), void{}, .{ .file_name = "build.zig.zon" });
    std.log.info("JSON: {s}", .{out.items});

    // ZON 格式化
    const source = ".{ .name = .zig_lamp }";
    const formatted = try zigLamp.fmtZon(source, alloc); defer alloc.free(formatted);
    std.log.info("Formatted: {s}", .{formatted});
}
```

说明：校验功能通过 FFI 暴露给 Neovim（`check_shasum`），当前未作为 Zig 公共 API 提供。

## 兼容性
- 插件版本：`0.1.0`
- 需要 Zig：`0.15.1+`
- Neovim：`0.10+`（0.11+ 将使用内置 LSP API）

## 故障排查
- ZLS 未找到：执行 `:ZigLamp zls install`，或设置 `vim.g.zig_lamp_fall_back_sys_zls = 1` 以回退系统 zls
- 动态库未加载：运行 `:ZigLampBuild sync`，构建完成后重启 Neovim；Windows 库在 `zig-out/bin`，类 Unix 在 `zig-out/lib`
- 构建失败：确认系统已安装 `curl` 与相应解压工具（Windows `unzip`，非 Windows `tar`）
- 健康检查：运行 `:ZigLamp health`

## 开发
```bash
# 构建插件本身（动态库）
zig build -Doptimize=ReleaseFast

# 运行测试
zig build test
```

## 许可证与支持
- 欢迎在仓库发起 Issue/Discussions
- 欢迎 PR，共建更好的 Zig 开发体验
