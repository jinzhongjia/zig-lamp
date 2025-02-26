local cmd = require("zig-lamp.cmd")
local job = require("plenary.job")
local util = require("zig-lamp.util")
local zig_ffi = require("zig-lamp.ffi")
local M = {}

local api, fn = vim.api, vim.fn

local nvim_open_win = api.nvim_open_win
local nvim_set_option_value = api.nvim_set_option_value

local help_namespace = vim.api.nvim_create_namespace("ZigLamp_pkg_help")
local help_hl_group = "ZigLamp_pkg_help"

-- find zig.build.zon file
--- @param _path string?
local function find_build_zon(_path)
    local path = require("plenary.path")
    if not _path then
        _path = fn.getcwd()
    end
    local _p = path:new(_path)
    -- try find build.zig.zon
    local _root = _p:find_upwards("build.zig.zon")
    return _root
end

--- @param _url string
local function get_hash(_url)
    if vim.fn.executable("zig") == 0 then
        return nil
    end
    --- @diagnostic disable-next-line: missing-fields
    local _tmp = job:new({ command = "zig", args = { "fetch", _url } })
    _tmp:after_failure(vim.schedule_wrap(function(_, code, signal)
        -- stylua: ignore
        util.Error(string.format("failed fetch: %s, code is %d, signal is %d", _url, code, signal))
    end))
    util.Info("fetching: " .. _url)
    local _result, _ = _tmp:sync(vim.g.zig_lamp_zig_fetch_timeout)
    if not _result then
        return nil
    end
    return _result[1]
end

local function render_help_text(buffer)
    local content = {
        "Key [q] to quit",
        "Key [i] to add or edit",
        "Key [o] to switch dependency type(url or path)",
        "Key [<leader>r] to reload from file",
        "Key [d] to delete dependency or path",
        "Key [<leader>s] to sync changes to file",
    }

    for _index, ele in pairs(content) do
        api.nvim_buf_set_extmark(buffer, help_namespace, _index - 1, 0, {
            virt_text = {
                { ele .. " ", help_hl_group },
            },
            virt_text_pos = "right_align",
        })
    end
end

