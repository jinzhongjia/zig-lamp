local vim = vim
-- pkg/init.lua
-- Migrated from module/pkg.lua, maintains interface compatibility
-- Package management module for Zig projects, handles build.zig.zon file operations

local cmd = require("zig-lamp.core.core_cmd")
local job = require("plenary.job")
local util = require("zig-lamp.core.core_util")
local zig_ffi = require("zig-lamp.core.core_ffi")
local M = {}

-- API shortcuts
local api, fn = vim.api, vim.fn
local nvim_open_win = api.nvim_open_win
local nvim_set_option_value = api.nvim_set_option_value

-- Constants
local HELP_NAMESPACE = vim.api.nvim_create_namespace("ZigLamp_pkg_help")
local HELP_HL_GROUP = "ZigLamp_pkg_help"
local FILETYPE = "ZigLamp_info"

-- Helper functions

--- Find build.zig.zon file starting from a directory
--- Searches upward from the given directory to locate the Zig package configuration file
--- @param start_path string|nil Starting directory path (defaults to current working directory)
--- @return table|nil Path object if found, nil otherwise
local function find_build_zon(start_path)
    local ok, path = pcall(require, "plenary.path")
    if not ok then
        util.Error("Failed to load plenary.path")
        return nil
    end
    
    local search_path = start_path or fn.getcwd()
    local path_obj = path:new(search_path)
    return path_obj:find_upwards("build.zig.zon")
end

--- Get package hash from URL using zig fetch
--- Uses Zig's built-in fetch command to retrieve and hash a package from a URL
--- @param url string Package URL to fetch
--- @return string|nil Package hash or nil if failed
local function get_hash(url)
    if vim.fn.executable("zig") == 0 then
        util.Error("Zig executable not found")
        return nil
    end
    
    util.Info("Getting package hash for: " .. url)
    
    local handle = vim.system({ "zig", "fetch", url }, { text = true })
    local result = handle:wait()
    
    if result.code ~= 0 then
        util.Error(string.format("Failed to fetch package: %s (exit code: %d)", url, result.code))
        return nil
    end
    
    return result.stdout and vim.trim(result.stdout) or nil
end

--- Get ZON information with error handling
--- Safely parses the build.zig.zon file and returns its content
--- @param zon_path table Path object to build.zig.zon file
--- @return table|nil ZON information or nil if failed
local function get_zon_info_safe(zon_path)
    if not zon_path then
        util.Warn("build.zig.zon file not found")
        return nil
    end
    
    local zon_info = zig_ffi.get_build_zon_info(zon_path:absolute())
    if not zon_info then
        util.Warn("Failed to parse build.zig.zon file")
        return nil
    end
    
    return zon_info
end

--- Check if current file is in workspace paths
--- Determines whether the current file is included in the project's workspace paths
--- @param zon_info table ZON information containing paths array
--- @param current_file string Current file path to check
--- @return boolean True if file is in workspace, false otherwise
local function is_file_in_workspace(zon_info, current_file)
    if not zon_info.paths or #zon_info.paths == 0 then
        return false
    end
    
    for _, path in ipairs(zon_info.paths) do
        local full_path = vim.fn.fnamemodify(path, ":p")
        if full_path == current_file then
            return true
        end
    end
    
    return false
end

--- Execute zig build command with target
--- Runs a Zig build command with specified arguments and provides feedback
--- @param command_args table Command arguments array (first element is command, rest are args)
--- @param target_name string Target name for logging purposes
--- @param action_name string Action description for user feedback
--- @return boolean Success status
local function execute_zig_build_command(command_args, target_name, action_name)
    local result = job:new({
        command = command_args[1],
        args = vim.list_slice(command_args, 2),
        cwd = vim.fn.expand("%:p:h"),
        env = { ZIGBUILD_EXEC = "true" },
    }):sync()
    
    if result and #result > 0 then
        util.Info(string.format("%s target '%s' completed successfully", action_name, target_name))
        return true
    else
        util.Error(string.format("Failed to %s target '%s'", action_name, target_name))
        return false
    end
end

