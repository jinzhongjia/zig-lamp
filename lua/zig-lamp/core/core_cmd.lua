-- Command system for zig-lamp plugin
-- Provides hierarchical subcommand support with auto-completion

local vim = vim
local util = require("zig-lamp.core.core_util")
local api, fn = vim.api, vim.fn

local M = {}

-- Root command structure
local command = {
    cmd = "ZigLamp",
    cb = nil,
    sub = {},
    complete = nil,
}

-- Create a new subcommand structure
local function create_subcommand(cmd, cb, complete)
    return { cmd = cmd, cb = cb, sub = {}, complete = complete }
end

-- Find command in hierarchy and return it with metadata
local function get_command(cmd_args)
    if #cmd_args == 0 then
        return command, -2
    end

    local current_cmd = command
    local depth = 0

    for i, cmd_name in ipairs(cmd_args) do
        -- Find matching subcommand
        local next_cmd = nil
        for _, sub_cmd in ipairs(current_cmd.sub) do
            if sub_cmd.cmd == cmd_name then
                next_cmd = sub_cmd
                break
            end
        end

        -- Command not found
        if not next_cmd then
            return nil, -1
        end

        -- Found target command
        if i == #cmd_args then
            return next_cmd, 0
        end

        -- Continue traversing if has subcommands
        if vim.tbl_isempty(next_cmd.sub) then
            return next_cmd, depth + 1
        end

        current_cmd = next_cmd
        depth = depth + 1
    end

    return current_cmd, 0
end

-- Get available completions for a command
local function get_completions(cmd)
    local result = {}

    -- Add subcommand names
    for _, sub_cmd in ipairs(cmd.sub) do
        if sub_cmd.cmd then
            table.insert(result, sub_cmd.cmd)
        end
    end

    -- Add custom completions
    local completions = cmd.complete
    if type(completions) == "function" then
        completions = completions()
    end

    if type(completions) == "table" then
        vim.list_extend(result, completions)
    end

    return result
end

-- Register a new command or subcommand
function M.set_command(cb, complete, ...)
    local cmd_path = { ... }
    local current_sub = command.sub

    for i, cmd_name in ipairs(cmd_path) do
        local found_cmd = nil

        -- Look for existing command
        for _, sub_cmd in ipairs(current_sub) do
            if sub_cmd.cmd == cmd_name then
                found_cmd = sub_cmd
                break
            end
        end

        if found_cmd then
            -- Update existing command if at end of path
            if i == #cmd_path then
                found_cmd.cb = cb
                found_cmd.complete = complete
            end
            current_sub = found_cmd.sub
        else
            -- Create new command
            local is_leaf = i == #cmd_path
            local new_cmd = create_subcommand(cmd_name, is_leaf and cb or nil, is_leaf and complete or nil)
            table.insert(current_sub, new_cmd)
            current_sub = new_cmd.sub
        end
    end
end

-- Remove a command from the hierarchy
function M.delete_command(cmd_path)
    local current_sub = command.sub

    for i, cmd_name in ipairs(cmd_path) do
        for j, sub_cmd in ipairs(current_sub) do
            if sub_cmd.cmd == cmd_name then
                if i == #cmd_path then
                    table.remove(current_sub, j)
                    return
                end
                current_sub = sub_cmd.sub
                break
            end
        end
    end
end

-- Handle command completion
local function complete_command(_, cmdline, _)
    local args = fn.split(cmdline)
    table.remove(args, 1) -- Remove command name

    local sub_cmd, meta_result = get_command(vim.deepcopy(args))
    if meta_result == -1 or meta_result > 1 or not sub_cmd then
        return {}
    end

    local candidates = get_completions(sub_cmd)
    if #args == 0 then
        return candidates
    end

    -- Filter candidates based on partial input
    local last_arg = args[#args]
    local filtered = vim.tbl_filter(function(candidate)
        return candidate:find("^" .. vim.pesc(last_arg))
    end, candidates)

    return #filtered > 0 and filtered or candidates
end

-- Execute command with given arguments
local function handle_command(info)
    local args_copy = vim.deepcopy(info.fargs)
    local sub_cmd, meta_result = get_command(args_copy)

    if meta_result == -1 then
        util.Info("Command not found")
        return
    end

    -- Calculate remaining arguments after command path
    local args_to_remove = math.max(0, meta_result)
    local params = vim.list_slice(info.fargs, args_to_remove + 1)

    if sub_cmd and sub_cmd.cb then
        sub_cmd.cb(params)
    end
end

-- Initialize the main command
function M.init_command()
    api.nvim_create_user_command(command.cmd, handle_command, {
        range = true,
        nargs = "*",
        desc = "ZigLamp plugin commands",
        complete = complete_command,
    })
end

return M
