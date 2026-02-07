local stop  = require("nyro.cli.stop")
local start = require("nyro.cli.start")

local lapp = [[
Usage: nyro restart
]]

local function execute()

    pcall(stop.execute)

    pcall(start.execute)
end

return {
    lapp = lapp,
    execute = execute
}