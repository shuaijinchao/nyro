--
-- NYRO LLM FFI Bindings
--
-- LuaJIT FFI 绑定，通过统一 FFI 基础模块调用 Rust LLM 协议转换
--

local ffi = require("ffi")
local base_ffi = require("nyro.ffi")

local _M = {
    _VERSION = "0.1.0"
}

-- FFI C 函数声明
ffi.cdef[[
    int nyro_llm_convert_request(
        const uint8_t *from_proto, size_t from_len,
        const uint8_t *to_proto,   size_t to_len,
        const uint8_t *input,      size_t input_len,
        uint8_t **out,             size_t *out_len
    );

    int nyro_llm_convert_response(
        const uint8_t *from_proto, size_t from_len,
        const uint8_t *to_proto,   size_t to_len,
        const uint8_t *input,      size_t input_len,
        uint8_t **out,             size_t *out_len
    );

    void nyro_llm_free(uint8_t *ptr, size_t len);
]]

-- 返回码常量
_M.OK           = 0
_M.ERR_PROTOCOL = -1
_M.ERR_CONVERT  = -2
_M.ERR_INVALID  = -3

-- 支持的 llm-converter 内部协议名 (传给 Rust FFI 的标识)
-- 用户侧协议名 (openai, openai.chat 等) 由 ai-proxy handler 的
-- PROTOCOL_ALIAS 映射为内部名后再传入此层
_M.PROTOCOLS = {
    "openai_chat",
    "openai_responses",
    "anthropic_messages",
    "claude_code",
    "gemini_chat",
    "ollama_chat",
}

-- 协议名 -> boolean 快速查找表
local protocol_set = {}
for _, p in ipairs(_M.PROTOCOLS) do
    protocol_set[p] = true
end

--- 检查内部协议名是否合法
function _M.is_valid_protocol(name)
    return protocol_set[name] == true
end

-- 预分配 FFI 指针
local out_ptr = ffi.new("uint8_t*[1]")
local out_len = ffi.new("size_t[1]")

--- 内部: 调用 FFI 转换函数并处理结果
local function call_convert(fn_name, from_proto, to_proto, body)
    local lib, err = base_ffi.get_lib()
    if not lib then
        return nil, "failed to load libnyro: " .. (err or "unknown")
    end

    out_ptr[0] = nil
    out_len[0] = 0

    local rc = lib[fn_name](
        from_proto, #from_proto,
        to_proto, #to_proto,
        body, #body,
        out_ptr, out_len
    )

    if rc == _M.OK then
        local result = ffi.string(out_ptr[0], out_len[0])
        lib.nyro_llm_free(out_ptr[0], out_len[0])
        return result, nil
    end

    -- 错误: out 中包含错误信息
    local errmsg = "unknown error"
    if out_ptr[0] ~= nil and out_len[0] > 0 then
        errmsg = ffi.string(out_ptr[0], out_len[0])
        lib.nyro_llm_free(out_ptr[0], out_len[0])
    end

    return nil, errmsg
end

--- 转换 LLM 请求体
-- @param from_proto string 源协议 (如 "openai_chat")
-- @param to_proto   string 目标协议 (如 "anthropic_messages")
-- @param body       string 原始 JSON 请求体
-- @return string|nil 转换后的 JSON, nil 表示失败
-- @return nil|string 错误信息
function _M.convert_request(from_proto, to_proto, body)
    return call_convert("nyro_llm_convert_request", from_proto, to_proto, body)
end

--- 转换 LLM 响应体 (完整响应或单个 SSE chunk)
-- @param from_proto string 源协议 (上游 provider 的协议)
-- @param to_proto   string 目标协议 (客户端期望的协议)
-- @param body       string 原始 JSON 响应体
-- @return string|nil 转换后的 JSON
-- @return nil|string 错误信息
function _M.convert_response(from_proto, to_proto, body)
    return call_convert("nyro_llm_convert_response", from_proto, to_proto, body)
end

return _M
