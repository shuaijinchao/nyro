# Nyro AI Gateway — 设计文档

> **目标**：将 Nyro 从 OpenResty(Lua) + Rust FFI 的服务端 API Gateway 重构为纯 Rust AI 协议网关。  
> **交付形式**：  
> - **Desktop 版**：跨平台桌面应用（Tauri v2，macOS / Windows / Linux）  
> - **Server 版**：独立二进制，可部署到服务器，通过 HTTP 访问 WebUI  
> - **License**：Apache 2.0 开源

---

## 一、产品定位

Nyro AI Gateway 是一个**本地运行**的 AI 协议代理网关桌面应用，面向 AI 开发者和重度使用者。核心价值：

- 使用 OpenAI SDK、Anthropic SDK、Gemini SDK 的**任意客户端应用**，无需改代码，只需修改 `base_url`，即可把请求路由到任意 LLM Provider
- 提供可视化的配置、路由规则、实时日志、用量统计等管理界面
- 纯 Rust 后端，单进程，启动快（<1s）、包体小（~20-30MB）、无外部运行时依赖

### 差异化定位

| 竞品 | 形态 | 痛点 |
|---|---|---|
| LiteLLM Proxy | Python 服务端部署 | 依赖重、需自行部署、不适合桌面场景 |
| One API | Go 服务端部署 | 服务端产品、配置复杂 |
| OpenRouter | SaaS 云服务 | 请求经第三方、隐私顾虑、需付额外费用 |
| **Nyro** | **本地桌面应用** | **零部署、零依赖、数据不离开本机** |

### 目标用户

- 使用多个 LLM Provider 的个人开发者（核心用户）
- 需要在多模型间灵活切换的 AI 应用开发者
- 希望统一管理 API Key 并监控用量的重度 AI 使用者

---

## 二、整体架构

### 2.1 技术栈

| 层 | 技术 | 作用 |
|---|---|---|
| 桌面壳 | **Tauri v2**（Rust） | 窗口管理、系统托盘、IPC、自动更新、打包分发 |
| 前端 | **React 19 + TypeScript + Vite 7** | 管理界面 UI（复用现有 webui 设计体系） |
| 前端状态 | **Zustand** | 全局状态管理 |
| 前端数据获取 | **TanStack Query** | IPC 请求封装、缓存、轮询 |
| 前端路由 | **React Router v7** | 页面路由 |
| UI 样式 | **Tailwind CSS 4** | 组件样式（复用现有 glass 设计风格） |
| 图表 | **Recharts** | 统计看板图表 |
| 代理服务 | **axum 0.7 + tokio** | 异步 HTTP 服务，协议入口 |
| 出口调用 | **reqwest 0.12** | 直接调用上游 Provider HTTP API |
| SSE 解析 | **eventsource-stream** | 解析上游 SSE 流 |
| 数据库 | **sqlx 0.8**（async SQLite） | 配置、日志、统计持久化 |
| 日志 | **tracing + tracing-subscriber** | 结构化日志 |
| 打包/CI | **tauri-apps/tauri-action** | 三平台自动构建发布 |

### 2.2 Cargo Workspace 分层

核心网关逻辑独立为 library crate，Desktop 版和 Server 版各自作为 binary crate 依赖它：

```
nyro/
├── Cargo.toml                    # workspace 定义
├── crates/
│   └── nyro-core/             # 核心库（lib crate）
│       ├── Cargo.toml
│       └── src/
│           ├── lib.rs            # 对外暴露 Gateway struct + 管理 API
│           ├── proxy/            # 代理面：axum router、handler、client
│           ├── protocol/         # 协议转换引擎
│           ├── router/           # 路由规则匹配
│           ├── db/               # SQLite 数据层
│           ├── logging/          # 日志采集
│           ├── crypto/           # API Key 加解密
│           └── admin/            # 管理 API（纯 Rust 函数，不绑定任何传输层）
│
├── src-tauri/                    # Desktop 版（Tauri binary）
│   ├── Cargo.toml                # 依赖 nyro-core
│   └── src/
│       ├── main.rs               # Tauri 入口
│       └── commands.rs           # Tauri IPC → 调用 nyro-core 管理 API
│
├── src-server/                   # Server 版（独立 binary）
│   ├── Cargo.toml                # 依赖 nyro-core
│   └── src/
│       ├── main.rs               # tokio 入口，启动 axum
│       └── admin_routes.rs       # HTTP REST → 调用 nyro-core 管理 API
│
└── webui/                        # 前端（共用）
```

**关键原则**：`nyro-core` 只暴露纯 Rust API（struct + async fn），不感知传输层。Desktop 版通过 Tauri IPC 调用它，Server 版通过 HTTP REST 调用它。

```
nyro-core（核心库）
├── Gateway::new(config)          → 初始化数据库、启动代理服务
├── Gateway::start_proxy()        → 启动 axum HTTP Server（代理面）
├── Gateway::admin()              → 返回 AdminService，提供全部管理操作
│   ├── .list_providers()
│   ├── .create_provider(input)
│   ├── .test_provider(id)
│   ├── .list_routes()
│   ├── .query_logs(filter)
│   ├── .get_stats_overview()
│   └── ...
└── Gateway::shutdown()           → 优雅关闭
```

### 2.3 两种部署形态

#### Desktop 版

```
Tauri v2 主进程
├── nyro-core（嵌入）
│   ├── axum :18080 ─── 代理面（对外暴露）
│   ├── SQLite + 日志采集 + 统计聚合
│   └── AdminService（纯函数）
├── Tauri IPC Commands ─── 管理面
│   └── 每个 Command 调用 AdminService 对应方法
├── WebView（React 前端）
│   └── 通过 Tauri invoke() 调 IPC Commands
├── 系统托盘
└── 自动更新
```

管理 API 通过 Tauri IPC 调用，**外部应用不可访问**。

#### Server 版

```
独立 Rust 二进制
├── nyro-core（嵌入）
│   ├── axum :18080 ─── 代理面（对外暴露）
│   ├── SQLite + 日志采集 + 统计聚合
│   └── AdminService（纯函数）
├── axum :18081 ─── 管理面（HTTP REST API）
│   ├── /api/v1/providers
│   ├── /api/v1/routes
│   ├── /api/v1/logs
│   ├── /api/v1/stats
│   ├── /api/v1/settings
│   └── 静态文件服务 → webui dist/
└── CLI 参数（--proxy-port、--admin-port、--data-dir）
```

管理 API 通过 HTTP REST 暴露，前端通过 HTTP 调用（而非 IPC）。管理端口独立于代理端口，可配置鉴权。

### 2.4 前端适配层

前端通过一个薄抽象层兼容两种部署形态：

```typescript
// webui/src/lib/backend.ts

// Desktop 版：通过 Tauri IPC 调用
async function invokeIPC<T>(cmd: string, args?: object): Promise<T> {
  const { invoke } = await import('@tauri-apps/api/core');
  return invoke<T>(cmd, args);
}

// Server 版：通过 HTTP 调用
async function invokeHTTP<T>(cmd: string, args?: object): Promise<T> {
  const resp = await fetch(`/api/v1/${cmd}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(args),
  });
  return resp.json();
}

