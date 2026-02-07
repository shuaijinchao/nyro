--
-- NYRO System Balancer
--
-- 负载均衡模块，使用 Store 抽象层获取 backends 数据
--

local ngx      = ngx
local ipairs   = ipairs
local pairs    = pairs
local type     = type
local core      = require("nyro.core")
local store    = require("nyro.store")
local schema   = require("nyro.schema")
local events   = require("resty.worker.events")
local ngx_process        = require("ngx.process")
local balancer           = require("ngx.balancer")
local balancer_round     = require('resty.roundrobin')
local balancer_chash     = require('resty.chash')
local ngx_timer_at       = ngx.timer.at
local ngx_sleep          = ngx.sleep
local ngx_worker_exiting = ngx.worker.exiting

local backend_objects = {}
local current_version = 0

local _M = {}

_M.events_source_backend = "events_source_backend"
_M.events_type_rebuild_backend = "events_type_rebuild_backend"

-- 从 Store 获取 backends 数据
local function load_backends_from_store()
    if not store.is_initialized() then
        return nil, "store not initialized"
    end

    local backends, err = store.get_backends()
    if err then
        return nil, err
    end

    if not backends or #backends == 0 then
        return nil, "no backends found"
    end

    return backends
end

-- 规范化 algorithm 名称
local function normalize_algorithm(algo)
    if not algo then
        return core.const.BALANCER_ROUNDROBIN
    end
    
    local upper_algo = string.upper(algo)
    if upper_algo == "ROUNDROBIN" or upper_algo == "ROUND_ROBIN" or upper_algo == "RR" then
        return core.const.BALANCER_ROUNDROBIN
    elseif upper_algo == "CHASH" or upper_algo == "CONSISTENT_HASH" or upper_algo == "CH" then
        return core.const.BALANCER_CHASH
    else
        return core.const.BALANCER_ROUNDROBIN
    end
end

-- 生成 backend balancer 对象
local function generate_backend_balancer(backend_data)
    if not backend_data or type(backend_data) ~= "table" then
        return nil
    end

    local endpoints = backend_data.endpoints
    local endpoint_list = {}

    if endpoints and #endpoints > 0 then
        for _, endpoint in ipairs(endpoints) do
            local addr = endpoint.address
            local port = endpoint.port
            
            -- 如果 address 包含端口号 (如 "192.168.1.10:9001")
            if addr and not port then
                local host, p = addr:match("^(.+):(%d+)$")
                if host and p then
                    addr = host
                    port = tonumber(p)
                end
            end
            
            if addr and port then
                local weight = endpoint.weight or 1
                endpoint_list[addr .. '|' .. port] = weight
            end
        end
    end

    if not next(endpoint_list) then
        ngx.log(ngx.WARN, "[sys.balancer] no valid endpoints for backend: ", backend_data.name)
        return nil
    end

    local algorithm = normalize_algorithm(backend_data.algorithm)

    local timeout_config = backend_data.timeout or {}
    local backend_balancer = {
        algorithm       = algorithm,
        read_timeout    = timeout_config.read or core.const.UPSTREAM_DEFAULT_TIMEOUT,
        write_timeout   = timeout_config.send or core.const.UPSTREAM_DEFAULT_TIMEOUT,
        connect_timeout = timeout_config.connect or core.const.UPSTREAM_DEFAULT_TIMEOUT,
    }

    if algorithm == core.const.BALANCER_ROUNDROBIN then
        backend_balancer.handler = balancer_round:new(endpoint_list)
    elseif algorithm == core.const.BALANCER_CHASH then
        backend_balancer.handler = balancer_chash:new(endpoint_list)
    else
        backend_balancer.handler = balancer_round:new(endpoint_list)
    end

    ngx.log(ngx.DEBUG, "[sys.balancer] created balancer for backend: ", backend_data.name, 
            ", algorithm: ", algorithm, ", endpoints: ", (function() local c = 0; for _ in pairs(endpoint_list) do c = c + 1 end; return c end)())

    return backend_balancer
end

