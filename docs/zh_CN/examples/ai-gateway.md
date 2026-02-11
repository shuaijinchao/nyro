# AI 网关配置示例

> 以下示例展示 AI 网关场景, 基于 `ai-proxy` 插件实现协议转换和认证注入。
> 支持的 Provider: `openai` / `anthropic` / `gemini`

---

## 1. 最简 — OpenAI 直连

客户端用 OpenAI SDK, 直通 OpenAI:

```yaml
version: "1.0"

plugins:
  - ai-proxy

services:
  - name: openai
    provider: openai
    url: https://api.openai.com

routes:
  - name: chat
    service: openai
    paths:
      - /v1/chat/completions
    methods: ["POST"]
    plugins:
      - id: ai-proxy
        config:
          api_key: "sk-xxxxx"
```

```bash
curl http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"gpt-4o","messages":[{"role":"user","content":"hello"}]}'
```

---

## 2. 协议转换 — OpenAI 客户端 → Anthropic 后端

客户端用 OpenAI 格式请求, 网关自动转为 Anthropic 格式转发到 Claude:

```yaml
plugins:
  - ai-proxy

services:
  - name: claude
    provider: anthropic
    url: https://api.anthropic.com

routes:
  - name: chat-claude
    service: claude
    paths:
      - /v1/chat/completions
    methods: ["POST"]
    plugins:
      - id: ai-proxy
        config:
          api_key: "sk-ant-xxxxx"
          model: "claude-sonnet-4-20250514"
```

客户端完全无感知, 发送标准 OpenAI 格式即可:

```bash
curl http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"gpt-4o","messages":[{"role":"user","content":"hello"}]}'
```

> `model` 字段会被插件配置的 `claude-sonnet-4-20250514` 覆盖。

---

## 3. 协议转换 — OpenAI 客户端 → Gemini 后端

```yaml
plugins:
  - ai-proxy

services:
  - name: gemini
    provider: gemini
    url: https://generativelanguage.googleapis.com

routes:
  - name: chat-gemini
    service: gemini
    paths:
      - /v1/chat/completions
    methods: ["POST"]
    plugins:
      - id: ai-proxy
        config:
          api_key: "AIzaSy-xxxxx"
          model: "gemini-2.0-flash"
```

> Gemini 的 upstream path 会自动构造:
> - 非流式: `/v1beta/models/gemini-2.0-flash:generateContent`
> - 流式: `/v1beta/models/gemini-2.0-flash:streamGenerateContent?alt=sse`

---

## 4. 带客户端认证

使用 Nyro API Key 保护 AI 接口:

```yaml
plugins:
  - key-auth
  - ai-proxy

consumers:
  - name: app-client
    credentials:
      key-auth:
        key: "nyro-sk-001"

services:
  - name: claude
    provider: anthropic
    url: https://api.anthropic.com

routes:
  - name: chat
    service: claude
    paths:
      - /v1/chat/completions
    methods: ["POST"]
    plugins:
      - id: key-auth
      - id: ai-proxy
        config:
          api_key: "sk-ant-xxxxx"
          model: "claude-sonnet-4-20250514"
```

```bash
curl http://localhost:8080/v1/chat/completions \
  -H "apikey: nyro-sk-001" \
  -H "Content-Type: application/json" \
  -d '{"model":"gpt-4o","messages":[{"role":"user","content":"hello"}]}'
```

---

## 5. 多 API Key 轮换 (负载均衡)

使用 `backends` + `endpoint.headers` 实现 API Key 轮换:

```yaml
plugins:
  - ai-proxy

backends:
  - name: openai-keys
    algorithm: roundrobin
    timeout:
      connect: 5000
      read: 120000
      send: 5000
    endpoints:
      - address: "api.openai.com"
        port: 443
        weight: 100
        headers:
          Authorization: "Bearer sk-proj-A-xxxxx"
      - address: "api.openai.com"
        port: 443
        weight: 100
        headers:
          Authorization: "Bearer sk-proj-B-xxxxx"

services:
  - name: openai-ha
    provider: openai
    scheme: https
    backend: openai-keys

routes:
  - name: chat
    service: openai-ha
    paths:
      - /v1/chat/completions
    methods: ["POST"]
    plugins:
      - id: ai-proxy
        config: {}
```

> `api_key` 无需在插件配置中指定, 由 `endpoint.headers` 自动注入。
> 每次请求 roundrobin 轮换不同的 API Key。

---

## 6. 多 Provider 共存 — 不同 Path

同一网关同时服务多个 AI Provider:

```yaml
plugins:
  - ai-proxy

services:
  - name: openai
    provider: openai
    url: https://api.openai.com

  - name: claude
    provider: anthropic
    url: https://api.anthropic.com

  - name: gemini
    provider: gemini
    url: https://generativelanguage.googleapis.com

routes:
  - name: chat-openai
    service: openai
    paths:
      - /v1/chat/completions
    methods: ["POST"]
    plugins:
      - id: ai-proxy
        config:
          api_key: "sk-openai-xxxxx"

  - name: chat-claude
    service: claude
    paths:
      - /ai/claude/chat
    methods: ["POST"]
    plugins:
      - id: ai-proxy
        config:
          api_key: "sk-ant-xxxxx"
          from: openai

  - name: chat-gemini
    service: gemini
    paths:
      - /ai/gemini/chat
    methods: ["POST"]
    plugins:
      - id: ai-proxy
        config:
          api_key: "AIzaSy-xxxxx"
          model: "gemini-2.0-flash"
          from: openai
```

