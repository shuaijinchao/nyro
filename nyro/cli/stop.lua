local nginx_signals = require "nyro/cli/utils/nginx_signals"

local lapp = [[
Usage: nyro stop
]]

local function execute()
    nginx_signals.stop()
end

return {
    lapp = lapp,
    execute = execute
}