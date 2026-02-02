--
-- APIOAK Service Module
--
-- 服务资源管理模块
-- 服务作为 upstream 的逻辑抽象，关联 route 和 backend
--

local ngx = ngx
local store = require("apioak.store")

local _M = {
    _VERSION = "1.0.0"
}

-- 服务缓存
local service_cache = {}

-- 从 Store 加载服务
local function load_services()
    if not store.is_initialized() then
        return nil, "store not initialized"
    end
    
    local services, err = store.get_services()
    if err then
        return nil, err
    end
    
    return services or {}
end

-- 重建服务缓存
function _M.rebuild()
    local services, err = load_services()
    if err then
        ngx.log(ngx.WARN, "[service] failed to load services: ", err)
        return false
    end
    
    local cache = {}
    for _, svc in ipairs(services) do
        if svc.name then
            cache[svc.name] = svc
        end
    end
    
    service_cache = cache
    ngx.log(ngx.INFO, "[service] services rebuilt, count: ", #services)
    return true
end

-- 通过名称获取服务
function _M.get_by_name(name)
    return service_cache[name]
end

-- 获取所有服务
function _M.get_all()
    return service_cache
end

return _M
