local _M = {}

_M.schema = {
    type       = "object",
    properties = {
        -- Custom header name to read the API key from.
        -- If unset, auto-detect from standard AI SDK headers,
        -- then fallback to "NYRO-KEY-AUTH".
        key_name = {
            type      = "string",
            minLength = 1,
        },
        -- Where to read the key: "header" (default) or "query".
        key_in = {
            type    = "string",
            enum    = { "header", "query" },
            default = "header",
        },
        -- Remove the credential from the request before forwarding.
        hide_credentials = {
            type    = "boolean",
            default = false,
        },
    },
    required = {},
}

return _M
