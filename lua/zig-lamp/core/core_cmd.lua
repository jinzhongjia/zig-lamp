-- this file for zig-lamp command support

local vim = vim
local util = require("zig-lamp.core.core_util")
local api, fn = vim.api, vim.fn
local M = {}

local command = {
    cmd = "ZigLamp",
    cb = nil,
    sub = {},
    complete = nil,
}

local function create_subCmd(cmd, cb, complete)
    return { cmd = cmd, cb = cb, sub = {}, complete = complete }
end

local function get_command(cmds)
    if #cmds == 0 then
        return command, -2
    end
    local current_cmd = command
    local depth = 0
    for i, cmd_name in ipairs(cmds) do
        local next_cmd = nil
        for _, sub_cmd in ipairs(current_cmd.sub) do
            if sub_cmd.cmd == cmd_name then
                next_cmd = sub_cmd
                break
            end
        end
        if not next_cmd then
            return nil, -1
        end
        if i == #cmds then
            return next_cmd, 0
        end
        if vim.tbl_isempty(next_cmd.sub) then
            return next_cmd, depth + 1
        end
        current_cmd = next_cmd
        depth = depth + 1
    end
    return current_cmd, 0
end

local function get_cmd_after_keys(cmd)
    local result = {}
    for _, sub_cmd in ipairs(cmd.sub) do
        if sub_cmd.cmd then
            table.insert(result, sub_cmd.cmd)
        end
    end
    local completions = cmd.complete
    if type(completions) == "function" then
        completions = completions()
    end
    if type(completions) == "table" then
        for _, completion in pairs(completions) do
            table.insert(result, completion)
        end
    end
    return result
end

function M.set_command(cb, complete, ...)
    local cmds = { ... }
    local current_sub = command.sub
    for i, cmd_name in ipairs(cmds) do
        local found_cmd = nil
        for _, sub_cmd in ipairs(current_sub) do
            if sub_cmd.cmd == cmd_name then
                found_cmd = sub_cmd
                break
            end
        end
        if found_cmd then
            if i == #cmds then
                found_cmd.cb = cb
                found_cmd.complete = complete
            end
            current_sub = found_cmd.sub
        else
            local new_cmd = create_subCmd(
                cmd_name,
                i == #cmds and cb or nil,
                i == #cmds and complete or nil
            )
            table.insert(current_sub, new_cmd)
            current_sub = new_cmd.sub
        end
    end
end

function M.delete_command(cmds)
    local current_sub = command.sub
    for i, cmd_name in ipairs(cmds) do
        for j, sub_cmd in ipairs(current_sub) do
            if sub_cmd.cmd == cmd_name then
                if i == #cmds then
                    table.remove(current_sub, j)
                    return
                end
                current_sub = sub_cmd.sub
                break
            end
        end
    end
end

local function complete_command(_, cmdline, _)
    local args = fn.split(cmdline)
    table.remove(args, 1)
    local sub_cmd, meta_result = get_command(vim.deepcopy(args))
    if meta_result == -1 or meta_result > 1 or not sub_cmd then
        return {}
    end
    local candidates = get_cmd_after_keys(sub_cmd)
    if #args == 0 then
        return candidates
    end
    local last_arg = args[#args]
    local filtered = {}
    for _, candidate in ipairs(candidates) do
        if candidate:find("^" .. vim.pesc(last_arg)) then
            table.insert(filtered, candidate)
        end
    end
    return #filtered > 0 and filtered or candidates
end

local function handle_command(info)
    local args_copy = vim.deepcopy(info.fargs)
    local sub_cmd, meta_result = get_command(args_copy)
    if meta_result == -1 then
        util.Info("not exist function")
        return
    end
    local args_to_remove = math.max(0, meta_result)
    local params = vim.list_slice(info.fargs, args_to_remove + 1)
    if sub_cmd and sub_cmd.cb then
        sub_cmd.cb(params)
    end
end

function M.init_command()
    api.nvim_create_user_command(command.cmd, handle_command, {
        range = true,
        nargs = "*",
        desc = "Command for zig-lamp",
        complete = complete_command,
    })
end

return M
