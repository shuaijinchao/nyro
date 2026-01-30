--
-- APIOAK Admin Router
--
-- 在 standalone 模式下禁用 Admin API
-- 在 hybrid 模式下提供配置管理 API
--

local ngx = ngx
local config = require("apioak.sys.config")
local pdk = require("apioak.pdk")

local router
local admin_enabled = false

local _M = {}

-- 简单的路由分发器（用于 Admin API）
local SimpleRouter = {}
SimpleRouter.__index = SimpleRouter

function SimpleRouter.new()
    local self = setmetatable({}, SimpleRouter)
    self.routes = {}
    return self
end

function SimpleRouter:add(method, path, handler)
    if not self.routes[method] then
        self.routes[method] = {}
    end
    -- 将路径模式转换为 Lua pattern
    local pattern = "^" .. path:gsub("{[^}]+}", "([^/]+)") .. "$"
    table.insert(self.routes[method], {
        pattern = pattern,
        handler = handler,
        path = path,
    })
end

function SimpleRouter:get(path, handler)
    self:add("GET", path, handler)
end

function SimpleRouter:post(path, handler)
    self:add("POST", path, handler)
end

function SimpleRouter:put(path, handler)
    self:add("PUT", path, handler)
end

function SimpleRouter:delete(path, handler)
    self:add("DELETE", path, handler)
end

function SimpleRouter:dispatch(uri, method)
    local method_routes = self.routes[method]
    if not method_routes then
        return false
    end

    for _, route in ipairs(method_routes) do
        local matches = { uri:match(route.pattern) }
        if #matches > 0 or uri:match(route.pattern) then
            if route.handler then
                route.handler(unpack(matches))
                return true
            end
        end
    end

    return false
end

function _M.init_worker()
    -- 检查 store 模式
    local store_config, err = config.query("store")
    if err then
        store_config = { mode = "standalone" }
    end

    local admin_config, _ = config.query("admin")
    if admin_config and admin_config.enabled == true then
        admin_enabled = true
    end

    -- Standalone 模式下禁用 Admin API
    if store_config.mode == "standalone" then
        ngx.log(ngx.INFO, "[sys.admin] Admin API disabled in standalone mode")
        admin_enabled = false
        return
    end

    if not admin_enabled then
        ngx.log(ngx.INFO, "[sys.admin] Admin API disabled by configuration")
        return
    end

    -- 创建简单路由器
    router = SimpleRouter.new()

    -- Admin API 路由将在 hybrid 模式下实现
    -- 目前提供基础的健康检查和配置重载接口

    -- 健康检查
    router:get("/apioak/admin/health", function()
        pdk.response.exit(200, { status = "ok", mode = store_config.mode })
    end)

    -- 配置版本
    router:get("/apioak/admin/version", function()
        local store = require("apioak.store")
        local version = store.get_version()
        pdk.response.exit(200, { version = version })
    end)

    -- 重新加载配置
    router:post("/apioak/admin/reload", function()
        local store = require("apioak.store")
        local ok, reload_err = store.reload()
        if ok then
            pdk.response.exit(200, { message = "configuration reloaded" })
        else
            pdk.response.exit(500, { error = reload_err })
        end
    end)

    ngx.log(ngx.INFO, "[sys.admin] Admin API initialized")
end

function _M.routers()
    if not admin_enabled or not router then
        -- 返回一个空的路由器
        return {
            dispatch = function()
                pdk.response.exit(503, {
                    error = "Admin API is disabled in standalone mode. Use YAML configuration instead."
                })
                return true
            end
        }
    end
    return router
end

function _M.is_enabled()
    return admin_enabled
end

return _M
