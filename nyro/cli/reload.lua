local nginx_signals = require("nyro/cli/utils/nginx_signals")
local generator     = require("nyro/cli/generator")

local lapp = [[
Usage: nyro reload
]]

local function execute()
    generator.generate()
    nginx_signals.reload()
end

return {
    lapp = lapp,
    execute = execute
}