// 运行时检测环境，自动选择调用方式
const IS_TAURI = '__TAURI_INTERNALS__' in window;
export const backend = IS_TAURI ? invokeIPC : invokeHTTP;
```

这样前端页面代码**完全不需要区分**运行环境。

### 2.5 数据面与管理面分离

```
代理面 HTTP :18080（两种版本共用，对外暴露给客户端应用）
├── POST /v1/chat/completions          ← OpenAI SDK
├── POST /v1/messages                  ← Anthropic SDK
├── POST /v1beta/models/{m}:generateContent      ← Gemini SDK
├── POST /v1beta/models/{m}:streamGenerateContent ← Gemini SDK（流式）
└── GET  /health                       ← 健康检查

管理面（传输层因版本而异）
├── Desktop 版：Tauri IPC（仅 WebView 可调用，外部不可访问）
└── Server 版：HTTP :18081 /api/v1/...（独立端口，支持 Bearer token 鉴权）
```

---

## 三、核心功能：协议代理

### 3.1 支持的入口协议

| 客户端 SDK | 入口路径 | base_url 配置 |
|---|---|---|
| OpenAI SDK | `POST /v1/chat/completions` | `http://localhost:18080/v1` |
| Anthropic SDK | `POST /v1/messages` | `http://localhost:18080` |
| Gemini SDK | `POST /v1beta/models/{model}:generateContent` | `http://localhost:18080/v1beta` |
| Gemini SDK（流式）| `POST /v1beta/models/{model}:streamGenerateContent` | 同上 |

### 3.2 支持的出口 Provider

通过 reqwest 直接调用，优先支持：

| Provider | 出口协议 | 备注 |
|---|---|---|
| OpenAI | OpenAI 格式 | gpt-4o、gpt-4o-mini 等 |
| DeepSeek | OpenAI 兼容格式 | deepseek-chat、deepseek-reasoner |
| Anthropic | Anthropic 原生格式 | claude-3-5-sonnet 等 |
| Google Gemini | Gemini 原生格式 | gemini-1.5-pro、gemini-2.0-flash 等 |
| Ollama | OpenAI 兼容格式 | 本地模型 |
| OpenAI 兼容 | OpenAI 格式 | Groq、Together、Mistral 等任意兼容 Provider |

> 大多数 Provider（DeepSeek、Ollama、Groq、Together 等）都兼容 OpenAI 格式，实际只需实现 3 套出口协议：OpenAI 格式、Anthropic 格式、Gemini 格式。

### 3.3 协议转换流程

```
客户端请求（任意协议）
  → axum 入口路由
  → Protocol Decoder（反序列化为内部统一格式）
  → Route Matcher（匹配路由规则，选择 Provider + Model）
  → Protocol Encoder（内部格式 → 目标 Provider 协议请求体）
  → reqwest 发送 HTTP 请求
  → 接收响应 / SSE 流
  → Response Encoder（Provider 响应 → 客户端期望协议格式）
  → 返回客户端

同时：日志采集器异步记录请求元数据和 token 统计
```

### 3.4 入口类型设计

**不依赖任何外部类型 crate**，自定义类型 + `#[serde(flatten)]` 透传未知字段：

```rust
// OpenAI 入口请求
#[derive(Debug, Deserialize, Serialize)]
pub struct OpenAIRequest {
    pub model: String,
    pub messages: Vec<OpenAIMessage>,
    #[serde(default)]
    pub stream: bool,
    pub temperature: Option<f64>,
    pub max_tokens: Option<u32>,
    pub top_p: Option<f64>,
    pub tools: Option<Vec<Value>>,
    pub tool_choice: Option<Value>,
    pub stream_options: Option<Value>,
    #[serde(flatten)]
    pub extra: HashMap<String, Value>,
}

// Anthropic 入口请求
#[derive(Debug, Deserialize, Serialize)]
pub struct AnthropicRequest {
    pub model: String,
    pub messages: Vec<AnthropicMessage>,
    pub max_tokens: u32,
    pub system: Option<AnthropicSystem>,
    #[serde(default)]
    pub stream: bool,
    pub temperature: Option<f64>,
    pub top_p: Option<f64>,
    pub tools: Option<Vec<Value>>,
    pub tool_choice: Option<Value>,
    #[serde(flatten)]
    pub extra: HashMap<String, Value>,
}

// Gemini 入口请求
#[derive(Debug, Deserialize, Serialize)]
pub struct GeminiRequest {
    pub contents: Vec<GeminiContent>,
    #[serde(rename = "generationConfig")]
    pub generation_config: Option<GeminiGenerationConfig>,
    pub tools: Option<Vec<Value>>,
    #[serde(rename = "systemInstruction")]
    pub system_instruction: Option<GeminiContent>,
    #[serde(flatten)]
    pub extra: HashMap<String, Value>,
}
```

> `#[serde(flatten)] pub extra` 确保：Provider 新增的任何参数自动捕获并透传，网关无需更新即可支持。

### 3.5 内部统一格式

```rust
#[derive(Debug, Clone)]
pub struct InternalRequest {
    pub messages: Vec<InternalMessage>,
    pub model: String,
    pub stream: bool,
    pub temperature: Option<f64>,
    pub max_tokens: Option<u32>,
    pub top_p: Option<f64>,
    pub tools: Option<Vec<Value>>,
    pub tool_choice: Option<Value>,
    pub source_protocol: Protocol,
    pub extra: HashMap<String, Value>,
}

#[derive(Debug, Clone)]
pub struct InternalMessage {
    pub role: Role,
    pub content: MessageContent,
    pub tool_calls: Option<Vec<Value>>,
    pub tool_call_id: Option<String>,
}

#[derive(Debug, Clone)]
pub enum MessageContent {
    Text(String),
    Blocks(Vec<ContentBlock>),
}

#[derive(Debug, Clone)]
pub enum ContentBlock {
    Text { text: String },
    Image { source: ImageSource },
    ToolUse { id: String, name: String, input: Value },
    ToolResult { tool_use_id: String, content: Value },
}

#[derive(Debug, Clone, Copy)]
pub enum Protocol {
    OpenAI,
    Anthropic,
    Gemini,
}
```

### 3.6 协议转换 trait 体系

```rust
/// 入口解码：客户端协议 → 内部格式
pub trait IngressDecoder {
    fn decode_request(&self, body: Value) -> Result<InternalRequest>;
}

/// 出口编码：内部格式 → Provider 协议请求体
pub trait EgressEncoder {
    fn encode_request(&self, req: &InternalRequest) -> Result<(Value, HeaderMap)>;
}

/// 响应解码+重编码
pub trait ResponseTranscoder {
    /// 非流式：Provider 响应 JSON → 客户端协议响应 JSON
    fn transcode_response(&self, resp: Value) -> Result<(Value, TokenUsage)>;
    /// 流式：创建状态机 encoder
    fn stream_transcoder(&self) -> Box<dyn StreamTranscoder + Send>;
}

/// 流式编码状态机
pub trait StreamTranscoder: Send {
    /// 输入一个原始 SSE data 行，输出 0~N 个重编码后的 SSE 事件
    fn process_chunk(&mut self, chunk: &str) -> Result<Vec<SseEvent>>;
    /// 流结束时输出收尾事件
    fn finish(&mut self) -> Result<Vec<SseEvent>>;
    /// 提取累积的 token 统计
    fn usage(&self) -> TokenUsage;
}
```

