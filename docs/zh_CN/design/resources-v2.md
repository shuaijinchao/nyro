# Nyro 统一资源设计 v2

> 目标: 一套资源模型同时覆盖 API 网关和 AI 网关场景。
> 范围: 第一版 AI 能力仅支持 Chat 类型的 3x3 (OpenAI / Anthropic / Gemini 入口 x 出口)。

---

## 1. 设计原则

1. **不发明新资源** — AI 场景复用已有的 consumers / routes / services / backends 四种资源。
2. **AI 特性下沉到 service** — `provider` 字段是唯一判断"这是不是 AI 服务"的标志；路由和后端保持协议无关。
3. **插件只做插件的事** — `ai-proxy` 只负责协议转换；认证、限流等仍由各自插件处理。
4. **逐层可选** — 最简配置只需 route + service；随着需求增长逐步加入 consumer 和 backend。

---

## 2. 资源总览

```
consumers ──┐
             ├── routes ──── services ──┬── (url 直连)
             │       │                  └── backends (负载均衡)
             │       │
             │       └── plugins: [key-auth, ai-proxy, limit-req, ...]
```

| 资源 | 职责 | AI 场景新增字段 |
|------|------|----------------|
| consumers | 客户端身份 + 凭证 | 无变化 |
| routes | 流量入口: path, method, host, plugins | `hosts` (新增) |
| services | 上游逻辑抽象: url/backend, timeout | `provider`, `scheme` |
| backends | 物理节点池: endpoints, algorithm | `endpoints[].headers` |

---

## 3. 各资源详细定义

### 3.1 Consumers (无变化)

```yaml
consumers:
  - name: "web-client"
    credentials:
      key-auth:
        key: "nyro-sk-web-001"

  - name: "mobile-client"
    credentials:
      key-auth:
        key: "nyro-sk-mobile-002"
```

说明:
- 与现有实现完全一致，不做任何改动。
- consumer 只管"你是谁"，与后端是 AI 还是 HTTP 无关。

---

### 3.2 Backends

```yaml
backends:
  - name: "openai-pool"
    algorithm: roundrobin          # 保持现有字段名
    timeout:
      connect: 5000
      read: 120000                 # AI 场景建议 120s
      send: 5000
    endpoints:
      - address: "api.openai.com"
        port: 443
        weight: 100
        headers:                   # [新增] 节点级请求头 (用于 API Key 轮换)
          Authorization: "Bearer sk-key-A-xxxxx"
      - address: "api.openai.com"
        port: 443
        weight: 100
        headers:
          Authorization: "Bearer sk-key-B-xxxxx"
```

变更说明:

| 字段 | 状态 | 说明 |
|------|------|------|
| `algorithm` | 保持 | 现有字段，不改名 |
| `endpoints[].address` | 保持 | 现有字段 |
| `endpoints[].port` | 保持 | 现有字段 |
| `endpoints[].weight` | 保持 | 现有字段 |
| `endpoints[].headers` | **新增** | map 类型，balancer 选中节点后注入到请求头 |

实现要点:
- `backend.prepare_upstream()` 在 **http_access 阶段** 完成节点选择 + DNS 解析 + headers 注入。
- 注意: `ngx.req.set_header()` 在 `balancer_by_lua*` 阶段 **不可用**，因此必须在 access 阶段完成。
- balancer 阶段 (`gogogo`) 仅执行 `set_current_peer()`，从 `oak_ctx._upstream` 读取预选结果。
- 普通 HTTP 场景同样可用（如多个认证不同的后端节点）。

---

### 3.3 Services

```yaml
services:
  # ---- AI 服务 ----
  - name: "anthropic-claude"
    provider: anthropic            # [新增] AI provider 标识
    url: "https://api.anthropic.com"
    timeout:
      connect: 5000
      read: 120000
      send: 5000

  - name: "openai-direct"
    provider: openai
    url: "https://api.openai.com"

  - name: "openai-balanced"
    provider: openai
    scheme: https                  # [新增] backend 模式下必须显式指定 scheme
    backend: "openai-pool"         # 引用 backend 做负载均衡

  - name: "gemini-direct"
    provider: gemini
    url: "https://generativelanguage.googleapis.com"

  # ---- 普通 HTTP 服务 (无 provider) ----
  - name: "httpbin"
    url: "http://httpbin.org"
```

