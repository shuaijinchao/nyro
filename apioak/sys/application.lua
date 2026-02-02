--
-- APIOAK System Application
--
-- 应用资源管理模块，用于 API 消费者认证
--

local ngx = ngx
local ipairs = ipairs
local pairs = pairs
local type = type
local store = require("apioak.store")
local events = require("resty.worker.events")
local ngx_process = require("ngx.process")
local ngx_timer_at = ngx.timer.at
local ngx_sleep = ngx.sleep
local ngx_worker_exiting = ngx.worker.exiting

-- 应用数据索引
local applications = {}
-- 凭证索引: { ["key-auth:mobile-app-key"] = application_name }
local credential_index = {}
local current_version = 0

local _M = {}

_M.events_source_application = "events_source_application"
_M.events_type_rebuild_application = "events_type_rebuild_application"

-- 从 Store 加载应用数据
local function load_applications_from_store()
    if not store.is_initialized() then
        return nil, "store not initialized"
    end

    local apps, err = store.get_applications()
    if err then
        return nil, err
    end

    return apps or {}
end

-- 构建凭证索引
local function build_credential_index(apps)
    local index = {}
    
    for _, app in ipairs(apps) do
        if app.name and app.credentials then
            for cred_type, cred_data in pairs(app.credentials) do
                -- 支持不同类型的凭证
                if cred_type == "key-auth" and cred_data.key then
                    index["key-auth:" .. cred_data.key] = app.name
                elseif cred_type == "basic-auth" and cred_data.username then
                    index["basic-auth:" .. cred_data.username] = app.name
                elseif cred_type == "jwt-auth" and cred_data.key then
                    index["jwt-auth:" .. cred_data.key] = app.name
                elseif cred_type == "hmac-auth" and cred_data.key then
                    index["hmac-auth:" .. cred_data.key] = app.name
                end
            end
        end
    end
    
    return index
end

-- 重建应用数据
local function rebuild_applications()
    local apps, err = load_applications_from_store()
    if err then
        ngx.log(ngx.WARN, "[sys.application] failed to load applications: ", err)
        return false
    end

    -- 构建应用索引
    local app_map = {}
    for _, app in ipairs(apps) do
        if app.name then
            app_map[app.name] = app
        end
    end

    -- 构建凭证索引
    local cred_idx = build_credential_index(apps)

    applications = app_map
    credential_index = cred_idx
    current_version = store.get_version()

    ngx.log(ngx.INFO, "[sys.application] applications rebuilt, count: ", #apps,
            ", credentials: ", (function() local c = 0; for _ in pairs(cred_idx) do c = c + 1 end; return c end)())

    return true
end

-- Worker 初始化
local function worker_init_applications(premature)
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
        ngx.log(ngx.ERR, "[sys.application] store not initialized after ", max_wait, "s")
        return
    end

    local ok = rebuild_applications()
    if ok then
        ngx.log(ngx.INFO, "[sys.application] worker initialized applications successfully")
    else
        ngx.log(ngx.WARN, "[sys.application] worker failed to initialize applications")
    end
end

-- 协调器
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
                    _M.events_source_application,
                    _M.events_type_rebuild_application,
                    { version = new_version }
                )

                if post_err then
                    ngx.log(ngx.WARN, "[sys.application] failed to broadcast rebuild signal: ", post_err)
                else
                    ngx.log(ngx.INFO, "[sys.application] broadcasted rebuild signal, version: ", new_version)
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
        if source ~= _M.events_source_application or event ~= _M.events_type_rebuild_application then
            return
        end

        ngx.log(ngx.INFO, "[sys.application] received rebuild signal, version: ", data and data.version or "unknown")
        rebuild_applications()
    end

    events.register(rebuild_handler, _M.events_source_application, _M.events_type_rebuild_application)
end

-- ============================================================
-- 公共 API
-- ============================================================

function _M.init_worker()
    worker_event_handler_register()
    ngx_timer_at(0, worker_init_applications)

    if ngx_process.type() == "privileged agent" then
        ngx_timer_at(0, coordinator_sync)
    end
end

-- 通过名称获取应用
function _M.get_by_name(name)
    return applications[name]
end

-- 通过凭证查找应用
-- @param cred_type string 凭证类型 (key-auth, basic-auth, jwt-auth 等)
-- @param credential string 凭证值 (API key, username, JWT key 等)
-- @return application table 或 nil
function _M.find_by_credential(cred_type, credential)
    if not cred_type or not credential then
        return nil
    end
    
    local key = cred_type .. ":" .. credential
    local app_name = credential_index[key]
    
    if not app_name then
        return nil
    end
    
    return applications[app_name]
end

-- 验证 API Key
function _M.verify_key_auth(api_key)
    return _M.find_by_credential("key-auth", api_key)
end

-- 验证 Basic Auth
function _M.verify_basic_auth(username)
    local app = _M.find_by_credential("basic-auth", username)
    if not app then
        return nil
    end
    
    -- 返回应用及密码供验证
    return app, app.credentials and app.credentials["basic-auth"] and app.credentials["basic-auth"].password
end

-- 验证 JWT Key
function _M.verify_jwt_auth(jwt_key)
    local app = _M.find_by_credential("jwt-auth", jwt_key)
    if not app then
        return nil
    end
    
    -- 返回应用及 secret
    return app, app.credentials and app.credentials["jwt-auth"] and app.credentials["jwt-auth"].secret
end

-- 获取所有应用 (调试用)
function _M.get_all()
    return applications
end

return _M
