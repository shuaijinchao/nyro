local nginx_signals = require "nyro/cli/utils/nginx_signals"
local env           = require "nyro/cli/env"
local generator     = require "nyro/cli/generator"

local lapp = [[
Usage: nyro start
]]

local function execute()
    env.execute()
    generator.generate()
    print("----------------------------")

    nginx_signals.start()

    print("Nyro started successfully!")
end

return {
    lapp = lapp,
    execute = execute
}
