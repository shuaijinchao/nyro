local nginx_signals = require("apioak/cli/utils/nginx_signals")
local generator     = require("apioak/cli/generator")

local lapp = [[
Usage: apioak reload
]]

local function execute()
    generator.generate()
    nginx_signals.reload()
end

return {
    lapp = lapp,
    execute = execute
}
