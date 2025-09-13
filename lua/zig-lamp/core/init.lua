-- zig-lamp core module
-- Unified management of core functionality and initialization process

local M = {}

local util = require("zig-lamp.core.core_util")
local config = require("zig-lamp.core.core_config")
local cmd = require("zig-lamp.core.core_cmd")

--- Whether core module is initialized
local _initialized = false

--- Plugin configuration
local _plugin_config = {}

--- Initialize core module
---@param user_config table User configuration
function M.setup(user_config)
    if _initialized then
        -- Silently skip duplicate initialization in most cases
        -- Only warn if config is significantly different
        return
    end

    _plugin_config = user_config or {}

    -- Initialize command system
    cmd.init_command()

    -- Register basic commands
    M.register_commands()

    -- Initialize sub-modules
    require("zig-lamp.info").setup()
    require("zig-lamp.pkg").setup()
    require("zig-lamp.zig").setup()
    require("zig-lamp.zls").setup()

    _initialized = true
    util.Info("zig-lamp initialization completed")
end

--- Register plugin commands
function M.register_commands()
    -- Health check command
    cmd.set_command(function()
        require("zig-lamp.health").check()
    end, nil, "health")

    -- Info panel command
    cmd.set_command(function()
        require("zig-lamp.info").show()
    end, nil, "info")

    -- Package manager command
    cmd.set_command(function()
        require("zig-lamp.pkg").open()
    end, nil, "pkg")

    -- Build command
    cmd.set_command(function(args)
        local mode = args[1] or "async"
        local timeout = args[2] and tonumber(args[2]) or nil

        local build = require("zig-lamp.core.core_build")
        build.build_library({
            mode = mode,
            timeout = timeout,
            optimization = "ReleaseFast",
            verbose = false,
            clean = false,
        })
    end, function()
        return { "sync", "async" }
    end, "build")

    -- Test command
    cmd.set_command(function(args)
        local mode = args[1] or "async"
        local build = require("zig-lamp.core.core_build")
        build.test({
            mode = mode,
            optimization = "ReleaseFast",
            verbose = false,
            clean = false,
        })
    end, function()
        return { "sync", "async" }
    end, "test")

    -- Clean command
    cmd.set_command(function()
        local build = require("zig-lamp.core.core_build")
        build.build_library({
            mode = "sync",
            clean = true,
            optimization = "ReleaseFast",
            verbose = false,
        })
    end, nil, "clean")

    -- ZLS management commands
    cmd.set_command(function()
        require("zig-lamp.zls").install()
    end, nil, "zls", "install")

    cmd.set_command(function()
        require("zig-lamp.zls").uninstall()
    end, nil, "zls", "uninstall")

    cmd.set_command(function()
        local status = require("zig-lamp.zls").status()

        -- Format status information for user-friendly display
        local lines = {
            "=== ZLS Status ===",
            "Zig Version: " .. (status.zig_version or "unknown"),
            "Current ZLS Version: " .. (status.current_zls_version or "none"),
            "Using System ZLS: " .. (status.using_system_zls and "yes" or "no"),
            "System ZLS Available: " .. (status.system_zls_available and "yes" or "no"),
            "LSP Initialized: " .. (status.lsp_initialized and "yes" or "no"),
        }

        if status.system_zls_version then
            table.insert(lines, "System ZLS Version: " .. status.system_zls_version)
        end

        if status.available_local_versions and #status.available_local_versions > 0 then
            table.insert(lines, "Available Local Versions:")
            for _, version in ipairs(status.available_local_versions) do
                table.insert(lines, "  - " .. version)
            end
        else
            table.insert(lines, "Available Local Versions: none")
        end

        -- Display in a formatted way
        local message = table.concat(lines, "\n")
        -- Use vim.notify to ensure status is always shown regardless of log level
        vim.notify(message, vim.log.levels.INFO, { title = "ZLS Status" })
    end, nil, "zls", "status")
end

--- Get plugin configuration
---@return table config Current configuration
function M.get_config()
    return vim.deepcopy(_plugin_config)
end

--- Check if core module is initialized
---@return boolean initialized Whether initialized
function M.is_initialized()
    return _initialized
end

--- Get core module version
---@return string version Version number
function M.version()
    return config.version
end

return M
