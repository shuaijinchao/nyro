--
-- NYRO Schema Module
--
-- Schema 定义模块
--

return {
    common        = require("nyro.schema.common"),
    service       = require("nyro.schema.service"),
    route         = require("nyro.schema.route"),
    plugin        = require("nyro.schema.plugin"),
    backend       = require("nyro.schema.backend"),
    certificate   = require("nyro.schema.certificate"),
    upstream_node = require("nyro.schema.upstream_node"),
}
