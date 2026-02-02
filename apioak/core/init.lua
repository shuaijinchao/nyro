--
-- APIOAK Core Module
--
-- 核心工具模块，提供通用功能
--

return {
    log      = require("apioak.core.log"),
    ctx      = require("apioak.core.ctx"),
    json     = require("apioak.core.json"),
    time     = require("apioak.core.utils.time"),
    shared   = require("apioak.core.shared"),
    table    = require("apioak.core.utils.table"),
    string   = require("apioak.core.utils.string"),
    request  = require("apioak.core.request"),
    response = require("apioak.core.response"),
    schema   = require("apioak.core.schema"),
    pool     = require("apioak.core.utils.tablepool"),
    const    = require("apioak.core.const"),
    config   = require("apioak.core.config"),
    cache    = require("apioak.core.cache"),
}
