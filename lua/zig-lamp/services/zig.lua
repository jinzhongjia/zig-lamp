---@diagnostic disable-next-line: undefined-global
local vim = vim

local Config = require("zig-lamp.config")
local Log = require("zig-lamp.log")
local System = require("zig-lamp.system")

local Zig = {}

local function resolve_cmd()
    return Config.get("zig.cmd") or "zig"
end

local function resolve_timeout()
    return Config.get("zig.timeout")
end

function Zig.version()
    local cmd = resolve_cmd()
    if vim.fn.executable(cmd) == 0 then
        Log.warn(string.format("未找到 zig 可执行文件（当前配置为 %s）", cmd))
        return nil
    end
    local result = System.run(cmd, { "version" }, { timeout = resolve_timeout() })
    if result.code ~= 0 then
        Log.debug("无法获取 zig 版本", {
            cmd = cmd,
            code = result.code,
            stderr = result.stderr,
        })
        return nil
    end
    local output = vim.trim(result.stdout or "")
    if output == "" then
        return nil
    end
    return output
end

function Zig.command()
    return resolve_cmd()
end

return Zig

