--
-- APIOAK System DAO
-- 
-- 数据访问层初始化，使用新的 Store 抽象层
--

local ngx = ngx
local store = require("apioak.store")
local config = require("apioak.sys.config")
local uuid = require("resty.jit-uuid")

local ngx_timer_at = ngx.timer.at

local _M = {}

local initialized = false

-- 初始化 Store
local function init_store(premature)
    if premature then
        return
    end

    if initialized then
        return
    end

    -- 获取 store 配置
    local store_config, err = config.query("store")
    if err then
        ngx.log(ngx.WARN, "[sys.dao] store config not found, using defaults: ", err)
        store_config = {
            mode = "standalone",
            standalone = {
                config_file = ngx.config.prefix() .. "conf/config.yaml"
            }
        }
    end

    -- 初始化 Store
    local ok, init_err = store.init(store_config)
    if not ok then
        ngx.log(ngx.ERR, "[sys.dao] failed to initialize store: ", init_err)
        return
    end

    initialized = true
    ngx.log(ngx.INFO, "[sys.dao] store initialized, mode: ", store.get_mode())
end

function _M.init_worker()
    -- 初始化 UUID
    uuid.seed()

    -- 初始化 Store
    ngx_timer_at(0, init_store)
end

-- 检查是否已初始化
function _M.is_initialized()
    return initialized
end

-- 获取 Store 实例
function _M.get_store()
    return store
end

return _M
