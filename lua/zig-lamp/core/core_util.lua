-- Core utility functions for zig-lamp plugin
-- Provides platform detection, notifications, and data conversion utilities

local vim = vim

local M = {}

-- Platform and architecture detection
local arch = vim.uv.os_uname().machine

-- Get normalized architecture string
function M.arch()
    return arch == "arm64" and "aarch64" or arch
end

-- Detect operating system
if vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1 then
    M.sys = "windows"
elseif vim.fn.has("macunix") == 1 then
    M.sys = "macos"
elseif vim.fn.has("unix") == 1 then
    M.sys = "linux"
end

-- File system utilities
function M.mkdir(path)
    vim.fn.mkdir(path, "p")
end

-- Notification system with consistent prefix
local NOTIFY_PREFIX = "[ZigLamp]: "

-- Show error notification
function M.Error(message)
    vim.api.nvim_notify(NOTIFY_PREFIX .. message, vim.log.levels.ERROR, {})
end

-- Show info notification
function M.Info(message)
    vim.api.nvim_notify(NOTIFY_PREFIX .. message, vim.log.levels.INFO, {})
end

-- Show warning notification
function M.Warn(message)
    vim.api.nvim_notify(NOTIFY_PREFIX .. message, vim.log.levels.WARN, {})
end

-- Check if table is an array (consecutive integer keys starting from 1)
local function is_array(t)
    local i = 0
    for _ in pairs(t) do
        i = i + 1
        if t[i] == nil then
            return false
        end
    end
    return true
end

-- Check if string is a valid Zig identifier
local function is_valid_identifier(str)
    local first_char = str:sub(1, 1)
    return not str:find("-") and first_char:match("[%a_]")
end

-- Check if a string should be formatted as a symbol (.name) or string ("name")
local function should_be_symbol(str)
    -- Common cases that should be symbols
    if str:match("^[%a_][%w_]*$") then -- Valid identifier
        return true
    end
    return false
end

function M.data2zon(obj, context)
    local obj_type = type(obj)
    local ctx = context or {}

    if obj_type == "table" then
        local is_arr = is_array(obj)
        local items = {}

        for key, value in pairs(obj) do
            if not is_arr then
                local key_str
                if is_valid_identifier(key) then
                    key_str = "." .. key .. " = "
                else
                    key_str = '.@"' .. key .. '" = '
                end
                table.insert(
                    items,
                    key_str .. M.data2zon(value, { parent_key = key })
                )
            else
                table.insert(items, M.data2zon(value, { in_array = true }))
            end
        end

        if #items == 0 then
            return ".{}"
        end

        -- Format with proper indentation and newlines
        if is_arr then
            -- Always format arrays as multi-line for better readability
            local content = table.concat(items, ",\n    ")
            return ".{\n    " .. content .. ",\n}"
        else
            -- Object format
            local content = table.concat(items, ",\n    ")
            return ".{\n    " .. content .. ",\n}"
        end
    elseif obj_type == "string" then
        -- Use symbol format for simple identifiers, but not in array context
        -- Arrays should always use string format for paths and other values
        if should_be_symbol(obj) and not ctx.in_array then
            return "." .. obj
        else
            return string.format('"%s"', obj)
        end
    elseif obj_type == "boolean" then
        return obj and "true" or "false"
    elseif obj_type == "number" then
        -- Format hex numbers properly
        if obj >= 0x1000000 then -- Large numbers likely to be hex
            return string.format("0x%x", obj)
        end
        return tostring(obj)
    end

    return ""
end

-- Convert build.zon info to ZON format
function M.wrap_j2zon(info)
    local components = {}

    -- Add name
    if info.name and info.name ~= "" then
        table.insert(components, "    .name = " .. M.data2zon(info.name))
    end

    -- Add version
    if info.version and info.version ~= "" then
        table.insert(components, "    .version = " .. M.data2zon(info.version))
    end

    -- Add fingerprint (format as hex if it's a number)
    if info.fingerprint then
        local fingerprint_str
        if type(info.fingerprint) == "number" then
            fingerprint_str = string.format("0x%x", info.fingerprint)
        else
            fingerprint_str = tostring(info.fingerprint)
        end
        table.insert(components, "    .fingerprint = " .. fingerprint_str)
    end

    -- Add minimum zig version
    if info.minimum_zig_version and info.minimum_zig_version ~= "" then
        table.insert(
            components,
            "    .minimum_zig_version = "
                .. M.data2zon(info.minimum_zig_version)
        )
    end

    -- Add dependencies
    local deps = info.dependencies or {}
    if vim.tbl_isempty(deps) then
        table.insert(components, "    .dependencies = .{}")
    else
        table.insert(components, "    .dependencies = " .. M.data2zon(deps))
    end

    -- Add paths
    local paths = info.paths or {}
    if
        vim.tbl_isempty(paths)
        or (type(paths) == "table" and #paths == 1 and paths[1] == "")
    then
        table.insert(components, "    .paths = .{}")
    else
        -- Filter out empty paths
        local filtered_paths = {}
        for _, path in ipairs(paths) do
            if path ~= "" then
                table.insert(filtered_paths, path)
            end
        end

        if #filtered_paths == 0 then
            table.insert(components, "    .paths = .{}")
        else
            local paths_zon = M.data2zon(filtered_paths)
            -- Replace the default indentation with proper indentation
            paths_zon = paths_zon:gsub("\n    ", "\n        ")
            table.insert(components, "    .paths = " .. paths_zon)
        end
    end

    return ".{\n" .. table.concat(components, ",\n") .. ",\n}"
end

-- Adjust color brightness for UI theming
function M.adjust_brightness(color, amount)
    local r = tonumber(color:sub(2, 3), 16) or 0
    local g = tonumber(color:sub(4, 5), 16) or 0
    local b = tonumber(color:sub(6, 7), 16) or 0

    r = math.min(255, math.max(0, r + amount))
    g = math.min(255, math.max(0, g + amount))
    b = math.min(255, math.max(0, b + amount))

    return string.format("#%02X%02X%02X", r, g, b)
end

return M
