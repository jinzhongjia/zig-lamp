local Pkg = require("zig-lamp.services.pkg")
local Log = require("zig-lamp.log")

local UI = {}

local function format_dependencies(deps)
    local lines = {}
    if not deps or vim.tbl_isempty(deps) then
        table.insert(lines, "  (无依赖)")
        return lines
    end

    for name, info in pairs(deps) do
        table.insert(lines, string.format("  - %s", name))
        if info.url then
            table.insert(lines, string.format("      url: %s", info.url))
        end
        if info.path then
            table.insert(lines, string.format("      path: %s", info.path))
        end
        if info.hash then
            table.insert(lines, string.format("      hash: %s", info.hash))
        end
        if info.lazy ~= nil then
            table.insert(lines, string.format("      lazy: %s", tostring(info.lazy)))
        end
    end
    return lines
end

local function build_lines(state)
    local info = state.zon or {}
    local lines = {
        "build.zig.zon",
        string.format("  路径: %s", state.path or "未找到"),
        "",
        string.format("  名称: %s", info.name or "[未设置]"),
        string.format("  版本: %s", info.version or "[未设置]"),
        string.format("  最低 Zig 版本: %s", info.minimum_zig_version or "[未设置]"),
        "",
        "路径:",
    }

    if info.paths and #info.paths > 0 then
        for _, path in ipairs(info.paths) do
            table.insert(lines, "  - " .. path)
        end
    else
        table.insert(lines, "  (无额外路径，默认全部包含)")
    end

    table.insert(lines, "")
    table.insert(lines, "依赖:")
    vim.list_extend(lines, format_dependencies(info.dependencies))
    table.insert(lines, "")
    table.insert(lines, "键位: q=关闭  r=重载  s=保存  e=编辑信息  p=配置路径")
    table.insert(lines, "      a=添加依赖  d=删除依赖  h=刷新依赖 hash")
    return lines
end

local function render(state)
    if not vim.api.nvim_buf_is_valid(state.buf) then
        return
    end
    vim.api.nvim_buf_set_option(state.buf, "modifiable", true)
    vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, build_lines(state))
    vim.api.nvim_buf_set_option(state.buf, "modifiable", false)
end

local function prompt(prompt_text, default)
    local ok, result = pcall(vim.ui.input, { prompt = prompt_text, default = default })
    if not ok then
        return nil
    end
    return result
end

local function edit_metadata(state)
    local info = state.zon
    local name = prompt("包名称:", info.name or "")
    if name then
        info.name = name ~= "" and name or nil
    end

    local version = prompt("包版本:", info.version or "")
    if version then
        info.version = version ~= "" and version or nil
    end

    local min_zig = prompt("最低 Zig 版本:", info.minimum_zig_version or "")
    if min_zig then
        info.minimum_zig_version = min_zig ~= "" and min_zig or nil
    end
    render(state)
end

local function edit_paths(state)
    local info = state.zon
    local current = info.paths and table.concat(info.paths, ", ") or ""
    local value = prompt("逗号分隔的路径列表 (留空表示全部)", current)
    if value == nil then
        return
    end
    if value == "" then
        info.paths = nil
    else
        local paths = {}
        for entry in value:gmatch("([^,]+)") do
            table.insert(paths, vim.trim(entry))
        end
        info.paths = paths
    end
    render(state)
end

local function add_dependency(state)
    local deps = state.zon.dependencies or {}
    state.zon.dependencies = deps

    local name = prompt("依赖名称:", "")
    if not name or name == "" then
        return
    end

    local dep = deps[name] or {}
    local mode = prompt("类型 (url/path):", dep.url and "url" or "path") or "url"
    if mode == "url" then
        local url = prompt("URL:", dep.url or "")
        if not url or url == "" then
            return
        end
        dep.url = url
        local hash = Pkg.fetch_hash(url)
        if hash then
            dep.hash = hash
        end
        dep.path = nil
    else
        local path = prompt("本地路径:", dep.path or "")
        if not path or path == "" then
            return
        end
        dep.path = path
        dep.url = nil
        dep.hash = nil
    end

    local lazy = prompt("lazy (true/false/空):", dep.lazy and tostring(dep.lazy) or "")
    if lazy == "true" then
        dep.lazy = true
    elseif lazy == "false" then
        dep.lazy = false
    else
        dep.lazy = nil
    end

    deps[name] = dep
    render(state)
end

local function delete_dependency(state)
    if not state.zon.dependencies or vim.tbl_isempty(state.zon.dependencies) then
        Log.warn("没有依赖可以删除")
        return
    end
    local name = prompt("要删除的依赖名称:", "")
    if not name or name == "" then
        return
    end
    if state.zon.dependencies[name] then
        state.zon.dependencies[name] = nil
        render(state)
    else
        Log.warn("未找到依赖 " .. name)
    end
end

local function refresh_hash(state)
    local name = prompt("需要刷新 hash 的依赖名称:", "")
    if not name or name == "" then
        return
    end
    local dep = state.zon.dependencies and state.zon.dependencies[name]
    if not dep or not dep.url then
        Log.warn("依赖不存在或不是 URL 类型")
        return
    end
    local hash = Pkg.fetch_hash(dep.url)
    if hash then
        dep.hash = hash
        Log.info("已刷新 hash", { dependency = name })
        render(state)
    end
end

local function reload(state)
    local info, path = Pkg.read(state.path)
    if not info then
        return
    end
    state.zon = info
    state.path = path
    render(state)
    Log.info("已重新加载 build.zig.zon")
end

local function save(state)
    if not state.path then
        Log.error("未知的 build.zig.zon 路径")
        return
    end
    if Pkg.write(state.path, state.zon) then
        Log.info("保存成功")
    end
end

local function close_window(state)
    if state.win and vim.api.nvim_win_is_valid(state.win) then
        vim.api.nvim_win_close(state.win, true)
    end
end

local function set_keymaps(state)
    local buf = state.buf
    local function map(lhs, fn, desc)
        vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, silent = true, desc = desc })
    end

    map("q", function()
        close_window(state)
    end, "关闭窗口")

    map("r", function()
        reload(state)
    end, "重载文件")

    map("s", function()
        save(state)
    end, "保存文件")

    map("e", function()
        edit_metadata(state)
    end, "编辑基本信息")

    map("p", function()
        edit_paths(state)
    end, "编辑路径")

    map("a", function()
        add_dependency(state)
    end, "添加依赖")

    map("d", function()
        delete_dependency(state)
    end, "删除依赖")

    map("h", function()
        refresh_hash(state)
    end, "刷新依赖 hash")
end

function UI.open()
    local info, path = Pkg.read()
    if not info then
        vim.notify(
            "无法打开包管理面板：请先运行 :ZigLampBuild 构建本地 FFI 库",
            vim.log.levels.WARN,
            { title = "ZigLamp" }
        )
        return
    end

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
    vim.api.nvim_buf_set_option(buf, "filetype", "ziglamp_pkg")

    local width = math.min(90, math.floor(vim.o.columns * 0.7))
    local height = math.min(30, math.floor(vim.o.lines * 0.7))

    local win = vim.api.nvim_open_win(buf, true, {
        relative = "editor",
        width = width,
        height = height,
        row = math.floor((vim.o.lines - height) / 2),
        col = math.floor((vim.o.columns - width) / 2),
        style = "minimal",
        border = "rounded",
        title = "build.zig.zon",
        title_pos = "center",
    })

    local state = {
        buf = buf,
        win = win,
        path = path,
        zon = info,
    }

    render(state)
    set_keymaps(state)
end

return UI

