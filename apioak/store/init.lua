--
-- APIOAK Store 抽象层
-- 
-- 提供统一的数据存储接口，支持多种后端：
-- - standalone: YAML 文件 (DB Less)
-- - hybrid: 从 Control Plane 同步 (未来实现)
--

local _M = {
    _VERSION = "0.1.0"
}

-- 存储模式
_M.MODE_STANDALONE = "standalone"   -- DB Less 模式
_M.MODE_HYBRID     = "hybrid"       -- CP/DP 分离模式

-- 当前适配器实例
local adapter = nil
local current_mode = nil

-- 加载适配器
local function load_adapter(mode)
    if mode == _M.MODE_STANDALONE then
        return require("apioak.store.adapter.yaml")
    elseif mode == _M.MODE_HYBRID then
        return require("apioak.store.adapter.sync")
    else
        return nil, "unknown store mode: " .. tostring(mode)
    end
end

-- 初始化存储层
-- @param config table 配置
--   - mode: string 存储模式 (standalone/hybrid)
--   - standalone: table Standalone 模式配置
--     - config_file: string 配置文件路径
--   - hybrid: table Hybrid 模式配置
--     - control_plane_endpoints: table CP 地址列表
function _M.init(config)
    if not config then
        return false, "config is required"
    end

    local mode = config.mode or _M.MODE_STANDALONE
    
    local adp, err = load_adapter(mode)
    if not adp then
        return false, err
    end

    local ok, init_err = adp.init(config[mode] or {})
    if not ok then
        return false, init_err
    end

    adapter = adp
    current_mode = mode
    
    return true
end

-- 获取当前模式
function _M.get_mode()
    return current_mode
end

-- 检查是否已初始化
function _M.is_initialized()
    return adapter ~= nil
end

-- ============================================================
-- 数据访问接口
-- ============================================================

-- 获取所有服务
function _M.get_services()
    if not adapter then
        return nil, "store not initialized"
    end
    return adapter.get_services()
end

-- 获取所有路由
function _M.get_routes()
    if not adapter then
        return nil, "store not initialized"
    end
    return adapter.get_routes()
end

-- 获取所有上游
function _M.get_upstreams()
    if not adapter then
        return nil, "store not initialized"
    end
    return adapter.get_upstreams()
end

-- 获取所有插件配置
function _M.get_plugins()
    if not adapter then
        return nil, "store not initialized"
    end
    return adapter.get_plugins()
end

-- 获取所有证书
function _M.get_certificates()
    if not adapter then
        return nil, "store not initialized"
    end
    return adapter.get_certificates()
end

-- 获取配置版本号
function _M.get_version()
    if not adapter then
        return nil, "store not initialized"
    end
    return adapter.get_version()
end

-- ============================================================
-- 热加载接口
-- ============================================================

-- 重新加载配置
function _M.reload()
    if not adapter then
        return false, "store not initialized"
    end
    
    if not adapter.reload then
        return false, "adapter does not support reload"
    end
    
    return adapter.reload()
end

-- 监听配置变更
-- @param callback function(event_type, data)
function _M.watch(callback)
    if not adapter then
        return false, "store not initialized"
    end
    
    if not adapter.watch then
        return false, "adapter does not support watch"
    end
    
    return adapter.watch(callback)
end

return _M
