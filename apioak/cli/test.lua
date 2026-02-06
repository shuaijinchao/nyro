local nginx_signals = require "apioak/cli/utils/nginx_signals"
local generator     = require "apioak/cli/generator"

local lapp = [[
Usage: apioak test
]]

local function execute()
    generator.generate()
    nginx_signals.test()
end

return {
    lapp = lapp,
    execute = execute
}