-- this function only display content, and set key_cb, not do other thing!!!!
--- @param ctx pkg_ctx
local function render(ctx)
    local buffer = ctx.buffer
    local zon_info = ctx.zon_info

    local str_len = string.len
    local package_info_str = "  Package Info"
    --- @type string[], function[]
    local content = { package_info_str, "" }
    --- @type { group: string, line: integer, col_start: integer, col_end: integer }[]
    local highlight = {
        {
            group = "Title",
            line = 0,
            col_start = 0,
            col_end = str_len(package_info_str),
        },
    }
    local current_lnum = 1

    local name_str = "  Name: "
    table.insert(content, name_str .. (zon_info.name or "[none]"))
    current_lnum = current_lnum + 1
    table.insert(highlight, {
        group = "Title",
        line = current_lnum,
        col_start = 0,
        col_end = str_len(name_str),
    })

    local version_str = "  Version: "
    table.insert(content, version_str .. (zon_info.version or "[none]"))
    current_lnum = current_lnum + 1
    table.insert(highlight, {
        group = "Title",
        line = current_lnum,
        col_start = 0,
        col_end = str_len(version_str),
    })

    local min_version = zon_info.minimum_zig_version or "[none]"
    local min_version_str = "  Minimum zig version: "
    table.insert(content, min_version_str .. min_version)
    current_lnum = current_lnum + 1
    table.insert(highlight, {
        group = "Title",
        line = current_lnum,
        col_start = 0,
        col_end = str_len(min_version_str),
    })

    if zon_info.paths and #zon_info.paths == 1 and zon_info.paths[1] == "" then
        local paths_str = "  Paths [include all]"
        table.insert(content, paths_str)
        current_lnum = current_lnum + 1
        table.insert(highlight, {
            group = "Title",
            line = current_lnum,
            col_start = 0,
            col_end = str_len(paths_str),
        })
    elseif zon_info.paths and #zon_info.paths > 0 then
        local paths_str = "  Paths: "
        table.insert(content, paths_str)
        current_lnum = current_lnum + 1
        table.insert(highlight, {
            group = "Title",
            line = current_lnum,
            col_start = 0,
            col_end = str_len(paths_str),
        })
        if zon_info.paths and #zon_info.paths > 0 then
            for _, val in pairs(zon_info.paths) do
                current_lnum = current_lnum + 1
                table.insert(content, "    - " .. val)
            end
        end
    else
        local paths_str = "  Paths [none]"
        table.insert(content, paths_str)
        current_lnum = current_lnum + 1
        table.insert(highlight, {
            group = "Title",
            line = current_lnum,
            col_start = 0,
            col_end = str_len(paths_str),
        })
    end

    local deps_str = string.format(
        "  Dependencies [%s]: ",
        vim.tbl_count(zon_info.dependencies)
    )
    table.insert(content, deps_str)
    current_lnum = current_lnum + 1
    table.insert(highlight, {
        group = "Title",
        line = current_lnum,
        col_start = 0,
        col_end = str_len(deps_str),
    })
    local deps_is_empty = vim.tbl_isempty(zon_info.dependencies)
    if zon_info.dependencies and not deps_is_empty then
        for name, _info in pairs(zon_info.dependencies) do
            local name_prefix = "    - "
            table.insert(content, name_prefix .. name)
            current_lnum = current_lnum + 1
            table.insert(highlight, {
                group = "Tag",
                line = current_lnum,
                col_start = str_len(name_prefix),
                col_end = str_len(name_prefix) + str_len(name),
            })

            if _info.url then
                local url_prefix = "      url: "
                table.insert(content, url_prefix .. _info.url)
                current_lnum = current_lnum + 1
                table.insert(highlight, {
                    group = "Underlined",
                    line = current_lnum,
                    col_start = str_len(url_prefix),
                    col_end = str_len(url_prefix) + str_len(_info.url),
                })
            elseif _info.path then
                local path_prefix = "      path: "
                table.insert(content, path_prefix .. _info.path)
                current_lnum = current_lnum + 1
                table.insert(highlight, {
                    group = "Underlined",
                    line = current_lnum,
                    col_start = str_len(path_prefix),
                    col_end = str_len(path_prefix) + str_len(_info.path),
                })
            else
                local __prefix = "      url or path is none"
                table.insert(content, __prefix)
                current_lnum = current_lnum + 1
            end

            if _info.url then
                local hash_prefix = "      hash: "
                table.insert(content, hash_prefix .. (_info.hash or "[none]"))
                current_lnum = current_lnum + 1
                table.insert(highlight, {
                    group = "Underlined",
                    line = current_lnum,
                    col_start = str_len(hash_prefix),
                    col_end = str_len(hash_prefix)
                        + str_len(_info.hash or "[none]"),
                })
            end

            if _info.lazy == nil then
                local lazy_prefix = "      lazy: [empty]"
                table.insert(content, lazy_prefix)
                current_lnum = current_lnum + 1
            else
                local lazy_prefix = "      lazy: "
                table.insert(content, lazy_prefix .. tostring(_info.lazy))
                current_lnum = current_lnum + 1
            end
        end
    end

    nvim_set_option_value("modifiable", true, { buf = buffer })
    api.nvim_buf_set_lines(buffer, 0, -1, true, content)

    for _, hl in pairs(highlight) do
        api.nvim_buf_add_highlight(
            buffer,
            help_namespace,
            hl.group,
            hl.line,
            hl.col_start,
            hl.col_end
        )
    end

    render_help_text(buffer)
    nvim_set_option_value("modifiable", false, { buf = buffer })
end

--- @param ctx pkg_ctx
local function delete_cb(ctx)
    -- local buffer = ctx.buffer
    return function()
        local lnum = api.nvim_win_get_cursor(0)[1] - 2
        if lnum < 1 then
            return
        end
        lnum = lnum - 4

        if
            ctx.zon_info.paths
            and #ctx.zon_info.paths > 0
            and ctx.zon_info.paths[1] ~= ""
        then
            for _index, _ in pairs(ctx.zon_info.paths) do
                if lnum - 1 == 0 then
                    table.remove(ctx.zon_info.paths, _index)
                    render(ctx)
                    return
                end
                lnum = lnum - 1
            end
        end

        lnum = lnum - 1
        local deps_is_empty = vim.tbl_isempty(ctx.zon_info.dependencies)
        if ctx.zon_info.dependencies and not deps_is_empty then
            for name, _info in pairs(ctx.zon_info.dependencies) do
                local _len
                if _info.url then
                    _len = 4
                else
                    _len = 3
                end

                if lnum > 0 and lnum < _len + 1 then
                    ctx.zon_info.dependencies[name] = nil
                    render(ctx)
                    return
                end
                lnum = lnum - _len
            end
        end
    end
