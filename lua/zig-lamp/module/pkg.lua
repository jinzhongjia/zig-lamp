local cmd = require("zig-lamp.cmd")
local util = require("zig-lamp.util")
local zig_ffi = require("zig-lamp.ffi")
local M = {}

local api, fn = vim.api, vim.fn

local ns = api.nvim_create_namespace("ZigLamp_pkg")

local nvim_open_win = api.nvim_open_win
local nvim_set_option_value = api.nvim_set_option_value

-- find zig.build.zon file
--- @param _path string?
local function find_build_zon(_path)
    local path = require("plenary.path")
    if not _path then
        _path = vim.fn.getcwd()
    end
    local _p = path:new(_path)
    -- try find build.zig.zon
    local _root = _p:find_upwards("build.zig.zon")
    return _root
end

local function test()
    vim.ui.input(
        { prompt = "Enter value for shiftwidth: ", default = "kkkk" },
        function(input)
            vim.o.shiftwidth = tonumber(input)
        end
    )
    -- vim.ui.select({ "tabs", "spaces" }, {
    --     prompt = "Select tabs or spaces:",
    --     format_item = function(item)
    --         return "I'd like to choose " .. item
    --     end,
    -- }, function(choice)
    --     if choice == "spaces" then
    --         vim.o.expandtab = true
    --     else
    --         vim.o.expandtab = false
    --     end
    -- end)
end

-- local function get_zon_obj_from_line()
--
-- end

-- this function only display content, and set key_cb, not do other thing!!!!
--- @param buffer integer
--- @param zon_info ZigBuildZon
local function render(buffer, zon_info)
    --- @type string[], function[]
    local content = { "  Package Info", "" }

    if zon_info.name then
        table.insert(content, "  Name: " .. zon_info.name)
    end

    if zon_info.version then
        table.insert(content, "  Version: " .. zon_info.version)
    end

    if zon_info.minimum_zig_version then
        -- stylua: ignore
        table.insert(content, "  Minimum zig version: " .. zon_info.minimum_zig_version)
    end

    if zon_info.paths and #zon_info.paths == 1 and zon_info.paths[1] == "" then
        table.insert(content, "  Paths [include all]")
    else
        table.insert(content, "  Paths")
        if zon_info.paths and #zon_info.paths > 0 then
            for _, val in pairs(zon_info.paths) do
                table.insert(content, "    - " .. val)
            end
        end
    end

    table.insert(content, "  Dependencies:")
    local deps_is_empty = vim.tbl_isempty(zon_info.dependencies)
    if zon_info.dependencies and not deps_is_empty then
        for name, _info in pairs(zon_info.dependencies) do
            table.insert(content, "    - " .. name)
            table.insert(content, "      url: " .. _info.url)
            table.insert(content, "      hash: " .. _info.hash)
        end
    end

    nvim_set_option_value("modifiable", true, { buf = buffer })
    vim.api.nvim_buf_set_lines(buffer, 0, -1, true, content)
end

--- @param buffer integer
--- @param zon_info ZigBuildZon
local d_cb = function(buffer, zon_info)
    return function()
        local lnum = api.nvim_win_get_cursor(0)[1] - 2
        print(lnum)
        if lnum < 1 then
            return
        end
        lnum = lnum - 4

        if
            zon_info.paths
            and #zon_info.paths > 0
            and zon_info.paths[1] ~= ""
        then
            for _index, val in pairs(zon_info.paths) do
                if lnum - 1 == 0 then
                    table.remove(zon_info.paths, _index)
                    render(buffer, zon_info)
                    return
                end
                lnum = lnum - 1
            end
        end

        lnum = lnum - 1
        local deps_is_empty = vim.tbl_isempty(zon_info.dependencies)
        if zon_info.dependencies and not deps_is_empty then
            for name, _info in pairs(zon_info.dependencies) do
                if lnum > 0 and lnum < 4 then
                    zon_info.dependencies[name] = nil
                    render(buffer, zon_info)
                    return
                end
                lnum = lnum - 3
            end
        end
    end
end

