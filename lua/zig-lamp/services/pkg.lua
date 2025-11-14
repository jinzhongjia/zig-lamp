local FFI = require("zig-lamp.services.ffi")
local Log = require("zig-lamp.log")
local Utils = require("zig-lamp.utils")
local System = require("zig-lamp.system")

local Pkg = {}

local function ensure_ffi()
    if FFI.available() then
        return true
    end
    Log.warn('包管理面板需要本地 FFI 库，请运行 ":ZigLampBuild" 后重试')
    return false
end

function Pkg.find_build_zon(start_path)
    return System.find_upwards("build.zig.zon", start_path or vim.fn.getcwd())
end

function Pkg.read(path)
    if not ensure_ffi() then
        return nil, nil
    end
    path = path or Pkg.find_build_zon()
    if not path then
        Log.warn("未找到 build.zig.zon")
        return nil, nil
    end
    local info = FFI.read_build_zon(path)
    if not info then
        Log.error("解析 build.zig.zon 失败", { path = path })
        return nil, path
    end
    return info, path
end

function Pkg.write(path, content)
    if not ensure_ffi() then
        return false
    end
    if not path then
        return false
    end
    local zon_string = Utils.pkg_to_zon(content)
    local formatted = FFI.format_zon(zon_string) or zon_string
    local ok, err = System.write_file(path, formatted)
    if not ok then
        Log.error("写入 build.zig.zon 失败", { path = path, error = err })
        return false
    end
    Log.info("已写入 build.zig.zon", { path = path })
    return true
end

function Pkg.fetch_hash(url)
    if vim.fn.executable("zig") == 0 then
        Log.error("需要 zig 可执行文件以获取依赖 hash")
        return nil
    end
    local result = System.run("zig", { "fetch", url }, { timeout = 20000 })
    if result.code ~= 0 then
        Log.error("zig fetch 执行返回非零", { stderr = result.stderr })
        return nil
    end
    local output = vim.trim(result.stdout or "")
    return output ~= "" and output or nil
end

function Pkg.file_in_paths(pkg_info, file_path)
    if not pkg_info.paths or #pkg_info.paths == 0 then
        return false
    end
    local normalized = vim.fn.fnamemodify(file_path, ":p")
    for _, entry in ipairs(pkg_info.paths) do
        local abs = vim.fn.fnamemodify(entry, ":p")
        if abs == normalized then
            return true
        end
    end
    return false
end

return Pkg

