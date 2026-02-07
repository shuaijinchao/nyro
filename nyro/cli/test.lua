local nginx_signals = require "nyro/cli/utils/nginx_signals"
local generator     = require "nyro/cli/generator"

local lapp = [[
Usage: nyro test
]]

local function execute()
    generator.generate()
    nginx_signals.test()
end

return {
    lapp = lapp,
    execute = execute
}
