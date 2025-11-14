local ffi = require("ffi")
local Log = require("zig-lamp.log")
local System = require("zig-lamp.system")

local FFI = {}

local state = {
    cdef_ready = false,
    library = nil,
    load_attempts = 0,
    max_attempts = 3,
    plugin_path = nil,
}

local definitions = [[
    bool check_shasum(const char* file_path, const char* shasum);
    const char* get_build_zon_info(const char* file_path);
    void free_build_zon_info();
    const char* fmt_zon(const char* source_code);
    void free_fmt_zon();
]]

local function ensure_cdef()
    if state.cdef_ready then
        return true
    end
    local ok, err = pcall(ffi.cdef, definitions)
    if not ok then
        Log.error("初始化 FFI 定义失败", { error = err })
        return false
    end
    state.cdef_ready = true
    return true
end

local function locate_plugin_root()
    if state.plugin_path then
        return state.plugin_path
    end
    local source = debug.getinfo(1, "S").source:sub(2)
    local current = vim.fs.dirname(source)

    while current and current ~= "" do
        local marker = vim.fs.joinpath(current, "lua", "zig-lamp")
        if vim.loop.fs_stat(marker) then
            state.plugin_path = System.normalize(current)
            return state.plugin_path
        end
        local parent = vim.fs.dirname(current)
        if parent == current then
            break
        end
        current = parent
    end
    return nil
end

local function resolve_library_path()
    local root = locate_plugin_root()
    if not root then
        return nil
    end
    local info = System.info()
    local subdir = info.is_windows and "bin" or "lib"
    return vim.fs.joinpath(root, "zig-out", subdir, System.library_name("zig-lamp"))
end

local function load_library()
    if state.library then
        return state.library ~= true and state.library or nil
    end

    if state.load_attempts >= state.max_attempts then
        return nil
    end

    if not ensure_cdef() then
        return nil
    end

    state.load_attempts = state.load_attempts + 1
    local lib_path = resolve_library_path()
    if not lib_path or not System.is_file(lib_path) then
        Log.warn("未找到本地 zig-lamp 动态库", { path = lib_path })
        return nil
    end

    local ok, lib = pcall(ffi.load, lib_path)
    if not ok then
        Log.error("加载 zig-lamp 动态库失败", { path = lib_path, error = lib })
        if state.load_attempts >= state.max_attempts then
            state.library = true
        end
        return nil
    end

    state.library = lib
    Log.info("已加载 zig-lamp FFI", { path = lib_path })
    return state.library
end

function FFI.plugin_path()
    return locate_plugin_root()
end

function FFI.library_path()
    return resolve_library_path()
end

function FFI.available()
    return load_library() ~= nil
end

function FFI.check_shasum(file_path, shasum)
    local lib = load_library()
    if not lib then
        return true
    end
    local ok, result = pcall(lib.check_shasum, file_path, shasum)
    if not ok then
        Log.error("校验 shasum 失败", { error = result })
        return false
    end
    return result
end

function FFI.read_build_zon(file_path)
    local lib = load_library()
    if not lib then
        return nil
    end
    if not System.is_file(file_path) then
        return nil
    end
    local ok, data = pcall(lib.get_build_zon_info, file_path)
    if not ok then
        Log.error("解析 build.zig.zon 失败", { error = data })
        return nil
    end
    local result = ffi.string(data or "")
    lib.free_build_zon_info()
    if result == "" then
        return nil
    end
    return vim.fn.json_decode(result)
end

function FFI.format_zon(content)
    local lib = load_library()
    if not lib then
        return nil
    end
    local ok, data = pcall(lib.fmt_zon, content)
    if not ok then
        Log.error("格式化 ZON 失败", { error = data })
        return nil
    end
    local result = ffi.string(data or "")
    lib.free_fmt_zon()
    return result ~= "" and result or nil
end

return FFI

