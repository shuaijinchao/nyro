local common = require "nyro.schema.common"

local _M = {}

-- Constants
_M.DEFAULT_PORT = 80
_M.DEFAULT_WEIGHT = 10
_M.DEFAULT_HEALTH = "healthy"
_M.DEFAULT_UNHEALTH = "unhealthy"
_M.DEFAULT_ENABLED_TRUE = true
_M.DEFAULT_ENABLED_FALSE = false
_M.DEFAULT_INTERVAL = 10
_M.DEFAULT_TIMEOUT = 5

local address = {
    type  = "string",
    anyOf = {
        {
            format = "ipv4"
        },
        {
            format = "ipv6"
        }
    }
}

local method_enum = {
    "",
    "GET",
    "POST",
    "HEADER",
    "OPTIONS"
}

local uri_pattern = "^\\/\\*?[0-9a-zA-Z-.=?_*/{}]+$"

local port = {
    type    = "number",
    minimum = 1,
    maximum = 65535,
}

local weight = {
    type    = "number",
    minimum = 1,
    maximum = 100,
}

local health = {
    type = "string",
    enum = { _M.DEFAULT_HEALTH, _M.DEFAULT_UNHEALTH }
}

local enabled = {
    type = "boolean",
}

local host = {
    type      = "string",
    maxLength = 150,
}

local method = {
    type = "string",
    enum = method_enum
}

local uri = {
    type      = "string",
    maxLength = 150,
    anyOf     = {
        {
            pattern = uri_pattern
        },
        {}
    }
}

local interval = {
    type    = "number",
    minimum = 0,
    maximum = 86400,
}

local timeout = {
    type    = "number",
    minimum = 0,
    maximum = 86400,
}

_M.created = {
    type       = "object",
    properties = {
        name    = common.name,
        address = address,
        port    = {
            type    = "number",
            minimum = 1,
            maximum = 65535,
            default = _M.DEFAULT_PORT
        },
        weight  = {
            type    = "number",
            minimum = 1,
            maximum = 100,
            default = _M.DEFAULT_WEIGHT
        },
        health  = {
            type = "string",
            enum = { _M.DEFAULT_HEALTH, _M.DEFAULT_UNHEALTH }
        },
        check   = {
            type       = "object",
            properties = {
                enabled  = {
                    type    = "boolean",
                    default = _M.DEFAULT_ENABLED_FALSE,
                },
                tcp      = {
                    type    = "boolean",
                    default = _M.DEFAULT_ENABLED_TRUE,
                },
                method   = method,
                host     = host,
                uri      = uri,
                interval = {
                    type    = "number",
                    minimum = 0,
                    maximum = 86400,
                    default = _M.DEFAULT_INTERVAL
                },
                timeout  = {
                    type    = "number",
                    minimum = 0,
                    maximum = 86400,
                    default = _M.DEFAULT_TIMEOUT
                }
            }
        }
    },
    required   = { "name", "address", "port", "check" }
}

_M.updated = {
    type       = "object",
    properties = {
        upstream_node_key = common.param_key,
        name              = common.name,
        address           = address,
        port              = port,
        weight            = weight,
        health            = health,
        check             = {
            type       = "object",
            properties = {
                enabled  = enabled,
                tcp      = enabled,
                method   = method,
                host     = host,
                uri      = uri,
                interval = interval,
                timeout  = timeout
            }
        }
    },
    required   = { "upstream_node_key" }
}

_M.upstream_node_data = {
    type       = "object",
    properties = {
        id      = common.id,
        name    = common.name,
        address = address,
        port    = port,
        weight  = weight,
        health  = health,
        check   = {
            type       = "object",
            properties = {
                enabled  = enabled,
                tcp      = enabled,
                method   = method,
                host     = host,
                uri      = uri,
                interval = interval,
                timeout  = timeout
            },
            required   = { "enabled", "interval", "timeout" }
        }
    },
    required   = { "id", "name", "address", "port", "weight", "health", "check" }
}

_M.schema_ip = address

_M.schema_port = port

return _M