### 3.7 流式响应实现

#### 3.7.1 三种协议的 SSE 格式

**OpenAI 格式**：
```
data: {"id":"...","choices":[{"delta":{"content":"Hello"},"index":0}]}

data: [DONE]
```

**Anthropic 格式**（必须严格按事件序列）：
```
event: message_start
data: {"type":"message_start","message":{"id":"...","type":"message","role":"assistant","content":[],"model":"...","usage":{"input_tokens":10}}}

event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}

event: content_block_stop
data: {"type":"content_block_stop","index":0}

event: message_delta
data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":15}}

event: message_stop
data: {"type":"message_stop"}
```

**Gemini 格式**（每个 chunk 是独立完整 JSON）：
```
data: {"candidates":[{"content":{"parts":[{"text":"Hello"}],"role":"model"}}]}
```

#### 3.7.2 流式状态机设计（以 Anthropic Encoder 为例）

```rust
pub struct AnthropicStreamTranscoder {
    state: State,
    usage: TokenUsage,
    block_index: usize,
    model: String,
    request_id: String,
}

enum State {
    Init,
    InContentBlock,
    InToolUse,
    Finished,
}

impl StreamTranscoder for AnthropicStreamTranscoder {
    fn process_chunk(&mut self, openai_data: &str) -> Result<Vec<SseEvent>> {
        // "data: [DONE]" → finish()
        // 首个 chunk → 先发 message_start + content_block_start，再发 delta
        // 后续 chunk → 发 content_block_delta
        // 含 usage 的 chunk → 记录 token 统计
        // tool_calls 开始 → content_block_stop + 新的 content_block_start(tool_use)
    }

    fn finish(&mut self) -> Result<Vec<SseEvent>> {
        // content_block_stop → message_delta(usage) → message_stop
    }
}
```

#### 3.7.3 流式错误处理

| 场景 | 处理策略 |
|---|---|
| 上游返回非 200 | 不进入流式，直接返回错误 JSON |
| 流中途上游断连 | 发送协议规范的结束事件，关闭流，日志记录错误 |
| 流中途上游返回错误 | 插入错误信息到当前 chunk，发送结束事件 |
| 客户端断连 | 检测到 writer 关闭，终止上游读取，释放资源 |
| Fallback 重试 | **仅非流式支持**，流式已发出部分数据无法回退 |

#### 3.7.4 Token 统计

- **OpenAI 出口**：请求时加 `stream_options: {"include_usage": true}`，最后一个 chunk 含 `usage` 字段
- **Anthropic 出口**：`message_start` 事件含 `input_tokens`，`message_delta` 事件含 `output_tokens`
- **Gemini 出口**：最后一个 chunk 的 `usageMetadata` 字段
- 非流式：直接从响应体的 `usage` 字段读取
- 统计数据通过 channel 异步发送给日志采集器，不阻塞响应

### 3.8 Tool Calling 协议转换

三种协议的 Tool Calling 格式差异：

| | OpenAI | Anthropic | Gemini |
|---|---|---|---|
| 工具定义 | `tools: [{type: "function", function: {name, parameters}}]` | `tools: [{name, description, input_schema}]` | `tools: [{functionDeclarations: [{name, parameters}]}]` |
| 工具调用 | `tool_calls: [{id, function: {name, arguments}}]` | `content: [{type: "tool_use", id, name, input}]` | `functionCall: {name, args}` |
| 结果返回 | `{role: "tool", tool_call_id, content}` | `{role: "user", content: [{type: "tool_result", tool_use_id, content}]}` | `{functionResponse: {name, response}}` |

转换策略：以 OpenAI 格式为内部中间格式，入口解码时将 Anthropic/Gemini 的 tool 格式映射到 OpenAI 格式，出口编码时再映射回目标 Provider 格式。

---

## 四、数据库设计（SQLite）

数据库文件：`~/.nyro/gateway.db`，启用 WAL 模式。

### 4.1 表结构

```sql
PRAGMA journal_mode = WAL;
PRAGMA busy_timeout = 5000;

-- Provider 配置
CREATE TABLE providers (
    id          TEXT PRIMARY KEY,
    name        TEXT NOT NULL,
    protocol    TEXT NOT NULL,            -- openai / anthropic / gemini（决定出口编码方式）
    base_url    TEXT NOT NULL,            -- API 地址
    api_key     TEXT NOT NULL,            -- 加密存储
    is_active   INTEGER DEFAULT 1,
    priority    INTEGER DEFAULT 0,
    created_at  TEXT DEFAULT (datetime('now')),
    updated_at  TEXT DEFAULT (datetime('now'))
);

-- 路由规则
CREATE TABLE routes (
    id                TEXT PRIMARY KEY,
    name              TEXT NOT NULL,
    match_pattern     TEXT NOT NULL,       -- 匹配规则：精确 "gpt-4o" 或通配 "gpt-*" 或兜底 "*"
    target_provider   TEXT NOT NULL REFERENCES providers(id),
    target_model      TEXT NOT NULL,       -- 实际发给 Provider 的模型名
    fallback_provider TEXT REFERENCES providers(id),
    fallback_model    TEXT,
    is_active         INTEGER DEFAULT 1,
    priority          INTEGER DEFAULT 0,   -- 越小越优先
    created_at        TEXT DEFAULT (datetime('now'))
);

-- 请求日志
CREATE TABLE request_logs (
    id                TEXT PRIMARY KEY,
    created_at        TEXT DEFAULT (datetime('now')),
    ingress_protocol  TEXT,                -- openai / anthropic / gemini
    egress_protocol   TEXT,                -- openai / anthropic / gemini
    request_model     TEXT,                -- 客户端请求的模型名
    actual_model      TEXT,                -- 实际调用的模型名
    provider_name     TEXT,
    status_code       INTEGER,
    duration_ms       REAL,
    input_tokens      INTEGER DEFAULT 0,
    output_tokens     INTEGER DEFAULT 0,
    is_stream         INTEGER DEFAULT 0,
    is_tool_call      INTEGER DEFAULT 0,
    error_message     TEXT,
    request_preview   TEXT,                -- 请求体前 500 字符
    response_preview  TEXT                 -- 响应前 500 字符
);

CREATE INDEX idx_logs_created_at ON request_logs(created_at);
CREATE INDEX idx_logs_provider ON request_logs(provider_name);
CREATE INDEX idx_logs_status ON request_logs(status_code);
CREATE INDEX idx_logs_model ON request_logs(actual_model);

-- 按小时聚合统计（后台定时任务生成）
CREATE TABLE stats_hourly (
    hour                TEXT,
    provider            TEXT,
    model               TEXT,
    request_count       INTEGER DEFAULT 0,
    error_count         INTEGER DEFAULT 0,
    total_input_tokens  INTEGER DEFAULT 0,
    total_output_tokens INTEGER DEFAULT 0,
    avg_duration_ms     REAL DEFAULT 0,
    PRIMARY KEY (hour, provider, model)
);

-- 模型列表（自动发现 + 手动添加）
CREATE TABLE models (
    id          TEXT PRIMARY KEY,
    provider_id TEXT NOT NULL REFERENCES providers(id) ON DELETE CASCADE,
    model_name  TEXT NOT NULL,            -- 模型标识，如 gpt-4o、claude-3-5-sonnet
    display_name TEXT,                    -- 可选显示名称
    is_custom   INTEGER DEFAULT 0,       -- 0=自动发现、1=手动添加
    created_at  TEXT DEFAULT (datetime('now')),
    UNIQUE(provider_id, model_name)
);

-- 系统配置（K-V）
CREATE TABLE settings (
    key        TEXT PRIMARY KEY,
    value      TEXT NOT NULL,
    updated_at TEXT DEFAULT (datetime('now'))
);
```

