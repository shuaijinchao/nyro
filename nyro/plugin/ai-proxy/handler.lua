--
-- NYRO AI Proxy Plugin
--
-- 复用 Nyro 的 routes -> services -> backends 资源模型:
--   http_access:       协议转换请求体 + 改写请求头/路径 (不短路)
--   http_header_filter: SSE 响应头处理 + 清除 Content-Length
--   http_body_filter:  非流式整体转换 / 流式 SSE 逐行转换
--

local ngx          = ngx
local type         = type
local pairs        = pairs
local tostring     = tostring
local string_find  = string.find
local string_sub   = string.sub
local string_match = string.match
local table_insert = table.insert
local table_concat = table.concat
local pdk          = require("nyro.core")
local json         = require("cjson.safe")
local llm_ffi      = require("nyro.ffi.llm")

local _M = {}

-- ── 用户协议名 -> llm-converter 内部协议名 映射 ──────────────────────────
--
-- 支持三种写法, 均映射到同一内部名:
--   短名:     "openai"              -> "openai_chat"
--   点号:     "openai.chat"         -> "openai_chat"
--   内部名:   "openai_chat"         -> "openai_chat"  (向后兼容)

local PROTOCOL_ALIAS = {
    -- 短名 (provider 默认能力)
    ["openai"]               = "openai_chat",
    ["anthropic"]            = "anthropic_messages",
    ["gemini"]               = "gemini_chat",
    ["ollama"]               = "ollama_chat",

    -- 点号展开 (provider.capability)
    ["openai.chat"]          = "openai_chat",
    ["openai.responses"]     = "openai_responses",
    ["anthropic.messages"]   = "anthropic_messages",
    ["anthropic.code"]       = "claude_code",
    ["gemini.chat"]          = "gemini_chat",
    ["ollama.chat"]          = "ollama_chat",

    -- 内部名 (向后兼容 llm-converter 原始标识)
    ["openai_chat"]          = "openai_chat",
    ["openai_responses"]     = "openai_responses",
    ["anthropic_messages"]   = "anthropic_messages",
    ["claude_code"]          = "claude_code",
    ["gemini_chat"]          = "gemini_chat",
    ["ollama_chat"]          = "ollama_chat",
}

--- 将用户协议名解析为内部协议名
local function resolve_protocol(name)
    if not name or name == "" then
        return nil
    end
    return PROTOCOL_ALIAS[name]
end

-- ── provider -> 默认内部协议名 ────────────────────────────────────────────

local PROVIDER_PROTOCOL = {
    openai    = "openai_chat",
    anthropic = "anthropic_messages",
    gemini    = "gemini_chat",
}

-- ── 协议 -> 认证 header 注入 ──────────────────────────────────────────────
-- 统一使用请求头注入 (包括 Gemini 使用 x-goog-api-key)

local function inject_auth_headers(target_proto, api_key)
    if not api_key or api_key == "" then
        return
    end

    ngx.req.set_header("Content-Type", "application/json")

    if target_proto == "openai_chat" or target_proto == "openai_responses" then
        ngx.req.set_header("Authorization", "Bearer " .. api_key)

    elseif target_proto == "anthropic_messages" or target_proto == "claude_code" then
        ngx.req.set_header("x-api-key", api_key)
        ngx.req.set_header("anthropic-version", "2023-06-01")

    elseif target_proto == "gemini_chat" then
        ngx.req.set_header("x-goog-api-key", api_key)

    elseif target_proto == "ollama_chat" then
        ngx.req.set_header("Content-Type", "application/json")
    end
end

-- ── 从客户端原始请求头提取 API key (按源协议) ───────────────────────────

local function extract_client_key(source_proto)
    local headers = ngx.req.get_headers()

    if source_proto == "openai_chat" or source_proto == "openai_responses" then
        local auth = headers["Authorization"]
        if auth then
            local prefix = string.lower(string.sub(auth, 1, 7))
            if prefix == "bearer " then
                return string.sub(auth, 8)
            end
        end

    elseif source_proto == "anthropic_messages" or source_proto == "claude_code" then
        return headers["x-api-key"]

    elseif source_proto == "gemini_chat" then
        return headers["x-goog-api-key"]
    end

    return nil
end

-- ── 协议 -> 默认上游路径 ─────────────────────────────────────────────────

local PROTO_DEFAULT_PATH = {
    openai_chat         = "/v1/chat/completions",
    openai_responses    = "/v1/responses",
    anthropic_messages  = "/v1/messages",
    claude_code         = "/v1/messages",
    ollama_chat         = "/api/chat",
    -- gemini_chat: 需要 model + streaming, 运行时构造
}

--- 根据目标协议确定上游路径
local function resolve_upstream_path(target_proto, cfg, streaming)
    -- 显式配置优先
    if cfg.upstream_path and cfg.upstream_path ~= "" then
        return cfg.upstream_path
    end

    -- Gemini 需要动态构造路径 (区分流式/非流式端点)
    if target_proto == "gemini_chat" then
        local model = cfg.model or "gemini-pro"
        if streaming then
            return "/v1beta/models/" .. model .. ":streamGenerateContent?alt=sse"
        else
            return "/v1beta/models/" .. model .. ":generateContent"
        end
    end

    return PROTO_DEFAULT_PATH[target_proto]
