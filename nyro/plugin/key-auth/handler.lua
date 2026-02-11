--
-- NYRO Key-Auth Plugin
--
-- Authenticates requests via API key, integrated with the consumer/credential system.
--
-- Key extraction priority (when key_name is NOT configured):
--   1. Authorization: Bearer {key}     (OpenAI SDK)
--   2. x-api-key: {key}                (Anthropic SDK)
--   3. x-goog-api-key: {key}           (Gemini SDK)
--   4. NYRO-KEY-AUTH: {key}             (Nyro default)
--
-- After successful authentication:
--   - oak_ctx._consumer          = consumer object
--   - oak_ctx._authenticated_key = the raw API key (for ai-proxy passthrough)
--

local pdk      = require("nyro.core")
local consumer = require("nyro.consumer")

local ngx         = ngx
local type         = type
local string_sub   = string.sub
local string_lower = string.lower
local string_find  = string.find

local _M = {}

-- ── Extract key from request ────────────────────────────────────────────────

--- Extract API key from a specific header.
local function get_key_from_header(name)
    local val = ngx.req.get_headers()[name]
    if not val or val == "" then
        return nil
    end

    -- Handle "Bearer {key}" format
    if string_lower(name) == "authorization" then
        local prefix = string_sub(val, 1, 7)
        if string_lower(prefix) == "bearer " then
            return string_sub(val, 8)
        end
        return nil
    end

    return val
end

--- Extract API key from a query parameter.
local function get_key_from_query(name)
    local args = ngx.req.get_uri_args()
    local val = args[name]
    if not val or val == "" or val == true then
        return nil
    end
    return val
end

--- Auto-detect API key from standard AI SDK headers + Nyro default.
local AUTO_DETECT_HEADERS = {
    { name = "Authorization",  bearer = true  },   -- OpenAI
    { name = "x-api-key",     bearer = false },   -- Anthropic
    { name = "x-goog-api-key", bearer = false },   -- Gemini
    { name = "NYRO-KEY-AUTH",  bearer = false },   -- Nyro default
}

local function auto_detect_key()
    local headers = ngx.req.get_headers()

    for _, spec in ipairs(AUTO_DETECT_HEADERS) do
        local val = headers[spec.name]
        if val and val ~= "" then
            if spec.bearer then
                local prefix = string_sub(val, 1, 7)
                if string_lower(prefix) == "bearer " then
                    return string_sub(val, 8), spec.name
                end
            else
                return val, spec.name
            end
        end
    end

    return nil, nil
end

-- ── Remove credential from request ─────────────────────────────────────────

local function hide_header_credential(name)
    ngx.req.set_header(name, nil)
end

local function hide_query_credential(name)
    local args = ngx.req.get_uri_args()
    args[name] = nil
    ngx.req.set_uri_args(args)
end

-- ── Access phase ────────────────────────────────────────────────────────────

function _M.http_access(oak_ctx, plugin_config)
    local cfg = plugin_config or {}
    local key_in   = cfg.key_in or "header"
    local key_name = cfg.key_name
    local hide     = cfg.hide_credentials

    local api_key, found_in_name

    if key_name then
        -- Explicit key location
        if key_in == "query" then
            api_key = get_key_from_query(key_name)
        else
            api_key = get_key_from_header(key_name)
        end
        found_in_name = key_name
    else
        -- Auto-detect from standard AI headers + Nyro default
        api_key, found_in_name = auto_detect_key()
    end

    if not api_key then
        pdk.response.exit(401, {
            error = { message = "Unauthorized: missing API key" }
        })
        return
    end

    -- Lookup consumer by credential
    local matched_consumer = consumer.verify_key_auth(api_key)
    if not matched_consumer then
        pdk.response.exit(401, {
            error = { message = "Unauthorized: invalid API key" }
        })
        return
    end

    -- Store auth context for downstream plugins (e.g. ai-proxy)
    oak_ctx._consumer          = matched_consumer
    oak_ctx._authenticated_key = api_key

    -- Optionally remove credential from upstream request
    if hide and found_in_name then
        if key_in == "query" and key_name then
            hide_query_credential(key_name)
        else
            hide_header_credential(found_in_name)
        end
    end
end

return _M