### 4.2 默认配置项

| key | 默认值 | 说明 |
|---|---|---|
| `gateway_port` | `18080` | 代理监听端口 |
| `gateway_auth_key` | `""` | 代理鉴权 Key（空=不鉴权） |
| `log_retention_days` | `30` | 日志保留天数 |
| `default_model` | `""` | 无匹配路由时的兜底模型 |
| `default_provider` | `""` | 兜底 Provider |
| `auto_start` | `false` | 开机自启 |

---

## 五、路由规则匹配

### 5.1 匹配逻辑

1. 从数据库加载所有 `is_active=1` 的路由规则，按 `priority` 升序排列
2. 用客户端请求中的 `model` 字段依次匹配规则的 `match_pattern`
3. 匹配方式：精确匹配 > 通配符匹配（`*` 匹配任意字符序列）> 兜底规则（`*`）
4. 命中第一条规则，取其 `target_provider` + `target_model`
5. 若无匹配规则，使用系统设置中的默认 Provider + Model
6. 调用失败（非流式）且有 `fallback_provider` 时，切换到备用 Provider 重试一次

### 5.2 路由缓存

路由规则缓存在内存中，通过管理 API 修改路由规则后立即刷新缓存，无需重启代理服务。

---

## 六、日志采集

### 6.1 异步 channel + 批量写入

```
请求处理线程                    日志采集后台任务
     │                              │
     ├── log_tx.send(LogEntry) ──→ │ channel buffer (cap: 1024)
     │                              │
     │                              ├── buffer.len() >= 64 → batch INSERT
     │                              ├── interval 2s tick   → batch INSERT
     │                              └── 循环
```

日志写入不阻塞请求处理，channel 满时（1024）丢弃最旧的条目，避免背压。

### 6.2 日志清理

后台定时任务（每小时执行一次）：
- 删除超过 `log_retention_days` 的 `request_logs` 记录
- 删除超过 90 天的 `stats_hourly` 记录

---

## 七、前端页面设计

### 7.1 页面列表

```
/                    → 重定向到 /dashboard
/dashboard           → 统计看板
/providers           → Provider 管理
/models              → 模型列表（自动发现 + 手动配置）
/routes              → 路由规则管理
/playground          → 调试面板（内置对话测试）
/logs                → 请求日志
/settings            → 系统设置
```

### 7.2 复用策略

从现有 webui 复用：
- **设计体系**：glass morphism 风格、圆角卡片、Tailwind 配置、color palette
- **布局组件**：`AppLayout`（左侧导航 + 主内容区）、`Sidebar`（改导航项）、`Header`
- **通用模式**：`QueryClient` 配置、`ErrorBoundary`、`formatNum` 等工具函数
- **图表模式**：Recharts 配置、表格样式

需要重写的部分：
- 导航项（从 API Gateway 资源改为 AI Gateway 页面）
- 全部页面组件（业务实体完全不同）
- API 调用层（改为 `backend()` 抽象层，自动适配 Tauri IPC / HTTP，见 2.4 节）

### 7.3 各页面功能

#### Dashboard（统计看板）
- 顶部 4 张指标卡片：今日总请求数 / 今日 Token 消耗（input+output）/ 错误率 / 平均响应时延
- 折线图：过去 7 天每小时请求量趋势
- 饼图：按 Provider 分布
- 柱状图：按入口协议分布（OpenAI / Anthropic / Gemini）
- 表格：Top Models（请求数、token 数）
- 最近 10 条请求日志（5s 轮询）

#### Providers（Provider 管理）
- Provider 列表（卡片形式）：名称、协议类型 badge、状态开关、最近请求数、平均延迟
- 新增/编辑 Provider 对话框：名称、协议类型（openai/anthropic/gemini）、Base URL、API Key（显示为 `****`）
- "测试连通性"按钮：发一条测试请求，实时显示结果（成功/失败+耗时+返回的模型列表）
- 启用/禁用开关
- 每个 Provider 卡片展开后显示健康趋势：近 24 小时的延迟和错误率迷你图

#### Models（模型列表）
- 汇总展示所有 Provider 下可用的模型，表格形式
- 每行显示：模型名、所属 Provider、协议类型、是否已配置路由、累计请求数、累计 Token
- 支持"拉取模型列表"按钮（对 OpenAI 兼容 Provider 调用 `GET /v1/models`，对 Ollama 调用 `GET /api/tags`）
- 手动添加模型（用于不支持自动发现的 Provider）
- 快捷操作：点击某个模型可一键创建路由规则

#### Routes（路由规则）
- 路由规则列表（可拖拽排序调整优先级）
- 每条规则显示：模型匹配模式 → Provider/Model、Fallback 配置、启用状态
- 新增/编辑路由规则对话框
- 优先级说明提示
- 路由测试：输入一个模型名，实时显示会匹配到哪条规则

#### Playground（调试面板）
- 内置对话界面，用于验证网关是否正常工作
- 顶部选择：入口协议（OpenAI / Anthropic / Gemini）+ 模型名
- 对话区域：发消息 → 通过网关代理 → 显示响应
- 支持流式输出实时显示
- 右侧面板显示本次请求的元数据：实际路由到的 Provider/Model、延迟、Token 用量、请求/响应原始 JSON
- 切换"原始模式"：直接编辑请求 JSON 发送，查看原始响应 JSON

#### Logs（请求日志）
- 日志表格：时间、入口协议、出口协议、请求模型、实际模型、Provider、状态码、耗时、Input Tokens、Output Tokens、是否流式、是否 Tool Call
- 顶部筛选栏：入口协议、Provider、模型、状态（success/error）、时间范围
- 点击某条日志展开详情面板：
  - 请求/响应 JSON 预览（格式化高亮）
  - 错误信息（如有）
  - 耗时分解（如果可追踪：路由匹配时间 + 上游响应时间）
