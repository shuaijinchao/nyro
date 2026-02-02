local nginx_signals = require "apioak/cli/utils/nginx_signals"

local lapp = [[
Usage: apioak stop
]]

local function execute()
    nginx_signals.stop()
end

return {
    lapp = lapp,
    execute = execute
}