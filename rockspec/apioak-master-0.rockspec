package = "apioak"
version = "master-0"
rockspec_format = "3.0"
supported_platforms = {"linux", "macosx"}

source = {
    url = "git://github.com/apioak/apioak",
    branch = "master",
}

description = {
    summary = "APIOAK provides full life cycle management of API release, management, and operation and maintenance.",
    homepage = "https://github.com/apioak/apioak",
    license = "Apache License 2.0",
    maintainer = "Janko <shuaijinchao@gmail.com>"
}

dependencies = {
    "lua-resty-worker-events == 2.0.1-1",
    "lua-resty-balancer == 0.02rc5",
    "lua-resty-jwt == 0.2.0",
    "lua-resty-http == 0.15-0",
    "lua-resty-lrucache == 0.09-2",
    "jsonschema == 0.9.8-0",
    "luasocket == 3.0rc1-2",
    "luafilesystem == 1.7.0-2",
    "lua-tinyyaml == 0.1",
    "multipart == 0.5.5-1",
    "penlight == 1.5.4-1",
    "lua-resty-jit-uuid == 0.0.7-2",
    "lua-resty-dns == 0.21-1"
}

build = {
    type = "builtin",
    modules = {
        -- Main entry
        ["apioak"] = "apioak/apioak.lua",

        -- Core modules
        ["apioak.core"] = "apioak/core/init.lua",
        ["apioak.core.const"] = "apioak/core/const.lua",
        ["apioak.core.ctx"] = "apioak/core/ctx.lua",
        ["apioak.core.json"] = "apioak/core/json.lua",
        ["apioak.core.log"] = "apioak/core/log.lua",
        ["apioak.core.request"] = "apioak/core/request.lua",
        ["apioak.core.response"] = "apioak/core/response.lua",
        ["apioak.core.schema"] = "apioak/core/schema.lua",
        ["apioak.core.shared"] = "apioak/core/shared.lua",
        ["apioak.core.config"] = "apioak/core/config.lua",
        ["apioak.core.cache"] = "apioak/core/cache.lua",
        ["apioak.core.meta"] = "apioak/core/meta.lua",
        ["apioak.core.utils.string"] = "apioak/core/utils/string.lua",
        ["apioak.core.utils.table"] = "apioak/core/utils/table.lua",
        ["apioak.core.utils.tablepool"] = "apioak/core/utils/tablepool.lua",
        ["apioak.core.utils.time"] = "apioak/core/utils/time.lua",

        -- Route modules (routes resource)
        ["apioak.route"] = "apioak/route/init.lua",
        ["apioak.route.matcher"] = "apioak/route/matcher.lua",
        ["apioak.route.ffi"] = "apioak/route/ffi.lua",

        -- Backend modules (backends resource)
        ["apioak.backend"] = "apioak/backend/init.lua",

        -- Service modules (services resource)
        ["apioak.service"] = "apioak/service/init.lua",

        -- Application modules (applications resource)
        ["apioak.application"] = "apioak/application/init.lua",

        -- Certificate modules (certificates resource)
        ["apioak.certificate"] = "apioak/certificate/init.lua",

        -- Plugin modules (plugins resource)
        ["apioak.plugin"] = "apioak/plugin/init.lua",
        ["apioak.plugin.common"] = "apioak/plugin/common.lua",
        ["apioak.plugin.cors.handler"] = "apioak/plugin/cors/handler.lua",
        ["apioak.plugin.cors.schema"] = "apioak/plugin/cors/schema.lua",
        ["apioak.plugin.jwt-auth.handler"] = "apioak/plugin/jwt-auth/handler.lua",
        ["apioak.plugin.jwt-auth.schema"] = "apioak/plugin/jwt-auth/schema.lua",
        ["apioak.plugin.key-auth.handler"] = "apioak/plugin/key-auth/handler.lua",
        ["apioak.plugin.key-auth.schema"] = "apioak/plugin/key-auth/schema.lua",
        ["apioak.plugin.limit-conn.handler"] = "apioak/plugin/limit-conn/handler.lua",
        ["apioak.plugin.limit-conn.schema"] = "apioak/plugin/limit-conn/schema.lua",
        ["apioak.plugin.limit-count.handler"] = "apioak/plugin/limit-count/handler.lua",
        ["apioak.plugin.limit-count.schema"] = "apioak/plugin/limit-count/schema.lua",
        ["apioak.plugin.limit-req.handler"] = "apioak/plugin/limit-req/handler.lua",
        ["apioak.plugin.limit-req.schema"] = "apioak/plugin/limit-req/schema.lua",
        ["apioak.plugin.mock.handler"] = "apioak/plugin/mock/handler.lua",
        ["apioak.plugin.mock.schema"] = "apioak/plugin/mock/schema.lua",

        -- Schema modules
        ["apioak.schema"] = "apioak/schema/init.lua",
        ["apioak.schema.common"] = "apioak/schema/common.lua",
        ["apioak.schema.backend"] = "apioak/schema/backend.lua",
        ["apioak.schema.service"] = "apioak/schema/service.lua",
        ["apioak.schema.route"] = "apioak/schema/route.lua",
        ["apioak.schema.plugin"] = "apioak/schema/plugin.lua",
        ["apioak.schema.certificate"] = "apioak/schema/certificate.lua",
        ["apioak.schema.upstream_node"] = "apioak/schema/upstream_node.lua",

        -- Store modules
        ["apioak.store"] = "apioak/store/init.lua",
        ["apioak.store.adapter.yaml"] = "apioak/store/adapter/yaml.lua",

        -- CLI modules
        ["apioak.cli"] = "apioak/cli/init.lua",
        ["apioak.cli.env"] = "apioak/cli/env.lua",
        ["apioak.cli.help"] = "apioak/cli/help.lua",
        ["apioak.cli.init"] = "apioak/cli/init.lua",
        ["apioak.cli.quit"] = "apioak/cli/quit.lua",
        ["apioak.cli.reload"] = "apioak/cli/reload.lua",
        ["apioak.cli.restart"] = "apioak/cli/restart.lua",
        ["apioak.cli.start"] = "apioak/cli/start.lua",
        ["apioak.cli.stop"] = "apioak/cli/stop.lua",
        ["apioak.cli.test"] = "apioak/cli/test.lua",
        ["apioak.cli.version"] = "apioak/cli/version.lua",
        ["apioak.cli.utils.common"] = "apioak/cli/utils/common.lua",
        ["apioak.cli.utils.kill"] = "apioak/cli/utils/kill.lua",
        ["apioak.cli.utils.nginx_signals"] = "apioak/cli/utils/nginx_signals.lua",
    },
}
