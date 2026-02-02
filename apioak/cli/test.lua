
local nginx_signals = require "apioak/cli/utils/nginx_signals"

local lapp = [[
Usage: apioak test
]]

local function execute()
    nginx_signals.test()
end

return {
    lapp = lapp,
    execute = execute
}