end

--- @param ctx pkg_ctx
local edit_cb = function(ctx)
    return function()
        local lnum = api.nvim_win_get_cursor(0)[1] - 2
        if lnum < 1 then
            return
        end
        -- for name
        if lnum - 1 == 0 then
            vim.ui.input({
                prompt = "Enter value for name: ",
                default = ctx.zon_info.name,
            }, function(input)
                -- stylua: ignore
                if not input then return end
                if input == "" then
                    util.Warn("sorry, the name of package can not be empty!")
                    return
                end

                ctx.zon_info.name = input
                render(ctx)
            end)
            return
        end
        lnum = lnum - 1

        -- for version
        if lnum - 1 == 0 then
            vim.ui.input({
                prompt = "Enter value for version: ",
                default = ctx.zon_info.version,
            }, function(input)
                -- stylua: ignore
                if not input then return end
                if input == "" then
                    util.Warn("sorry, the version of package can not be empty!")
                    return
                end
                ctx.zon_info.version = input
                render(ctx)
            end)
            return
        end
        lnum = lnum - 1

        -- for minimum zig version
        if lnum - 1 == 0 then
            vim.ui.input({
                prompt = "Enter value for minimum zig version: ",
                default = ctx.zon_info.minimum_zig_version,
            }, function(input)
                -- stylua: ignore
                if not input then return end
                ctx.zon_info.minimum_zig_version = input
                render(ctx)
            end)
            return
        end
        lnum = lnum - 1

        -- for path
        if lnum - 1 == 0 then
            vim.ui.input({
                prompt = "Enter value for new path: ",
            }, function(input)
                -- stylua: ignore
                if not input then return end
                if
                    ctx.zon_info.paths
                    and #ctx.zon_info.paths == 1
                    and ctx.zon_info.paths[1] == ""
                then
                    ctx.zon_info.paths = { input }
                else
                    table.insert(ctx.zon_info.paths, input)
                end

                render(ctx)
            end)
            return
        end
        lnum = lnum - 1

        if
            ctx.zon_info.paths
            and #ctx.zon_info.paths > 0
            and ctx.zon_info.paths[1] ~= ""
        then
            for _index, val in pairs(ctx.zon_info.paths) do
                if lnum - 1 == 0 then
                    vim.ui.input({
                        prompt = "Enter value for path: ",
                        default = val,
                    }, function(input)
                        -- stylua: ignore
                        if not input then return end
                        ctx.zon_info.paths[_index] = input
                        render(ctx)
                    end)
                    return
                end
                lnum = lnum - 1
            end
        end

        -- for dependencies
        if lnum - 1 == 0 then
            vim.ui.input({
                prompt = "Enter value for new dependency name: ",
                default = "new_dep",
            }, function(input)
                -- stylua: ignore
                if not input then return end
                ctx.zon_info.dependencies[input] = {}
                render(ctx)
            end)
            return
        end
        lnum = lnum - 1

        -- for dependency
        local deps_is_empty = vim.tbl_isempty(ctx.zon_info.dependencies)
        if ctx.zon_info.dependencies and not deps_is_empty then
            for name, _info in pairs(ctx.zon_info.dependencies) do
                if lnum - 1 == 0 then
                    vim.ui.input({
                        prompt = "Enter value for dependency name: ",
                        default = name,
                    }, function(input)
                        -- stylua: ignore
                        if not input then return end
                        ctx.zon_info.dependencies[input] = _info
                        ctx.zon_info.dependencies[name] = nil
                        render(ctx)
                    end)
                    return
                end
                lnum = lnum - 1

                if lnum - 1 == 0 then
                    if _info.url == nil and _info.path == nil then
                        --- @type "url" | "path" | nil
                        local choice
                        local function __input()
                            vim.ui.input({
                                -- stylua: ignore
                                prompt = string.format("Enter value for dependency %s: ", choice),
                            }, function(input)
                                -- stylua: ignore
                                if not input then return end
                                if choice == "path" then
                                    ctx.zon_info.dependencies[name].path = input
                                else
                                    ctx.zon_info.dependencies[name].url = input
                                    local _hash = get_hash(input)
                                    if _hash then
                                        ctx.zon_info.dependencies[name].hash =
                                            _hash
                                    end
                                end

                                render(ctx)
                            end)
                        end
                        vim.ui.select({ "url", "path" }, {
                            prompt = "Select tabs or spaces:",
                            format_item = function(item)
                                return "I'd like to choose " .. item
                            end,
                        }, function(_tmp)
                            -- stylua: ignore
                            if not _tmp then return end
                            choice = _tmp
                            __input()
                        end)
                        return
                    end
                    local is_url = _info.url ~= nil
                    vim.ui.input({
                        prompt = string.format(
                            "Enter value for dependency %s: ",
                            is_url and "url" or "path"
                        ),
                        default = is_url and _info.url or _info.path,
                    }, function(input)
                        -- stylua: ignore
                        if not input then return end
                        -- when input empty string
                        if input == "" then
                            ctx.zon_info.dependencies[name].url = nil
                            ctx.zon_info.dependencies[name].path = nil
                            render(ctx)
                            return
                        end

                        if is_url then
                            ctx.zon_info.dependencies[name].url = input
                            local _hash = get_hash(input)
                            if _hash then
                                ctx.zon_info.dependencies[name].hash = _hash
                            end
                        else
                            ctx.zon_info.dependencies[name].path = input
                        end
                        render(ctx)
                    end)
                    return
                end
                lnum = lnum - 1

                if _info.url then
                    if lnum - 1 == 0 then
                        vim.ui.input({
                            prompt = "Enter value for dependency hash: ",
                            default = _info.hash,
                        }, function(input)
                        -- stylua: ignore
                        if not input then return end
                            ctx.zon_info.dependencies[name].hash = input
                            render(ctx)
                        end)
                        return
                    end
                    lnum = lnum - 1
                end

                if lnum - 1 == 0 then
                    vim.ui.select({ "true", "false", "empty" }, {
                        prompt = "choose whether to lazy:",
                        format_item = function(item)
                            return "I'd like to choose " .. item
                        end,
                    }, function(choice)
                        -- stylua: ignore
                        if not choice then return end
                        if choice == "true" then
                            ctx.zon_info.dependencies[name].lazy = true
                        elseif choice == "false" then
                            ctx.zon_info.dependencies[name].lazy = false
                        elseif choice == "empty" then
                            ctx.zon_info.dependencies[name].lazy = nil
                        end
                        render(ctx)
                    end)
                end
                lnum = lnum - 1
            end
        end
    end
