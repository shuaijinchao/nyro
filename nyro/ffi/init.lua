--
-- NYRO FFI Base Module
--
-- Unified native library loader. All Rust FFI modules share
-- a single cdylib (libnyro), loaded once and cached here.
--

local ffi = require("ffi")

local _M = {
    _VERSION = "0.1.0"
}

local lib = nil
local lib_loaded = false

-- Resolve the project root from this file's location (nyro/ffi/).
local function get_project_root()
    local info = debug.getinfo(1, "S")
    local dir  = info.source:match("^@(.*/)")
    if not dir then
        return "./"
    end
    -- nyro/ffi/ → go up two levels
    local root = dir:match("^(.*/)[^/]+/[^/]+/$")
    return root or "./"
end

-- Build a list of candidate library paths.
local function get_lib_paths()
    local root    = get_project_root()
    local os_name = jit and jit.os or "Linux"
    local ext     = (os_name == "OSX") and ".dylib" or ".so"

    return {
        -- Development (local build)
        root .. "lua_modules/lib/libnyro" .. ext,
        root .. "engine/target/release/libnyro" .. ext,
        "./lua_modules/lib/libnyro" .. ext,
        "./engine/target/release/libnyro" .. ext,
        -- Production (system install)
        "/usr/local/nyro/lib/libnyro" .. ext,
        "/usr/local/lib/libnyro" .. ext,
    }
end

function _M.load()
    if lib_loaded then
        return lib, nil
    end

    local paths  = get_lib_paths()
    local errors = {}

    for _, path in ipairs(paths) do
        local ok, result = pcall(ffi.load, path)
        if ok then
            lib = result
            lib_loaded = true
            return lib, nil
        else
            table.insert(errors, string.format("  %s: %s", path, tostring(result)))
        end
    end

    return nil, "Failed to load libnyro:\n" .. table.concat(errors, "\n")
end

function _M.get_lib()
    if not lib_loaded then
        return _M.load()
    end
    return lib, nil
end

return _M
