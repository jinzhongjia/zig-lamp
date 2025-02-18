local fs, fn = vim.fs, vim.fn

local M = {}

---@diagnostic disable-next-line: param-type-mismatch
M.data_path = fs.normalize(fs.joinpath(fn.stdpath("data"), "zig-lamp"))

M.tmp_path = fs.normalize(fs.joinpath(M.data_path, "tmp"))

M.version = "0.0.1"

return M