变更说明:

| 字段 | 状态 | 说明 |
|------|------|------|
| `name` | 保持 | |
| `url` | 保持 | Base URL，与 `backend` 二选一。scheme 从 URL 中解析 |
| `backend` | 保持 | 引用 backends 资源名 |
| `scheme` | **新增** | 可选，默认 `http`。backend 模式下 URL 不存在无法推断 scheme，需显式指定。url 模式下自动从 URL 解析，无需手动填 |
| `timeout` | 保持 | |
| `provider` | **新增** | 可选。不填 = 普通 HTTP；填写 = AI 服务 |

`provider` 枚举值 (第一版):

| 值 | 对应 llm-converter Protocol | 默认 upstream path |
|----|---------------------------|--------------------|
| `openai` | `openai_chat` | `/v1/chat/completions` |
| `anthropic` | `anthropic_messages` | `/v1/messages` |
| `gemini` | `gemini_chat` | 非流式: `/v1beta/models/{model}:generateContent`<br>流式: `/v1beta/models/{model}:streamGenerateContent?alt=sse` |

设计决策:
- **service 不管认证头** — API Key、anthropic-version 等全部由 ai-proxy 插件注入。service 只负责"地址在哪 + 超时多久"。
- **provider 是语义标签** — 告诉 ai-proxy 目标协议是什么，由插件自动推导 path、headers、认证方式。
- **无 provider 的 service 就是普通 HTTP** — 完全走现有逻辑，ai-proxy 插件不介入。
- **scheme 在 backend 模式下需显式指定** — 所有 AI Provider 都使用 HTTPS，如果只用 `url` 直连 scheme 可从 URL 解析；使用 `backend` 时无 URL 可解析，必须在 service 上声明 `scheme: https`。

---

### 3.4 Routes

```yaml
routes:
  # ---- AI 路由 (host + path 联合匹配) ----
  - name: "chat-to-claude"
    hosts: ["claude.ai.example.com"]      # [新增] 支持域名匹配
    service: "anthropic-claude"
    paths:
      - "/v1/chat/completions"
    methods: ["POST"]
    plugins:
      - id: key-auth
      - id: ai-proxy
        config:
          api_key: "sk-ant-xxxxx"
          model: "claude-sonnet-4-20250514"

  - name: "chat-to-openai"
    hosts: ["openai.ai.example.com"]
    service: "openai-direct"
    paths:
      - "/v1/chat/completions"            # 相同 path，不同 host 区分路由
    methods: ["POST"]
    plugins:
      - id: ai-proxy
        config:
          api_key: "sk-openai-xxxxx"

  - name: "chat-to-gemini"
    hosts: ["gemini.ai.example.com"]
    service: "gemini-direct"
    paths:
      - "/v1/chat/completions"
    methods: ["POST"]
    plugins:
      - id: ai-proxy
        config:
          api_key: "AIzaSy-xxxxx"
          model: "gemini-2.0-flash"

  # ---- 不使用 host 区分时，用不同 path ----
  - name: "chat-to-gemini-alt"
    service: "gemini-direct"
    paths:
      - "/ai/gemini/chat"
    methods: ["POST"]
    plugins:
      - id: ai-proxy
        config:
          api_key: "AIzaSy-xxxxx"
          model: "gemini-2.0-flash"

  # ---- 普通 HTTP 路由 (无 ai-proxy 插件) ----
  - name: "http-debug"
    service: "httpbin"
    paths:
      - "/anything/*"
    plugins:
      - id: limit-req
        config:
          rate: 10
          burst: 5
```

变更说明:

