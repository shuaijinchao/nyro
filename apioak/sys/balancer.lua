--
-- APIOAK System Balancer
--
-- 负载均衡模块，使用新的 Store 抽象层获取 upstream 数据
--

local ngx      = ngx
local ipairs   = ipairs
local pairs    = pairs
local type     = type
local pdk      = require("apioak.pdk")
local store    = require("apioak.store")
local schema   = require("apioak.schema")
local events   = require("resty.worker.events")
local cache    = require("apioak.sys.cache")
local resolver = require("resty.dns.resolver")
local math_random        = math.random
local ngx_process        = require("ngx.process")
local balancer           = require("ngx.balancer")
local balancer_round     = require('resty.roundrobin')
local balancer_chash     = require('resty.chash')
local ngx_timer_at       = ngx.timer.at
local ngx_sleep          = ngx.sleep
local ngx_worker_exiting = ngx.worker.exiting

local resolver_address_cache_prefix = "resolver_address_cache_prefix"

local upstream_objects = {}
local resolver_client
local current_version = 0

local _M = {}

_M.events_source_upstream   = "events_source_upstream"
_M.events_type_rebuild_upstream = "events_type_rebuild_upstream"

-- 从 Store 获取 upstream 数据
local function load_upstreams_from_store()
    if not store.is_initialized() then
        return nil, "store not initialized"
    end

    local upstreams, err = store.get_upstreams()
    if err then
        return nil, err
    end

    if not upstreams or #upstreams == 0 then
        return nil, "no upstreams found"
    end

    return upstreams
end

-- 规范化 algorithm 名称
local function normalize_algorithm(algo)
    if not algo then
        return pdk.const.BALANCER_ROUNDROBIN
    end
    
    local upper_algo = string.upper(algo)
    if upper_algo == "ROUNDROBIN" or upper_algo == "ROUND_ROBIN" or upper_algo == "RR" then
        return pdk.const.BALANCER_ROUNDROBIN
    elseif upper_algo == "CHASH" or upper_algo == "CONSISTENT_HASH" or upper_algo == "CH" then
        return pdk.const.BALANCER_CHASH
    else
        return pdk.const.BALANCER_ROUNDROBIN
    end
end

-- 生成 upstream balancer 对象
local function generate_upstream_balancer(upstream_data)
    if not upstream_data or type(upstream_data) ~= "table" then
        return nil
    end

    local nodes = upstream_data.nodes
    local node_list = {}

    if nodes and #nodes > 0 then
        for _, node in ipairs(nodes) do
            -- 支持两种格式: address 或 host
            local addr = node.address or node.host
            local port = node.port
            
            if addr and port then
                local weight = node.weight or 1
                node_list[addr .. '|' .. port] = weight
            end
        end
    end

    if not next(node_list) then
        ngx.log(ngx.WARN, "[sys.balancer] no valid nodes for upstream: ", upstream_data.id)
        return nil
    end

    local algorithm = normalize_algorithm(upstream_data.algorithm)

    -- 支持两种超时格式
    local timeout_config = upstream_data.timeout or {}
    local upstream_balancer = {
        algorithm       = algorithm,
        read_timeout    = upstream_data.read_timeout or timeout_config.read or pdk.const.UPSTREAM_DEFAULT_TIMEOUT,
        write_timeout   = upstream_data.write_timeout or timeout_config.send or pdk.const.UPSTREAM_DEFAULT_TIMEOUT,
        connect_timeout = upstream_data.connect_timeout or timeout_config.connect or pdk.const.UPSTREAM_DEFAULT_TIMEOUT,
    }

    if algorithm == pdk.const.BALANCER_ROUNDROBIN then
        upstream_balancer.handler = balancer_round:new(node_list)
    elseif algorithm == pdk.const.BALANCER_CHASH then
        upstream_balancer.handler = balancer_chash:new(node_list)
    else
        upstream_balancer.handler = balancer_round:new(node_list)
    end

    ngx.log(ngx.DEBUG, "[sys.balancer] created balancer for upstream: ", upstream_data.id, 
            ", algorithm: ", algorithm, ", nodes: ", (function() local c = 0; for _ in pairs(node_list) do c = c + 1 end; return c end)())

    return upstream_balancer
end

