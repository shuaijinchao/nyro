local meta = require "nyro.core.meta"

local lapp = [[
Usage: nyro version [OPTIONS]

Print Nyro's version. With the -a option, will print
the version of all underlying dependencies.

Options:
 -a,--all         get version of all dependencies
]]

local str = [[
nyro: %s
ngx_lua: %s
nginx: %s
Lua: %s]]

local function execute()
  print(string.format(str,
                      meta.__VERSION,
                      ngx.config.ngx_lua_version,
                      ngx.config.nginx_version,
                      jit and jit.version or _VERSION
  ))
end

return {
  lapp = lapp,
  execute = execute
}