--- @param buffer integer
--- @param zon_info ZigBuildZon
local i_cb = function(buffer, zon_info)
    return function()
        local lnum = api.nvim_win_get_cursor(0)[1] - 2
        print(lnum)
        if lnum < 1 then
            return
        end
        if zon_info.name and lnum - 1 == 0 then
            vim.ui.input({
                prompt = "Enter value for name: ",
                default = zon_info.name,
            }, function(input)
                -- stylua: ignore
                if not input then return end

                zon_info.name = input
                render(buffer, zon_info)
            end)
            return
        end
        lnum = lnum - 1

        if zon_info.version and lnum - 1 == 0 then
            vim.ui.input({
                prompt = "Enter value for version: ",
                default = zon_info.version,
            }, function(input)
                -- stylua: ignore
                if not input then return end
                zon_info.version = input
                render(buffer, zon_info)
            end)
            return
        end
        lnum = lnum - 1

        if zon_info.minimum_zig_version and lnum - 1 == 0 then
            vim.ui.input({
                prompt = "Enter value for minimum zig version: ",
                default = zon_info.minimum_zig_version,
            }, function(input)
                -- stylua: ignore
                if not input then return end
                zon_info.minimum_zig_version = input
                render(buffer, zon_info)
            end)
            return
        end
        lnum = lnum - 1

        if lnum - 1 == 0 then
            vim.ui.input({
                prompt = "Enter value for new path: ",
            }, function(input)
                -- stylua: ignore
                if not input then return end
                if
                    zon_info.paths
                    and #zon_info.paths == 1
                    and zon_info.paths[1] == ""
                then
                    zon_info.paths = { input }
                else
                    table.insert(zon_info.paths, input)
                end

                render(buffer, zon_info)
            end)
            return
        end
        lnum = lnum - 1

        if
            zon_info.paths
            and #zon_info.paths > 0
            and zon_info.paths[1] ~= ""
        then
            for _index, val in pairs(zon_info.paths) do
                if lnum - 1 == 0 then
                    vim.ui.input({
                        prompt = "Enter value for path: ",
                        default = val,
                    }, function(input)
                        -- stylua: ignore
                        if not input then return end
                        zon_info.paths[_index] = input
                        render(buffer, zon_info)
                    end)
                    return
                end
                lnum = lnum - 1
            end
        end
        if lnum - 1 == 0 then
            vim.ui.input({
                prompt = "Enter value for dependency name: ",
                default = "new_dep",
            }, function(input)
                -- stylua: ignore
                if not input then return end
                zon_info.dependencies[input] = {
                    url = "new url",
                    hash = "hash",
                }
                render(buffer, zon_info)
            end)
            return
        end
        local deps_is_empty = vim.tbl_isempty(zon_info.dependencies)
        if zon_info.dependencies and not deps_is_empty then
            lnum = lnum - 1
            for name, _info in pairs(zon_info.dependencies) do
                if lnum - 1 == 0 then
                    vim.ui.input({
                        prompt = "Enter value for dependency name: ",
                        default = name,
                    }, function(input)
                        -- stylua: ignore
                        if not input then return end
                        zon_info.dependencies[input] = _info
                        zon_info.dependencies[name] = nil
                        render(buffer, zon_info)
                    end)
                    return
                end
                lnum = lnum - 1
                if lnum - 1 == 0 then
                    vim.ui.input({
                        prompt = "Enter value for dependency url: ",
                        default = _info.url,
                    }, function(input)
                        -- stylua: ignore
                        if not input then return end
                        zon_info.dependencies[name].url = input
                        render(buffer, zon_info)
                    end)
                    return
                end
                lnum = lnum - 1
                if lnum - 1 == 0 then
                    vim.ui.input({
                        prompt = "Enter value for dependency hash: ",
                        default = _info.hash,
                    }, function(input)
                        -- stylua: ignore
                        if not input then return end
                        zon_info.dependencies[name].hash = input
                        render(buffer, zon_info)
                    end)
                    return
                end
                lnum = lnum - 1
            end
        end
    end
end

--- @param buffer integer
--- @param zon_info ZigBuildZon
local function keymap(buffer, zon_info)
    api.nvim_buf_set_keymap(buffer, "n", "q", "", {
        noremap = true,
        nowait = true,
        desc = "quit for ZigLamp info panel",
        callback = function()
            api.nvim_win_close(0, true)
        end,
    })

    api.nvim_buf_set_keymap(buffer, "n", "i", "", {
        noremap = true,
        nowait = true,
        callback = i_cb(buffer, zon_info),
        desc = "edit for ZigLamp info panel",
    })

    api.nvim_buf_set_keymap(buffer, "n", "d", "", {
        noremap = true,
        nowait = true,
        callback = d_cb(buffer, zon_info),
        desc = "delete for ZigLamp info panel",
    })
end

--- @param buffer integer
local function set_buf_option(buffer)
    nvim_set_option_value("filetype", "ZigLamp_info", { buf = buffer })
    nvim_set_option_value("bufhidden", "delete", { buf = buffer })
    nvim_set_option_value("undolevels", -1, { buf = buffer })
    nvim_set_option_value("modifiable", false, { buf = buffer })
end

--- @param params string[]
local function cb_pkg(params)
    -- try find build.zig.zon
    local _root = find_build_zon()
    if not _root then
        util.Warn("not found build.zig.zon")
        return
    end

    -- try parse build.zig.zon
    local zon_info = zig_ffi.get_build_zon_info(_root:absolute())
    if not zon_info then
        util.Warn("parse build.zig.zon failed!")
        return
    end

    local bak_zon_info = vim.deepcopy(zon_info)
    local new_buf = api.nvim_create_buf(false, true)

    render(new_buf, zon_info)
    set_buf_option(new_buf)

    -- stylua: ignore
    local win = api.nvim_open_win(new_buf, true, { split = "below", style = "minimal" })
    keymap(new_buf, zon_info)
end

function M.setup()
    cmd.set_command(cb_pkg, { "info" }, "pkg")
end

return M