> 自定义 path (如 `/ai/claude/chat`) 无法自动推断 from, 需显式配置。

---

## 7. 多 Provider 共存 — Host 路由

相同 path, 通过域名区分 Provider:

```yaml
plugins:
  - ai-proxy

services:
  - name: openai
    provider: openai
    url: https://api.openai.com

  - name: claude
    provider: anthropic
    url: https://api.anthropic.com

  - name: gemini
    provider: gemini
    url: https://generativelanguage.googleapis.com

routes:
  - name: chat-openai
    hosts: ["openai.ai.example.com"]
    service: openai
    paths:
      - /v1/chat/completions
    methods: ["POST"]
    plugins:
      - id: ai-proxy
        config:
          api_key: "sk-openai-xxxxx"

  - name: chat-claude
    hosts: ["claude.ai.example.com"]
    service: claude
    paths:
      - /v1/chat/completions
    methods: ["POST"]
    plugins:
      - id: ai-proxy
        config:
          api_key: "sk-ant-xxxxx"

  - name: chat-gemini
    hosts: ["gemini.ai.example.com"]
    service: gemini
    paths:
      - /v1/chat/completions
    methods: ["POST"]
    plugins:
      - id: ai-proxy
        config:
          api_key: "AIzaSy-xxxxx"
          model: "gemini-2.0-flash"
```

```bash
# 发到 Claude
curl -H "Host: claude.ai.example.com" \
     http://localhost:8080/v1/chat/completions \
     -d '{"model":"gpt-4o","messages":[{"role":"user","content":"hello"}]}'

# 发到 OpenAI
curl -H "Host: openai.ai.example.com" \
     http://localhost:8080/v1/chat/completions \
     -d '{"model":"gpt-4o","messages":[{"role":"user","content":"hello"}]}'
```

---

## 8. 完整示例 — 认证 + 限流 + 协议转换 + 负载均衡

```yaml
plugins:
  - key-auth
  - limit-req
  - ai-proxy

consumers:
  - name: premium
    credentials:
      key-auth:
        key: "nyro-sk-premium-001"

  - name: free
    credentials:
      key-auth:
        key: "nyro-sk-free-001"

backends:
  - name: openai-keys
    algorithm: roundrobin
    timeout:
      connect: 5000
      read: 120000
      send: 5000
    endpoints:
      - address: "api.openai.com"
        port: 443
        weight: 100
        headers:
          Authorization: "Bearer sk-proj-A-xxxxx"
      - address: "api.openai.com"
        port: 443
        weight: 100
        headers:
          Authorization: "Bearer sk-proj-B-xxxxx"

services:
  - name: openai-ha
    provider: openai
    scheme: https
    backend: openai-keys

routes:
  - name: chat
    service: openai-ha
    paths:
      - /v1/chat/completions
    methods: ["POST"]
    plugins:
      - id: key-auth
      - id: limit-req
        config:
          rate: 20
          burst: 10
      - id: ai-proxy
        config: {}
```

---

## 参考

### 支持的 Provider

| Provider | `service.provider` | 认证 Header |
|----------|-------------------|-------------|
| OpenAI | `openai` | `Authorization: Bearer {key}` |
| Anthropic | `anthropic` | `x-api-key: {key}` + `anthropic-version: 2023-06-01` |
| Gemini | `gemini` | `x-goog-api-key: {key}` |

### 协议名格式

`from` / `to` 支持三种写法:

| 格式 | 示例 | 说明 |
|------|------|------|
| **短名** (推荐) | `openai` | 使用 provider 默认能力 |
| 点号展开 | `openai.chat` | 指定具体能力 |
| 内部名 | `openai_chat` | 向后兼容 |

完整协议列表:

| 短名 | 点号展开 | 说明 |
|------|---------|------|
| `openai` | `openai.chat` | OpenAI Chat Completions |
| — | `openai.responses` | OpenAI Responses API |
| `anthropic` | `anthropic.messages` | Anthropic Messages |
| — | `anthropic.code` | Claude Code |
| `gemini` | `gemini.chat` | Gemini Chat |
| `ollama` | `ollama.chat` | Ollama Chat |

### from 自动推断

按优先级: path → auth header → default

**1) Path 匹配**

| 请求 Path | 推断协议 |
|-----------|---------|
| `/v1/chat/completions` | `openai` |
| `/v1/responses` | `openai.responses` |
| `/v1/messages` | `anthropic` |
| `/v1beta/models/...` | `gemini` |

**2) Auth Header**

| Header | 推断协议 |
|--------|---------|
| `x-goog-api-key` | `gemini` |
| `x-api-key` | `anthropic` |

**3)** 默认 `openai`