- 分页（每页 20 条）
- 导出日志（CSV / JSON）

#### Settings（系统设置）
- **连接信息**（最显眼位置）
  - 网关端口（修改需重启代理）
  - 三种协议的 base_url 示例 + 对应 SDK 代码片段 + 一键复制按钮
  ```
  OpenAI SDK:
    base_url = "http://localhost:18080/v1"

  Anthropic SDK:
    base_url = "http://localhost:18080"

  Gemini SDK:
    base_url = "http://localhost:18080/v1beta"
  ```
- **安全**
  - 网关代理鉴权 Key（留空=不鉴权）
  - 管理 API 鉴权 Key（Server 版专用）
- **数据**
  - 日志保留天数
  - 默认兜底 Provider + Model
  - 导出/导入配置（JSON 格式，含 providers + routes + settings）
  - 数据目录路径显示
- **桌面**（Desktop 版专用，Server 版隐藏）
  - 开机自启动
  - 最小化到托盘
  - 检查更新
- **外观**
  - 深色/浅色模式切换

### 7.4 全局 UI 元素
- 左侧固定导航栏（复用现有 Sidebar glass 风格）
- 顶部显示网关运行状态指示灯（绿色=运行中 / 红色=异常 / 灰色=未启动）+ 当前监听端口
- 系统托盘（Desktop 版）：显示网关状态、快速开关代理、退出应用
- 首次启动引导：选择常用 Provider → 填 API Key → 拉取模型列表 → 自动生成默认路由
- 深色/浅色模式支持
- 全局键盘快捷键：`Cmd/Ctrl+K` 打开命令面板（快速跳转页面、搜索模型、搜索日志）

---

## 八、API Key 安全

- API Key 在写入 SQLite 前使用 AES-256-GCM 加密
- 加密密钥从操作系统密钥链获取：
  - macOS: Keychain
  - Windows: Credential Manager
  - Linux: Secret Service
- 通过 `tauri-plugin-stronghold` 或 `keyring` crate 实现
- 调用上游 Provider 时，将解密后的 API Key 直接通过 `reqwest` 的 `Authorization` header 传递，**不注入环境变量**
- 前端展示时显示为 `sk-****...****`（前 4 位 + 后 4 位）

---

## 九、目录结构

```
nyro/
├── Cargo.toml                          # Workspace 定义
│
├── crates/
│   └── nyro-core/                   # 核心库（lib crate，不感知传输层）
│       ├── Cargo.toml
│       ├── migrations/                 # sqlx 数据库迁移
│       │   └── 001_init.sql
│       └── src/
│           ├── lib.rs                  # 对外暴露 Gateway + AdminService
│           ├── config.rs              # GatewayConfig 配置结构
│           │
│           ├── proxy/                  # 代理面
│           │   ├── mod.rs
│           │   ├── server.rs          # axum Router 注册（代理路由）
│           │   ├── handler.rs         # 请求处理主流程
│           │   ├── client.rs          # reqwest 出口 HTTP 调用
│           │   └── auth.rs           # 代理鉴权中间件
│           │
│           ├── protocol/               # 协议转换引擎
│           │   ├── mod.rs             # trait 定义 + Protocol enum
│           │   ├── types.rs           # InternalRequest/Response/Message
│           │   ├── openai/
│           │   │   ├── mod.rs
│           │   │   ├── types.rs       # OpenAI 请求/响应结构体
│           │   │   ├── decoder.rs     # OpenAI 入口解码
│           │   │   ├── encoder.rs     # OpenAI 出口编码
│           │   │   └── stream.rs      # OpenAI SSE 流式状态机
│           │   ├── anthropic/
│           │   │   ├── mod.rs
│           │   │   ├── types.rs
│           │   │   ├── decoder.rs
│           │   │   ├── encoder.rs
│           │   │   └── stream.rs      # Anthropic SSE 流式状态机（最复杂）
│           │   └── gemini/
│           │       ├── mod.rs
│           │       ├── types.rs
│           │       ├── decoder.rs
│           │       ├── encoder.rs
│           │       └── stream.rs
│           │
│           ├── router/                 # 路由规则匹配
│           │   ├── mod.rs
│           │   └── matcher.rs         # 通配符匹配 + 优先级排序 + 缓存
│           │
│           ├── admin/                  # 管理 API（纯 Rust 函数，不绑定传输层）
│           │   ├── mod.rs             # AdminService struct
│           │   ├── providers.rs       # Provider CRUD
│           │   ├── routes.rs          # 路由规则 CRUD
│           │   ├── logs.rs            # 日志查询
│           │   ├── stats.rs           # 统计查询
│           │   └── settings.rs        # 系统设置
│           │
│           ├── db/                     # 数据层
│           │   ├── mod.rs             # sqlx pool 初始化
│           │   └── models.rs          # 表模型 + 查询/写入
│           │
│           ├── logging/                # 日志采集
│           │   └── collector.rs       # channel + 批量 flush + 定时清理
│           │
│           └── crypto/                 # API Key 加解密
│               └── mod.rs
│
├── src-tauri/                          # Desktop 版（Tauri binary）
│   ├── Cargo.toml                     # 依赖 nyro-core + tauri
│   ├── tauri.conf.json
│   ├── icons/
│   └── src/
│       ├── main.rs                    # Tauri 入口，setup 中初始化 Gateway
│       └── commands.rs               # IPC Commands → 调用 AdminService
│
├── src-server/                         # Server 版（独立 binary）
│   ├── Cargo.toml                     # 依赖 nyro-core + axum + tower-http
│   └── src/
│       ├── main.rs                    # CLI 解析、启动 Gateway + 管理 HTTP
│       └── admin_routes.rs           # HTTP REST Router → 调用 AdminService
│
├── webui/                              # React 前端（Desktop / Server 共用）
│   ├── package.json
│   ├── vite.config.ts
│   ├── tsconfig.json
│   ├── src/
│   │   ├── main.tsx                   # 入口
│   │   ├── index.css                  # Tailwind + glass 样式
│   │   ├── lib/
│   │   │   ├── backend.ts            # 抽象层：自动选择 IPC / HTTP
│   │   │   └── utils.ts              # 工具函数
│   │   ├── store/                     # Zustand store
│   │   │   └── gateway.ts
│   │   ├── components/
│   │   │   ├── layout/
│   │   │   │   ├── app-layout.tsx    # 复用现有布局
│   │   │   │   ├── sidebar.tsx       # 修改导航项
│   │   │   │   └── header.tsx        # 复用
│   │   │   ├── status-badge.tsx
│   │   │   ├── provider-card.tsx
│   │   │   └── log-detail-panel.tsx
│   │   └── pages/
│   │       ├── dashboard.tsx
│   │       ├── providers.tsx
│   │       ├── routes.tsx
│   │       ├── logs.tsx
│   │       └── settings.tsx
│   └── public/
│       └── assets/
│
├── .github/
│   └── workflows/
│       ├── ci.yml                     # PR lint + test
│       └── release.yml                # Desktop: tauri-action 三平台
│       └── release-server.yml         # Server: cargo build 三平台
│
├── README.md
├── CONTRIBUTING.md
└── LICENSE                            # Apache 2.0
```