end

--- @param ctx pkg_ctx
local function sync_cb(ctx)
    return function()
        local zon_str = util.wrap_j2zon(ctx.zon_info)
        local fmted_code = zig_ffi.fmt_zon(zon_str)
        if not fmted_code then
            util.warn("in sync zon step, format zon failed!")
            return
        end
        ctx.zon_path:write(fmted_code, "w", 438)
        util.Info("sync zon success!")
    end
end

--- @param ctx pkg_ctx
local function reload_cb(ctx)
    return function()
        -- try parse build.zig.zon
        local zon_info = zig_ffi.get_build_zon_info(ctx.zon_path:absolute())
        if not zon_info then
            util.Warn("reload failed, because parse build.zig.zon failed!")
            return
        end

        ctx.zon_info = zon_info
        render(ctx)
        util.Info("reload success!")
    end
end

--- @param _ pkg_ctx
local function quit_cb(_)
    return function()
        api.nvim_win_close(0, true)
    end
end

--- @param ctx pkg_ctx
local function switch_cb(ctx)
    return function()
        local lnum = api.nvim_win_get_cursor(0)[1] - 2
        if lnum < 1 then
            return
        end
        -- for name
        lnum = lnum - 1
        -- for version
        lnum = lnum - 1
        -- for minimum zig version
        lnum = lnum - 1

        -- for path title
        lnum = lnum - 1

        if
            ctx.zon_info.paths
            and #ctx.zon_info.paths > 0
            and ctx.zon_info.paths[1] ~= ""
        then
            for _, _ in pairs(ctx.zon_info.paths) do
                -- for path
                lnum = lnum - 1
            end
        end

        -- for dependencies
        lnum = lnum - 1

        -- for dependency
        local deps_is_empty = vim.tbl_isempty(ctx.zon_info.dependencies)
        if ctx.zon_info.dependencies and not deps_is_empty then
            for name, _info in pairs(ctx.zon_info.dependencies) do
                local _len
                local is_url = _info.url ~= nil
                if is_url then
                    _len = 4
                else
                    _len = 3
                end

                if lnum > 0 and lnum < _len + 1 then
                    vim.ui.input({
                        prompt = string.format(
                            "Enter value for dependency %s: ",
                            (not is_url) and "url" or "path"
                        ),
                    }, function(input)
                        -- stylua: ignore
                        if not input then return end
                        -- when input empty string
                        if input == "" then
                            ctx.zon_info.dependencies[name].url = nil
                            ctx.zon_info.dependencies[name].path = nil
                            render(ctx)
                            return
                        end

                        print(input)

                        if not is_url then
                            local _hash = get_hash(input)
                            if _hash then
                                ctx.zon_info.dependencies[name].url = input
                                ctx.zon_info.dependencies[name].hash = _hash
                                ctx.zon_info.dependencies[name].path = nil
                            end
                        else
                            ctx.zon_info.dependencies[name].path = input
                            ctx.zon_info.dependencies[name].url = nil
                            ctx.zon_info.dependencies[name].hash = nil
                        end
                        render(ctx)
                    end)
                    return
                end
                lnum = lnum - _len
            end
        end
    end
