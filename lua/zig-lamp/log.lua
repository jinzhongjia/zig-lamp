local vim = vim

local Log = {}

Log.levels = {
    trace = 0,
    debug = 1,
    info = 2,
    warn = 3,
    error = 4,
    fatal = 5,
}

local level_names = {
    [Log.levels.trace] = "TRACE",
    [Log.levels.debug] = "DEBUG",
    [Log.levels.info] = "INFO",
    [Log.levels.warn] = "WARN",
    [Log.levels.error] = "ERROR",
    [Log.levels.fatal] = "FATAL",
}

local level_to_vim = {
    [Log.levels.trace] = vim.log.levels.TRACE,
    [Log.levels.debug] = vim.log.levels.DEBUG,
    [Log.levels.info] = vim.log.levels.INFO,
    [Log.levels.warn] = vim.log.levels.WARN,
    [Log.levels.error] = vim.log.levels.ERROR,
    [Log.levels.fatal] = vim.log.levels.ERROR,
}

local settings = {
    level = Log.levels.warn,
    max_history = 100,
    title = "zig-lamp",
}

local history = {}

local function schedule(fn)
    if vim.in_fast_event() then
        vim.schedule(fn)
    else
        fn()
    end
end

local function normalize_level(level)
    if type(level) == "string" then
        return Log.levels[level:lower()] or settings.level
    end
    return level or settings.level
end

local function push_history(entry)
    table.insert(history, entry)
    if #history > settings.max_history then
        table.remove(history, 1)
    end
end

local function format_message(message, context)
    if not context or vim.tbl_isempty(context) then
        return message
    end
    local parts = { message }
    for key, value in pairs(context) do
        local ok, rendered = pcall(vim.inspect, value)
        table.insert(parts, string.format("%s=%s", key, ok and rendered or tostring(value)))
    end
    return table.concat(parts, " | ")
end

local function notify(level, message, opts)
    local payload = string.format("[zig-lamp] %s", message)
    local vim_level = level_to_vim[level] or vim.log.levels.INFO
    schedule(function()
        if type(vim.notify) == "function" then
            vim.notify(payload, vim_level, opts or { title = settings.title })
        else
            vim.api.nvim_echo({ { payload } }, true, {})
        end
    end)
end

local function emit(level, message, context, opts)
    if level < settings.level then
        return
    end

    local formatted = format_message(message, context)
    push_history({
        timestamp = os.date("%Y-%m-%d %H:%M:%S"),
        level = level,
        level_name = level_names[level],
        message = formatted,
    })

    if not opts or opts.notify ~= false then
        notify(level, formatted, opts)
    end
end

function Log.setup(opts)
    opts = opts or {}
    settings.level = normalize_level(opts.level)
    settings.max_history = math.max(10, opts.max_history or settings.max_history)
    settings.title = opts.title or settings.title
end

function Log.set_level(level)
    settings.level = normalize_level(level)
end

function Log.get_level()
    return settings.level
end

function Log.history(min_level)
    if not min_level then
        return vim.deepcopy(history)
    end
    local filtered = {}
    for _, entry in ipairs(history) do
        if entry.level >= min_level then
            table.insert(filtered, entry)
        end
    end
    return filtered
end

function Log.clear_history()
    history = {}
end

function Log.trace(message, context, opts)
    emit(Log.levels.trace, message, context, opts)
end

function Log.debug(message, context, opts)
    emit(Log.levels.debug, message, context, opts)
end

function Log.info(message, context, opts)
    emit(Log.levels.info, message, context, opts)
end

function Log.warn(message, context, opts)
    emit(Log.levels.warn, message, context, opts)
end

function Log.error(message, context, opts)
    emit(Log.levels.error, message, context, opts)
end

function Log.fatal(message, context, opts)
    emit(Log.levels.fatal, message, context, opts)
end

function Log.wrap(fn, context)
    local ok, result = xpcall(fn, debug.traceback)
    if not ok then
        Log.error("执行失败", vim.tbl_extend("keep", { error = result }, context or {}))
        return nil, result
    end
    return result
end

function Log.notify(message, level, opts)
    notify(level or Log.levels.info, message, opts)
end

return Log