---

## 十、关键实现细节

### 10.1 Tauri 内嵌 axum

```rust
// src-tauri/src/main.rs
fn main() {
    tauri::Builder::default()
        .plugin(tauri_plugin_autostart::init(/* ... */))
        .plugin(tauri_plugin_updater::Builder::new().build())
        .plugin(tauri_plugin_single_instance::init(|_, _, _| {}))
        .setup(|app| {
            let state = AppState::init(app.handle()).await?;

            // spawn axum server
            let proxy_state = state.clone();
            tokio::spawn(async move {
                let port = proxy_state.settings.gateway_port();
                let router = proxy::server::create_router(proxy_state);
                let listener = tokio::net::TcpListener::bind(
                    format!("127.0.0.1:{}", port)
                ).await.expect("port bindable");
                axum::serve(listener, router).await.ok();
            });

            // spawn 日志采集后台任务
            tokio::spawn(logging::collector::run(state.clone()));

            // spawn 统计聚合定时任务
            tokio::spawn(stats::aggregation::run(state.clone()));

            app.manage(state);
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            commands::providers::get_providers,
            commands::providers::create_provider,
            commands::providers::update_provider,
            commands::providers::delete_provider,
            commands::providers::test_provider,
            commands::routes::get_routes,
            commands::routes::create_route,
            commands::routes::update_route,
            commands::routes::delete_route,
            commands::routes::reorder_routes,
            commands::logs::query_logs,
            commands::logs::get_log_detail,
            commands::stats::get_overview,
            commands::stats::get_hourly,
            commands::stats::get_by_provider,
            commands::stats::get_by_model,
            commands::settings::get_settings,
            commands::settings::update_settings,
            commands::settings::export_config,
            commands::settings::import_config,
            commands::gateway::get_status,
        ])
        .system_tray(/* ... */)
        .run(tauri::generate_context!())
        .expect("error running app");
}
```

### 10.2 nyro-core 核心库入口

```rust
// crates/nyro-core/src/lib.rs

pub struct Gateway {
    db: SqlitePool,
    http_client: reqwest::Client,
    route_cache: Arc<RwLock<RouteCache>>,
    log_tx: mpsc::Sender<LogEntry>,
    config: GatewayConfig,
}

impl Gateway {
    /// 初始化数据库、连接池、路由缓存
    pub async fn new(config: GatewayConfig) -> Result<Self> { ... }

    /// 启动代理 HTTP Server（阻塞，需 tokio::spawn）
    pub async fn start_proxy(&self) -> Result<()> {
        let router = proxy::server::create_router(self.clone());
        let listener = bind_with_fallback(self.config.proxy_port).await;
        axum::serve(listener, router).await?;
        Ok(())
    }

    /// 启动后台任务（日志采集、统计聚合、日志清理）
    pub fn spawn_background_tasks(&self) {
        tokio::spawn(logging::collector::run(self.log_rx(), self.db.clone()));
        tokio::spawn(stats::aggregation::run(self.db.clone()));
    }

    /// 获取管理服务（纯函数接口，不绑定传输层）
    pub fn admin(&self) -> AdminService { AdminService::new(self) }

    /// 获取运行状态
    pub fn status(&self) -> GatewayStatus { ... }
}

/// 管理 API — 纯 Rust 接口
pub struct AdminService { ... }

impl AdminService {
    pub async fn list_providers(&self) -> Result<Vec<Provider>> { ... }
    pub async fn create_provider(&self, input: CreateProvider) -> Result<Provider> { ... }
    pub async fn update_provider(&self, id: &str, input: UpdateProvider) -> Result<Provider> { ... }
    pub async fn delete_provider(&self, id: &str) -> Result<()> { ... }
    pub async fn test_provider(&self, id: &str) -> Result<TestResult> { ... }

    pub async fn list_routes(&self) -> Result<Vec<Route>> { ... }
    pub async fn create_route(&self, input: CreateRoute) -> Result<Route> { ... }
    pub async fn reorder_routes(&self, ids: Vec<String>) -> Result<()> { ... }
    pub async fn test_route_match(&self, model: &str) -> Result<RouteMatch> { ... }

    pub async fn list_models(&self) -> Result<Vec<Model>> { ... }
    pub async fn fetch_provider_models(&self, provider_id: &str) -> Result<Vec<String>> { ... }

    pub async fn playground_chat(&self, input: PlaygroundInput) -> Result<PlaygroundOutput> { ... }
    // ... 日志、统计、设置同理
}
```

### 10.3 Desktop 版入口（src-tauri）

```rust
// src-tauri/src/main.rs
use nyro_gateway::{Gateway, GatewayConfig};

fn main() {
    tauri::Builder::default()
        .setup(|app| {
            let config = GatewayConfig::from_data_dir(app.path().app_data_dir()?);
            let gateway = Gateway::new(config).await?;
            gateway.spawn_background_tasks();

            let gw = gateway.clone();
            tokio::spawn(async move { gw.start_proxy().await });

            app.manage(gateway);
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            commands::get_providers,
            commands::create_provider,
            // ...
        ])
        .run(tauri::generate_context!())
        .unwrap();
}

// src-tauri/src/commands.rs — 薄包装层
#[tauri::command]
async fn get_providers(gw: State<'_, Gateway>) -> Result<Vec<Provider>, String> {
    gw.admin().list_providers().await.map_err(|e| e.to_string())
}

#[tauri::command]
async fn create_provider(gw: State<'_, Gateway>, input: CreateProvider) -> Result<Provider, String> {
    gw.admin().create_provider(input).await.map_err(|e| e.to_string())
}
// 每个 command 都是一行调用，无业务逻辑
```

### 10.4 Server 版入口（src-server）

```rust
// src-server/src/main.rs
use nyro_gateway::{Gateway, GatewayConfig};
use clap::Parser;

#[derive(Parser)]
struct Args {
    #[arg(long, default_value = "18080")]
    proxy_port: u16,
    #[arg(long, default_value = "18081")]
    admin_port: u16,
    #[arg(long, default_value = "~/.nyro")]
    data_dir: PathBuf,
    #[arg(long)]
    admin_key: Option<String>,
}

#[tokio::main]
async fn main() {
    let args = Args::parse();
    let config = GatewayConfig {
        proxy_port: args.proxy_port,
        data_dir: args.data_dir,
        ..Default::default()
    };

    let gateway = Gateway::new(config).await.unwrap();
    gateway.spawn_background_tasks();

    // 启动代理面
    let gw = gateway.clone();
    tokio::spawn(async move { gw.start_proxy().await });

    // 启动管理面（HTTP REST + 静态文件）
    let admin_router = admin_routes::create_router(gateway, args.admin_key)
        .fallback_service(tower_http::services::ServeDir::new("./webui/dist"));

    let listener = tokio::net::TcpListener::bind(
        format!("0.0.0.0:{}", args.admin_port)
    ).await.unwrap();

    println!("Proxy  → http://127.0.0.1:{}", args.proxy_port);
    println!("WebUI  → http://127.0.0.1:{}", args.admin_port);

    axum::serve(listener, admin_router).await.unwrap();
}
```