--- Process ZON operation for current file
--- Generic function to handle various Zig build operations (clean, edit, sync, reload)
--- @param operation_args table Operation-specific command arguments
--- @param action_name string Action description for logging
--- @return boolean Success status
local function process_zon_operation(operation_args, action_name)
    local zon_path = find_build_zon()
    local zon_info = get_zon_info_safe(zon_path)
    if not zon_info then
        return false
    end
    
    local current_file = fn.expand("%:p")
    if not is_file_in_workspace(zon_info, current_file) then
        util.Warn("Current file is not in workspace paths")
        return false
    end
    
    local target_file = vim.fn.fnamemodify(current_file, ":t")
    
    -- Search for matching target in build configuration
    if not zon_info.targets then
        util.Warn("No targets found in build.zig.zon")
        return false
    end
    
    for _, target in ipairs(zon_info.targets) do
        if target.name == target_file then
            local command = vim.list_extend({ "zig", "build-official" }, operation_args)
            table.insert(command, "--target")
            table.insert(command, target.name)
            
            return execute_zig_build_command(command, target.name, action_name)
        end
    end
    
    util.Warn(string.format("Target file '%s' not found in build configuration", target_file))
    return false
end

-- UI rendering functions

--- Render help text with key bindings
--- Displays contextual help information as virtual text on the right side of the buffer
--- @param buffer number Buffer handle to render help text in
local function render_help_text(buffer)
    local help_content = {
        "Key [q] to quit",
        "Key [i] to add or edit", 
        "Key [o] to switch dependency type (url or path)",
        "Key [<leader>r] to reload from file",
        "Key [d] to delete dependency or path",
        "Key [<leader>s] to sync changes to file",
    }
    
    for index, text in ipairs(help_content) do
        api.nvim_buf_set_extmark(buffer, HELP_NAMESPACE, index - 1, 0, {
            virt_text = {{ text .. " ", HELP_HL_GROUP }},
            virt_text_pos = "right_align",
        })
    end
end

--- Add syntax highlighting for a text segment
--- Helper function to create highlight table entries with proper positioning
--- @param highlights table Highlights array to append to
--- @param group string Highlight group name
--- @param line number Line number (0-indexed)
--- @param text string Text content to highlight
--- @param prefix string Text prefix to calculate offset
local function add_highlight(highlights, group, line, text, prefix)
    local prefix_len = string.len(prefix or "")
    local text_len = string.len(text or "")
    
    table.insert(highlights, {
        group = group,
        line = line,
        col_start = prefix_len,
        col_end = prefix_len + text_len,
    })
end

