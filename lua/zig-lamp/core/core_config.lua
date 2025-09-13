-- Configuration management for zig-lamp plugin
-- Enhanced configuration system with dynamic configuration and validation support

local vim = vim
local fs, fn = vim.fs, vim.fn

local M = {}

-- Plugin version
M.version = "0.1.0"

-- Configuration schema definitions
---@class ZigLampConfigSchema
---@field zls ZigLampZLSConfig ZLS related configuration
---@field ui ZigLampUIConfig UI related configuration
---@field build ZigLampBuildConfig Build related configuration
---@field logging ZigLampLoggingConfig Logging related configuration
---@field paths ZigLampPathsConfig Path related configuration

---@class ZigLampZLSConfig
---@field auto_install number|nil Auto-install timeout in milliseconds, nil to disable
---@field fall_back_sys boolean Whether to fallback to system ZLS
---@field lsp_opt table LSP configuration options
---@field version_check_interval number Version check interval in seconds

---@class ZigLampUIConfig
---@field pkg_help_fg string Package manager help text color
---@field border_style string Window border style
---@field window_blend number Window transparency
---@field icons table Icon configuration

---@class ZigLampBuildConfig
---@field timeout number Build timeout in milliseconds
---@field mode string Default build mode
---@field optimization string Optimization level
---@field parallel_jobs number Number of parallel jobs

---@class ZigLampLoggingConfig
---@field level number Log level (1=DEBUG, 2=INFO, 3=WARN, 4=ERROR, default=3)
---@field max_history number Maximum history records
---@field file_logging boolean Whether to write log files

---@class ZigLampPathsConfig
---@field data_path string Data directory path
---@field tmp_path string Temporary files directory path
---@field cache_path string Cache directory path

-- Default configuration
local default_config = {
    zls = {
        auto_install = nil,
        fall_back_sys = false,
        lsp_opt = {},
        version_check_interval = 3600, -- 1 hour
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
        timeout = 30000, -- 30 seconds
        mode = "async",
        optimization = "ReleaseFast",
        parallel_jobs = 0, -- auto-detect
    },
    logging = {
        level = 3, -- WARN
        max_history = 100,
        file_logging = false,
    },
    paths = {
        data_path = fs.normalize(fs.joinpath(fn.stdpath("data"), "zig-lamp")),
        tmp_path = nil, -- will be auto-set
        cache_path = nil, -- will be auto-set
    },
}

-- Set default paths
default_config.paths.tmp_path = fs.normalize(fs.joinpath(default_config.paths.data_path, "tmp"))
default_config.paths.cache_path = fs.normalize(fs.joinpath(default_config.paths.data_path, "cache"))

-- Current configuration
local current_config = vim.deepcopy(default_config)
local _config_initialized = false

-- Configuration validation rules
local validation_rules = {
    zls = {
        auto_install = function(v)
            return v == nil or (type(v) == "number" and v > 0)
        end,
        fall_back_sys = function(v)
            return type(v) == "boolean"
        end,
        version_check_interval = function(v)
            return type(v) == "number" and v > 0
        end,
    },
    ui = {
        pkg_help_fg = function(v)
            return type(v) == "string" and v:match("^#%x%x%x%x%x%x$")
        end,
        border_style = function(v)
            return vim.tbl_contains({ "none", "single", "double", "rounded", "solid", "shadow" }, v)
        end,
        window_blend = function(v)
            return type(v) == "number" and v >= 0 and v <= 100
        end,
    },
    build = {
        timeout = function(v)
            return type(v) == "number" and v > 0
        end,
        mode = function(v)
            return vim.tbl_contains({ "sync", "async" }, v)
        end,
        parallel_jobs = function(v)
            return type(v) == "number" and v >= 0
        end,
    },
    logging = {
        level = function(v)
            return type(v) == "number" and v >= 0 and v <= 5
        end,
        max_history = function(v)
            return type(v) == "number" and v > 0
        end,
        file_logging = function(v)
            return type(v) == "boolean"
        end,
    },
}

