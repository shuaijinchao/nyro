local function execute()
    print([[
    Usage: nyro [action] <argument>
    help:       show this message, then exit
    start:      start the nyro server
    quit:       quit the nyro server
    stop:       stop the nyro server
    restart:    restart the nyro server
    reload:     reload the nyro server
    test:       test the nyro nginx config
    env:        check nyro running environment
    version:    print nyro's version
    ]])
end

local lapp = [[
Usage: nyro help
]]


return {
    lapp = lapp,
    execute = execute
}