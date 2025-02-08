local health = vim.health
local M = {}

local function check_lspconig()
    health.start("check lspconfig")
    local status, _ = pcall(require, "lspconfig")
    if status then
        health.ok("found lspconfig")
    else
        health.error("not found lspconfig")
    end
end

local function check_zig()
    health.start("check zig")
    if vim.fn.executable("zig") == 1 then
        health.ok("found zig")
    else
        health.error("not found zig")
    end
end

local function check_curl()
    health.start("check curl")
    if vim.fn.executable("curl") == 1 then
        health.ok("found curl")
    else
        health.error("not found curl")
    end
end

local function check_unzip()
    health.start("check unzip")
    local util = require("zig-lamp.util")
    if util.sys == "windows" then
        if vim.fn.executable("unzip") == 1 then
            health.ok("found unzip")
        else
            health.error("not found unzip")
        end
    else
        health.info("no need to use unzip")
    end
end

M.check = function()
    check_zig()
    check_curl()
    check_unzip()
    check_lspconig()
end

return M
