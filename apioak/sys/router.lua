--
-- APIOAK System Router
-- 
-- 路由管理模块，使用新的 FFI 路由引擎和 Store 抽象层
--

local ngx = ngx
local pairs = pairs
local ipairs = ipairs
local type = type
local pdk = require("apioak.pdk")
local store = require("apioak.store")
local events = require("resty.worker.events")
local schema = require("apioak.schema")
local sys_certificate = require("apioak.sys.certificate")
local sys_balancer = require("apioak.sys.balancer")
local sys_plugin = require("apioak.sys.plugin")
local ngx_process = require("ngx.process")
local ngx_sleep = ngx.sleep
local ngx_timer_at = ngx.timer.at
local ngx_worker_exiting = ngx.worker.exiting
local ngx_shared = ngx.shared

-- 尝试加载新的路由引擎
local new_router_available = false
local router_matcher

do
    local ok, matcher = pcall(require, "apioak.sys.router.matcher")
    if ok then
        router_matcher = matcher
        new_router_available = true
        ngx.log(ngx.INFO, "[sys.router] new FFI router engine loaded")
    else
        ngx.log(ngx.WARN, "[sys.router] FFI router not available: ", matcher)
    end
end

local router_instance  -- 新路由引擎实例
local current_version = 0

local events_source_router = "events_source_router"
local events_type_rebuild_router = "events_type_rebuild_router"

local _M = {}

-- 从 Store 加载路由数据
local function load_routes_from_store()
    if not store.is_initialized() then
        return nil, "store not initialized"
    end

    local routes, err = store.get_routes()
    if err then
        return nil, err
    end

    local services, _ = store.get_services()
    local upstreams, _ = store.get_upstreams()
    local plugins, _ = store.get_plugins()

    -- 构建索引
    local service_map = {}
    if services then
        for _, svc in ipairs(services) do
            if svc.id then
                service_map[svc.id] = svc
            end
        end
    end

    local upstream_map = {}
    if upstreams then
        for _, ups in ipairs(upstreams) do
            if ups.id then
                upstream_map[ups.id] = ups
            end
        end
    end

    local plugin_map = {}
    if plugins then
        for _, plg in ipairs(plugins) do
            if plg.id then
                plugin_map[plg.id] = plg
            end
        end
    end

    return {
        routes = routes or {},
        services = service_map,
        upstreams = upstream_map,
        plugins = plugin_map,
    }
end

-- 构建路由表 (使用新路由引擎)
local function build_router_with_new_engine(data)
    if not new_router_available then
        return nil, "new router engine not available"
    end

    local r, err = router_matcher.new()
    if not r then
        return nil, "failed to create router: " .. tostring(err)
    end

    local routes = data.routes or {}
    local services = data.services or {}

    local added_count = 0
    for _, route in ipairs(routes) do
        if route.enabled ~= false then
            local paths = route.paths or {}
            local methods = route.methods or {"GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"}

            -- 获取关联的服务
            local service = nil
            if route.service_id then
                service = services[route.service_id]
            end

            for _, path in ipairs(paths) do
                local ok, add_err = r:add({
                    path = path,
                    methods = methods,
                    priority = route.priority or 0,
                    handler = {
                        route = route,
                        service = service,
                        upstream_id = route.upstream_id,
                        plugins = route.plugins or {},
                    },
                })

                if ok then
                    added_count = added_count + 1
                else
                    ngx.log(ngx.WARN, "[sys.router] failed to add route: ", route.id, " path: ", path, " err: ", add_err)
                end
            end
        end
    end

    if added_count == 0 then
        ngx.log(ngx.WARN, "[sys.router] no routes added to router")
        return nil, "no routes added"
    end

    local ok, build_err = r:build()
    if not ok then
        return nil, "failed to build router: " .. tostring(build_err)
    end

    ngx.log(ngx.INFO, "[sys.router] router built with ", r:count(), " routes")
    return r
end

-- 重新构建路由表
local function rebuild_router()
    local data, err = load_routes_from_store()
    if err then
        ngx.log(ngx.ERR, "[sys.router] failed to load routes from store: ", err)
        return false
    end

    if not data.routes or #data.routes == 0 then
        ngx.log(ngx.WARN, "[sys.router] no routes loaded from store")
        return false
    end

    if new_router_available then
        local new_router, build_err = build_router_with_new_engine(data)
        if new_router then
            router_instance = new_router
            current_version = store.get_version()
            ngx.log(ngx.INFO, "[sys.router] router updated, version: ", current_version)
            return true
        else
            ngx.log(ngx.ERR, "[sys.router] failed to build router: ", build_err)
            return false
        end
    end

    return false
end