end

-- ── 协议源自动推断 (path + auth header) ─────────────────────────────────────

local PATH_PROTOCOL_MAP = {
    ["/v1/chat/completions"]  = "openai_chat",
    ["/v1/responses"]         = "openai_responses",
    ["/v1/messages"]          = "anthropic_messages",
    ["/v1beta/models/"]       = "gemini_chat",        -- prefix match
}

--- Detect source protocol from request path and auth headers.
--- Priority: exact path > prefix path > auth header > default (openai_chat)
local function detect_source_protocol(uri)
    -- 1) exact / prefix path match
    for path, proto in pairs(PATH_PROTOCOL_MAP) do
        if uri == path or string_find(uri, path, 1, true) == 1 then
            return proto
        end
    end

    -- 2) auth header heuristic
    local headers = ngx.req.get_headers()
    if headers["x-goog-api-key"] then
        return "gemini_chat"
    end
    if headers["x-api-key"] then
        return "anthropic_messages"
    end

    -- 3) default
    return "openai_chat"
end

-- ── 归一化请求体: 确保 messages[].content 为数组格式 ────────────────────────
--
-- Anthropic / OpenAI SDK 均允许 content 为纯字符串简写:
--   "content": "Hello"
-- 但 llm-converter 严格要求数组格式:
--   "content": [{"type": "text", "text": "Hello"}]
--
-- 此函数在 FFI 转换前将字符串简写展开为数组。

local function normalize_messages_content(body_tbl, source_proto)
    local messages = body_tbl.messages
    if not messages then
        return
    end

    for _, msg in ipairs(messages) do
        if type(msg.content) == "string" then
            if source_proto == "anthropic_messages" then
                msg.content = { { type = "text", text = msg.content } }
            end
            -- openai_chat 的 content 字符串是合法的, 不做转换
        end
    end
end

-- ── 可选: 覆盖请求体中的 model 字段 ────────────────────────────────────────

local function override_model(body_str, model)
    if not model or model == "" then
        return body_str
    end

    local body_tbl = json.decode(body_str)
    if not body_tbl then
        return body_str
    end

    body_tbl.model = model
    local new_body = json.encode(body_tbl)
    return new_body or body_str
end

-- ── 检测请求是否为流式 ──────────────────────────────────────────────────────

local function is_stream_request(body_str)
    local tbl = json.decode(body_str)
    return tbl and tbl.stream == true
end

-- ═══════════════════════════════════════════════════════════════════════════
-- http_access: 改写请求体 + 请求头 + 上游路径, 不短路
-- ═══════════════════════════════════════════════════════════════════════════

function _M.http_access(oak_ctx, plugin_config)
    local cfg = plugin_config or {}

    -- 从 service.provider 推导目标协议 (插件 config.to 可覆盖)
    local service = oak_ctx.config and oak_ctx.config.service
    local provider = service and service.provider

    local target_proto = resolve_protocol(cfg.to)
    if not target_proto then
        target_proto = provider and PROVIDER_PROTOCOL[provider]
    end

    if not target_proto then
        -- 非 AI 服务 (无 provider, 无 to), 跳过
        return
    end

    -- 读取请求体
    ngx.req.read_body()
    local body = ngx.req.get_body_data()
    if not body then
        pdk.response.exit(400, { error = { message = "empty request body" } })
        return
    end

    -- 确定源协议 (config.from, 或按 path 自动推断)
    local source_proto = resolve_protocol(cfg.from)
    if not source_proto then
        source_proto = detect_source_protocol(oak_ctx.matched.uri)
    end

    -- 检测是否流式 (在转换前, 从原始请求体检测)
    local streaming = is_stream_request(body)

    -- model 覆盖 (在转换之前, 对原始请求体操作)
    if cfg.model then
        body = override_model(body, cfg.model)
    end

    -- 归一化: 将 messages[].content 字符串简写展开为数组 (llm-converter 要求)
    if source_proto ~= target_proto then
        local body_tbl = json.decode(body)
        if body_tbl then
            normalize_messages_content(body_tbl, source_proto)
            body = json.encode(body_tbl) or body
        end
    end

    -- 请求体协议转换
    local converted_body = body
    if source_proto ~= target_proto then
        local converted, conv_err = llm_ffi.convert_request(source_proto, target_proto, body)
        if not converted then
            ngx.log(ngx.ERR, "[ai-proxy] request conversion failed: ", conv_err)
            pdk.response.exit(400, {
                error = { message = "protocol conversion failed: " .. tostring(conv_err) }
            })
            return
        end
        converted_body = converted
    end

    -- 确保转换后的 body 包含正确的 model 字段
    -- Gemini 的 model 在 URL 路径中 (如 /v1beta/models/{model}:action), body 中没有
    -- llm-converter 转换时会产生占位符 model, 需要用 URL 中的真实 model 覆盖
    local final_tbl = json.decode(converted_body)
    if final_tbl then
        -- 从 Gemini URL 提取 model (覆盖 llm-converter 的占位符)
        if source_proto == "gemini_chat" then
            local uri_model = string_match(oak_ctx.matched.uri, "/v1beta/models/([^/:]+)")
            if uri_model then
                final_tbl.model = uri_model
            end
        end
        -- 插件配置的 model 优先级最高
        if cfg.model then
            final_tbl.model = cfg.model
        end
        converted_body = json.encode(final_tbl) or converted_body
    end

    -- 用转换后的 body 替换原始请求体
    ngx.req.set_body_data(converted_body)

    -- 注入上游认证 header
    -- 优先级: cfg.api_key > 客户端透传 key > endpoint.headers (框架层已注入)
    local upstream_key = cfg.api_key
    if not upstream_key then
        -- 透传: 从 key-auth 认证结果或客户端原始 header 提取 key,
        -- 按目标协议格式重新注入 (解决跨协议 header 名不匹配问题)
        upstream_key = oak_ctx._authenticated_key
                    or extract_client_key(source_proto)
    end
    if upstream_key then
        inject_auth_headers(target_proto, upstream_key)
    end

    -- 改写上游路径
    local upstream_path = resolve_upstream_path(target_proto, cfg, streaming)
    if upstream_path then
        ngx.var.upstream_uri = upstream_path
    end

    -- 需要转换响应体时, 禁止上游返回压缩数据 (否则 body_filter 无法 JSON 解析)
    if source_proto ~= target_proto then
        ngx.req.set_header("Accept-Encoding", "identity")
    end

    -- 在 oak_ctx 上存储状态, 供后续 filter 阶段使用
    oak_ctx._ai_proxy = {
        enabled        = true,
        source_proto   = source_proto,
        target_proto   = target_proto,
        streaming      = streaming,
        need_convert   = (source_proto ~= target_proto),
    }

    -- 请求正常流转到 balancer -> proxy_pass, 不短路
