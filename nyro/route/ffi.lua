--
-- NYRO Router FFI Bindings
-- 
-- LuaJIT FFI 绑定，通过统一 FFI 基础模块加载 libnyro
--

local ffi = require("ffi")
local base_ffi = require("nyro.ffi")

local _M = {
    _VERSION = "0.1.0"
}

-- FFI C 函数声明
ffi.cdef[[
    /* 路由器句柄 */
    typedef struct nyro_router_s nyro_router_t;

    /* 路由参数 */
    typedef struct {
        const char *name;
        const char *value;
        size_t name_len;
        size_t value_len;
    } nyro_router_param_t;

    /* 匹配结果 */
    typedef struct {
        uintptr_t handler;
        nyro_router_param_t *params;
        int param_count;
        int match_type;
    } nyro_router_match_result_t;

    /* API 函数 */
    nyro_router_t *nyro_router_new(void);
    void nyro_router_free(nyro_router_t *router);

    int nyro_router_add(nyro_router_t *router,
                          const char *host,
                          const char *path,
                          size_t path_len,
                          uint32_t methods,
                          int match_type,
                          int priority,
                          uintptr_t handler);

    int nyro_router_build(nyro_router_t *router);

    int nyro_router_match(nyro_router_t *router,
                            const char *host,
                            size_t host_len,
                            const char *path,
                            size_t path_len,
                            uint32_t method,
                            nyro_router_match_result_t *result);

    void nyro_router_match_result_free(nyro_router_match_result_t *result);

    size_t nyro_router_count(nyro_router_t *router);

    void nyro_router_clear(nyro_router_t *router);
]]

-- 匹配类型常量
_M.MATCH_EXACT  = 1
_M.MATCH_PREFIX = 2
_M.MATCH_PARAM  = 3

-- 错误码
_M.OK          = 0
_M.ERR         = -1
_M.ERR_NOMEM   = -2
_M.ERR_INVALID = -3

-- HTTP 方法位掩码
_M.METHOD_GET     = 0x001
_M.METHOD_POST    = 0x002
_M.METHOD_PUT     = 0x004
_M.METHOD_DELETE  = 0x008
_M.METHOD_PATCH   = 0x010
_M.METHOD_HEAD    = 0x020
_M.METHOD_OPTIONS = 0x040
_M.METHOD_CONNECT = 0x080
_M.METHOD_TRACE   = 0x100
_M.METHOD_ALL     = 0xFFFFFFFF

-- HTTP 方法名到位掩码的映射
_M.METHOD_MAP = {
    GET     = _M.METHOD_GET,
    POST    = _M.METHOD_POST,
    PUT     = _M.METHOD_PUT,
    DELETE  = _M.METHOD_DELETE,
    PATCH   = _M.METHOD_PATCH,
    HEAD    = _M.METHOD_HEAD,
    OPTIONS = _M.METHOD_OPTIONS,
    CONNECT = _M.METHOD_CONNECT,
    TRACE   = _M.METHOD_TRACE,
}

-- 库访问 (委托给统一 FFI 基础模块)
function _M.load()
    return base_ffi.load()
end

function _M.get_lib()
    return base_ffi.get_lib()
end

-- 将 HTTP 方法字符串转换为位掩码
function _M.methods_to_bitmask(methods)
    if type(methods) == "number" then
        return methods
    end

    if type(methods) == "string" then
        return _M.METHOD_MAP[methods:upper()] or 0
    end

    if type(methods) == "table" then
        local mask = 0
        for _, method in ipairs(methods) do
            local m = _M.METHOD_MAP[method:upper()]
            if m then
                mask = bit.bor(mask, m)
            end
        end
        return mask
    end

    return 0
end

-- 将位掩码转换为 HTTP 方法字符串列表
function _M.bitmask_to_methods(mask)
    local methods = {}
    for name, value in pairs(_M.METHOD_MAP) do
        if bit.band(mask, value) ~= 0 then
            table.insert(methods, name)
        end
    end
    return methods
end

return _M
