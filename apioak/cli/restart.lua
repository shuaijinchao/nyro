local stop  = require("apioak.cli.stop")
local start = require("apioak.cli.start")

local lapp = [[
Usage: apioak restart
]]

local function execute()

    pcall(stop.execute)

    pcall(start.execute)
end

return {
    lapp = lapp,
    execute = execute
}