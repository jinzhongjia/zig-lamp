-- Configuration management for zig-lamp plugin
-- Defines data paths and version information

local vim = vim
local fs, fn = vim.fs, vim.fn

local M = {}

-- Plugin data directory in Neovim's data path
M.data_path = fs.normalize(fs.joinpath(fn.stdpath("data"), "zig-lamp"))

-- Temporary files directory
M.tmp_path = fs.normalize(fs.joinpath(M.data_path, "tmp"))

-- Plugin version
M.version = "0.0.1"

return M