-- 重建 backend 对象
local function rebuild_backends()
    local backends, err = load_backends_from_store()
    if err then
        ngx.log(ngx.WARN, "[sys.balancer] failed to load backends: ", err)
        return false
    end

    local new_backend_objects = {}

    for _, backend in ipairs(backends) do
        if backend.name then
            local balancer_obj = generate_backend_balancer(backend)
            if balancer_obj then
                new_backend_objects[backend.name] = balancer_obj
                ngx.log(ngx.DEBUG, "[sys.balancer] loaded backend: ", backend.name)
            end
        end
    end

    backend_objects = new_backend_objects
    current_version = store.get_version()

    ngx.log(ngx.INFO, "[sys.balancer] backends rebuilt, count: ", 
        (function() local c = 0; for _ in pairs(new_backend_objects) do c = c + 1 end; return c end)())

    return true
end

-- Worker 初始化 backends
local function worker_init_backends(premature)
    if premature then
        return
    end

    local max_wait = 30
    local waited = 0

    while not store.is_initialized() and waited < max_wait do
        ngx_sleep(0.5)
        waited = waited + 0.5
    end

    if not store.is_initialized() then
        ngx.log(ngx.ERR, "[sys.balancer] store not initialized after ", max_wait, "s")
        return
    end

    local ok = rebuild_backends()
    if ok then
        ngx.log(ngx.INFO, "[sys.balancer] worker initialized backends successfully")
    else
        ngx.log(ngx.WARN, "[sys.balancer] worker failed to initialize backends")
    end
end

-- 协调器：检测配置变更并广播重建信号
local function coordinator_sync(premature)
    if premature then
        return
    end

    if ngx_process.type() ~= "privileged agent" then
        return
    end

    local check_interval = 3

    while not ngx_worker_exiting() do
        repeat
            if not store.is_initialized() then
                ngx_sleep(1)
                break
            end

            local new_version = store.get_version()

            if new_version ~= current_version then
                local ok, post_err = events.post(
                    _M.events_source_backend,
                    _M.events_type_rebuild_backend,
                    { version = new_version }
                )

                if post_err then
                    ngx.log(ngx.WARN, "[sys.balancer] failed to broadcast rebuild signal: ", post_err)
                else
                    ngx.log(ngx.INFO, "[sys.balancer] broadcasted rebuild signal, version: ", new_version)
                    current_version = new_version
                end
            end

            ngx_sleep(check_interval)
        until true
    end
end

-- Worker 事件处理器
local function worker_event_handler_register()
    local rebuild_handler = function(data, event, source)
        if source ~= _M.events_source_backend or event ~= _M.events_type_rebuild_backend then
            return
        end

        ngx.log(ngx.INFO, "[sys.balancer] received rebuild signal, version: ", data and data.version or "unknown")
        rebuild_backends()
    end

    events.register(rebuild_handler, _M.events_source_backend, _M.events_type_rebuild_backend)
end

function _M.init_worker()
    worker_event_handler_register()
    ngx_timer_at(0, worker_init_backends)

    if ngx_process.type() == "privileged agent" then
        ngx_timer_at(0, coordinator_sync)
    end
end

-- 检查是否为 IP 地址
local function is_ip_address(addr)
    if not addr then
        return false
    end
    -- IPv4
    if addr:match("^%d+%.%d+%.%d+%.%d+$") then
        return true
    end
    return false
end

-- DNS 解析 (每次创建新的 resolver)
local function resolve_host(host)
    if is_ip_address(host) then
        return host
    end
    
    local resolver = require("resty.dns.resolver")
    local r, err = resolver:new{
        nameservers = { "8.8.8.8", "114.114.114.114" },
        retrans = 3,
        timeout = 2000,
    }
    
    if not r then
        return nil, "resolver init failed: " .. tostring(err)
    end
    
    local answers, query_err = r:query(host, nil, {})
    if not answers then
        return nil, "DNS query failed: " .. tostring(query_err)
    end
    
    for _, ans in ipairs(answers) do
        if ans.type == 1 or ans.type == 28 then -- A or AAAA
            return ans.address
        end
    end
    
    return nil, "no A/AAAA record found"
end

