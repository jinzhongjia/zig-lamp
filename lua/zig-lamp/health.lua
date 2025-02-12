local health = vim.health
local M = {}

local function check_lspconfig()
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

local function check_tar()
    local util = require("zig-lamp.util")
    if util.sys ~= "windows" then
        health.start("check tar")
        if vim.fn.executable("tar") == 1 then
            health.ok("found tar")
        else
            health.error("not found tar")
        end
    end
end

local function check_unzip()
    local util = require("zig-lamp.util")
    if util.sys == "windows" then
        health.start("check unzip")
        if vim.fn.executable("unzip") == 1 then
            health.ok("found unzip")
        else
            health.error("not found unzip")
        end
    end
end

local function check_lib()
    health.start("check dynamic library")
    local zig_ffi = require("zig-lamp.ffi")
    if zig_ffi.get_lamp() then
        health.ok("found lib")
    else
        health.error("not found lib")
    end
end

M.check = function()
    check_zig()
    check_curl()
    check_unzip()
    check_tar()
    check_lspconfig()
    check_lib()
end

return M
