local Path = require("plenary.path")

local M = {}

M.data_path = Path:new(vim.fn.stdpath("data"), "zig-lamp")

local default_config = {
    lsp_config = {},
}

return M
