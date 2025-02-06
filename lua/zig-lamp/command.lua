-- this file for zig-lamp command support

local api, fn = vim.api, vim.fn
local M = {}

--- @type subCmd
local command = {
    cmd = "ZigLamp",
    cb = nil,
    sub = {},
}

--- @alias cmdCb fun(param:string)|nil

--- @class subCmd
--- @field cmd string|nil
--- @field cb cmdCb|nil
--- @field sub subCmd[]|nil

--- @param cmd string|nil
--- @param cb cmdCb|nil
--- @return subCmd
local function create_subCmd(cmd, cb)
    return { cmd = cmd, cb = cb, sub = {} }
end

--- @param sub_cmd subCmd[]
--- @param cmds string[]
--- @param _index number
local function get_command_meta(sub_cmd, cmds, _index)
    local _cmd = cmds[1]
    for _, ele in pairs(sub_cmd) do
        if ele.cmd and ele.cmd == _cmd then
            if #cmds == 1 then
                return ele, 0
            end
            if vim.tbl_isempty(ele.sub) then
                return ele, _index
            end
            table.remove(cmds, 1)
            return get_command_meta(ele.sub, cmds, _index + 1)
        end
    end
    return nil, -1
end

--- @param cmds string[]
--- @param cb cmdCb
function M.set_command_meta(cmds, cb)
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
            table.insert(_sub_cmd, create_subCmd(_cmd, cb))
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
                    print("log")
                    return
                end
                _sub_cmd = ele_sub_cmd.sub
            end
        end
    end
end

--- @param cmd subCmd
--- @return string[]
local function get_cmd_keys(cmd)
    --- @type string[]
    local __res = {}
    for _, ele in pairs(cmd.sub) do
        if ele.cmd then
            table.insert(__res, ele.cmd)
        end
    end
    return __res
end

M.set_command_meta({ "first", "second" }, function()
    print("hello")
end)

-- set_command_meta({ "a", "b", "c" }, function()
--     print("hello")
-- end)
--
-- set_command_meta({ "a", "b", "a" }, function()
--     print("aaaa")
-- end)
--
-- delete_command_meta({ "a", "b", "c" })

local complete_command = function(arglead, cmdline, cursorpos)
    local args = fn.split(cmdline)
    table.remove(args, 1)
    if #args == 0 then
        return get_cmd_keys(command)
    end

    local last_arg = args[#args]
    table.remove(args)

    local _sub_cmd, meta_result = get_command_meta(command.sub, args, 1)
    if meta_result ~= 0 or not _sub_cmd then
        return {}
    end

    --- @type string[]
    local _result = {}
    local candidates = get_cmd_keys(_sub_cmd)
    for _, candidate in ipairs(candidates) do
        if candidate:find("^" .. last_arg) then
            table.insert(_result, candidate)
        end
    end

    if #_result == 0 then
        print(vim.inspect(candidates))
        return candidates
    end
    return _result
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

function M.create_command()
    api.nvim_create_user_command(
        command.cmd,
        --- @param info commandCallback
        function(info) end,
        {
            range = true,
            nargs = "*",
            desc = "Command for zig-lamp",
            complete = complete_command,
        }
    )
end

return M
