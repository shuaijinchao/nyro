--
-- NYRO Router Matcher
--
-- 高层封装，提供 Lua 友好的路由匹配 API
-- 支持精确匹配、前缀匹配、参数匹配
--

local ffi = require("ffi")
local ffi_lib = require("nyro.route.ffi")

local setmetatable = setmetatable
local type = type
local pairs = pairs
local ipairs = ipairs
local tostring = tostring
local tonumber = tonumber
local string_sub = string.sub
local string_find = string.find

local _M = {
    _VERSION = "0.3.0"
}

local mt = { __index = _M }

-- 匹配类型常量 (导出)
_M.MATCH_EXACT  = ffi_lib.MATCH_EXACT
_M.MATCH_PREFIX = ffi_lib.MATCH_PREFIX
_M.MATCH_PARAM  = ffi_lib.MATCH_PARAM

-- 匹配类型字符串映射
local MATCH_TYPE_MAP = {
    exact  = _M.MATCH_EXACT,
    prefix = _M.MATCH_PREFIX,
    param  = _M.MATCH_PARAM,
}

-- 路由处理器存储 (handler_id -> handler_data)
local handlers = {}
local handler_id_counter = 0

-- 解析 match_type 参数
-- 支持数字常量或字符串
local function parse_match_type(match_type)
    if type(match_type) == "number" then
        return match_type
    elseif type(match_type) == "string" then
        return MATCH_TYPE_MAP[match_type:lower()]
    end
    return nil
end

-- 检测路径的匹配类型
local function detect_match_type(path)
    if not path or path == "" then
        return _M.MATCH_EXACT
    end

    -- 包含 {param} 表示参数匹配
    if string_find(path, "{", 1, true) then
        return _M.MATCH_PARAM
    end

    -- 以 * 结尾表示前缀匹配
    if string_sub(path, -1) == "*" then
        return _M.MATCH_PREFIX
    end

    return _M.MATCH_EXACT
end

-- 创建新的路由匹配器实例
function _M.new()
    local lib, err = ffi_lib.get_lib()
    if not lib then
        return nil, err
    end

    local router = lib.nyro_router_new()
    if router == nil then
        return nil, "failed to create router instance"
    end

    -- 使用 ffi.gc 注册垃圾回收时的清理函数
    ffi.gc(router, lib.nyro_router_free)

    local self = {
        _router = router,
        _lib = lib,
        _built = false,
        _handlers = {},       -- 本实例的处理器映射
    }

    return setmetatable(self, mt)
end

-- 添加路由
-- @param opts table 路由配置
--   - path: string 路径模式 (必需)
--   - methods: string|table HTTP 方法 (可选，默认 ALL)
--   - host: string 主机名 (可选)
--   - match_type: string|number 匹配类型 (可选，默认自动检测)
--     支持: "exact", "prefix", "param" 或常量
--   - priority: number 优先级 (可选，默认 0)
--   - handler: any 处理器数据 (必需)
function _M.add(self, opts)
    if not opts or type(opts) ~= "table" then
        return false, "opts must be a table"
    end

    if not opts.path or type(opts.path) ~= "string" then
        return false, "path is required and must be a string"
    end

    if opts.handler == nil then
        return false, "handler is required"
    end

    local path = opts.path
    local host = opts.host or "*"
    local methods = ffi_lib.methods_to_bitmask(opts.methods or ffi_lib.METHOD_ALL)
    local priority = opts.priority or 0

    -- 解析或自动检测匹配类型
    local match_type = parse_match_type(opts.match_type)
    if not match_type then
        match_type = detect_match_type(path)
    end

    -- 生成 handler_id 并存储 handler
    handler_id_counter = handler_id_counter + 1
    local handler_id = handler_id_counter
    handlers[handler_id] = opts.handler
    self._handlers[handler_id] = true

    -- 处理前缀匹配路径 (去掉尾部 *)
    local c_path = path
    if match_type == _M.MATCH_PREFIX and string_sub(path, -1) == "*" then
        c_path = string_sub(path, 1, -2)
        if c_path == "" then
            c_path = "/"
        end
    end

    local path_len = #c_path

    -- 调用 C 函数添加路由
    local ret = self._lib.nyro_router_add(
        self._router,
        host,
        c_path,
        path_len,
        methods,
        match_type,
        priority,
        handler_id
    )

    if ret ~= ffi_lib.OK then
        handlers[handler_id] = nil
        self._handlers[handler_id] = nil
        return false, "failed to add route, error code: " .. tostring(ret)
    end

    self._built = false
    return true
end

-- 批量添加路由
function _M.add_routes(self, routes)
    if type(routes) ~= "table" then
        return false, "routes must be a table"
    end

    for i, route in ipairs(routes) do
        local ok, err = self:add(route)
        if not ok then
            return false, "failed to add route #" .. i .. ": " .. err
        end
    end

    return true
end

-- 构建路由索引
function _M.build(self)
    if self._built then
        return true
    end

    local ret = self._lib.nyro_router_build(self._router)
    if ret ~= ffi_lib.OK then
        return false, "failed to build router, error code: " .. tostring(ret)
    end

    self._built = true
    return true
end

-- 匹配路由
-- @param host string 请求主机名
-- @param path string 请求路径
-- @param method string|number HTTP 方法
-- @return handler, params, match_type 或 nil, error
function _M.match(self, host, path, method)
    if not self._built then
        local ok, err = self:build()
        if not ok then
            return nil, err
        end
    end

    if not path or type(path) ~= "string" then
        return nil, "path is required"
    end

    local host_ptr = nil
    local host_len = 0
    if host and type(host) == "string" then
        host_ptr = host
        host_len = #host
    end

    local path_len = #path
    local method_mask = ffi_lib.methods_to_bitmask(method or "GET")

    -- 创建结果结构
    local result = ffi.new("nyro_router_match_result_t[1]")

    local matched = self._lib.nyro_router_match(
        self._router,
        host_ptr,
        host_len,
        path,
        path_len,
        method_mask,
        result
    )

    if matched == 1 then
        -- C 层匹配成功
        local handler_id = tonumber(result[0].handler)
        local handler = handlers[handler_id]
        local match_type = result[0].match_type

        -- 提取参数
        local params = {}
        if result[0].param_count > 0 and result[0].params ~= nil then
            for i = 0, result[0].param_count - 1 do
                local param = result[0].params[i]
                local name = ffi.string(param.name, param.name_len)
                local value = ffi.string(param.value, param.value_len)
                params[name] = value
            end
            -- 释放参数内存
            self._lib.nyro_router_match_result_free(result)
        end

        return handler, params, match_type
    end

    return nil, nil  -- 未匹配，不是错误
end

-- 获取路由数量
function _M.count(self)
    return tonumber(self._lib.nyro_router_count(self._router))
end

-- 清空所有路由
function _M.clear(self)
    -- 清理本实例的处理器
    for handler_id in pairs(self._handlers) do
        handlers[handler_id] = nil
    end
    self._handlers = {}

    self._lib.nyro_router_clear(self._router)
    self._built = false
end

-- 销毁路由器 (通常不需要手动调用，ffi.gc 会自动处理)
function _M.destroy(self)
    self:clear()
    -- ffi.gc 会自动调用 nyro_router_free
    self._router = nil
end

return _M