```rust
// src-server/src/admin_routes.rs
pub fn create_router(gateway: Gateway, admin_key: Option<String>) -> Router {
    let api = Router::new()
        .route("/providers", get(list_providers).post(create_provider))
        .route("/providers/{id}", put(update_provider).delete(delete_provider))
        .route("/providers/{id}/test", post(test_provider))
        .route("/routes", get(list_routes).post(create_route))
        .route("/routes/reorder", put(reorder_routes))
        .route("/logs", get(query_logs))
        .route("/stats/overview", get(stats_overview))
        .route("/stats/hourly", get(stats_hourly))
        .route("/settings", get(get_settings).put(update_settings))
        .with_state(gateway);

    // 可选鉴权
    let api = if let Some(key) = admin_key {
        api.layer(/* bearer token auth middleware */)
    } else {
        api
    };

    Router::new().nest("/api/v1", api)
}

async fn list_providers(State(gw): State<Gateway>) -> impl IntoResponse {
    Json(gw.admin().list_providers().await.unwrap())
}
// 同样每个 handler 都是一行调用
```

### 10.5 代理请求处理主流程

```rust
// crates/nyro-core/src/proxy/handler.rs
pub async fn handle_proxy_request(
    ingress_protocol: Protocol,
    body: Value,
    state: AppState,
) -> Result<Response, AppError> {
    // 1. 入口解码
    let decoder = get_decoder(ingress_protocol);
    let internal_req = decoder.decode_request(body)?;

    // 2. 路由匹配
    let route = state.router.match_route(&internal_req.model)?;
    let provider = state.db.get_provider(&route.target_provider).await?;
    let api_key = state.crypto.decrypt(&provider.api_key)?;

    // 3. 出口编码
    let egress_protocol = provider.protocol.parse::<Protocol>()?;
    let encoder = get_encoder(egress_protocol);
    let (outbound_body, extra_headers) = encoder.encode_request(&internal_req)?;

    // 4. 确定 transcoder（入口协议 + 出口协议 → 选择响应转换器）
    let transcoder = get_transcoder(ingress_protocol, egress_protocol);

    if internal_req.stream {
        // 5a. 流式调用
        let stream = state.client.call_stream(
            &provider.base_url, &api_key, outbound_body, extra_headers
        ).await?;

        let mut stream_transcoder = transcoder.stream_transcoder();
        let log_tx = state.log_tx.clone();
        let sse_stream = transform_sse_stream(stream, stream_transcoder, log_tx);

        Ok(Response::builder()
            .header("content-type", "text/event-stream")
            .header("cache-control", "no-cache")
            .body(Body::from_stream(sse_stream))?)
    } else {
        // 5b. 非流式调用
        let resp = state.client.call(
            &provider.base_url, &api_key, outbound_body, extra_headers
        ).await;

        match resp {
            Ok(resp_json) => {
                let (encoded, usage) = transcoder.transcode_response(resp_json)?;
                state.log_tx.send(LogEntry::success(/* ... */, usage)).ok();
                Ok(Json(encoded).into_response())
            }
            Err(e) if route.fallback_provider.is_some() => {
                // Fallback 重试（仅非流式）
                let fb = state.db.get_provider(&route.fallback_provider.unwrap()).await?;
                let fb_key = state.crypto.decrypt(&fb.api_key)?;
                let fb_protocol = fb.protocol.parse::<Protocol>()?;
                let fb_encoder = get_encoder(fb_protocol);
                let (fb_body, fb_headers) = fb_encoder.encode_request(&internal_req)?;
                let fb_transcoder = get_transcoder(ingress_protocol, fb_protocol);
                let fb_resp = state.client.call(
                    &fb.base_url, &fb_key, fb_body, fb_headers
                ).await?;
                let (encoded, usage) = fb_transcoder.transcode_response(fb_resp)?;
                state.log_tx.send(LogEntry::fallback(/* ... */, usage)).ok();
                Ok(Json(encoded).into_response())
            }
            Err(e) => {
                state.log_tx.send(LogEntry::error(/* ... */)).ok();
                Err(e.into())
            }
        }
    }
}
```

### 10.3 端口冲突处理

```rust
async fn bind_with_fallback(preferred: u16) -> (TcpListener, u16) {
    match TcpListener::bind(format!("127.0.0.1:{}", preferred)).await {
        Ok(listener) => (listener, preferred),
        Err(_) => {
            // 尝试随机端口
            let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
            let port = listener.local_addr().unwrap().port();
            tracing::warn!("port {} in use, using {}", preferred, port);
            (listener, port)
        }
    }
}
```

实际绑定端口通过 `Gateway::status()` 返回，Desktop 版经 IPC 传给前端，Server 版经 HTTP 传给前端。

---

## 十一、CI/CD

### release.yml（Desktop 版）

```yaml
on:
  push:
    tags: ['v*']

jobs:
  desktop:
    strategy:
      matrix:
        include:
          - os: ubuntu-latest
            target: x86_64-unknown-linux-gnu
          - os: macos-latest
            target: x86_64-apple-darwin
          - os: macos-latest
            target: aarch64-apple-darwin
          - os: windows-latest
            target: x86_64-pc-windows-msvc
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - uses: pnpm/action-setup@v4
      - uses: actions/setup-node@v4
      - uses: dtolnay/rust-toolchain@stable
      - name: Install frontend deps
        run: cd webui && pnpm install
      - name: Build Tauri App
        uses: tauri-apps/tauri-action@v0
        with:
          tagName: ${{ github.ref_name }}
          releaseName: 'Nyro v__VERSION__'
          releaseDraft: true
```

### release-server.yml（Server 版）

```yaml
on:
  push:
    tags: ['v*']

jobs:
  server:
    strategy:
      matrix:
        include:
          - os: ubuntu-latest
            target: x86_64-unknown-linux-gnu
          - os: macos-latest
            target: x86_64-apple-darwin
          - os: macos-latest
            target: aarch64-apple-darwin
          - os: windows-latest
            target: x86_64-pc-windows-msvc
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - uses: pnpm/action-setup@v4
      - uses: actions/setup-node@v4
      - uses: dtolnay/rust-toolchain@stable
        with:
          targets: ${{ matrix.target }}
      - name: Build WebUI
        run: cd webui && pnpm install && pnpm build
      - name: Build Server Binary
        run: cargo build --release --package nyro-server --target ${{ matrix.target }}
      - name: Package
        run: |
          mkdir -p release/nyro-server
          cp target/${{ matrix.target }}/release/nyro-server release/nyro-server/
          cp -r webui/dist release/nyro-server/webui
          tar czf nyro-server-${{ matrix.target }}.tar.gz -C release nyro-server
      - name: Upload to Release
        uses: softprops/action-gh-release@v2
        with:
          files: nyro-server-*.tar.gz
          draft: true
```

