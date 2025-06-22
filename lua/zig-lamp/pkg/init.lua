local vim = vim
-- pkg/init.lua
-- 迁移自 module/pkg.lua，接口与原始保持一致

local cmd = require("zig-lamp.core.core_cmd")
local job = require("plenary.job")
local util = require("zig-lamp.core.core_util")
local zig_ffi = require("zig-lamp.core.core_ffi")
local M = {}

local api, fn = vim.api, vim.fn
local nvim_open_win = api.nvim_open_win
local nvim_set_option_value = api.nvim_set_option_value

local help_namespace = vim.api.nvim_create_namespace("ZigLamp_pkg_help")
local help_hl_group = "ZigLamp_pkg_help"

-- find zig.build.zon file
local function find_build_zon(_path)
    local path = require("plenary.path")
    if not _path then
        _path = fn.getcwd()
    end
    local _p = path:new(_path)
    local _root = _p:find_upwards("build.zig.zon")
    return _root
end

local function get_hash(_url)
    if vim.fn.executable("zig") == 0 then
        return nil
    end
    util.Info("start get package hash")
    local _handle = vim.system({ "zig", "fetch", _url }, { text = true })
    local result = _handle:wait()
    if result.code ~= 0 then
        util.Error(string.format("failed fetch: %s, code is %d, signal is %d", _url, result.code, result.signal))
        return nil
    end
    if result.stdout then
        return vim.trim(result.stdout)
    end
    return nil
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