-- 主协调进程：检测配置变更并广播重建信号
local function coordinator_sync(premature)
    if premature then
        return
    end

    if ngx_process.type() ~= "privileged agent" then
        return
    end

    local check_interval = 2
    local max_retries = 10
    local retry_count = 0

    while not ngx_worker_exiting() and retry_count < max_retries do
        repeat
            -- 等待 Store 初始化
            if not store.is_initialized() then
                ngx_sleep(1)
                break
            end

            local new_version = store.get_version()

            -- 检测版本变更
            if new_version ~= current_version then
                -- 广播重建信号给所有 worker
                local ok, post_err = events.post(
                    events_source_router, 
                    events_type_rebuild_router, 
                    { version = new_version }
                )

                if post_err then
                    ngx.log(ngx.WARN, "[sys.router] failed to broadcast rebuild signal: ", post_err)
                else
                    ngx.log(ngx.INFO, "[sys.router] broadcasted rebuild signal, version: ", new_version)
                    current_version = new_version
                end
            end

            ngx_sleep(check_interval)
            retry_count = 0  -- 重置重试计数

        until true

        retry_count = retry_count + 1
    end

    -- 继续调度
    if not ngx_worker_exiting() then
        ngx_timer_at(0, coordinator_sync)
    end
end

-- Worker 初始化：构建本地路由表
local function worker_init_router(premature)
    if premature then
        return
    end

    local max_wait = 30
    local waited = 0

    -- 等待 Store 初始化
    while not store.is_initialized() and waited < max_wait do
        ngx_sleep(0.5)
        waited = waited + 0.5
    end

    if not store.is_initialized() then
        ngx.log(ngx.ERR, "[sys.router] store not initialized after ", max_wait, "s")
        return
    end

    -- 构建路由表
    local ok = rebuild_router()
    if ok then
        ngx.log(ngx.INFO, "[sys.router] worker initialized router successfully")
    else
        ngx.log(ngx.WARN, "[sys.router] worker failed to initialize router, will retry on signal")
    end
end

-- Worker 事件处理器注册
local function worker_event_router_handler_register()
    local rebuild_handler = function(data, event, source)
        if source ~= events_source_router then
            return
        end

        if event ~= events_type_rebuild_router then
            return
        end

        -- 收到重建信号，重新构建本地路由表
        ngx.log(ngx.INFO, "[sys.router] received rebuild signal, version: ", data and data.version or "unknown")
        rebuild_router()
    end

    events.register(rebuild_handler, events_source_router, events_type_rebuild_router)
end

function _M.init_worker()
    worker_event_router_handler_register()
    
    -- 每个 worker 独立初始化路由表
    ngx_timer_at(0, worker_init_router)
    
    -- 只有 privileged agent 进程运行协调器
    if ngx_process.type() == "privileged agent" then
        ngx_timer_at(0, coordinator_sync)
    end
end

-- 提取请求参数
function _M.parameter(oak_ctx)
    local env = pdk.request.header(pdk.const.REQUEST_API_ENV_KEY)
    if env then
        env = pdk.string.upper(env)
    else
        env = pdk.const.ENVIRONMENT_PROD
    end

    oak_ctx.matched = {}
    oak_ctx.matched.host = ngx.var.host
    oak_ctx.matched.uri = ngx.var.uri
    oak_ctx.matched.scheme = ngx.var.scheme
    oak_ctx.matched.query = pdk.request.query()
    oak_ctx.matched.method = pdk.request.get_method()
    oak_ctx.matched.header = pdk.request.header()
    oak_ctx.matched.header[pdk.const.REQUEST_API_ENV_KEY] = env
end

-- 路由匹配
function _M.router_match(oak_ctx)
    if not oak_ctx.matched or not oak_ctx.matched.host or not oak_ctx.matched.uri then
        pdk.log.error("[sys.router] oak_ctx data format error")
        return false
    end

    if not router_instance then
        pdk.log.error("[sys.router] router not initialized")
        return false
    end

    -- 使用新路由引擎匹配
    local handler, params, match_type = router_instance:match(
        oak_ctx.matched.host,
        oak_ctx.matched.uri,
        oak_ctx.matched.method
    )

    if not handler then
        return false
    end

    -- 设置匹配结果
    oak_ctx.matched.path = params or {}
    oak_ctx.config = {}
    oak_ctx.config.route = handler.route
    oak_ctx.config.service = handler.service
    oak_ctx.config.upstream_id = handler.upstream_id
    oak_ctx.config.plugins = handler.plugins
    oak_ctx.config.match_type = match_type

    -- 兼容旧的 service_router 结构
    oak_ctx.config.service_router = {
        protocols = handler.service and handler.service.protocols or {"http", "https"},
        plugins = handler.service and handler.service.plugins or {},
        router = {
            path = oak_ctx.matched.uri,
            plugins = handler.plugins or {},
            upstream = handler.upstream_id and { id = handler.upstream_id } or nil,
            headers = handler.route and handler.route.headers or {},
            methods = handler.route and handler.route.methods or {},
        }
    }

    return true
end

return _M
