local vim = vim

local Log = require("zig-lamp.log")

local CommandRegistry = {}
CommandRegistry.__index = CommandRegistry

local function new_node(name)
    return {
        name = name,
        children = {},
        handler = nil,
        complete = nil,
        desc = nil,
    }
end

local function find_child(node, name)
    for _, child in ipairs(node.children) do
        if child.name == name then
            return child
        end
    end
    return nil
end

local function ensure_child(node, name)
    local child = find_child(node, name)
    if not child then
        child = new_node(name)
        table.insert(node.children, child)
    end
    return child
end

function CommandRegistry.new(root_name)
    local self = setmetatable({
        root_name = root_name or "ZigLamp",
        root = new_node(root_name or "ZigLamp"),
    }, CommandRegistry)
    return self
end

function CommandRegistry:register(spec)
    local path = spec.path or {}
    local node = self.root
    for index, segment in ipairs(path) do
        node = ensure_child(node, segment)
        if index == #path then
            node.handler = spec.handler
            node.complete = spec.complete
            node.desc = spec.desc
        end
    end
end

local function matches_prefix(candidate, prefix)
    if not prefix or prefix == "" then
        return true
    end
    return candidate:find("^" .. vim.pesc(prefix)) ~= nil
end

function CommandRegistry:complete_command(_, cmdline, cursor)
    local args = vim.fn.split(cmdline)
    table.remove(args, 1)
    local node = self.root
    local depth = 0

    while depth < #args and node do
        local next_node = find_child(node, args[depth + 1])
        if not next_node then
            break
        end
        node = next_node
        depth = depth + 1
    end

    if not node then
        return {}
    end

    local candidates = {}
    for _, child in ipairs(node.children) do
        table.insert(candidates, child.name)
    end

    if type(node.complete) == "function" then
        local ok, extra = pcall(node.complete, args, cmdline, cursor)
        if ok and type(extra) == "table" then
            vim.list_extend(candidates, extra)
        end
    elseif type(node.complete) == "table" then
        vim.list_extend(candidates, node.complete)
    end

    if #args == 0 then
        return candidates
    end

    local last = args[#args]
    local filtered = vim.tbl_filter(function(item)
        return matches_prefix(item, last)
    end, candidates)

    return #filtered > 0 and filtered or candidates
end

function CommandRegistry:dispatch(args)
    local node = self.root
    local depth = 0

    while depth < #args and node do
        local child = find_child(node, args[depth + 1])
        if not child then
            break
        end
        node = child
        depth = depth + 1
    end

    if not node or not node.handler then
        Log.warn("未找到匹配的命令")
        return
    end

    local remaining = {}
    for index = depth + 1, #args do
        table.insert(remaining, args[index])
    end

    local ok, err = pcall(node.handler, remaining)
    if not ok then
        Log.error("命令执行失败", { error = err })
    end
end

function CommandRegistry:install()
    vim.api.nvim_create_user_command(self.root_name, function(info)
        self:dispatch(info.fargs)
    end, {
        nargs = "*",
        desc = "zig-lamp 命令",
        complete = function(...)
            return self:complete_command(...)
        end,
    })
end

return CommandRegistry