--- Render package information display
--- Creates a formatted display of package information from build.zig.zon
--- @param ctx table Context containing buffer handle and zon_info data
local function render(ctx)
    local buffer = ctx.buffer
    local zon_info = ctx.zon_info
    local content = {}
    local highlights = {}
    local current_line = 0
    
    -- Package Info header
    local header = "  Package Information"
    table.insert(content, header)
    add_highlight(highlights, "Title", current_line, header, "")
    current_line = current_line + 1
    
    table.insert(content, "") -- Empty line for spacing
    current_line = current_line + 1
    
    -- Package metadata section
    local details = {
        { label = "  Name: ", value = zon_info.name or "[none]" },
        { label = "  Version: ", value = zon_info.version or "[none]" },
        { label = "  Fingerprint: ", value = zon_info.fingerprint or "[none]" },
        { label = "  Minimum Zig version: ", value = zon_info.minimum_zig_version or "[none]" },
    }
    
    for _, detail in ipairs(details) do
        table.insert(content, detail.label .. detail.value)
        add_highlight(highlights, "Title", current_line, detail.label, "")
        current_line = current_line + 1
    end
    
    -- Paths section - shows which paths are included in the package
    if zon_info.paths and #zon_info.paths == 1 and zon_info.paths[1] == "" then
        local paths_text = "  Paths [include all]"
        table.insert(content, paths_text)
        add_highlight(highlights, "Title", current_line, paths_text, "")
        current_line = current_line + 1
    elseif zon_info.paths and #zon_info.paths > 0 then
        local paths_header = "  Paths: "
        table.insert(content, paths_header)
        add_highlight(highlights, "Title", current_line, paths_header, "")
        current_line = current_line + 1
        
        for _, path_item in ipairs(zon_info.paths) do
            table.insert(content, "    - " .. path_item)
            current_line = current_line + 1
        end
    else
        local paths_text = "  Paths [none]"
        table.insert(content, paths_text)
        add_highlight(highlights, "Title", current_line, paths_text, "")
        current_line = current_line + 1
    end
    
    -- Dependencies section - shows all package dependencies
    local dep_count = zon_info.dependencies and vim.tbl_count(zon_info.dependencies) or 0
    local deps_header = string.format("  Dependencies [%d]: ", dep_count)
    table.insert(content, deps_header)
    add_highlight(highlights, "Title", current_line, deps_header, "")
    current_line = current_line + 1
    
    if zon_info.dependencies and not vim.tbl_isempty(zon_info.dependencies) then
        for name, dep_info in pairs(zon_info.dependencies) do
            -- Dependency name
            local name_prefix = "    - "
            table.insert(content, name_prefix .. name)
            add_highlight(highlights, "Tag", current_line, name, name_prefix)
            current_line = current_line + 1
            
            -- URL or local path source
            if dep_info.url then
                local url_prefix = "      url: "
                table.insert(content, url_prefix .. dep_info.url)
                add_highlight(highlights, "Underlined", current_line, dep_info.url, url_prefix)
                current_line = current_line + 1
            elseif dep_info.path then
                local path_prefix = "      path: "
                table.insert(content, path_prefix .. dep_info.path)
                add_highlight(highlights, "Underlined", current_line, dep_info.path, path_prefix)
                current_line = current_line + 1
            else
                table.insert(content, "      [no url or path specified]")
                current_line = current_line + 1
            end
            
            -- Hash (only displayed for URL dependencies)
            if dep_info.url then
                local hash_prefix = "      hash: "
                local hash_value = dep_info.hash or "[none]"
                table.insert(content, hash_prefix .. hash_value)
                add_highlight(highlights, "Underlined", current_line, hash_value, hash_prefix)
                current_line = current_line + 1
            end
            
            -- Lazy loading flag - indicates if dependency should be loaded on-demand
            local lazy_prefix = "      lazy: "
            local lazy_value = dep_info.lazy == nil and "[unset]" or tostring(dep_info.lazy)
            table.insert(content, lazy_prefix .. lazy_value)
            current_line = current_line + 1
        end
    end
    
    -- Update buffer content and apply styling
    nvim_set_option_value("modifiable", true, { buf = buffer })
    api.nvim_buf_set_lines(buffer, 0, -1, true, content)
    
    -- Apply syntax highlighting
    for _, hl in ipairs(highlights) do
        api.nvim_buf_add_highlight(buffer, HELP_NAMESPACE, hl.group, hl.line, hl.col_start, hl.col_end)
    end
    
    render_help_text(buffer)
    nvim_set_option_value("modifiable", false, { buf = buffer })
end

-- Command callbacks - Functions that handle user interactions

--- Delete/clean callback
--- Handles the 'd' key press to delete dependencies or paths based on cursor position
--- @param ctx table Package context containing buffer and zon info
--- @return function Callback function for keymap
local function delete_cb(ctx)
    return function()
        local lnum = api.nvim_win_get_cursor(0)[1] - 2
        if lnum < 1 then
            return
        end
        lnum = lnum - 4 -- Skip header and metadata lines

        lnum = lnum - 1 -- Skip paths header

        -- Handle path deletion
        if ctx.zon_info.paths and #ctx.zon_info.paths > 0 and ctx.zon_info.paths[1] ~= "" then
            for index, _ in pairs(ctx.zon_info.paths) do
                if lnum - 1 == 0 then
                    table.remove(ctx.zon_info.paths, index)
                    render(ctx)
                    return
                end
                lnum = lnum - 1
            end
        end

        lnum = lnum - 1 -- Skip dependencies header
        
        -- Handle dependency deletion
        local deps_is_empty = vim.tbl_isempty(ctx.zon_info.dependencies)
        if ctx.zon_info.dependencies and not deps_is_empty then
            for name, dep_info in pairs(ctx.zon_info.dependencies) do
                local line_count = dep_info.url and 4 or 3
                
                if lnum > 0 and lnum < line_count + 1 then
                    ctx.zon_info.dependencies[name] = nil
                    render(ctx)
                    return
                end
                lnum = lnum - line_count
            end
        end
    end
end