local function render(ctx)
    local buffer = ctx.buffer
    local zon_info = ctx.zon_info
    local str_len = string.len
    local package_info_str = "  Package Info"
    local content = { package_info_str, "" }
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
    local fingerprint_str = "  Fingerprint: "
    table.insert(content, fingerprint_str .. (zon_info.fingerprint or "[none]"))
    current_lnum = current_lnum + 1
    table.insert(highlight, {
        group = "Title",
        line = current_lnum,
        col_start = 0,
        col_end = str_len(fingerprint_str),
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
        for _, val in pairs(zon_info.paths) do
            current_lnum = current_lnum + 1
            table.insert(content, "    - " .. val)
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
                    col_end = str_len(hash_prefix) + str_len(_info.hash or "[none]"),
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

-- ===================== Zig Package Info 面板完整逻辑 =====================

local help_namespace = vim.api.nvim_create_namespace("ZigLamp_pkg_help")
local help_hl_group = "ZigLamp_pkg_help"

--- @param ctx pkg_ctx
local function delete_cb(ctx)
    local zon_path = find_build_zon()
    if not zon_path then
        util.Warn("not found build.zig.zon")
        return
    end
    local zon_info = zig_ffi.get_build_zon_info(zon_path:absolute())
    if not zon_info then
        util.Warn("parse build.zig.zon failed!")
        return
    end
    local current_file = fn.expand("%:p")
    local is_in_workspace = false
    if zon_info.paths and #zon_info.paths > 0 then
        for _, path in ipairs(zon_info.paths) do
            local full_path = vim.fn.fnamemodify(path, ":p")
            if full_path == current_file then
                is_in_workspace = true
                break
            end
        end
    end
    if not is_in_workspace then
        util.Warn("current file not in workspace paths")
        return
    end
    local target_file = vim.fn.fnamemodify(current_file, ":t")
    for _, target in ipairs(zon_info.targets) do
        if target.name == target_file then
            local command = { "zig", "build-official", "--clean", "--target", target.name }
            local result = job:new({
                command = command[1],
                args = vim.list_slice(command, 2),
                cwd = vim.fn.expand("%:p:h"),
                env = { ZIGBUILD_EXEC = "true" },
            }):sync()
            if result and #result > 0 then
                util.Info("clean target " .. target.name .. " success")
            else
                util.Error("clean target " .. target.name .. " failed")
            end
            return
        end
    end
    util.Warn("未找到目标文件 " .. target_file .. " 的清理命令")
end

--- @param ctx pkg_ctx
local edit_cb = function(ctx)
    local zon_path = find_build_zon()
    if not zon_path then
        util.Warn("not found build.zig.zon")
        return
    end
    local zon_info = zig_ffi.get_build_zon_info(zon_path:absolute())
    if not zon_info then
        util.Warn("parse build.zig.zon failed!")
        return
    end
    local current_file = fn.expand("%:p")
    local is_in_workspace = false
    if zon_info.paths and #zon_info.paths > 0 then
        for _, path in ipairs(zon_info.paths) do
            local full_path = vim.fn.fnamemodify(path, ":p")
            if full_path == current_file then
                is_in_workspace = true
                break
            end
        end
    end
    if not is_in_workspace then
        util.Warn("current file not in workspace paths")
        return
    end
    local target_file = vim.fn.fnamemodify(current_file, ":t")
    for _, target in ipairs(zon_info.targets) do
        if target.name == target_file then
            local command = { "zig", "build-official", "--edit", "--target", target.name }
            local result = job:new({
                command = command[1],
                args = vim.list_slice(command, 2),
                cwd = vim.fn.expand("%:p:h"),
                env = { ZIGBUILD_EXEC = "true" },
            }):sync()
            if result and #result > 0 then
                util.Info("edit target " .. target.name .. " success")
            else
                util.Error("edit target " .. target.name .. " failed")
            end
            return
        end
    end
    util.Warn("未找到目标文件 " .. target_file .. " 的编辑命令")
end

--- @param ctx pkg_ctx
local function sync_cb(ctx)
    local zon_path = find_build_zon()
    if not zon_path then
        util.Warn("not found build.zig.zon")
        return
    end
    local zon_info = zig_ffi.get_build_zon_info(zon_path:absolute())
    if not zon_info then
        util.Warn("parse build.zig.zon failed!")
        return
    end
    local current_file = fn.expand("%:p")
    local is_in_workspace = false
    if zon_info.paths and #zon_info.paths > 0 then
        for _, path in ipairs(zon_info.paths) do
            local full_path = vim.fn.fnamemodify(path, ":p")
            if full_path == current_file then
                is_in_workspace = true
                break
            end
        end
    end
    if not is_in_workspace then
        util.Warn("current file not in workspace paths")
        return
    end
    local target_file = vim.fn.fnamemodify(current_file, ":t")
    for _, target in ipairs(zon_info.targets) do
        if target.name == target_file then
            local command = { "zig", "build-official", "--sync", "--target", target.name }
            local result = job:new({
                command = command[1],
                args = vim.list_slice(command, 2),
                cwd = vim.fn.expand("%:p:h"),
                env = { ZIGBUILD_EXEC = "true" },
            }):sync()
            if result and #result > 0 then
                util.Info("sync target " .. target.name .. " success")
            else
                util.Error("sync target " .. target.name .. " failed")
            end
            return
        end
    end
    util.Warn("未找到目标文件 " .. target_file .. " 的同步命令")
end

--- @param ctx pkg_ctx
local function reload_cb(ctx)
    local zon_path = find_build_zon()
    if not zon_path then
        util.Warn("not found build.zig.zon")
        return
    end
    local zon_info = zig_ffi.get_build_zon_info(zon_path:absolute())
    if not zon_info then
        util.Warn("parse build.zig.zon failed!")
        return
    end
    local current_file = fn.expand("%:p")
    local is_in_workspace = false
    if zon_info.paths and #zon_info.paths > 0 then
        for _, path in ipairs(zon_info.paths) do
            local full_path = vim.fn.fnamemodify(path, ":p")
            if full_path == current_file then
                is_in_workspace = true
                break
            end
        end
    end
    if not is_in_workspace then
        util.Warn("current file not in workspace paths")
        return
    end
    local target_file = vim.fn.fnamemodify(current_file, ":t")
    for _, target in ipairs(zon_info.targets) do
        if target.name == target_file then
            local command = { "zig", "build-official", "--reload", "--target", target.name }
            local result = job:new({
                command = command[1],
                args = vim.list_slice(command, 2),
                cwd = vim.fn.expand("%:p:h"),
                env = { ZIGBUILD_EXEC = "true" },
            }):sync()
            if result and #result > 0 then
                util.Info("reload target " .. target.name .. " success")
            else
                util.Error("reload target " .. target.name .. " failed")
            end
            return
        end
    end
    util.Warn("未找到目标文件 " .. target_file .. " 的重载命令")
end

--- @param _ pkg_ctx
local function quit_cb(_)
    return function()
        api.nvim_win_close(0, true)
    end
end

--- @param ctx pkg_ctx
local function switch_cb(ctx)
    local zon_path = find_build_zon()
    if not zon_path then
        util.Warn("not found build.zig.zon")
        return
    end
    local zon_info = zig_ffi.get_build_zon_info(zon_path:absolute())
    if not zon_info then
        util.Warn("parse build.zig.zon failed!")
        return
    end
    local current_file = fn.expand("%:p")
    local is_in_workspace = false
    if zon_info.paths and #zon_info.paths > 0 then
        for _, path in ipairs(zon_info.paths) do
            local full_path = vim.fn.fnamemodify(path, ":p")
            if full_path == current_file then
                is_in_workspace = true
                break
            end
        end
    end
    if not is_in_workspace then
        util.Warn("current file not in workspace paths")
        return
    end
    local target_file = vim.fn.fnamemodify(current_file, ":t")
    for _, target in ipairs(zon_info.targets) do
        if target.name == target_file then
            local new_target = target.name
            if target.type == "path" then
                new_target = target.url
            end
            local command = { "zig", "build-official", "--switch", "--target", new_target }
            local result = job:new({
                command = command[1],
                args = vim.list_slice(command, 2),
                cwd = vim.fn.expand("%:p:h"),
                env = { ZIGBUILD_EXEC = "true" },
            }):sync()
            if result and #result > 0 then
                util.Info("switch target " .. target.name .. " success")
            else
                util.Error("switch target " .. target.name .. " failed")
            end
            return
        end
    end
    util.Warn("未找到目标文件 " .. target_file .. " 的切换命令")
end

--- @param ctx pkg_ctx
local function set_keymap(ctx)
    local key_metas = {
        { lhs = "q", desc = "quit for ZigLamp info panel", cb = quit_cb },
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
    local zon_path = find_build_zon()
    if not zon_path then
        util.Warn("not found build.zig.zon")
        return
    end
    local zon_info = zig_ffi.get_build_zon_info(zon_path:absolute())
    if not zon_info then
        util.Warn("parse build.zig.zon failed!")
        return
    end
    local new_buf = api.nvim_create_buf(false, true)
    local ctx = {
        zon_info = zon_info,
        zon_path = zon_path,
        buffer = new_buf,
    }
    render(ctx)
    set_buf_option(new_buf)
    local _ = nvim_open_win(new_buf, true, { split = "below", style = "minimal" })
    set_keymap(ctx)
end

function M.setup()
    cmd.set_command(cb_pkg, { "info" }, "pkg")
    vim.schedule(function()
        local hl_val = {
            fg = util.adjust_brightness(
                vim.g.zig_lamp_pkg_help_fg or "#CF5C00",
                30
            ),
            italic = true,
        }
        api.nvim_set_hl(0, help_hl_group, hl_val)
    end)
end

return M
