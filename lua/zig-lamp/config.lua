---@diagnostic disable-next-line: undefined-global
local vim = vim

local System = require("zig-lamp.system")

local Config = {}

Config.version = "0.1.0"

local function default_paths()
    local data = System.normalize(vim.fs.joinpath(vim.fn.stdpath("data"), "zig-lamp"))
    return {
        data = data,
        tmp = System.normalize(vim.fs.joinpath(data, "tmp")),
        cache = System.normalize(vim.fs.joinpath(data, "cache")),
    }
end

local defaults = {
    zls = {
        auto_install = nil,
        fall_back_sys = false,
        lsp_opt = {},
        settings = {},
        version_check_interval = 3600,
        fetch_timeout = 5000,
    },
    zig = {
        cmd = "zig",
        timeout = 15000,
    },
    ui = {
        pkg_help_fg = "#CF5C00",
        border_style = "rounded",
        window_blend = 0,
        icons = {
            package = "📦",
            build = "🔨",
            error = "❌",
            warning = "⚠️",
            info = "ℹ️",
            success = "✅",
        },
    },
    build = {
        timeout = 30000,
        mode = "async",
        optimization = "ReleaseFast",
        parallel_jobs = 0,
    },
    logging = {
        level = "warn",
        max_history = 100,
        title = "zig-lamp",
    },
    paths = default_paths(),
}

local current = vim.deepcopy(defaults)

local global_aliases = {
    zig_lamp_zls_auto_install = { "zls", "auto_install" },
    zig_lamp_fall_back_sys_zls = { "zls", "fall_back_sys", function(value)
        if value == nil then
            return false
        end
        if type(value) == "number" then
            return value ~= 0
        end
        if type(value) == "string" then
            return value ~= "" and value ~= "0"
        end
        return value == true
    end },
    zig_lamp_zls_lsp_opt = { "zls", "lsp_opt" },
    zig_lamp_zls_settings = { "zls", "settings" },
    zig_lamp_pkg_help_fg = { "ui", "pkg_help_fg" },
    zig_lamp_zig_fetch_timeout = { "zls", "fetch_timeout" },
    zig_lamp_zig_cmd = { "zig", "cmd" },
    zig_lamp_zig_timeout = { "zig", "timeout" },
}

local function segments(path)
    if type(path) == "table" then
        return path
    end
    return vim.split(path, ".", { trimempty = true, plain = true })
end

local function set_by_path(tbl, path, value)
    local target = tbl
    for index = 1, #path - 1 do
        local key = path[index]
        if type(target[key]) ~= "table" then
            target[key] = {}
        end
        target = target[key]
    end
    target[path[#path]] = value
end

local function get_by_path(tbl, path)
    local result = tbl
    for _, key in ipairs(path) do
        if type(result) ~= "table" then
            return nil
        end
        result = result[key]
        if result == nil then
            return nil
        end
    end
    return result
end

local function apply_globals(conf)
    for name, mapping in pairs(global_aliases) do
        local value = vim.g[name]
        if value ~= nil then
            if mapping[3] and type(mapping[3]) == "function" then
                value = mapping[3](value)
            end
            set_by_path(conf, { mapping[1], mapping[2] }, value)
        end
    end
end

local function ensure_paths(conf)
    local paths = conf.paths or default_paths()
    for key, value in pairs(paths) do
        paths[key] = System.normalize(value)
        System.ensure_dir(paths[key])
    end
    conf.paths = paths
end

function Config.bootstrap(user_config)
    local merged = vim.tbl_deep_extend("force", {}, defaults, user_config or {})
    apply_globals(merged)
    ensure_paths(merged)
    current = merged
    return Config.get()
end

function Config.reset()
    current = vim.deepcopy(defaults)
    ensure_paths(current)
end

function Config.get(path)
    if not path then
        return vim.deepcopy(current)
    end
    local value = get_by_path(current, segments(path))
    if type(value) == "table" then
        return vim.deepcopy(value)
    end
    return value
end

function Config.set(path, value)
    set_by_path(current, segments(path), value)
end

function Config.paths()
    return Config.get("paths")
end

return Config

