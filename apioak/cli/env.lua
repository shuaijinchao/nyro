local common  = require "apioak/cli/utils/common"
local io_open = io.open

local lapp = [[
Usage: apioak env
]]

local config

local function get_config()
    local res, err = io.open(common.apioak_home .. "/conf/apioak.yaml", "r")
    if not res then
        print("Config Loading         ...FAIL(" .. err ..")")
        os.exit(1)
    else
        print("Config Loading         ...OK")
    end

    local config_content = res:read("*a")
    res:close()

    local yaml = require("tinyyaml")
    local config_table = yaml.parse(config_content)
    if not config_table or type(config_table) ~= "table" then
        print("Config Parse           ...FAIL")
        os.exit(1)
    else
        print("Config Parse           ...OK")
    end

    return config_table, nil
end

local function validate_store()
    local res, _ = get_config()
    
    -- 验证 store 配置
    if not res.store then
        print("Config Store           ...FAIL (store configuration not found)")
        os.exit(1)
    end
    
    local store_config = res.store
    local mode = store_config.mode
    
    if not mode then
        print("Config Store Mode      ...FAIL (store.mode not specified)")
        os.exit(1)
    end
    
    if mode ~= "standalone" and mode ~= "hybrid" then
        print("Config Store Mode      ...FAIL (invalid mode: " .. mode .. ", expected: standalone or hybrid)")
        os.exit(1)
    end
    
    print("Config Store Mode      ...OK (" .. mode .. ")")
    
    -- Standalone 模式验证
    if mode == "standalone" then
        local standalone_config = store_config.standalone
        if not standalone_config then
            print("Config Standalone      ...FAIL (standalone configuration not found)")
            os.exit(1)
        end
        
        local config_file = standalone_config.config_file
        if not config_file then
            print("Config File            ...FAIL (standalone.config_file not specified)")
            os.exit(1)
        end
        
        -- 检查配置文件是否存在
        local config_file_path = common.apioak_home .. "/" .. config_file
        local f, err = io_open(config_file_path, "r")
        if not f then
            print("Config File            ...FAIL (file not found: " .. config_file_path .. ")")
            os.exit(1)
        end
        f:close()
        
        print("Config File            ...OK (" .. config_file .. ")")
        
        -- 验证声明式配置文件格式
        local yaml = require("tinyyaml")
        local cf, _ = io_open(config_file_path, "r")
        local content = cf:read("*a")
        cf:close()
        
        local data_config = yaml.parse(content)
        if not data_config then
            print("Config File Parse      ...FAIL (invalid YAML format)")
            os.exit(1)
        end
        
        -- 检查必要的字段
        local has_routes = data_config.routes and #data_config.routes > 0
        if not has_routes then
            print("Config Routes          ...WARN (no routes defined)")
        else
            print("Config Routes          ...OK (" .. #data_config.routes .. " routes)")
        end
    end
    
    -- Hybrid 模式验证 (未来实现)
    if mode == "hybrid" then
        print("Config Hybrid          ...INFO (hybrid mode will be validated at runtime)")
    end
    
    config = res
end

local function validate_plugin()

    local plugins = config.plugins

    if not plugins or #plugins == 0 then
        print("Plugin Check           ...WARN (no plugins configured)")
        return
    end

    local err_plugins = {}

    for i = 1, #plugins do

        local file_path = common.apioak_home .. "/apioak/plugin/" .. plugins[i] .. "/handler.lua"

        local _, err = io_open(file_path, "r")

        if err then
            table.insert(err_plugins, plugins[i])
        end

    end

    if next(err_plugins) then
        print("Plugin Check           ...FAIL (Plugin not found: " .. table.concat(err_plugins, ', ') .. ")")
        os.exit(1)
    else
        print("Plugin Check           ...OK (" .. #plugins .. " plugins)")
    end
end

local function execute()
    local nginx_path = common.trim(common.execute_cmd("which openresty"))
    if not nginx_path then
        print("OpenResty PATH         ...FAIL(OpenResty not found in system PATH)")
        os.exit(1)
    else
        print("OpenResty PATH         ...OK")
    end


    if ngx.config.nginx_version < 1015008 then
        print("OpenResty Version      ...FAIL(OpenResty version must be greater than 1.15.8)")
        os.exit(1)
    else

        print("OpenResty Version      ...OK")
    end

    validate_store()

    validate_plugin()
end

return {
    lapp = lapp,
    execute = execute
}