end

-- ═══════════════════════════════════════════════════════════════════════════
-- http_header_filter: 处理上游响应头
-- ═══════════════════════════════════════════════════════════════════════════

function _M.http_header_filter(oak_ctx, _plugin_config)
    local ctx = oak_ctx._ai_proxy
    if not ctx or not ctx.enabled then
        return
    end

    if ctx.streaming then
        -- SSE: 确保响应头正确
        ngx.header["Content-Type"] = "text/event-stream"
        ngx.header["Cache-Control"] = "no-cache"
        ngx.header["X-Accel-Buffering"] = "no"
    end

    -- body 会被改写, 原始 Content-Length 不再准确
    if ctx.need_convert then
        ngx.header["Content-Length"] = nil
    end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- http_body_filter: 响应体协议转换
-- ═══════════════════════════════════════════════════════════════════════════

function _M.http_body_filter(oak_ctx, _plugin_config)
    local ctx = oak_ctx._ai_proxy
    if not ctx or not ctx.enabled or not ctx.need_convert then
        return
    end

    local chunk = ngx.arg[1]
    local eof   = ngx.arg[2]

    -- 跳过非 200 响应
    if ngx.status ~= 200 then
        return
    end

    local source_proto = ctx.source_proto
    local target_proto = ctx.target_proto

    if not ctx.streaming then
        -- ── 非流式: 缓冲所有 chunk, eof 时一次性转换 ────────────────────
        local buf = ctx._buf or ""
        buf = buf .. (chunk or "")

        if eof then
            if #buf > 0 then
                local converted, conv_err = llm_ffi.convert_response(
                    target_proto, source_proto, buf
                )
                if converted then
                    ngx.arg[1] = converted
                else
                    ngx.log(ngx.WARN, "[ai-proxy] response conversion failed: ", conv_err)
                    ngx.arg[1] = buf
                end
            end
        else
            -- 抑制中间 chunk 输出, 等待完整响应
            ngx.arg[1] = ""
            ctx._buf = buf
        end
    else
        -- ── 流式 SSE: 逐行扫描, 转换 data: 行 ──────────────────────────
        local buf = (ctx._buf or "") .. (chunk or "")
        local output = {}

        while true do
            local nl = string_find(buf, "\n", 1, true)
            if not nl then
                break
            end

            local line = string_sub(buf, 1, nl)  -- 包含 \n
            buf = string_sub(buf, nl + 1)

            -- 检查是否是 data: 行
            local payload = string_match(line, "^data:%s*(.-)%s*$")
            if payload and payload ~= "" and payload ~= "[DONE]" then
                local converted, conv_err = llm_ffi.convert_response(
                    target_proto, source_proto, payload
                )
                if converted then
                    table_insert(output, "data: " .. converted .. "\n")
                else
                    ngx.log(ngx.WARN, "[ai-proxy] SSE chunk conversion failed: ", conv_err)
                    table_insert(output, line)
                end
            else
                table_insert(output, line)
            end
        end

        ctx._buf = buf  -- 保留未完成的行

        if eof and #buf > 0 then
            -- 刷出残留数据
            table_insert(output, buf)
            ctx._buf = ""
        end

        ngx.arg[1] = table_concat(output)
    end
end

return _M