-- 验证配置值
---@param config table 配置对象
---@param path string 配置路径（用于错误报告）
---@return boolean valid 是否有效
---@return string|nil error 错误信息
local function validate_config(config, path)
    path = path or "config"

    for key, value in pairs(config) do
        local current_path = path .. "." .. key
        local rule_section = validation_rules[key]

        if type(value) == "table" and rule_section then
            local valid, err = validate_config(value, current_path)
            if not valid then
                return false, err
            end
        elseif rule_section and rule_section[key] then
            if not rule_section[key](value) then
                return false, string.format("配置项 %s 的值无效: %s", current_path, vim.inspect(value))
            end
        end
    end

    return true
end

-- 初始化配置系统
function M.init()
    if _config_initialized then
        return
    end

    -- 确保数据目录存在
    local util = require("zig-lamp.core.core_util")
    util.mkdir(current_config.paths.data_path)
    util.mkdir(current_config.paths.tmp_path)
    util.mkdir(current_config.paths.cache_path)

    _config_initialized = true
end

-- 更新配置
---@param new_config table 新配置
---@return boolean success 是否成功
---@return string|nil error 错误信息
function M.update(new_config)
    if not new_config then
        return true
    end

    -- 合并配置
    local merged_config = vim.tbl_deep_extend("force", current_config, new_config)

    -- 验证配置
    local valid, err = validate_config(merged_config, "config")
    if not valid then
        return false, err
    end

    -- 应用配置
    current_config = merged_config

    -- 重新初始化（如果路径发生变化）
    if new_config.paths then
        _config_initialized = false
        M.init()
    end

    return true
end

-- 获取配置值
---@param key string|nil 配置键，nil 返回全部配置
---@return any value 配置值
function M.get(key)
    M.init() -- 确保已初始化

    if not key then
        return vim.deepcopy(current_config)
    end

    local keys = vim.split(key, ".", { plain = true })
    local value = current_config

    for _, k in ipairs(keys) do
        if type(value) ~= "table" or value[k] == nil then
            return nil
        end
        value = value[k]
    end

    return vim.deepcopy(value)
end

-- 设置配置值
---@param key string 配置键
---@param value any 配置值
---@return boolean success 是否成功
---@return string|nil error 错误信息
function M.set(key, value)
    local keys = vim.split(key, ".", { plain = true })
    local config_copy = vim.deepcopy(current_config)
    local target = config_copy

    -- 导航到目标位置
    for i = 1, #keys - 1 do
        local k = keys[i]
        if type(target[k]) ~= "table" then
            target[k] = {}
        end
        target = target[k]
    end

    -- 设置值
    target[keys[#keys]] = value

    -- 验证并应用
    return M.update(config_copy)
end

-- 重置配置为默认值
function M.reset()
    current_config = vim.deepcopy(default_config)
    _config_initialized = false
    M.init()
end

-- 导出配置到文件
---@param filepath string 文件路径
---@return boolean success 是否成功
function M.export(filepath)
    local success, err = pcall(function()
        local file = io.open(filepath, "w")
        if not file then
            error("无法打开文件: " .. filepath)
        end

        file:write("-- zig-lamp 配置文件\n")
        file:write("-- 生成时间: " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n\n")
        file:write("return " .. vim.inspect(current_config, { indent = "  " }))
        file:close()
    end)

    if not success then
        local util = require("zig-lamp.core.core_util")
        util.Error("配置导出失败", { error = tostring(err), file = filepath })
        return false
    end

    return true
end

-- 从文件导入配置
---@param filepath string 文件路径
---@return boolean success 是否成功
function M.import(filepath)
    local success, result = pcall(dofile, filepath)
    if not success then
        local util = require("zig-lamp.core.core_util")
        util.Error("配置导入失败", { error = tostring(result), file = filepath })
        return false
    end

    if type(result) ~= "table" then
        local util = require("zig-lamp.core.core_util")
        util.Error("配置文件格式无效", { file = filepath })
        return false
    end

    return M.update(result)
end

-- 向后兼容的属性访问
M.data_path = current_config.paths.data_path
M.tmp_path = current_config.paths.tmp_path

return M