-- 重建 upstream 对象
local function rebuild_upstreams()
    local upstreams, err = load_upstreams_from_store()
    if err then
        ngx.log(ngx.WARN, "[sys.balancer] failed to load upstreams: ", err)
        return false
    end

    local new_upstream_objects = {}

    for _, upstream in ipairs(upstreams) do
        if upstream.id then
            local balancer_obj = generate_upstream_balancer(upstream)
            if balancer_obj then
                new_upstream_objects[upstream.id] = balancer_obj
                ngx.log(ngx.DEBUG, "[sys.balancer] loaded upstream: ", upstream.id)
            end
        end
    end

    -- 更新 upstream 对象
    upstream_objects = new_upstream_objects
    current_version = store.get_version()

    ngx.log(ngx.INFO, "[sys.balancer] upstreams rebuilt, count: ", 
        (function() local c = 0; for _ in pairs(new_upstream_objects) do c = c + 1 end; return c end)())

    return true
end

-- Worker 初始化 upstream
local function worker_init_upstreams(premature)
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
        ngx.log(ngx.ERR, "[sys.balancer] store not initialized after ", max_wait, "s")
        return
    end

    -- 构建 upstream 对象
    local ok = rebuild_upstreams()
    if ok then
        ngx.log(ngx.INFO, "[sys.balancer] worker initialized upstreams successfully")
    else
        ngx.log(ngx.WARN, "[sys.balancer] worker failed to initialize upstreams")
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
                    _M.events_source_upstream,
                    _M.events_type_rebuild_upstream,
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
local function worker_event_upstream_handler_register()
    local rebuild_handler = function(data, event, source)
        if source ~= _M.events_source_upstream then
            return
        end

        if event ~= _M.events_type_rebuild_upstream then
            return
        end

        ngx.log(ngx.INFO, "[sys.balancer] received rebuild signal, version: ", data and data.version or "unknown")
        rebuild_upstreams()
    end

    events.register(rebuild_handler, _M.events_source_upstream, _M.events_type_rebuild_upstream)
end

function _M.init_worker()
    worker_event_upstream_handler_register()

    -- 每个 worker 独立初始化 upstream
    ngx_timer_at(0, worker_init_upstreams)

    -- 只有 privileged agent 进程运行协调器
    if ngx_process.type() == "privileged agent" then
        ngx_timer_at(0, coordinator_sync)
    end
end

function _M.init_resolver()
    local client, err = resolver:new{
        nameservers = { {"114.114.114.114", 53}, "8.8.8.8" },
        retrans = 3,
        timeout = 500,
        no_random = false,
    }

    if err then
        pdk.log.error("init resolver error: [" .. tostring(err) .. "]")
        return
    end

    resolver_client = client
end