--- Edit callback  
--- Handles the 'i' key press to edit package information based on cursor position
--- @param ctx table Package context containing buffer and zon info
--- @return function Callback function for keymap
local function edit_cb(ctx)
    return function()
        local lnum = api.nvim_win_get_cursor(0)[1] - 2
        if lnum < 1 then
            return
        end

        -- Edit package name
        if lnum - 1 == 0 then
            vim.ui.input({
                prompt = "Enter value for name: ",
                default = ctx.zon_info.name,
            }, function(input)
                if not input then return end
                if input == "" then
                    util.Warn("Package name cannot be empty!")
                    return
                end
                ctx.zon_info.name = input
                render(ctx)
            end)
            return
        end
        lnum = lnum - 1

        -- Edit package version
        if lnum - 1 == 0 then
            vim.ui.input({
                prompt = "Enter value for version: ",
                default = ctx.zon_info.version,
            }, function(input)
                if not input then return end
                if input == "" then
                    util.Warn("Package version cannot be empty!")
                    return
                end
                ctx.zon_info.version = input
                render(ctx)
            end)
            return
        end
        lnum = lnum - 1

        -- Edit package fingerprint
        if lnum - 1 == 0 then
            vim.ui.input({
                prompt = "Enter value for fingerprint: ",
                default = ctx.zon_info.fingerprint,
            }, function(input)
                if not input then return end
                ctx.zon_info.fingerprint = input == "" and nil or input
                render(ctx)
            end)
            return
        end
        lnum = lnum - 1

        -- Edit minimum Zig version
        if lnum - 1 == 0 then
            vim.ui.input({
                prompt = "Enter value for minimum Zig version: ",
                default = ctx.zon_info.minimum_zig_version,
            }, function(input)
                if not input then return end
                ctx.zon_info.minimum_zig_version = input == "" and nil or input
                render(ctx)
            end)
            return
        end
        lnum = lnum - 1

        -- Add new path
        if lnum - 1 == 0 then
            vim.ui.input({
                prompt = "Enter value for new path: ",
            }, function(input)
                if not input then return end
                if ctx.zon_info.paths and #ctx.zon_info.paths == 1 and ctx.zon_info.paths[1] == "" then
                    ctx.zon_info.paths = { input }
                else
                    ctx.zon_info.paths = ctx.zon_info.paths or {}
                    table.insert(ctx.zon_info.paths, input)
                end
                render(ctx)
            end)
            return
        end
        lnum = lnum - 1

        -- Edit existing paths
        if ctx.zon_info.paths and #ctx.zon_info.paths > 0 and ctx.zon_info.paths[1] ~= "" then
            for index, val in pairs(ctx.zon_info.paths) do
                if lnum - 1 == 0 then
                    vim.ui.input({
                        prompt = "Enter value for path: ",
                        default = val,
                    }, function(input)
                        if not input then return end
                        ctx.zon_info.paths[index] = input
                        render(ctx)
                    end)
                    return
                end
                lnum = lnum - 1
            end
        end

        -- Add new dependency
        if lnum - 1 == 0 then
            vim.ui.input({
                prompt = "Enter name for new dependency: ",
                default = "new_dep",
            }, function(input)
                if not input then return end
                ctx.zon_info.dependencies = ctx.zon_info.dependencies or {}
                ctx.zon_info.dependencies[input] = {}
                render(ctx)
            end)
            return
        end
        lnum = lnum - 1

        -- Edit existing dependencies
        local deps_is_empty = vim.tbl_isempty(ctx.zon_info.dependencies or {})
        if ctx.zon_info.dependencies and not deps_is_empty then
            for name, dep_info in pairs(ctx.zon_info.dependencies) do
                -- Edit dependency name
                if lnum - 1 == 0 then
                    vim.ui.input({
                        prompt = "Enter value for dependency name: ",
                        default = name,
                    }, function(input)
                        if not input then return end
                        ctx.zon_info.dependencies[input] = dep_info
                        ctx.zon_info.dependencies[name] = nil
                        render(ctx)
                    end)
                    return
                end
                lnum = lnum - 1

                -- Edit dependency URL/path
                if lnum - 1 == 0 then
                    if dep_info.url == nil and dep_info.path == nil then
                        -- Choose dependency type
                        vim.ui.select({ "url", "path" }, {
                            prompt = "Select dependency type:",
                            format_item = function(item)
                                return "I'd like to choose " .. item
                            end,
                        }, function(choice)
                            if not choice then return end
                            vim.ui.input({
                                prompt = string.format("Enter value for dependency %s: ", choice),
                            }, function(input)
                                if not input then return end
                                if choice == "path" then
                                    ctx.zon_info.dependencies[name].path = input
                                else
                                    ctx.zon_info.dependencies[name].url = input
                                    local hash = get_hash(input)
                                    if hash then
                                        ctx.zon_info.dependencies[name].hash = hash
                                    end
                                end
                                render(ctx)
                            end)
                        end)
                        return
                    end
                    
                    local is_url = dep_info.url ~= nil
                    vim.ui.input({
                        prompt = string.format("Enter value for dependency %s: ", is_url and "url" or "path"),
                        default = is_url and dep_info.url or dep_info.path,
                    }, function(input)
                        if not input then return end
                        if input == "" then
                            ctx.zon_info.dependencies[name].url = nil
                            ctx.zon_info.dependencies[name].path = nil
                            render(ctx)
                            return
                        end

                        if is_url then
                            ctx.zon_info.dependencies[name].url = input
                            local hash = get_hash(input)
                            if hash then
                                ctx.zon_info.dependencies[name].hash = hash
                            end
                        else
                            ctx.zon_info.dependencies[name].path = input
                        end
                        render(ctx)
                    end)
                    return
                end
                lnum = lnum - 1

                -- Edit hash (only for URL dependencies)
                if dep_info.url then
                    if lnum - 1 == 0 then
                        vim.ui.input({
                            prompt = "Enter value for dependency hash: ",
                            default = dep_info.hash,
                        }, function(input)
                            if not input then return end
                            ctx.zon_info.dependencies[name].hash = input
                            render(ctx)
                        end)
                        return
                    end
                    lnum = lnum - 1
                end

                -- Edit lazy flag
                if lnum - 1 == 0 then
                    vim.ui.select({ "true", "false", "unset" }, {
                        prompt = "Choose lazy loading option:",
                        format_item = function(item)
                            return "I'd like to choose " .. item
                        end,
                    }, function(choice)
                        if not choice then return end
                        if choice == "true" then
                            ctx.zon_info.dependencies[name].lazy = true
                        elseif choice == "false" then
                            ctx.zon_info.dependencies[name].lazy = false
                        elseif choice == "unset" then
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

--- Sync callback
--- Handles the '<leader>s' key press to sync changes to the build.zig.zon file
--- @param ctx table Package context containing buffer and zon info
--- @return function Callback function for keymap
local function sync_cb(ctx)
    return function()
        local zon_str = util.wrap_j2zon(ctx.zon_info)
        local fmted_code = zig_ffi.fmt_zon(zon_str)
        if not fmted_code then
            util.Warn("Format ZON failed during sync!")
            return
        end
        ctx.zon_path:write(fmted_code, "w", 438)
        util.Info("Sync ZON success!")
    end
end

--- Reload callback
--- Handles the '<leader>r' key press to reload configuration from file
--- @param ctx table Package context containing buffer and zon info
--- @return function Callback function for keymap
local function reload_cb(ctx)
    return function()
        local zon_info = zig_ffi.get_build_zon_info(ctx.zon_path:absolute())
        if not zon_info then
            util.Warn("Reload failed - could not parse build.zig.zon!")
            return
        end
        ctx.zon_info = zon_info
        render(ctx)
        util.Info("Reload success!")
    end
end

--- Quit callback
--- Handles the 'q' key press to close the package info window
--- @param ctx table Package context (unused but kept for consistency)
--- @return function Callback function for keymap
local function quit_cb(ctx)
    return function()
        api.nvim_win_close(0, true)
    end
end

--- Switch dependency type callback
--- Handles the 'o' key press to switch between URL and path dependency types
--- @param ctx table Package context containing buffer and zon info
--- @return function Callback function for keymap
local function switch_cb(ctx)
    return function()
        local lnum = api.nvim_win_get_cursor(0)[1] - 2
        if lnum < 1 then
            return
        end
        
        -- Skip metadata lines
        lnum = lnum - 4 -- name, version, fingerprint, minimum zig version
        lnum = lnum - 1 -- paths header
        
        -- Skip path lines
        if ctx.zon_info.paths and #ctx.zon_info.paths > 0 and ctx.zon_info.paths[1] ~= "" then
            for _, _ in pairs(ctx.zon_info.paths) do
                lnum = lnum - 1
            end
        end
        
        lnum = lnum - 1 -- dependencies header
        
        -- Find and switch dependency type
        local deps_is_empty = vim.tbl_isempty(ctx.zon_info.dependencies or {})
        if ctx.zon_info.dependencies and not deps_is_empty then
            for name, dep_info in pairs(ctx.zon_info.dependencies) do
                local is_url = dep_info.url ~= nil
                local line_count = is_url and 4 or 3
                
                if lnum > 0 and lnum < line_count + 1 then
                    vim.ui.input({
                        prompt = string.format("Enter value for dependency %s: ", (not is_url) and "url" or "path"),
                    }, function(input)
                        if not input then return end
                        if input == "" then
                            ctx.zon_info.dependencies[name].url = nil
                            ctx.zon_info.dependencies[name].path = nil
                            render(ctx)
                            return
                        end

                        if not is_url then
                            -- Switch from path to URL
                            local hash = get_hash(input)
                            if hash then
                                ctx.zon_info.dependencies[name].url = input
                                ctx.zon_info.dependencies[name].hash = hash
                                ctx.zon_info.dependencies[name].path = nil
                            end
                        else
                            -- Switch from URL to path
                            ctx.zon_info.dependencies[name].path = input
                            ctx.zon_info.dependencies[name].url = nil
                            ctx.zon_info.dependencies[name].hash = nil
                        end
                        render(ctx)
                    end)
                    return
                end
                lnum = lnum - line_count
            end
        end
    end
end

--- Setup key mappings for the package info panel
--- Configures all keyboard shortcuts for interacting with the package display
--- @param ctx table Package context containing buffer handle and zon info
local function set_keymap(ctx)
    local key_mappings = {
        { key = "q", desc = "Quit ZigLamp info panel", callback = quit_cb },
        { key = "i", desc = "Add or edit dependency", callback = edit_cb },
        { key = "o", desc = "Switch dependency type", callback = switch_cb },
        { key = "<leader>r", desc = "Reload from file", callback = reload_cb },
        { key = "d", desc = "Delete dependency", callback = delete_cb },
        { key = "<leader>s", desc = "Sync changes to file", callback = sync_cb },
    }
    
    for _, mapping in ipairs(key_mappings) do
        api.nvim_buf_set_keymap(ctx.buffer, "n", mapping.key, "", {
            noremap = true,
            nowait = true,
            desc = mapping.desc,
            callback = mapping.callback(ctx),
        })
    end
end

--- Configure buffer options for the info panel
--- Sets appropriate buffer settings for the package information display
--- @param buffer number Buffer handle to configure
local function set_buf_option(buffer)
    local options = {
        { option = "filetype", value = FILETYPE },
        { option = "bufhidden", value = "delete" },  -- Auto-delete when hidden
        { option = "undolevels", value = -1 },       -- Disable undo for this buffer
        { option = "modifiable", value = false },    -- Make buffer read-only by default
    }
    
    for _, opt in ipairs(options) do
        nvim_set_option_value(opt.option, opt.value, { buf = buffer })
    end
end

--- Main callback for package info command
--- Entry point for the ':ZigLamp pkg info' command
--- @param args string[] Command arguments (currently unused)
local function cb_pkg(args)
    local zon_path = find_build_zon()
    local zon_info = get_zon_info_safe(zon_path)
    if not zon_info then
        return
    end
    
    -- Create and configure buffer for package display
    local new_buf = api.nvim_create_buf(false, true)
    local ctx = {
        zon_info = zon_info,
        zon_path = zon_path,
        buffer = new_buf,
    }
    
    -- Setup display content and styling
    render(ctx)
    set_buf_option(new_buf)
    
    -- Open window and setup interactive keymaps
    nvim_open_win(new_buf, true, { split = "below", style = "minimal" })
    set_keymap(ctx)
end

--- Initialize the package module
--- Sets up commands and highlighting for the package management features
function M.setup()
    -- Register the main package info command
    cmd.set_command(cb_pkg, { "info" }, "pkg")
    
    -- Setup custom highlight group for help text
    vim.schedule(function()
        local hl_config = {
            fg = util.adjust_brightness(vim.g.zig_lamp_pkg_help_fg or "#CF5C00", 30),
            italic = true,
        }
        api.nvim_set_hl(0, HELP_HL_GROUP, hl_config)
    end)
end

return M
