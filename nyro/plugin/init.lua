--
-- NYRO Plugin Module
--
-- 插件管理模块
--

local ngx = ngx
local pcall = pcall
local ipairs = ipairs
local core_config = require("nyro.core.config")
local core_log = require("nyro.core.log")
local core_string = require("nyro.core.utils.string")
local core_table = require("nyro.core.utils.table")
local events = require("resty.worker.events")
local ngx_process = require("ngx.process")
local ngx_timer_at = ngx.timer.at
local ngx_sleep = ngx.sleep
local ngx_worker_exiting = ngx.worker.exiting

local plugin_objects = {}

local _M = {}

_M.events_source_plugin = "events_source_plugin"
_M.events_type_rebuild_plugin = "events_type_rebuild_plugin"

-- 加载插件 handler
local function plugins_loading()
    local plugins, err = core_config.query("plugins")
    if err then
        core_log.error("[plugin] get plugin config error: ", err)
        return nil
    end

    if not plugins or #plugins == 0 then
        return nil
    end

    local plugin_data_list = {}

    for i = 1, #plugins do
        local plugin_path = core_string.format("nyro.plugin.%s.handler", plugins[i])
        local ok, plugin_handlers = pcall(require, plugin_path)

        if ok and plugin_handlers ~= true then
            core_table.insert(plugin_data_list, {
                key = plugins[i],
                handler = plugin_handlers
            })
        else
            core_log.warn("[plugin] failed to load plugin: ", plugins[i])
        end
    end

    if next(plugin_data_list) then
        return plugin_data_list
    end

    return nil
end

-- 构建插件 handler 映射
local function plugins_handler_map_name()
    local plugin_handler_list = plugins_loading()

    if not plugin_handler_list then
        return nil
    end

    local plugins_handler_map = {}

    for i = 1, #plugin_handler_list do
        plugins_handler_map[plugin_handler_list[i].key] = plugin_handler_list[i].handler
    end

    if next(plugins_handler_map) then
        return plugins_handler_map
    end

    return nil
end

-- 重建插件
local function rebuild_plugins()
    local plugins_name_handler_map = plugins_handler_map_name()

    if not plugins_name_handler_map then
        ngx.log(ngx.WARN, "[plugin] no plugins loaded")
        return false
    end

    local plugins_config, _ = core_config.query("plugins")
    if not plugins_config then
        plugins_config = {}
    end

    local new_plugin_objects = {}

    for key, handler in pairs(plugins_name_handler_map) do
        new_plugin_objects[key] = {
            key = key,
            handler = handler,
            config = {},
        }
    end

    plugin_objects = new_plugin_objects
    ngx.log(ngx.INFO, "[plugin] plugins rebuilt, count: ", 
        (function() local c = 0; for _ in pairs(new_plugin_objects) do c = c + 1 end; return c end)())

    return true
end

-- Worker 初始化
local function worker_init_plugins(premature)
    if premature then
        return
    end

    local max_wait = 10
    local waited = 0

    while waited < max_wait do
        local ok = rebuild_plugins()
        if ok then
            ngx.log(ngx.INFO, "[plugin] worker initialized plugins successfully")
            return
        end
        ngx_sleep(1)
        waited = waited + 1
    end

    ngx.log(ngx.WARN, "[plugin] worker failed to initialize plugins")
end

-- Worker 事件处理器
local function worker_event_handler_register()
    local rebuild_handler = function(data, event, source)
        if source ~= _M.events_source_plugin or event ~= _M.events_type_rebuild_plugin then
            return
        end
        ngx.log(ngx.INFO, "[plugin] received rebuild signal")
        rebuild_plugins()
    end

    events.register(rebuild_handler, _M.events_source_plugin, _M.events_type_rebuild_plugin)
end

function _M.init_worker()
    worker_event_handler_register()
    ngx_timer_at(0, worker_init_plugins)
end

-- 获取插件对象
function _M.plugin_subjects()
    return plugin_objects
end

-- 获取单个插件
function _M.get_plugin(name)
    return plugin_objects[name]
end

return _M
