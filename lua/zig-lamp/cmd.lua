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
    --- @type subCmd
    return { cmd = cmd, cb = cb, sub = {}, complete = complete }
end

--- @param cmds string[] note: this function will modify cmds
--- @return subCmd|nil
--- @return number -2 is no cmds, -1 is cmds not exist, 0 is just ok, >0 is too long
local function get_command(cmds)
    if #cmds == 0 then
        return command, -2
    end
    --- @param __sub_cmd subCmd
    --- @param __cmds string[]
    --- @param __index number
    local function __tmp(__sub_cmd, __cmds, __index)
        local _cmd = __cmds[1]
        for _, ele in pairs(__sub_cmd.sub) do
            if ele.cmd and ele.cmd == _cmd then
                if #__cmds == 1 then
                    return ele, 0
                end
                if vim.tbl_isempty(ele.sub) then
                    return ele, __index
                end
                table.remove(__cmds, 1)
                return __tmp(ele, __cmds, __index + 1)
            end
        end
        return nil, -1
    end

    return __tmp(command, cmds, 1)
end

--- @param cmd subCmd
--- @return string[]
local function get_cmd_after_keys(cmd)
    --- @type string[]
    local __res = {}
    for _, ele in pairs(cmd.sub) do
        if ele.cmd then
            table.insert(__res, ele.cmd)
        end
    end
    if type(cmd.complete) == "function" then
        local _complete = cmd.complete()
        for _, __complete in pairs(_complete) do
            table.insert(__res, __complete)
        end
    elseif type(cmd.complete) == "table" then
        ---@diagnostic disable-next-line: param-type-mismatch
        for _, _complete in pairs(cmd.complete) do
            table.insert(__res, _complete)
        end
    end
    return __res
end

--- @param cb cmdCb
--- @param complete cmdComplete
--- @param ...string
function M.set_command(cb, complete, ...)
    local cmds = { ... }
    --- @type subCmd[]
    local _sub_cmd = command.sub
    for _index, _cmd in pairs(cmds) do
        for _, ele_sub_cmd in pairs(_sub_cmd) do
            if ele_sub_cmd.cmd and ele_sub_cmd.cmd == _cmd then
                if _index == #cmds then
                    ele_sub_cmd.cb = cb
                end
                _sub_cmd = ele_sub_cmd.sub
                goto continue
            end
        end
        if _index == #cmds then
            table.insert(_sub_cmd, create_subCmd(_cmd, cb, complete))
        else
            table.insert(_sub_cmd, create_subCmd(_cmd))
        end
        do
            _sub_cmd = _sub_cmd[#_sub_cmd].sub
        end

        ::continue::
    end
end

--- @param cmds string[]
function M.delete_command(cmds)
    --- @type subCmd[]
    local _sub_cmd = command.sub
    for _index, _cmd in pairs(cmds) do
        for _sub_cmd_index, ele_sub_cmd in pairs(_sub_cmd) do
            if ele_sub_cmd.cmd and ele_sub_cmd.cmd == _cmd then
                if _index == #cmds then
                    table.remove(_sub_cmd, _sub_cmd_index)
                    return
                end
                _sub_cmd = ele_sub_cmd.sub
            end
        end
    end
end

local complete_command = function(_, cmdline, _)
    local args = fn.split(cmdline)
    table.remove(args, 1)

    local _sub_cmd, meta_result = get_command(args)
    if meta_result == -1 or meta_result > 1 or not _sub_cmd then
        return {}
    end

    local candidates = get_cmd_after_keys(_sub_cmd)
    if #args == 0 then
        return candidates
    end

    local last_arg = args[#args]
    table.remove(args)

    --- @type string[]
    local _result = {}

    for _, candidate in ipairs(candidates) do
        if candidate:find("^" .. last_arg) then
            table.insert(_result, candidate)
        end
    end

    if #_result == 0 then
        return candidates
    end
    return _result
end

--- @param info commandCallback
local function handle_command(info)
    local _tbl_1 = vim.deepcopy(info.fargs)
    local _tbl_2 = vim.deepcopy(info.fargs)
    local _sub_cmd, meta_result = get_command(_tbl_1)
    if meta_result == -1 then
        util.Info("not exist function")
        return
    elseif meta_result == 0 then
        table.remove(_tbl_2, 1)
    elseif meta_result > 0 then
        while meta_result > 0 do
            table.remove(_tbl_2, 1)
            meta_result = meta_result - 1
        end
    end
    if _sub_cmd and _sub_cmd.cb then
        _sub_cmd.cb(_tbl_2)
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
function M.setup_command()
    api.nvim_create_user_command(command.cmd, handle_command, {
        range = true,
        nargs = "*",
        desc = "Command for zig-lamp",
        complete = complete_command,
    })
end

return M
