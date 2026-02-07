local common = require "nyro.schema.common"

local _M = {}

-- Protocol constants
_M.PROTOCOLS_HTTP = "http"
_M.PROTOCOLS_HTTPS = "https"

local hosts = {
    type        = "array",
    minItems    = 1,
    uniqueItems = true,
    items       = {
        type      = "string",
        minLength = 3,
        pattern   = "^(?=^.{3,255}$)[a-zA-Z0-9][-a-zA-Z0-9]{0,62}(\\.[a-zA-Z0-9][-a-zA-Z0-9]{0,62})+$"
    }
}

local protocols = {
    type        = "array",
    minItems    = 1,
    uniqueItems = true,
    items       = {
        type = "string",
        enum = { _M.PROTOCOLS_HTTP, _M.PROTOCOLS_HTTPS }
    },
}

_M.created = {
    type       = "object",
    properties = {
        name      = common.name,
        protocols = {
            type        = "array",
            minItems    = 1,
            uniqueItems = true,
            items       = {
                type = "string",
                enum = { _M.PROTOCOLS_HTTP, _M.PROTOCOLS_HTTPS }
            },
            default     = { _M.PROTOCOLS_HTTP }
        },
        hosts     = hosts,
        plugins   = common.items_array_id_or_name_or_null,
    },
    required   = { "name", "hosts" }
}

_M.updated = {
    type       = "object",
    properties = {
        service_key = common.param_key,
        name        = common.name,
        protocols   = protocols,
        hosts       = hosts,
        plugins     = common.items_array_id_or_name_or_null,
    },
    required   = { "service_key" }
}

_M.detail = {
    type       = "object",
    properties = {
        service_key = common.param_key
    },
    required   = { "service_key" }
}

_M.deleted = {
    type       = "object",
    properties = {
        service_key = common.param_key
    },
    required   = { "service_key" }
}

_M.service_data = {
    type       = "object",
    properties = {
        id        = common.id,
        name      = common.name,
        protocols = protocols,
        hosts     = hosts,
        plugins   = common.items_array_id,
    },
    required   = { "id", "name", "protocols", "hosts", "plugins" }
}

return _M
