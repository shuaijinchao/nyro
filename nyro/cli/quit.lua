local nginx_signals = require "nyro/cli/utils/nginx_signals"

local lapp = [[
Usage: nyro quit
]]

local function execute()
    nginx_signals.quit()
end

return {
    lapp = lapp,
    execute = execute
}