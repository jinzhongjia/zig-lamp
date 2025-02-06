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

M.check = function()
	check_zig()
	check_curl()
	check_lspconig()
end
