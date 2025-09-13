-- Error handling and user feedback mechanism
-- Provides unified error handling, logging and user notification functionality

local vim = vim

local M = {}

--- Error level enumeration
--- Main levels: DEBUG(1) -> INFO(2) -> WARN(3) -> ERROR(4)
--- Default level: WARN (3)
M.Level = {
    TRACE = 0, -- Detailed tracing (rarely used)
    DEBUG = 1, -- Debug information
    INFO = 2, -- General information
    WARN = 3, -- Warnings (default level)
    ERROR = 4, -- Errors
    FATAL = 5, -- Fatal errors
}

--- Mapping from error level to Vim log level
local level_to_vim = {
    [M.Level.TRACE] = vim.log.levels.TRACE,
    [M.Level.DEBUG] = vim.log.levels.DEBUG,
    [M.Level.INFO] = vim.log.levels.INFO,
    [M.Level.WARN] = vim.log.levels.WARN,
    [M.Level.ERROR] = vim.log.levels.ERROR,
    [M.Level.FATAL] = vim.log.levels.ERROR,
}

--- Error level names
local level_names = {
    [M.Level.TRACE] = "TRACE",
    [M.Level.DEBUG] = "DEBUG",
    [M.Level.INFO] = "INFO",
    [M.Level.WARN] = "WARN",
    [M.Level.ERROR] = "ERROR",
    [M.Level.FATAL] = "FATAL",
}

--- Notification prefix
local NOTIFY_PREFIX = "[ZigLamp] "

--- Current log level
local current_log_level = M.Level.WARN

--- Log history
local log_history = {}
local max_history = 100

-- Safely call nvim notifications even in fast-event contexts
local function safe_notify(msg, vim_level, opts)
    local function do_notify()
        if type(vim.notify) == "function" then
            pcall(vim.notify, msg, vim_level, opts or {})
        else
            -- Fallback to echo when notify is unavailable
            pcall(vim.api.nvim_echo, { { tostring(msg) } }, true, {})
        end
    end
    if vim.in_fast_event() then
        vim.schedule(do_notify)
    else
        do_notify()
    end
end

local function safe_notify_once(msg, vim_level)
    local function do_notify_once()
        if type(vim.notify_once) == "function" then
            pcall(vim.notify_once, msg, vim_level)
        else
            -- Fallback to notify
            if type(vim.notify) == "function" then
                pcall(vim.notify, msg, vim_level)
            else
                pcall(vim.api.nvim_echo, { { tostring(msg) } }, true, {})
            end
        end
    end
    if vim.in_fast_event() then
        vim.schedule(do_notify_once)
    else
        do_notify_once()
    end
end

--- Unconditional user notification (bypass log level gating)
---@param message string
---@param level integer|nil vim.log.levels.*
---@param opts table|nil
function M.notify_always(message, level, opts)
    local vim_level = level or vim.log.levels.INFO
    safe_notify(NOTIFY_PREFIX .. tostring(message), vim_level, opts or { title = "ZigLamp" })
end

--- 设置日志级别
---@param level number 日志级别
function M.set_log_level(level)
    current_log_level = level
end

--- 获取当前日志级别
---@return number level 当前日志级别
function M.get_log_level()
    return current_log_level
end

--- 记录日志条目
---@param level number 日志级别
---@param message string 消息
---@param context table|nil 上下文信息
local function log_entry(level, message, context)
    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    local entry = {
        timestamp = timestamp,
        level = level,
        level_name = level_names[level],
        message = message,
        context = context,
    }

    -- 添加到历史记录
    table.insert(log_history, entry)
    if #log_history > max_history then
        table.remove(log_history, 1)
    end

    return entry
end

--- 格式化错误消息
---@param message string 基础消息
---@param context table|nil 上下文信息
---@return string formatted 格式化后的消息
local function format_message(message, context)
    if not context then
        return message
    end

    local parts = { message }

    if context.operation then
        table.insert(parts, string.format("Operation: %s", context.operation))
    end

    if context.file then
        table.insert(parts, string.format("File: %s", context.file))
    end

    if context.error then
        table.insert(parts, string.format("Error: %s", context.error))
    end

    if context.suggestion then
        table.insert(parts, string.format("Suggestion: %s", context.suggestion))
    end

    return table.concat(parts, " | ")
end