-- 检查并补充 backend 配置 (在 access 阶段调用)
function _M.check_backend(oak_ctx)
    if not oak_ctx.config or not oak_ctx.config.service_router or not oak_ctx.config.service_router.router then
        return
    end

    local service_router = oak_ctx.config.service_router
    local upstream = service_router.router.upstream

    -- 如果没有 upstream，尝试从 backend_name 获取
    if not upstream or not next(upstream) then
        if oak_ctx.config.backend_name and backend_objects[oak_ctx.config.backend_name] then
            service_router.router.upstream = { id = oak_ctx.config.backend_name }
        end
        return
    end

    -- 如果已有 backend id 并且存在，直接返回
    if upstream.id and backend_objects[upstream.id] then
        return
    end

    -- URL 直接代理模式：如果有 address 但不是 IP，需要在此阶段 DNS 解析
    -- (balancer 阶段不能使用 cosocket)
    if upstream.address and not is_ip_address(upstream.address) then
        local ip, err = resolve_host(upstream.address)
        if ip then
            upstream.resolved_ip = ip
            ngx.log(ngx.INFO, "[sys.balancer] resolved ", upstream.address, " -> ", ip)
        else
            ngx.log(ngx.ERR, "[sys.balancer] DNS resolve failed for ", upstream.address, ": ", err)
        end
    end
end

-- 执行负载均衡
function _M.gogogo(oak_ctx)
    if not oak_ctx.config or not oak_ctx.config.service_router or not oak_ctx.config.service_router.router then
        core.log.error("[sys.balancer] oak_ctx.config.service_router.router is null!")
        return
    end

    local upstream = oak_ctx.config.service_router.router.upstream

    if not upstream or not next(upstream) then
        core.log.error("[sys.balancer] upstream is null!")
        return
    end

    local address, port
    local timeout = {
        read_timeout    = core.const.UPSTREAM_DEFAULT_TIMEOUT,
        write_timeout   = core.const.UPSTREAM_DEFAULT_TIMEOUT,
        connect_timeout = core.const.UPSTREAM_DEFAULT_TIMEOUT,
    }

    if upstream.id then
        local backend_obj = backend_objects[upstream.id]

        if not backend_obj then
            core.log.error("[sys.balancer] backend not found: ", upstream.id)
            return
        end

        timeout.read_timeout = backend_obj.read_timeout
        timeout.write_timeout = backend_obj.write_timeout
        timeout.connect_timeout = backend_obj.connect_timeout

        local address_port
        if backend_obj.algorithm == core.const.BALANCER_ROUNDROBIN then
            address_port = backend_obj.handler:find()
        elseif backend_obj.algorithm == core.const.BALANCER_CHASH then
            address_port = backend_obj.handler:find(oak_ctx.matched.host or "")
        else
            address_port = backend_obj.handler:find()
        end

        if not address_port then
            core.log.error("[sys.balancer] backend handler find null!")
            return
        end

        local parts = core.string.split(address_port, "|")
        if #parts ~= 2 then
            core.log.error("[sys.balancer] address:port format error: ", address_port)
            return
        end

        address = parts[1]
        port = tonumber(parts[2])
    else
        -- URL 直接代理模式
        if not upstream.port then
            core.log.error("[sys.balancer] upstream port undefined")
            return
        end
        
        -- 使用在 access 阶段解析的 IP
        if upstream.resolved_ip then
            address = upstream.resolved_ip
        elseif upstream.address and is_ip_address(upstream.address) then
            address = upstream.address
        else
            core.log.error("[sys.balancer] upstream address not resolved: ", upstream.address)
            return
        end
        
        port = upstream.port
    end

    if not address or not port then
        core.log.error("[sys.balancer] address or port is null")
        return
    end

    -- 验证端口
    local _, err2 = core.schema.check(schema.upstream_node.schema_port, port)
    if err2 then
        core.log.error("[sys.balancer] port check error: ", port, " ", err2)
        return
    end

    -- 设置超时
    local ok, timeout_err = balancer.set_timeouts(
        timeout.connect_timeout / 1000, 
        timeout.write_timeout / 1000, 
        timeout.read_timeout / 1000
    )
    if not ok then
        core.log.error("[sys.balancer] set timeouts error: ", timeout_err)
        return
    end

    -- 设置目标
    local ok2, peer_err = balancer.set_current_peer(address, port)
    if not ok2 then
        core.log.error("[sys.balancer] set peer error: ", peer_err)
        return
    end
end

-- 获取 backend 对象 (调试用)
function _M.get_backend_objects()
    return backend_objects
end

return _M