function _M.check_replenish_upstream(oak_ctx)
    if not oak_ctx.config or not oak_ctx.config.service_router or not oak_ctx.config.service_router.router then
        pdk.log.error("check_replenish_upstream: oak_ctx data format error")
        return
    end

    local service_router = oak_ctx.config.service_router
    local upstream = service_router.router.upstream

    -- 如果有 upstream_id 并且已经在缓存中，直接返回
    if upstream and upstream.id and upstream_objects[upstream.id] then
        return
    end

    -- 尝试从路由配置中获取 upstream_id
    if oak_ctx.config.upstream_id and upstream_objects[oak_ctx.config.upstream_id] then
        if not upstream then
            service_router.router.upstream = {}
        end
        service_router.router.upstream.id = oak_ctx.config.upstream_id
        return
    end

    -- DNS 解析回退
    if not resolver_client or not oak_ctx.matched or not oak_ctx.matched.host or #oak_ctx.matched.host == 0 then
        return
    end

    local address_cache_key = resolver_address_cache_prefix .. ":" .. oak_ctx.matched.host

    local address_cache = cache.get(address_cache_key)

    if address_cache then
        if not upstream then
            service_router.router.upstream = {}
        end
        service_router.router.upstream.address = address_cache
        service_router.router.upstream.port    = 80
        return
    end

    local answers, err = resolver_client:query(oak_ctx.matched.host, nil, {})

    if err then
        pdk.log.error("failed to query the DNS server: [" .. pdk.json.encode(err, true) .. "]")
        return
    end

    local answers_list = {}

    for i = 1, #answers do
        if (answers[i].type == resolver_client.TYPE_A) or (answers[i].type == resolver_client.TYPE_AAAA) then
            pdk.table.insert(answers_list, answers[i])
        end
    end

    if #answers_list == 0 then
        return
    end

    local resolver_result = answers_list[math_random(1, #answers_list)]

    if not resolver_result or not next(resolver_result) then
        return
    end

    cache.set(address_cache_key, resolver_result.address, 60)

    if not upstream then
        service_router.router.upstream = {}
    end
    service_router.router.upstream.address = resolver_result.address
    service_router.router.upstream.port    = 80
end

function _M.gogogo(oak_ctx)
    if not oak_ctx.config or not oak_ctx.config.service_router or not oak_ctx.config.service_router.router then
        pdk.log.error("[sys.balancer.gogogo] oak_ctx.config.service_router.router is null!")
        return
    end

    local upstream = oak_ctx.config.service_router.router.upstream

    if not upstream or not next(upstream) then
        pdk.log.error("[sys.balancer.gogogo] upstream is null!")
        return
    end

    local address, port

    local timeout = {
        read_timeout    = pdk.const.UPSTREAM_DEFAULT_TIMEOUT,
        write_timeout   = pdk.const.UPSTREAM_DEFAULT_TIMEOUT,
        connect_timeout = pdk.const.UPSTREAM_DEFAULT_TIMEOUT,
    }

    if upstream.id then
        local upstream_object = upstream_objects[upstream.id]

        if not upstream_object then
            pdk.log.error("[sys.balancer.gogogo] upstream undefined, upstream_object is null! id=", upstream.id)
            return
        end

        if upstream_object.read_timeout then
            timeout.read_timeout = upstream_object.read_timeout
        end
        if upstream_object.write_timeout then
            timeout.write_timeout = upstream_object.write_timeout
        end
        if upstream_object.connect_timeout then
            timeout.connect_timeout = upstream_object.connect_timeout
        end

        local address_port

        if upstream_object.algorithm == pdk.const.BALANCER_ROUNDROBIN then
            address_port = upstream_object.handler:find()
        elseif upstream_object.algorithm == pdk.const.BALANCER_CHASH then
            address_port = upstream_object.handler:find(oak_ctx.config.service_router.host or "")
        else
            address_port = upstream_object.handler:find()
        end

        if not address_port then
            pdk.log.error("[sys.balancer.gogogo] upstream undefined, upstream_object find null!")
            return
        end

        local address_port_table = pdk.string.split(address_port, "|")

        if #address_port_table ~= 2 then
            pdk.log.error("[sys.balancer.gogogo] address port format error: [" .. pdk.json.encode(address_port_table, true) .. "]")
            return
        end

        address = address_port_table[1]
        port    = tonumber(address_port_table[2])
    else
        if not upstream.address or not upstream.port then
            pdk.log.error("[sys.balancer.gogogo] upstream address and port undefined")
            return
        end

        address = upstream.address
        port    = upstream.port
    end

    if not address or not port or (address == ngx.null) or (port == ngx.null) then
        pdk.log.error("[sys.balancer.gogogo] address or port is null [" .. pdk.json.encode(address, true) .. "][" .. pdk.json.encode(port, true) .. "]")
        return
    end

    local _, err = pdk.schema.check(schema.upstream_node.schema_ip, address)

    if err then
        pdk.log.error("[sys.balancer.gogogo] address schema check err:[" .. address .. "][" .. err .. "]")
        return
    end

    local _, err2 = pdk.schema.check(schema.upstream_node.schema_port, port)

    if err2 then
        pdk.log.error("[sys.balancer.gogogo] port schema check err:[" .. port .. "][" .. err2 .. "]")
        return
    end

    local ok, timeout_err = balancer.set_timeouts(
            timeout.connect_timeout / 1000, timeout.write_timeout / 1000, timeout.read_timeout / 1000)

    if not ok then
        pdk.log.error("[sys.balancer] could not set upstream timeouts: [" .. pdk.json.encode(timeout_err, true) .. "]")
        return
    end

    local ok2, peer_err = balancer.set_current_peer(address, port)

    if not ok2 then
        pdk.log.error("[sys.balancer] failed to set the current peer: ", peer_err)
        return
    end
end

-- 导出获取 upstream 对象的方法（用于调试）
function _M.get_upstream_objects()
    return upstream_objects
end

return _M
