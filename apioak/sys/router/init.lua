--
-- APIOAK Router Module
-- 
-- 路由模块入口，提供路由管理和匹配功能
--

local matcher = require("apioak.sys.router.matcher")
local ffi_lib = require("apioak.sys.router.ffi")

local _M = {
    _VERSION = "0.1.0"
}

-- 导出匹配类型常量
_M.MATCH_EXACT  = matcher.MATCH_EXACT
_M.MATCH_PREFIX = matcher.MATCH_PREFIX
_M.MATCH_PARAM  = matcher.MATCH_PARAM
_M.MATCH_REGEX  = matcher.MATCH_REGEX

-- 导出 HTTP 方法常量
_M.METHOD_GET     = ffi_lib.METHOD_GET
_M.METHOD_POST    = ffi_lib.METHOD_POST
_M.METHOD_PUT     = ffi_lib.METHOD_PUT
_M.METHOD_DELETE  = ffi_lib.METHOD_DELETE
_M.METHOD_PATCH   = ffi_lib.METHOD_PATCH
_M.METHOD_HEAD    = ffi_lib.METHOD_HEAD
_M.METHOD_OPTIONS = ffi_lib.METHOD_OPTIONS
_M.METHOD_ALL     = ffi_lib.METHOD_ALL

-- 创建新的路由器实例
-- @return router instance 或 nil, error
function _M.new()
    return matcher.new()
end

-- 预加载 FFI 库 (可选，用于提前检测库是否可用)
function _M.preload()
    local lib, err = ffi_lib.load()
    if not lib then
        return false, err
    end
    return true
end

-- 检查 FFI 库是否已加载
function _M.is_loaded()
    local lib = ffi_lib.get_lib()
    return lib ~= nil
end

-- 辅助函数：将方法字符串/列表转换为位掩码
function _M.methods_to_bitmask(methods)
    return ffi_lib.methods_to_bitmask(methods)
end

-- 辅助函数：将位掩码转换为方法列表
function _M.bitmask_to_methods(mask)
    return ffi_lib.bitmask_to_methods(mask)
end

return _M