---

## 十二、首次启动引导

```
Step 1: 欢迎页
  "Nyro 是一个本地 AI 协议网关，帮你统一管理所有 LLM 服务"
  [开始配置]

Step 2: 选择 Provider
  ☑ OpenAI    ☐ Anthropic    ☐ Google Gemini
  ☑ DeepSeek  ☐ Ollama       ☐ 自定义
  [下一步]

Step 3: 填入 API Key（每个选中的 Provider 一个输入框）
  OpenAI API Key:   sk-***
  DeepSeek API Key: sk-***
  [测试连通性] → 实时显示每个 Provider 的测试结果
  [下一步]

Step 4: 自动生成默认路由
  "已为你创建以下路由规则："
  gpt-*     → OpenAI / gpt-4o
  deepseek-*→ DeepSeek / deepseek-chat
  *         → OpenAI / gpt-4o （兜底）
  [完成配置]

Step 5: 显示 base_url
  "配置完成！在你的 AI 应用中使用以下地址："
  OpenAI SDK:    http://localhost:18080/v1       [复制]
  Anthropic SDK: http://localhost:18080           [复制]
  Gemini SDK:    http://localhost:18080/v1beta    [复制]
```

---

## 十三、自动更新

使用 `tauri-plugin-updater`：

- 更新源：GitHub Releases
- 检查频率：每次启动 + 每 24 小时
- 用户确认后下载并安装
- `tauri.conf.json` 中配置 updater endpoint

---

## 十四、实现阶段

### Phase 1 — 核心代理（2~3 周）
- [ ] Cargo workspace 初始化（nyro-core + src-tauri + src-server）
- [ ] nyro-core：Gateway struct、SQLite 数据库 + 迁移
- [ ] nyro-core：OpenAI 入口 + OpenAI 兼容出口（最常见路径）
- [ ] nyro-core：流式 + 非流式代理
- [ ] nyro-core：Provider CRUD + 路由规则匹配（AdminService）
- [ ] src-tauri：Tauri 入口 + IPC Commands
- [ ] webui：基础前端（Provider 管理 + 路由管理 + Settings）+ backend 抽象层

### Phase 2 — 多协议（1~2 周）
- [ ] Anthropic 入口协议（含完整 SSE 事件序列）
- [ ] Anthropic 出口协议
- [ ] Gemini 入口协议
- [ ] Gemini 出口协议
- [ ] Tool Calling 三协议转换

### Phase 3 — 可观测性（1~2 周）
- [ ] 日志采集 channel + 批量写入
- [ ] 请求日志页面
- [ ] 统计聚合定时任务
- [ ] Dashboard 统计看板
- [ ] 日志清理

### Phase 4 — 桌面体验（1 周）
- [ ] 系统托盘
- [ ] 开机自启（tauri-plugin-autostart）
- [ ] 自动更新（tauri-plugin-updater）
- [ ] 单实例（tauri-plugin-single-instance）
- [ ] 首次启动引导
- [ ] 配置导入/导出
- [ ] API Key 加密存储

### Phase 5 — Server 版（1 周）
- [ ] src-server：CLI 参数解析（clap）
- [ ] src-server：管理面 HTTP REST Router
- [ ] src-server：静态文件服务（webui dist/）
- [ ] src-server：管理 API Bearer token 鉴权
- [ ] webui：验证 backend 抽象层 HTTP 模式

### Phase 6 — CI/CD + 发布
- [ ] GitHub Actions Desktop 版三平台构建
- [ ] GitHub Actions Server 版三平台构建
- [ ] 自动发布到 GitHub Releases
- [ ] README + 架构图 + 快速上手文档

### 后续可选
- [ ] Fallback 重试（非流式）
- [ ] 限流/熔断
- [ ] 多模态完整支持（图像/PDF）
- [ ] 语义缓存
- [ ] WebSocket 实时日志推送（替代轮询）
- [ ] Docker 镜像（Server 版）

---

## 十五、Rust 依赖清单

### 根 Cargo.toml（workspace）

```toml
[workspace]
resolver = "2"
members = ["crates/nyro-core", "src-tauri", "src-server"]

[workspace.dependencies]
tokio = { version = "1", features = ["full"] }
axum = { version = "0.7", features = ["macros"] }
reqwest = { version = "0.12", features = ["stream", "json", "rustls-tls"] }
tower-http = { version = "0.6", features = ["cors", "trace"] }
sqlx = { version = "0.8", features = ["runtime-tokio", "sqlite"] }
serde = { version = "1", features = ["derive"] }
serde_json = "1"
tracing = "0.1"
tracing-subscriber = { version = "0.3", features = ["env-filter"] }
uuid = { version = "1", features = ["v4", "serde"] }
chrono = { version = "0.4", features = ["serde"] }
```

### crates/nyro-core/Cargo.toml

```toml
[package]
name = "nyro-core"
version = "0.1.0"
edition = "2021"

[dependencies]
tokio = { workspace = true }
axum = { workspace = true }
reqwest = { workspace = true }
tower-http = { workspace = true }
sqlx = { workspace = true }
serde = { workspace = true }
serde_json = { workspace = true }
tracing = { workspace = true }
uuid = { workspace = true }
chrono = { workspace = true }

eventsource-stream = "0.2"
async-stream = "0.3"
tokio-stream = "0.1"
futures = "0.3"
glob-match = "0.2"
aes-gcm = "0.10"
keyring = "3"
```

### src-tauri/Cargo.toml

```toml
[package]
name = "nyro-desktop"
version = "0.1.0"
edition = "2021"

[dependencies]
nyro-core = { path = "../crates/nyro-core" }
tauri = { version = "2", features = ["tray-icon"] }
tauri-plugin-autostart = "2"
tauri-plugin-updater = "2"
tauri-plugin-single-instance = "2"
tokio = { workspace = true }
serde = { workspace = true }
serde_json = { workspace = true }
tracing-subscriber = { workspace = true }
```

### src-server/Cargo.toml

```toml
[package]
name = "nyro-server"
version = "0.1.0"
edition = "2021"

[dependencies]
nyro-core = { path = "../crates/nyro-core" }
tokio = { workspace = true }
axum = { workspace = true }
tower-http = { workspace = true, features = ["cors", "trace", "fs"] }
serde = { workspace = true }
serde_json = { workspace = true }
tracing-subscriber = { workspace = true }
clap = { version = "4", features = ["derive"] }
```

---

## 十六、开源信息

- **License**：Apache 2.0
- **目标社区**：AI 开发者、LLM 重度使用者
- **交付物**：
  - `nyro-desktop` — 桌面安装包（.dmg / .exe / .AppImage）
  - `nyro-server` — 独立二进制 + webui 静态文件（可部署到服务器）
  - Docker 镜像（后续）
- **README 包含**：架构图、30 秒快速上手（Desktop + Server 两种方式）、支持协议矩阵、支持 Provider 列表、贡献指南
