local _M = {}

-- 用户可配置的协议名 (短名 + 点号展开 + 内部名向后兼容)
local protocol_enum = {
    -- 短名 (推荐)
    "openai",
    "anthropic",
    "gemini",
    "ollama",
    -- 点号展开
    "openai.chat",
    "openai.responses",
    "anthropic.messages",
    "anthropic.code",
    "gemini.chat",
    "ollama.chat",
    -- 内部名 (向后兼容)
    "openai_chat",
    "openai_responses",
    "anthropic_messages",
    "claude_code",
    "gemini_chat",
    "ollama_chat",
}

_M.schema = {
    type       = "object",
    properties = {
        -- 客户端协议 (可选, 不指定则根据请求 path 自动推断)
        -- 示例: "openai", "anthropic", "openai.responses"
        from = {
            type = "string",
            enum = protocol_enum,
        },
        -- 上游协议 (可选, 优先从 service.provider 推导)
        -- 示例: "anthropic", "gemini", "openai.responses"
        to = {
            type = "string",
            enum = protocol_enum,
        },
        -- Provider API Key (可选, backend endpoint.headers 可替代)
        api_key = {
            type      = "string",
            minLength = 1,
        },
        -- 可选: 上游路径覆盖
        upstream_path = {
            type      = "string",
            minLength = 1,
        },
        -- 可选: 覆盖请求中的 model 字段
        model = {
            type      = "string",
            minLength = 1,
        },
        -- 可选: 覆盖最大 token 数
        max_tokens = {
            type    = "number",
            minimum = 1,
        },
        -- 可选: 覆盖温度
        temperature = {
            type    = "number",
            minimum = 0,
            maximum = 2,
        },
        -- 请求体最大长度 (字节)
        max_body_size = {
            type    = "number",
            minimum = 1024,
            default = 10485760,  -- 10MB
        },
    },
    required = {},
}

return _M
