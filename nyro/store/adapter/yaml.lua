--
-- NYRO YAML Adapter
-- 
-- DB Less 模式的存储适配器，从 YAML 文件加载配置
--

local yaml = require("tinyyaml")
local io_open = io.open
local ngx = ngx
local type = type
local pairs = pairs
local ipairs = ipairs

local _M = {
    _VERSION = "2.0.0"
}

-- 内部状态
local config_data = nil
local config_version = 0
local config_file_path = nil
local watchers = {}

-- 默认配置文件路径
local DEFAULT_CONFIG_FILE = "conf/config.yaml"

-- 读取文件内容
local function read_file(path)
    local file, err = io_open(path, "r")
    if not file then
        return nil, "failed to open file: " .. tostring(err)
    end
    
    local content = file:read("*a")
    file:close()
    
    return content
end

-- 解析 YAML 内容
local function parse_yaml(content)
    if not content or content == "" then
        return nil, "empty content"
    end
    
    local ok, data = pcall(yaml.parse, content)
    if not ok then
        return nil, "YAML parse error: " .. tostring(data)
    end
    
    return data
end

-- 验证配置结构
local function validate_config(config)
    if type(config) ~= "table" then
        return false, "config must be a table"
    end
    
    local valid_sections = {
        version = true,
        plugins = true,
        backends = true,
        services = true,
        routes = true,
        consumers = true,
        certificates = true,
    }
    
    for key, _ in pairs(config) do
        if not valid_sections[key] then
            ngx.log(ngx.WARN, "[store.yaml] unknown config section: ", key)
        end
    end
    
    return true
end

-- 构建索引 (使用 name 作为 key)
local function build_index_by_name(list)
    if not list then
        return {}
    end
    local index = {}
    for _, item in ipairs(list) do
        if item.name then
            index[item.name] = item
        end
    end
    return index
end

-- 加载配置文件
local function load_config()
    if not config_file_path then
        return false, "config file path not set"
    end
    
    -- 读取文件
    local content, err = read_file(config_file_path)
    if not content then
        return false, err
    end
    
    -- 解析 YAML
    local data, parse_err = parse_yaml(content)
    if not data then
        return false, parse_err
    end
    
    -- 验证配置
    local valid, valid_err = validate_config(data)
    if not valid then
        return false, valid_err
    end
    
    -- 构建索引
    data._index = {
        plugins = build_index_by_name(data.plugins),
        backends = build_index_by_name(data.backends),
        services = build_index_by_name(data.services),
        routes = build_index_by_name(data.routes),
        consumers = build_index_by_name(data.consumers),
        certificates = build_index_by_name(data.certificates),
    }
    
    -- 更新版本号
    config_version = config_version + 1
    config_data = data
    
    ngx.log(ngx.INFO, "[store.yaml] config loaded, version: ", config_version, 
            ", backends: ", #(data.backends or {}),
            ", services: ", #(data.services or {}),
            ", routes: ", #(data.routes or {}))
    
    return true
end

-- 通知所有监听者
local function notify_watchers(event_type, data)
    for _, callback in ipairs(watchers) do
        local ok, err = pcall(callback, event_type, data)
        if not ok then
            ngx.log(ngx.ERR, "[store.yaml] watcher callback error: ", err)
        end
    end
end

-- ============================================================
-- 公共 API
-- ============================================================

-- 初始化适配器
function _M.init(config)
    config = config or {}
    
    if config.config_file then
        config_file_path = config.config_file
    else
        local prefix = ngx.config.prefix()
        config_file_path = prefix .. DEFAULT_CONFIG_FILE
    end
    
    ngx.log(ngx.INFO, "[store.yaml] initializing with config file: ", config_file_path)
    
    local ok, err = load_config()
    if not ok then
        return false, err
    end
    
    return true
end

-- 重新加载配置
function _M.reload()
    local old_version = config_version
    
    local ok, err = load_config()
    if not ok then
        return false, err
    end
    
    if config_version > old_version then
        notify_watchers("reload", {
            old_version = old_version,
            new_version = config_version,
        })
    end
    
    return true
end

-- 监听配置变更
function _M.watch(callback)
    if type(callback) ~= "function" then
        return false, "callback must be a function"
    end
    
    table.insert(watchers, callback)
    return true
end

-- 获取配置版本号
function _M.get_version()
    return config_version
end

-- ============================================================
-- 资源访问接口
-- ============================================================

-- 获取全局插件
function _M.get_plugins()
    if not config_data then
        return nil, "config not loaded"
    end
    return config_data.plugins or {}, nil
end

-- 获取所有后端
function _M.get_backends()
    if not config_data then
        return nil, "config not loaded"
    end
    return config_data.backends or {}, nil
end

-- 获取所有服务
function _M.get_services()
    if not config_data then
        return nil, "config not loaded"
    end
    return config_data.services or {}, nil
end

-- 获取所有路由
function _M.get_routes()
    if not config_data then
        return nil, "config not loaded"
    end
    return config_data.routes or {}, nil
end

-- 获取所有消费者
function _M.get_consumers()
    if not config_data then
        return nil, "config not loaded"
    end
    return config_data.consumers or {}, nil
end

-- 获取所有证书
function _M.get_certificates()
    if not config_data then
        return nil, "config not loaded"
    end
    return config_data.certificates or {}, nil
end

-- ============================================================
-- 按 name 查询接口
-- ============================================================

function _M.get_plugin_by_name(name)
    if not config_data or not config_data._index then
        return nil, "config not loaded"
    end
    return config_data._index.plugins[name]
end

function _M.get_backend_by_name(name)
    if not config_data or not config_data._index then
        return nil, "config not loaded"
    end
    return config_data._index.backends[name]
end

function _M.get_service_by_name(name)
    if not config_data or not config_data._index then
        return nil, "config not loaded"
    end
    return config_data._index.services[name]
end

function _M.get_route_by_name(name)
    if not config_data or not config_data._index then
        return nil, "config not loaded"
    end
    return config_data._index.routes[name]
end

function _M.get_consumer_by_name(name)
    if not config_data or not config_data._index then
        return nil, "config not loaded"
    end
    return config_data._index.consumers[name]
end

function _M.get_certificate_by_name(name)
    if not config_data or not config_data._index then
        return nil, "config not loaded"
    end
    return config_data._index.certificates[name]
end

return _M