--- 通用日志记录函数
---@param level number 日志级别
---@param message string 消息
---@param context table|nil 上下文信息
---@param notify boolean|nil 是否显示通知
local function log(level, message, context, notify)
    if level < current_log_level then
        return
    end

    local entry = log_entry(level, message, context)
    local formatted_msg = format_message(message, context)

    -- 显示通知（在 fast event 中安全调度）
    if notify ~= false and level >= M.Level.INFO then
        local vim_level = level_to_vim[level] or vim.log.levels.INFO
        safe_notify(NOTIFY_PREFIX .. formatted_msg, vim_level, { title = "ZigLamp" })
    end

    -- Output single-line log hint only for DEBUG level to avoid duplicates
    if level == M.Level.DEBUG then
        safe_notify_once(string.format("[ZigLamp:%s] %s", entry.level_name, formatted_msg), level_to_vim[level])
    end
end

--- 记录跟踪信息
---@param message string 消息
---@param context table|nil 上下文信息
function M.trace(message, context)
    log(M.Level.TRACE, message, context, false)
end

--- 记录调试信息
---@param message string 消息
---@param context table|nil 上下文信息
function M.debug(message, context)
    log(M.Level.DEBUG, message, context, false)
end

--- 记录信息
---@param message string 消息
---@param context table|nil 上下文信息
---@param notify boolean|nil 是否显示通知（默认 true）
function M.info(message, context, notify)
    log(M.Level.INFO, message, context, notify)
end

--- 记录警告
---@param message string 消息
---@param context table|nil 上下文信息
---@param notify boolean|nil 是否显示通知（默认 true）
function M.warn(message, context, notify)
    log(M.Level.WARN, message, context, notify)
end

--- 记录错误
---@param message string 消息
---@param context table|nil 上下文信息
---@param notify boolean|nil 是否显示通知（默认 true）
function M.error(message, context, notify)
    log(M.Level.ERROR, message, context, notify)
end

--- 记录致命错误
---@param message string 消息
---@param context table|nil 上下文信息
function M.fatal(message, context)
    log(M.Level.FATAL, message, context, true)
end

--- 安全执行函数并处理错误
---@param func function 要执行的函数
---@param error_context table|nil 错误上下文信息
---@return boolean success 是否成功
---@return any result 执行结果或错误信息
function M.safe_call(func, error_context)
    local success, result = pcall(func)

    if not success then
        local context = vim.tbl_extend("force", error_context or {}, {
            error = tostring(result),
        })
        M.error("函数执行失败", context)
        return false, result
    end

    return true, result
end

--- 包装异步函数的错误处理
---@param func function 异步函数
---@param error_context table|nil 错误上下文
---@return function wrapped 包装后的函数
function M.wrap_async(func, error_context)
    return function(...)
        local args = { ... }
        local success, result = M.safe_call(function()
            return func(unpack(args))
        end, error_context)

        if not success then
            M.error(
                "异步操作失败",
                vim.tbl_extend("force", error_context or {}, {
                    error = tostring(result),
                })
            )
        end

        return result
    end
end

--- 获取日志历史
---@param level number|nil 过滤的最低日志级别
---@return table logs 日志条目列表
function M.get_logs(level)
    if not level then
        return vim.deepcopy(log_history)
    end

    local filtered = {}
    for _, entry in ipairs(log_history) do
        if entry.level >= level then
            table.insert(filtered, entry)
        end
    end

    return filtered
end

--- 清空日志历史
function M.clear_logs()
    log_history = {}
end

--- 显示日志历史
function M.show_logs()
    local logs = M.get_logs(M.Level.INFO)
    if #logs == 0 then
        M.info("暂无日志记录")
        return
    end

    local lines = { "=== ZigLamp 日志历史 ===" }
    for _, entry in ipairs(logs) do
        local line = string.format("[%s] %s: %s", entry.timestamp, entry.level_name, entry.message)
        table.insert(lines, line)
    end

    -- 在新缓冲区中显示日志
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_buf_set_option(buf, "filetype", "log")
    vim.api.nvim_buf_set_option(buf, "modifiable", false)

    local win = vim.api.nvim_open_win(buf, true, {
        relative = "editor",
        width = math.min(120, vim.o.columns - 4),
        height = math.min(#lines + 2, vim.o.lines - 4),
        row = math.floor((vim.o.lines - math.min(#lines + 2, vim.o.lines - 4)) / 2),
        col = math.floor((vim.o.columns - math.min(120, vim.o.columns - 4)) / 2),
        border = "rounded",
        title = "ZigLamp 日志",
        title_pos = "center",
    })

    -- 设置按键映射
    vim.api.nvim_buf_set_keymap(buf, "n", "q", "<cmd>close<cr>", {
        noremap = true,
        silent = true,
        desc = "关闭日志窗口",
    })
end

-- 向后兼容的别名
M.Info = M.info
M.Warn = M.warn
M.Error = M.error

return M