| 字段 | 状态 | 说明 |
|------|------|------|
| `name, paths, methods, service` | 保持 | |
| `hosts` | **新增** | 可选，域名数组。不填则匹配所有域名。支持 `host + path` 联合路由 |
| `plugins[].id` | **统一** | 用 `id` 而非 `name`，与现有 `run_plugin` 一致 |
| `plugins[].config` | **统一** | 嵌套 config 对象，替代之前的 flat/override 混用 |

`hosts` 匹配规则:
- 精确匹配: `["api.example.com"]`
- 支持多值: `["api.example.com", "api2.example.com"]` 匹配其中任意一个
- 省略时匹配所有域名 (向后兼容)
- 匹配来源: `ngx.var.host` (即请求 Host 头)

ai-proxy 插件配置 (`plugins[].config`):

| 字段 | 必填 | 说明 |
|------|------|------|
| `api_key` | 否 | Provider API Key。backend endpoint.headers 可替代 |
| `to` | 否 | 上游协议。不填则从 `service.provider` 自动推导 |
| `from` | 否 | 客户端协议。不填则按 path 自动推断 |
| `model` | 否 | 覆盖客户端请求中的 model |
| `upstream_path` | 否 | 覆盖 provider 默认 path |
| `max_tokens` | 否 | 覆盖最大 token 数 |
| `temperature` | 否 | 覆盖温度 |

插件配置格式 (嵌套 config):

```yaml
plugins:
  - id: ai-proxy
    config:           # 业务配置与 id 等元信息分离
      api_key: "sk-xxx"
      model: "gpt-4o"
```

设计决策: `id` / `enabled` 等元信息在外层，业务配置在 `config` 中。避免字段名冲突，便于扩展 `enabled: false` 等元信息。

设计决策:
- **路由不需要 `type` 字段** — 是否走 AI 逻辑由"service 有没有 provider"和"有没有挂 ai-proxy 插件"共同决定。
- **不同 Provider 用不同 path** — 避免路由冲突。`/v1/chat/completions` 可以作为默认 OpenAI 兼容入口，其他 Provider 用 `/ai/{provider}/chat`。
- **api_key 放在 route 插件配置** — 而非 service，因为同一个 service 可能被多条 route 共用（不同 key 权限不同）。

---

## 4. 三种典型场景配置

### 场景 A: 最简 — 单后端直连 (routes + services)

```yaml
services:
  - name: "openai"
    provider: openai
    url: "https://api.openai.com"

routes:
  - name: "chat"
    service: "openai"
    paths: ["/v1/chat/completions"]
    methods: ["POST"]
    plugins:
      - id: ai-proxy
        config:
          api_key: "sk-xxxxx"
```

资源数: 1 service + 1 route。客户端发 OpenAI 格式到 `/v1/chat/completions`，直通 OpenAI。

---

### 场景 B: 带认证 + 协议转换 (consumers + routes + services)

```yaml
consumers:
  - name: "app-client"
    credentials:
      key-auth:
        key: "nyro-sk-001"

services:
  - name: "claude"
    provider: anthropic
    url: "https://api.anthropic.com"

routes:
  - name: "chat-claude"
    service: "claude"
    paths: ["/v1/chat/completions"]
    methods: ["POST"]
    plugins:
      - id: key-auth
      - id: ai-proxy
        config:
          api_key: "sk-ant-xxxxx"
          model: "claude-sonnet-4-20250514"
```

客户端用 OpenAI 格式 + Nyro API Key 访问，网关自动转为 Anthropic 格式转发。

---

### 场景 C: 认证 + 多后端负载均衡 (consumers + routes + services + backends)

```yaml
consumers:
  - name: "premium-client"
    credentials:
      key-auth:
        key: "nyro-sk-premium-001"

backends:
  - name: "openai-keys"
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
  - name: "openai-ha"
    provider: openai
    scheme: https                  # backend 模式，显式指定 HTTPS
    backend: "openai-keys"

routes:
  - name: "chat-openai"
    service: "openai-ha"
    paths: ["/v1/chat/completions"]
    methods: ["POST"]
    plugins:
      - id: key-auth
      - id: ai-proxy
        config: {}            # backend endpoints 已含 API Key，此处无需 api_key
```

