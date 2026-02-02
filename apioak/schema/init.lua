--
-- APIOAK Schema Module
--
-- Schema 定义模块
--

return {
    common        = require("apioak.schema.common"),
    service       = require("apioak.schema.service"),
    route         = require("apioak.schema.route"),
    plugin        = require("apioak.schema.plugin"),
    backend       = require("apioak.schema.backend"),
    certificate   = require("apioak.schema.certificate"),
    upstream_node = require("apioak.schema.upstream_node"),
}