end

--- @param ctx pkg_ctx
local function set_keymap(ctx)
    -- stylua: ignore
    --- @type { lhs: string, cb: fun(ctx: pkg_ctx), desc: string }[]
    local key_metas = {
        { lhs = "q", desc = "quit for ZigLamp info panel", cb = quit_cb },
        { lhs = "i", desc = "edit or add for ZigLamp info panel", cb = edit_cb },
        { lhs = "d", desc = "delete for ZigLamp info panel", cb = delete_cb },
        { lhs = "o", desc = "switch for ZigLamp info panel", cb = switch_cb },
        { lhs = "<leader>s", desc = "sync for ZigLamp info panel", cb = sync_cb },
        { lhs = "<leader>r", desc = "reload for ZigLamp info panel", cb = reload_cb },
    }
    for _, key_meta in pairs(key_metas) do
        api.nvim_buf_set_keymap(ctx.buffer, "n", key_meta.lhs, "", {
            noremap = true,
            nowait = true,
            desc = key_meta.desc,
            callback = key_meta.cb(ctx),
        })
    end
end

--- @param buffer integer
local function set_buf_option(buffer)
    nvim_set_option_value("filetype", "ZigLamp_info", { buf = buffer })
    nvim_set_option_value("bufhidden", "delete", { buf = buffer })
    nvim_set_option_value("undolevels", -1, { buf = buffer })
    nvim_set_option_value("modifiable", false, { buf = buffer })
end

--- @param _ string[]
local function cb_pkg(_)
    -- try find build.zig.zon
    local zon_path = find_build_zon()
    if not zon_path then
        util.Warn("not found build.zig.zon")
        return
    end

    -- try parse build.zig.zon
    local zon_info = zig_ffi.get_build_zon_info(zon_path:absolute())
    if not zon_info then
        util.Warn("parse build.zig.zon failed!")
        return
    end
    local new_buf = api.nvim_create_buf(false, true)

    --- @alias pkg_ctx { zon_info: ZigBuildZon, zon_path: table, buffer: integer }

    --- @type pkg_ctx
    local ctx = {
        zon_info = zon_info,
        zon_path = zon_path,
        buffer = new_buf,
    }

    -- local bak_zon_info = vim.deepcopy(zon_info)

    render(ctx)
    set_buf_option(new_buf)

    -- window
    -- stylua: ignore
    local _ = nvim_open_win(new_buf, true, { split = "below", style = "minimal" })
    set_keymap(ctx)
end

function M.setup()
    cmd.set_command(cb_pkg, { "info" }, "pkg")
    -- The timing of the delay function taking effect
    vim.schedule(function()
        local hl_val = {
            fg = util.adjust_brightness(
                vim.g.zig_lamp_pkg_help_fg or "#CF5C00",
                30
            ),
            italic = true,
            -- standout = true,
            -- undercurl = true,
        }
        api.nvim_set_hl(0, help_hl_group, hl_val)
    end)
end

return M