注意: 当 backend endpoint 有 `headers.Authorization` 时，ai-proxy 不再注入 `api_key` header。优先级: **endpoint headers > plugin api_key**。

---

## 5. 请求处理流程

```
客户端请求 (OpenAI/Anthropic/Gemini 格式)
    │
    ▼
┌─────────────────────────────────────────────────────────┐
│ route.match(host, path, method)                         │
│   → 匹配路由 (支持 hosts + path 联合), 获取 service      │
└─────────────────────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────────────────────┐
│ http_access 阶段 (框架层)                                │
│                                                         │
│ prepare_upstream:                                       │
│   service.url → DNS 解析 → 存入 oak_ctx._upstream       │
│   service.backend → roundrobin 选节点 → DNS 解析         │
│                   → 注入 endpoint.headers                │
│                   → 存入 oak_ctx._upstream               │
│                                                         │
│ 设置 nginx 变量:                                        │
│   upstream_scheme = oak_ctx._upstream.scheme             │
│   upstream_host   = oak_ctx._upstream.host               │
│   upstream_uri    = matched.uri                          │
└─────────────────────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────────────────────┐
│ http_access 阶段 (插件层, 接收嵌套 plugin config)        │
│                                                         │
│ 1. [key-auth]    验证客户端 API Key                      │
│ 2. [ai-proxy]    读取 body                              │
│                  推断 from (按 path 或配置)               │
│                  获取 to (按 service.provider)             │
│                  FFI convert_request (source → target)    │
│                  ngx.req.set_body_data(converted)        │
│                  注入 target 协议 auth headers            │
│                  改写 upstream_uri (target 默认 path)     │
│ 3. [limit-req]   限流检查                                │
└─────────────────────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────────────────────┐
│ http_balancer 阶段                                      │
│                                                         │
│ 仅执行 set_current_peer + set_timeouts                  │
│ (节点已在 access 阶段预选, 从 oak_ctx._upstream 读取)     │
└─────────────────────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────────────────────┐
│ proxy_pass $upstream_scheme://nyro_backend$upstream_uri  │
│ Host: $upstream_host                                    │
└─────────────────────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────────────────────┐
│ http_header_filter 阶段                                 │
│                                                         │
│ [ai-proxy]  SSE: Content-Type: text/event-stream        │
│             清除 Content-Length (body 将被改写)           │
└─────────────────────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────────────────────┐
│ http_body_filter 阶段                                   │
│                                                         │
│ [ai-proxy]  非流式: 缓冲 → eof → FFI convert_response   │
│             流式:   逐行扫描 data: → FFI convert → flush │
└─────────────────────────────────────────────────────────┘
    │
    ▼
客户端收到响应 (原始协议格式)
```

---

## 6. 协议转换矩阵 (第一版 3x3)

客户端入口协议由 route path 或 `from` 配置决定。
目标协议由 `service.provider` 或 `to` 决定。

| 入口 ＼ 出口 | OpenAI | Anthropic | Gemini |
|-------------|--------|-----------|--------|
| **OpenAI** (客户端用 OpenAI SDK) | 透传 (不转换) | FFI 转换 | FFI 转换 |
| **Anthropic** (客户端用 Claude SDK) | FFI 转换 | 透传 | FFI 转换 |
| **Gemini** (客户端用 Gemini SDK) | FFI 转换 | FFI 转换 | 透传 |

### 协议名格式

用户配置 `from` / `to` 时支持三种写法:

| 格式 | 示例 | 说明 |
|------|------|------|
| **短名** (推荐) | `openai` | 使用 provider 默认能力 |
| 点号展开 | `openai.chat` | 指定具体能力 |
| 内部名 | `openai_chat` | 向后兼容 llm-converter 标识 |

完整映射:

| 短名 | 点号展开 | 内部名 |
|------|---------|--------|
| `openai` | `openai.chat` | `openai_chat` |
| — | `openai.responses` | `openai_responses` |
| `anthropic` | `anthropic.messages` | `anthropic_messages` |
| — | `anthropic.code` | `claude_code` |
| `gemini` | `gemini.chat` | `gemini_chat` |
| `ollama` | `ollama.chat` | `ollama_chat` |

