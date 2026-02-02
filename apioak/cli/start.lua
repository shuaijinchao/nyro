local nginx_signals = require "apioak/cli/utils/nginx_signals"
local env           = require"apioak/cli/env"

local lapp = [[
Usage: apioak start
]]

local function execute()
    env.execute()
    print("----------------------------")

    nginx_signals.start()

    print("Apioak started successfully!")
end

return {
    lapp = lapp,
    execute = execute
}