local nginx_signals = require "apioak/cli/utils/nginx_signals"

local lapp = [[
Usage: apioak quit
]]

local function execute()
    nginx_signals.quit()
end

return {
    lapp = lapp,
    execute = execute
}