from 自动推断规则 (按优先级: path → auth header → default):

**1) Path 匹配**

| 路由 path | 推断协议 |
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

to 推断规则:

| service.provider | 映射 Protocol | 默认 upstream path |
|------------------|--------------|-------------------|
| `openai` | `openai_chat` | `/v1/chat/completions` |
| `anthropic` | `anthropic_messages` | `/v1/messages` |
| `gemini` | `gemini_chat` | 非流式: `/v1beta/models/{model}:generateContent`<br>流式: `/v1beta/models/{model}:streamGenerateContent?alt=sse` |

---

## 7. 认证注入策略

所有 Provider 统一使用请求头注入认证信息:

| Provider | 认证方式 | 注入位置 |
|----------|---------|---------|
| openai | `Authorization: Bearer {key}` | 请求头 |
| anthropic | `x-api-key: {key}` + `anthropic-version: 2023-06-01` | 请求头 |
| gemini | `x-goog-api-key: {key}` | 请求头 |

设计决策:
- **Gemini 不使用 URL query param** — 虽然 Gemini 同时支持 `?key=` 和 `x-goog-api-key` 头部，统一用头部有两个好处:
  1. 三家 Provider 认证逻辑完全一致: 全部是 header 注入，不需要 Gemini 的 URL query param 特殊分支
  2. API Key 不会泄漏到 access log 的 URL 中

Key 来源优先级:
1. **endpoint.headers** (backend 节点级) — 最高优先，适用于多 Key 轮换
2. **plugin config.api_key** (route 级) — 次之，适用于单 Key 直连
3. 若都没有 → 报错 500

---

## 8. 与现有代码的兼容性

| 模块 | 状态 | 说明 |
|------|------|------|
| `store/adapter/yaml.lua` | 无需改动 | 已支持 services, backends, routes, consumers, plugins |
| `route/init.lua` | **已改** | 1) `build_router` 遍历 `route.hosts` 注册路由；2) handler 存储完整 service 对象；3) backend upstream 携带 `service.scheme` |
| `backend/init.lua` | **已改** | 1) `generate_backend_balancer` 保留 `endpoint_details` (含 headers)；2) 新增 `prepare_upstream()`: access 阶段选节点 + DNS + 注入 headers；3) `gogogo` 简化为仅 `set_current_peer` |
| `nyro.lua` | **已改** | 1) 调用 `prepare_upstream` 替代 `check_backend`；2) 框架层设置 `upstream_scheme` / `upstream_host`；3) `run_plugin` 传递嵌套 `plugins[].config` |
| `plugin/ai-proxy/handler.lua` | **已改** | 1) 直接使用 `plugin_config` 参数 (嵌套 config)；2) 从 `service.provider` 推导 `to`；3) Gemini 认证改为 `x-goog-api-key` 头部；4) Gemini 流式路径 `streamGenerateContent?alt=sse`；5) `api_key` 可选 |
| `plugin/ai-proxy/schema.lua` | **已改** | `to` 可选 (从 provider 推导)；`from` 可选 (按 path 自动推断)；`api_key` 可选 (endpoint.headers 替代)；新增 `max_tokens`, `temperature` |
| `conf/config.yaml` | **已改** | 更新示例为嵌套 config 格式，覆盖 A/B/C/D 四种场景 |
| nginx_conf.lua 模板 | 已完成 | `proxy_buffering off` 已添加 |

---

## 9. 未来扩展 (不在 v1 范围)

- **多模态**: Embeddings / Image / Audio — 扩展 `provider` 映射表
- **model 白名单/映射**: route 级 `allowed_models` / `model_mapping`
- **Token 计量**: 通过 Rust FFI 在 body_filter 阶段统计
- **Fallback**: service 级 `fallback_service` 字段，上游 5xx 时自动切换
- **错误响应转换**: 非 200 响应的跨协议格式适配
- **流式 Token 计费**: SSE chunk 级的增量 token 统计
