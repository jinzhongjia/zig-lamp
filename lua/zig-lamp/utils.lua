local Utils = {}

local function is_identifier(value)
    return value:match("^[%a_][%w_]*$") ~= nil
end

local function is_array(tbl)
    if type(tbl) ~= "table" then
        return false
    end
    local count = 0
    for key in pairs(tbl) do
        count = count + 1
        if tbl[count] == nil then
            return false
        end
    end
    return true
end

local function quote_string(value)
    return string.format('"%s"', value)
end

function Utils.data_to_zon(value, ctx)
    ctx = ctx or {}
    local value_type = type(value)

    if value_type == "table" then
        local parts = {}
        local is_list = is_array(value)
        for key, item in pairs(value) do
            if is_list then
                table.insert(parts, Utils.data_to_zon(item, { in_array = true }))
            else
                local rendered_key
                if type(key) == "string" and is_identifier(key) then
                    rendered_key = string.format(".%s = ", key)
                else
                    rendered_key = string.format('.@"%s" = ', key)
                end
                table.insert(parts, rendered_key .. Utils.data_to_zon(item, { in_array = false }))
            end
        end

        if #parts == 0 then
            return ".{}"
        end

        local indent = ctx.indent or "    "
        local inner = table.concat(parts, ",\n" .. indent)
        return string.format(".{\n%s%s,\n}", indent, inner)
    elseif value_type == "string" then
        if ctx.in_array then
            return quote_string(value)
        end
        if is_identifier(value) then
            return "." .. value
        end
        return quote_string(value)
    elseif value_type == "boolean" then
        return value and "true" or "false"
    elseif value_type == "number" then
        return tostring(value)
    end
    return '""'
end

function Utils.pkg_to_zon(info)
    local blocks = {}
    local function add(line)
        table.insert(blocks, "    " .. line)
    end

    if info.name and info.name ~= "" then
        add(".name = " .. Utils.data_to_zon(info.name))
    end

    if info.version and info.version ~= "" then
        add(".version = " .. Utils.data_to_zon(info.version))
    end

    if info.fingerprint then
        add(".fingerprint = " .. tostring(info.fingerprint))
    end

    if info.minimum_zig_version and info.minimum_zig_version ~= "" then
        add(".minimum_zig_version = " .. Utils.data_to_zon(info.minimum_zig_version))
    end

    if info.dependencies and not vim.tbl_isempty(info.dependencies) then
        add(".dependencies = " .. Utils.data_to_zon(info.dependencies))
    else
        add(".dependencies = .{}")
    end

    if info.paths and #info.paths > 0 then
        add(".paths = " .. Utils.data_to_zon(info.paths))
    else
        add(".paths = .{}")
    end

    return ".{\n" .. table.concat(blocks, ",\n") .. ",\n}"
end

function Utils.adjust_brightness(hex, delta)
    local function clamp(value)
        return math.min(255, math.max(0, value))
    end
    local r = tonumber(hex:sub(2, 3), 16) or 0
    local g = tonumber(hex:sub(4, 5), 16) or 0
    local b = tonumber(hex:sub(6, 7), 16) or 0
    return string.format("#%02X%02X%02X", clamp(r + delta), clamp(g + delta), clamp(b + delta))
end

return Utils

