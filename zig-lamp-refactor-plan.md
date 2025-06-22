以下是针对 Neovim 插件的重构方案，分为四个阶段，每个阶段都包含主要目标和建议的重构内容。

---

## 1. core

- **目标**：将核心工具、配置、通知、命令注册、ffi 相关逻辑与具体模块解耦，形成独立的 core 层，便于后续维护和扩展。
- **建议重构内容**：
  - 新建 `lua/zig-lamp/core/` 目录。
  - 将 `util.lua`、`config.lua`、`ffi.lua`、`cmd.lua` 移动到 `core/` 下，并适当重命名为 `core_util.lua`、`core_config.lua`、`core_ffi.lua`、`core_cmd.lua`。
  - 修改 require 路径，所有模块引用 core 相关内容时统一走 `zig-lamp.core.*`。
  - 保持 core 层无业务逻辑，仅提供基础能力。

## 2. zls module

- **目标**：将 zls 相关逻辑（如安装、卸载、版本管理、lsp 启动等）独立为 `zls` 模块，接口清晰，依赖 core 层。
- **建议重构内容**：
  - 保留 `module/zls.lua`，但重命名为 `zls.lua` 并移至 `lua/zig-lamp/` 根目录或 `lua/zig-lamp/zls/`。
  - 只通过 require `zig-lamp.core.*` 获取工具和配置。
  - 将命令注册、lsp 启动、zls 版本管理等方法聚合，接口文档化。
  - 其他模块如 info 展示、pkg 依赖等通过接口调用，不直接操作 zls 内部状态。

## 3. zig module

- **目标**：将 zig 相关逻辑（如 zig 版本获取、zig 命令调用等）独立为 `zig` 模块，接口简洁，依赖 core 层。
- **建议重构内容**：
  - 保留 `module/zig.lua`，但重命名为 `zig.lua` 并移至 `lua/zig-lamp/` 根目录或 `lua/zig-lamp/zig/`。
  - 只通过 require `zig-lamp.core.*` 获取工具和配置。
  - 提供统一的 zig 版本获取、zig 命令执行等接口。
  - 其他模块通过接口调用，不直接依赖 zig 具体实现。

## 4. pkg module

- **目标**：将 pkg 相关逻辑（如 build.zig.zon 解析、依赖管理、UI 渲染等）独立为 `pkg` 模块，接口清晰，依赖 core 层和 zig/zls。
- **建议重构内容**：
  - 保留 `module/pkg.lua`，但重命名为 `pkg.lua` 并移至 `lua/zig-lamp/` 根目录或 `lua/zig-lamp/pkg/`。
  - 只通过 require `zig-lamp.core.*`、`zig-lamp.zig`、`zig-lamp.zls` 获取依赖。
  - UI 渲染、依赖编辑、同步等功能聚合，接口文档化。
  - 其他模块通过接口调用，不直接操作 pkg 内部状态。

---
