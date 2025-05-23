-- this file for zig-lamp command support

local util = require("zig-lamp.util")
local api, fn = vim.api, vim.fn
local M = {}

--- @type subCmd
local command = {
    cmd = "ZigLamp",
    cb = nil,
    sub = {},
    complete = nil,
}

--- @alias cmdCb fun(param:string[])|nil
--- @alias cmdComplete (fun():string[])|string[]|nil

--- @class subCmd
--- @field cmd string|nil
--- @field cb cmdCb|nil
--- @field sub subCmd[]|nil
--- @field complete cmdComplete|nil

--- @param cmd string|nil
--- @param cb cmdCb|nil
--- @param complete cmdComplete|nil
--- @return subCmd
local function create_subCmd(cmd, cb, complete)
    return { cmd = cmd, cb = cb, sub = {}, complete = complete }
end

--- @param cmds string[] note: this function will modify cmds
--- @return subCmd|nil
--- @return number -2 is no cmds, -1 is cmds not exist, 0 is just ok, >0 is too long
local function get_command(cmds)
    if #cmds == 0 then
        return command, -2
    end

    local current_cmd = command
    local depth = 0

    for i, cmd_name in ipairs(cmds) do
        local found = false
        for _, sub_cmd in pairs(current_cmd.sub) do
            if sub_cmd.cmd == cmd_name then
                if i == #cmds then
                    return sub_cmd, 0
                end
                if vim.tbl_isempty(sub_cmd.sub) then
                    return sub_cmd, depth + 1
                end
                current_cmd = sub_cmd
                depth = depth + 1
                found = true
                break
            end
        end
        if not found then
            return nil, -1
        end
    end

    return current_cmd, 0
end

--- @param cmd subCmd
--- @return string[]
local function get_cmd_after_keys(cmd)
    local result = {}

    -- Add sub commands
    for _, sub_cmd in pairs(cmd.sub) do
        if sub_cmd.cmd then
            table.insert(result, sub_cmd.cmd)
        end
    end

    -- Add completions
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

--- @param cb cmdCb
--- @param complete cmdComplete
--- @param ...string
function M.set_command(cb, complete, ...)
    local cmds = { ... }
    local current_sub = command.sub

    for i, cmd_name in pairs(cmds) do
        local found_cmd = nil

        -- Find existing command
        for _, sub_cmd in pairs(current_sub) do
            if sub_cmd.cmd == cmd_name then
                found_cmd = sub_cmd
                break
            end
        end

        -- Create or update command
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

--- @param cmds string[]
function M.delete_command(cmds)
    local current_sub = command.sub

    for i, cmd_name in pairs(cmds) do
        for j, sub_cmd in pairs(current_sub) do
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
    table.remove(args, 1) -- Remove command name

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

--- @param info commandCallback
local function handle_command(info)
    local args_copy = vim.deepcopy(info.fargs)
    local sub_cmd, meta_result = get_command(args_copy)

    if meta_result == -1 then
        util.Info("not exist function")
        return
    end

    -- Calculate how many arguments to remove
    local args_to_remove = math.max(0, meta_result)
    local params = vim.list_slice(info.fargs, args_to_remove + 1)

    if sub_cmd and sub_cmd.cb then
        sub_cmd.cb(params)
    end
end

--- @class commandCallback
--- @field name string
--- @field args string
--- @field fargs string[]
--- @field bang boolean
--- @field line1 number
--- @field line2 number
--- @field range number
--- @field count number
--- @field reg string
--- @field mods string
--- @field smods table

-- setup command, must be called by zig-lamp/init.lua
function M.init_command()
    api.nvim_create_user_command(command.cmd, handle_command, {
        range = true,
        nargs = "*",
        desc = "Command for zig-lamp",
        complete = complete_command,
    })
end

return M
