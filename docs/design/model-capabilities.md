# 模型能力识别与 CLI 接入配置生成

**Nyro Gateway · 产品开发文档**

---

## 1. 功能概述

Nyro 在路由配置和 CLI 接入两个场景中，需要感知模型的能力（是否支持工具、是否支持推理、上下文大小、输入输出类型等），以便：

- 路由选择模型时展示能力标签，辅助用户选择
- 转发请求时根据模型能力自动处理不兼容字段（如剥离 tools）
- CLI 接入页根据模型能力动态生成正确的工具配置

数据来源通过 **Provider 配置** 中的 `modelsSource` 和 `capabilitiesSource` 字段声明式指定，支持两类值：

| 值类型 | 示例 | 说明 |
|--------|------|------|
| HTTP URL | `https://api.openai.com/v1/models` | 直接向 HTTP 端点请求数据 |
| 内部协议 | `ai://models.dev/openai` | 从 Nyro 内嵌 / 缓存的 models.dev 数据中查询 |

---

## 2. 内部协议设计

### 2.1 协议格式

```
ai://{source}/{key}
```

| 部分 | 说明 | 示例 |
|------|------|------|
| `ai://` | 协议前缀，标识为 Nyro 内部数据源 | — |
| `{source}` | 数据源标识符 | `models-dev` |
| `{key}` | 数据源内的查询键 | `openai`、`google`、`deepseek` |

> `{source}` 和 `{key}` 使用 URI authority + path 方式组织，Rust `url::Url` 可正常解析。
> 字段名（`modelsSource` / `capabilitiesSource`）已表达用途，协议中不再编码 action 类型。

### 2.2 当前支持的数据源

| URI | 说明 |
|-----|------|
| `ai://models.dev/{vendor-key}` | 从内嵌 models.dev 快照或运行时缓存中查询指定厂商的模型列表和能力 |
| `ai://models.dev/` | 不指定厂商，进入全局模式：模型列表聚合所有厂商，能力按用户输入模型名做全局匹配 |

**预留扩展**（暂不实现）：

| URI | 说明 |
|-----|------|
| `ai://huggingface/{namespace}` | 从 HuggingFace 模型库查询 |
| `ai://custom-registry/{key}` | 自定义模型注册中心 |

### 2.3 解析逻辑

```rust
enum ResolvedSource {
    Http(String),           // "https://..." → 直接请求
    ModelsDev(String),      // "ai://models.dev/{key}" → 查内嵌数据
    Auto,                   // 空值 → 自动匹配模式
}

fn parse_source(uri: &str) -> ResolvedSource {
    if uri.is_empty() {
        ResolvedSource::Auto
    } else if uri.eq_ignore_ascii_case("ai://models.dev") {
        ResolvedSource::ModelsDev(String::new())
    } else if let Some(key) = uri.strip_prefix("ai://models.dev/") {
        ResolvedSource::ModelsDev(key.to_string())
    } else {
        ResolvedSource::Http(uri.to_string())
    }
}

/// 判断 HTTP URL 是否为 Ollama /api/show 能力查询端点
fn is_ollama_show_endpoint(url: &str) -> bool {
    url.trim_end_matches('/').ends_with("/api/show")
}
```

---

## 3. Provider 预设配置（providers.json）

### 3.1 从代码中抽离

当前 `providerPresets` 硬编码在 `webui/src/pages/providers.tsx` 中。改为独立 JSON 文件，前后端共享：

**文件路径**：`assets/providers.json`

- 编译时通过 `include_str!` 打包进后端二进制
- 前端通过 `import` 或 fetch 加载
- 新增/删除 Provider 只需编辑 JSON，无需变更代码

### 3.2 数据结构

```typescript
type ProviderProtocol = "openai" | "anthropic" | "gemini";

type ProviderEndpoint = {
  id: string;
  label: { zh: string; en: string };
  tags?: string[];                                      // ["global"] | ["china"] | ["china", "coding-plan"]
  baseUrls: Partial<Record<ProviderProtocol, string>>;
  modelsSource?: string;                                // 模型列表来源
  capabilitiesSource?: string;                          // 模型能力来源
  staticModels?: string[];                              // 静态模型列表（无 API 时的硬编码兜底）
};

type ProviderPreset = {
  id: string;
  label: { zh: string; en: string };
  icon?: string;                                        // 图标标识，用于页面渲染
  defaultProtocol: ProviderProtocol;
  supportedProtocols?: ProviderProtocol[];              // 该厂商支持的协议列表
  endpoints: ProviderEndpoint[];
};
```

### 3.3 完整配置示例

```json
[
  {
    "id": "custom",
    "label": { "zh": "自定义", "en": "Custom" },
    "defaultProtocol": "openai",
    "endpoints": []
  },
  {
    "id": "openai",
    "label": { "zh": "OpenAI", "en": "OpenAI" },
    "icon": "openai",
    "defaultProtocol": "openai",
    "endpoints": [
      {
        "id": "default",
        "label": { "zh": "默认", "en": "Default" },
        "baseUrls": {
          "openai": "https://api.openai.com/v1"
        },
        "modelsSource": "https://api.openai.com/v1/models",
        "capabilitiesSource": "ai://models.dev/openai"
      }
    ]
  },
  {
    "id": "anthropic",
    "label": { "zh": "Anthropic", "en": "Anthropic" },
    "icon": "anthropic",
    "defaultProtocol": "anthropic",
    "endpoints": [
      {
        "id": "default",
        "label": { "zh": "默认", "en": "Default" },
        "baseUrls": {
          "anthropic": "https://api.anthropic.com"
        },
        "modelsSource": "https://api.anthropic.com/v1/models",
        "capabilitiesSource": "ai://models.dev/anthropic"
      }
    ]
  },
  {
    "id": "google",
    "label": { "zh": "Google", "en": "Google" },
    "icon": "google",
    "defaultProtocol": "openai",
    "endpoints": [
      {
        "id": "default",
        "label": { "zh": "默认", "en": "Default" },
        "baseUrls": {
          "openai": "https://generativelanguage.googleapis.com/v1beta/openai",
          "gemini": "https://generativelanguage.googleapis.com"
        },
        "modelsSource": "https://generativelanguage.googleapis.com/v1beta/models",
        "capabilitiesSource": "ai://models.dev/google"
      }
    ]
  },
  {
    "id": "xai",
    "label": { "zh": "xAI", "en": "xAI" },
    "icon": "xai",
    "defaultProtocol": "openai",
    "endpoints": [
      {
        "id": "default",
        "label": { "zh": "默认", "en": "Default" },
        "baseUrls": {
          "openai": "https://api.x.ai/v1"
        },
        "modelsSource": "https://api.x.ai/v1/models",
        "capabilitiesSource": "ai://models.dev/xai"
      }
    ]
  },
  {
    "id": "deepseek",
    "label": { "zh": "DeepSeek", "en": "DeepSeek" },
    "icon": "deepseek",
    "defaultProtocol": "openai",
    "endpoints": [
      {
        "id": "default",
        "label": { "zh": "默认", "en": "Default" },
        "baseUrls": {
          "openai": "https://api.deepseek.com/v1",
          "anthropic": "https://api.deepseek.com/anthropic"
        },
        "modelsSource": "https://api.deepseek.com/v1/models",
        "capabilitiesSource": "ai://models.dev/deepseek"
      }
    ]
  },
  {
    "id": "kimi",
    "label": { "zh": "Kimi", "en": "Kimi" },
    "icon": "kimi",
    "defaultProtocol": "openai",
    "endpoints": [
      {
        "id": "default",
        "label": { "zh": "国际站", "en": "Global" },
        "tags": ["global"],
        "baseUrls": {
          "openai": "https://api.moonshot.ai/v1",
          "anthropic": "https://api.moonshot.ai/anthropic"
        },
        "modelsSource": "https://api.moonshot.ai/v1/models"
      },
      {
        "id": "china",
        "label": { "zh": "中国站", "en": "China" },
        "tags": ["china"],
        "baseUrls": {
          "openai": "https://api.moonshot.cn/v1",
          "anthropic": "https://api.moonshot.cn/anthropic"
        },
        "modelsSource": "https://api.moonshot.cn/v1/models"
      }
    ]
  },
  {
    "id": "minimax",
    "label": { "zh": "MiniMax", "en": "MiniMax" },
    "icon": "minimax",
    "defaultProtocol": "openai",
    "endpoints": [
      {
        "id": "default",
        "label": { "zh": "国际站", "en": "Global" },
        "tags": ["global"],
        "baseUrls": {
          "openai": "https://api.minimax.io/v1",
          "anthropic": "https://api.minimax.io/anthropic"
        },
        "modelsSource": "ai://models.dev/minimax",
        "capabilitiesSource": "ai://models.dev/minimax"
      },
      {
        "id": "china",
        "label": { "zh": "中国站", "en": "China" },
        "tags": ["china"],
        "baseUrls": {
          "openai": "https://api.minimaxi.com/v1",
          "anthropic": "https://api.minimaxi.com/anthropic"
        },
        "modelsSource": "ai://models.dev/minimax",
        "capabilitiesSource": "ai://models.dev/minimax"
      }
    ]
  },
  {
    "id": "zhipu",
    "label": { "zh": "智谱", "en": "Zhipu" },
    "icon": "zhipu",
    "defaultProtocol": "openai",
    "endpoints": [
      {
        "id": "default",
        "label": { "zh": "国际站", "en": "Global" },
        "tags": ["global"],
        "baseUrls": {
          "openai": "https://api.z.ai/api/paas/v4",
          "anthropic": "https://api.z.ai/api/anthropic"
        },
        "modelsSource": "https://api.z.ai/api/paas/v4/models",
        "capabilitiesSource": "ai://models.dev/zhipuai"
      },
      {
        "id": "china",
        "label": { "zh": "中国站", "en": "China" },
        "tags": ["china"],
        "baseUrls": {
          "openai": "https://open.bigmodel.cn/api/paas/v4",
          "anthropic": "https://open.bigmodel.cn/api/anthropic"
        },
        "modelsSource": "https://open.bigmodel.cn/api/paas/v4/models",
        "capabilitiesSource": "ai://models.dev/zhipuai"
      }
    ]
  },
  {
    "id": "nvidia",
    "label": { "zh": "NVIDIA", "en": "NVIDIA" },
    "icon": "nvidia",
    "defaultProtocol": "openai",
    "endpoints": [
      {
        "id": "default",
        "label": { "zh": "默认", "en": "Default" },
        "baseUrls": {
          "openai": "https://integrate.api.nvidia.com/v1"
        },
        "modelsSource": "https://integrate.api.nvidia.com/v1/models"
      }
    ]
  },
  {
    "id": "openrouter",
    "label": { "zh": "OpenRouter", "en": "OpenRouter" },
    "icon": "openrouter",
    "defaultProtocol": "openai",
    "endpoints": [
      {
        "id": "default",
        "label": { "zh": "默认", "en": "Default" },
        "baseUrls": {
          "openai": "https://openrouter.ai/api/v1",
          "anthropic": "https://openrouter.ai/api"
        },
        "modelsSource": "https://openrouter.ai/api/v1/models",
        "capabilitiesSource": "https://openrouter.ai/api/v1/models"
      }
    ]
  },
  {
    "id": "ollama",
    "label": { "zh": "Ollama", "en": "Ollama" },
    "icon": "ollama",
    "defaultProtocol": "openai",
    "endpoints": [
      {
        "id": "default",
        "label": { "zh": "默认", "en": "Default" },
        "baseUrls": {
          "openai": "http://127.0.0.1:11434/v1"
        },
        "modelsSource": "http://127.0.0.1:11434/v1/models",
        "capabilitiesSource": "http://127.0.0.1:11434/api/show"
      }
    ]
  }
]
```

**关键设计说明：**

- `capabilitiesSource` 使用 `ai://models.dev/{key}` 时，`{key}` 直接对应 models.dev 的 vendor key（如 `google` 而非 `gemini`），**在配置层面消除了 vendor 别名映射需求**
- 当 `capabilitiesSource` 设为 `ai://models.dev/`（或 `ai://models.dev`）时，按用户输入模型名在 models.dev 缓存中全局匹配，不要求预先指定 vendor key
- MiniMax 等无 models API 的厂商，`modelsSource` 和 `capabilitiesSource` 均指向 `ai://models.dev/minimax`，同一数据源同时提供模型列表和能力数据
- Kimi、NVIDIA 等不在 models.dev 中的厂商，不设 `capabilitiesSource`，走自动匹配模式（见第 5 节）
- Ollama 的 `modelsSource` 使用 OpenAI 兼容接口 `/v1/models`，`capabilitiesSource` 使用原生接口 `/api/show`
- OpenRouter 的 `modelsSource` 和 `capabilitiesSource` 指向同一 URL，因为该 API 同时返回列表和能力数据

---

## 4. 数据来源详述

### 4.1 models.dev（公有云模型）

**数据地址：** `https://models.dev/api.json`

**数据格式：**

```json
{
  "anthropic": {
    "id": "anthropic",
    "name": "Anthropic",
    "models": {
      "claude-opus-4-5-20251101": {
        "id": "claude-opus-4-5-20251101",
        "name": "Claude Opus 4.5",
        "reasoning": true,
        "tool_call": true,
        "attachment": true,
        "modalities": {
          "input": ["text", "image", "pdf"],
          "output": ["text"]
        },
        "cost": {
          "input": 5.0,
          "output": 25.0
        },
        "limit": {
          "context": 200000,
          "output": 64000
        }
      }
    }
  }
}
```

**内嵌与缓存：**

| 层级 | 文件 | 说明 |
|------|------|------|
| 编译时内嵌 | `assets/models.dev.json` | `include_str!` 打包进二进制，保证离线可用 |
| 运行时缓存 | `{data_dir}/models.dev.json` | 启动后异步刷新，TTL 24h，失败不报错 |

> 实现状态（2026-03-18）：上述两层均已落地；启动时异步刷新 `models.dev`，24h 内复用本地缓存，刷新失败自动回退到本地缓存或内嵌快照。

```rust
const MODELS_DEV_SNAPSHOT: &str = include_str!("../assets/models.dev.json");
```

**缓存优先级：**

```
运行时缓存（最新，TTL 内有效）
        ↓ 不存在或已过期
打包内嵌快照（保底）
```

> Desktop 版缓存路径使用 Tauri `app_data_dir()`，Server 版使用 `GatewayConfig.data_dir`。

### 4.2 Ollama（本地模型）

**模型发现接口：** `GET http://{host}/v1/models`（OpenAI 兼容端点）

```json
{
  "object": "list",
  "data": [
    { "id": "llama3.2:1b", "object": "model", "created": 1773223293, "owned_by": "library" },
    { "id": "gemma3:1b", "object": "model", "created": 1773222216, "owned_by": "library" },
    { "id": "qwen3.5:0.8b", "object": "model", "created": 1773216943, "owned_by": "library" }
  ]
}
```

**能力查询接口：** `POST http://{host}/api/show`

请求体：`{"name": "qwen3.5:0.8b"}`

```json
{
  "capabilities": ["completion", "vision", "tools", "thinking"],
  "model_info": {
    "general.architecture": "qwen35",
    "qwen35.context_length": 262144
  }
}
```

**capabilities 字段映射：**

| capabilities 值 | 对应能力 |
|----------------|---------|
| `tools` | 支持工具调用 |
| `thinking` | 支持推理 |
| `vision` | 支持图像输入 |
| `completion` | 支持文本补全（基础能力） |

**context_length 提取规则：**

```rust
fn extract_context_length(model_info: &Map<String, Value>) -> Option<u64> {
    let arch = model_info.get("general.architecture")?.as_str()?;
    let key = format!("{}.context_length", arch);
    model_info.get(&key)?.as_u64()
}
```

> Ollama 能力查询需逐模型 POST，可在模型发现后批量请求并缓存。

### 4.3 OpenRouter（聚合模型）

**接口：** `GET https://openrouter.ai/api/v1/models`

该 API 同时返回模型列表和能力数据，一次请求覆盖 `modelsSource` 和 `capabilitiesSource` 两个用途。

**响应格式（单条模型）：**

```json
{
  "id": "openai/gpt-3.5-turbo",
  "name": "OpenAI: GPT-3.5 Turbo",
  "context_length": 16385,
  "architecture": {
    "input_modalities": ["text"],
    "output_modalities": ["text"]
  },
  "pricing": {
    "prompt": "0.0000005",
    "completion": "0.0000015"
  },
  "top_provider": {
    "max_completion_tokens": 4096
  },
  "supported_parameters": [
    "tools", "tool_choice", "temperature", "max_tokens"
  ]
}
```

**字段映射规则：**

| 目标字段 | OpenRouter 来源 | 备注 |
|---------|----------------|------|
| `model_id` | `id` | 含厂商前缀如 `openai/gpt-3.5-turbo` |
| `context_window` | `context_length` | — |
| `output_max_tokens` | `top_provider.max_completion_tokens` | — |
| `tool_call` | `supported_parameters` 含 `"tools"` | — |
| `reasoning` | 按模型 ID 推断，兜底 `false` | OpenRouter 无显式字段 |
| `input_modalities` | `architecture.input_modalities` | — |
| `output_modalities` | `architecture.output_modalities` | — |
| `input_cost` | `pricing.prompt` × 1,000,000 | 换算为 $/M |
| `output_cost` | `pricing.completion` × 1,000,000 | 换算为 $/M |

---

## 5. DB 字段变更与 Rust 结构

### 5.1 字段命名变更

| DB 字段 | 变更 | 说明 |
|---------|------|------|
| `models_endpoint` | → **`models_source`** | 不再只是 HTTP endpoint，可存 `ai://` 内部协议 URI |
| `channel` | 保持不变 | "部署渠道" 语义准确，与 providers.json 的 `endpoints` 是不同层级概念 |
| — | 新增 **`capabilities_source`** | 模型能力数据来源 |

### 5.2 DB 迁移

```rust
// db/mod.rs migrate() 中新增
ensure_provider_column(pool, "models_source", "TEXT").await?;
ensure_provider_column(pool, "capabilities_source", "TEXT").await?;
backfill_models_source(pool).await?;  // 从 models_endpoint 迁移
```

```rust
async fn backfill_models_source(pool: &SqlitePool) -> anyhow::Result<()> {
    if column_exists(pool, "providers", "models_source").await?
        && column_exists(pool, "providers", "models_endpoint").await?
    {
        sqlx::query(
            "UPDATE providers SET models_source = models_endpoint \
             WHERE (models_source IS NULL OR models_source = '') \
               AND models_endpoint IS NOT NULL AND models_endpoint != ''"
        )
        .execute(pool)
        .await?;
    }
    Ok(())
}
```

### 5.3 Rust 结构体变更

```rust
// db/models.rs — Provider 新增字段
pub struct Provider {
    // ... 现有字段 ...
    pub models_source: Option<String>,          // 替代 models_endpoint
    pub capabilities_source: Option<String>,    // 新增
}

// CreateProvider 新增
pub struct CreateProvider {
    // ... 现有字段 ...
    pub models_source: Option<String>,
    pub capabilities_source: Option<String>,
}

// UpdateProvider 新增
pub struct UpdateProvider {
    // ... 现有字段 ...
    pub models_source: Option<String>,
    pub capabilities_source: Option<String>,
}

// ExportProvider 新增
pub struct ExportProvider {
    // ... 现有字段 ...
    pub models_source: Option<String>,
    pub capabilities_source: Option<String>,
}
```

> 迁移完成且确认稳定后，后续版本可移除 `models_endpoint` 旧列。
> SQL 查询中使用 `COALESCE(models_source, models_endpoint)` 过渡。

---

## 6. 统一数据模型与查询逻辑

### 6.1 ModelCapabilities 结构

```rust
struct ModelCapabilities {
    provider: String,                   // "anthropic" | "openai" | "ollama" | "openrouter" | ...
    model_id: String,                   // 模型 ID
    context_window: u64,                // 上下文窗口 token 数
    output_max_tokens: Option<u64>,     // 最大输出 token 数
    tool_call: bool,                    // 是否支持工具调用
    reasoning: bool,                    // 是否支持推理
    input_modalities: Vec<String>,      // ["text", "image", "pdf"] 等
    output_modalities: Vec<String>,     // ["text"] 等
    input_cost: Option<f64>,            // $/百万 token，Ollama 为 None
    output_cost: Option<f64>,           // $/百万 token，Ollama 为 None
}
```

**字段映射对照：**

| 字段 | models.dev | Ollama /api/show | OpenRouter /api/v1/models |
|------|-----------|----------------|--------------------------|
| `provider` | Provider key | 固定 `"ollama"` | 固定 `"openrouter"` |
| `model_id` | `model.id` | 请求的 `name` | `id` |
| `context_window` | `model.limit.context` | `model_info.{arch}.context_length` | `context_length` |
| `output_max_tokens` | `model.limit.output` | `None` | `top_provider.max_completion_tokens` |
| `tool_call` | `model.tool_call` | `capabilities` 含 `"tools"` | `supported_parameters` 含 `"tools"` |
| `reasoning` | `model.reasoning` | `capabilities` 含 `"thinking"` | 按模型 ID 推断 |
| `input_modalities` | `model.modalities.input` | 含 `"vision"` → `["text","image"]`，否则 `["text"]` | `architecture.input_modalities` |
| `output_modalities` | `model.modalities.output` | 固定 `["text"]` | `architecture.output_modalities` |
| `input_cost` | `model.cost.input` | `None` | `pricing.prompt × 1_000_000` |
| `output_cost` | `model.cost.output` | `None` | `pricing.completion × 1_000_000` |

### 6.2 查询逻辑

```rust
async fn resolve_capabilities(
    gw: &Gateway,
    provider: &Provider,
    model: &str,
) -> ModelCapabilities {
    let source = provider.capabilities_source.as_deref().unwrap_or("");

    match parse_source(source) {
        // ai://models.dev/{key} → 从内嵌数据查询
        ResolvedSource::ModelsDev(key) => {
            lookup_models_dev(&key, model)
                .unwrap_or_else(|| default_capabilities(model))
        }
        // HTTP URL → 根据端点类型分发
        ResolvedSource::Http(url) => {
            if is_ollama_show_endpoint(&url) {
                // Ollama /api/show：逐模型 POST 查询（带缓存）
                query_ollama_show(gw, &url, model).await
            } else {
                // OpenRouter 等全量 API：先查内存缓存，未命中则按需拉取
                lookup_cached_http_capabilities(gw, &provider.id, model).await
                    .or_else(|| fetch_and_cache_http_capabilities(gw, &provider.id, &url, model))
                    .unwrap_or_else(|| default_capabilities(model))
            }
        }
        // 空值 → 自动匹配模式
        ResolvedSource::Auto => {
            fuzzy_match_models_dev(model)
                .unwrap_or_else(|| default_capabilities(model))
        }
    }
}
```

> **OpenRouter 缓存未命中处理**：当 capabilities 被查询但缓存为空时（例如尚未执行过模型发现），
> 系统触发一次按需 HTTP 请求拉取全量数据并缓存，避免返回空结果。

### 6.3 自动匹配模式（Auto）

当 `capabilities_source` 为空时（Custom provider 默认行为），系统尝试从 models.dev 全量数据中模糊匹配。

**匹配优先级（从高到低）：**

1. **精确匹配**：model_id == 用户输入（忽略大小写）
2. **包含匹配**：model_id 包含用户输入，取 ID 最短者（更精确）
3. **反向包含**：用户输入包含 model_id（用户输入了更长的名称变体）

```rust
fn fuzzy_match_models_dev(user_model: &str) -> Option<ModelCapabilities> {
    let needle = user_model.to_lowercase();
    let mut best_match: Option<(&str, &str, &ModelEntry)> = None; // (vendor_key, model_id, model)

    for (vendor_key, vendor) in models_dev_data() {
        for (model_id, model) in &vendor.models {
            let mid = model_id.to_lowercase();

            // 精确匹配：立即返回
            if mid == needle {
                return Some(to_capabilities(vendor_key, model));
            }

            // 包含匹配：取 ID 最短的（最精确）
            if mid.contains(&needle) || needle.contains(&mid) {
                let dominated = best_match
                    .as_ref()
                    .map(|(_, prev_id, _)| model_id.len() < prev_id.len())
                    .unwrap_or(true);
                if dominated {
                    best_match = Some((vendor_key, model_id, model));
                }
            }
        }
    }

    best_match.map(|(vendor_key, _, model)| to_capabilities(vendor_key, model))
}
```

> 此模式适用于：用户通过 Custom provider 接入了一个 OpenAI 兼容的中转服务，模型 ID
> 与原始厂商一致（如 `gpt-4o`、`claude-sonnet-4-20250514`），无需手动配置能力来源。

### 6.4 新增接口

**Tauri command：**

```rust
#[tauri::command]
async fn get_model_capabilities(
    gw: State<'_, Gateway>,
    provider_id: String,
    model: String,
) -> Result<ModelCapabilities, String>
```

**HTTP API：** `GET /api/v1/providers/{id}/models/{model}/capabilities`

---

## 7. 数据缓存机制

### 7.1 models.dev 缓存

见 4.1 节。内嵌快照 + 运行时缓存双层设计。

### 7.2 Ollama 能力缓存

复用现有 `CapabilityCacheEntry`：

```rust
pub struct CapabilityCacheEntry {
    pub capabilities: Vec<String>,
    pub cached_at: Instant,
}

// Gateway 上已有字段
pub ollama_capability_cache: Arc<RwLock<HashMap<String, CapabilityCacheEntry>>>
// Key: "{provider_id}:{model}"
```

- TTL：3600 秒（与现有 `OLLAMA_CAPABILITY_CACHE_TTL_SECS` 一致）
- 触发清除：Provider 删除 / base_url 变更 / Provider 测试完成

> **扩展方向**：当前仅缓存 `capabilities: Vec<String>`，
> 后续需扩展为存储完整 `ModelCapabilities`（含 context_length 等），或新建并行缓存。

### 7.3 OpenRouter 能力缓存

OpenRouter 一次 GET 返回全量模型列表和能力数据，在模型发现阶段同步缓存到内存：

- 缓存 key：`openrouter:{provider_id}`
- 存储：`HashMap<String, ModelCapabilities>`（model_id → capabilities）
- TTL：1 小时
- 触发刷新：Provider 测试 / 手动刷新模型列表

---

## 8. Provider 配置页交互

### 8.1 新增字段

Provider 编辑表单中新增「能力发现」配置项：

| DB 字段 | 显示名 | 说明 |
|---------|--------|------|
| `models_source`（替代原 `models_endpoint`） | 模型发现 | 模型列表来源 |
| `capabilities_source`（新增） | 能力发现 | 模型能力来源 |

选择预设 Provider 时，两个字段从 `providers.json` 中自动填充。

**Custom provider 默认行为：**
- `models_source`：根据 base_url + protocol 自动推导（保持现有 `resolve_models_endpoint` 逻辑）
- `capabilities_source`：空 → 自动匹配模式（见 6.3 节）

> DB 迁移详见第 5 节。

### 8.2 路由配置页模型选择交互

用户在路由配置页选择目标模型时，下拉分三个区域：

```
┌── 下拉面板 ──────────────────────────────────────┐
│  📡 已发现模型 (12)                               │
│  ┌──────────────────────────────────────────────┐│
│  │ gpt-4o             🔧 🧠 👁  200K  $5/M     ││
│  │ gpt-4o-mini        🔧    👁  128K  $0.15/M  ││
│  │ gpt-3.5-turbo      🔧         16K  $0.5/M   ││
│  └──────────────────────────────────────────────┘│
│                                                   │
│  📦 models.dev 已知模型 (46)         [可折叠]     │
│  ┌──────────────────────────────────────────────┐│
│  │ gpt-4-turbo        🔧 🧠 👁  128K  $10/M    ││
│  │ o1-preview         🔧 🧠       128K  $15/M   ││
│  └──────────────────────────────────────────────┘│
│                                                   │
│  ✏️ 手动输入模型 ID                               │
└───────────────────────────────────────────────────┘
```

选中后展示能力卡片：

```
✓ 工具调用    ✓ 推理    ✓ 视觉
上下文: 200K    输出: 64K    输入: $5/M    输出: $25/M
```

**标签渲染规则：**

| 能力 | 有 | 无 |
|------|----|----|
| tool_call | ✓ 工具调用（绿色） | — |
| reasoning | ✓ 推理（绿色） | — |
| vision（input 含 image） | ✓ 视觉（绿色） | — |
| input_cost / output_cost | 展示价格 | Ollama 显示「本地免费」 |

---

## 9. 转发层能力适配

### 9.1 tools 字段剥离

复用现有 `maybe_strip_ollama_tools` 逻辑。后续可基于 `capabilities_source` 扩展至所有 provider 的通用 tools 检测。

### 9.2 覆盖端点

`/v1/chat/completions` 和 `/v1/responses` 两个端点共用 `proxy_pipeline`，能力检测逻辑只需实现一次。

---

## 10. CLI 接入配置动态生成

### 10.1 设计原则

CLI 工具配置同步时，根据路由绑定的模型能力自动生成最优配置，用户不需要手动填写参数。

### 10.2 各工具配置生成规则

**Claude Code**

配置文件：`~/.claude/settings.json`（或 legacy `~/.claude/claude.json`）

```json
{
  "env": {
    "ANTHROPIC_AUTH_TOKEN": "nyro-sk-xxxx",
    "ANTHROPIC_BASE_URL": "http://localhost:{port}",
    "ANTHROPIC_MODEL": "{model}",
    "ANTHROPIC_REASONING_MODEL": "{model}",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "{model}",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "{model}",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "{model}"
  },
  "model": "{inferred_profile}"
}
```

> `inferred_profile` 规则：模型名含 `haiku` → `"haiku"`，含 `sonnet` → `"sonnet"`，否则 → `"opus"`。
> Token key 优先使用已存在的 `ANTHROPIC_AUTH_TOKEN`，其次 `ANTHROPIC_API_KEY`，默认写 `ANTHROPIC_AUTH_TOKEN`。
> 写入时移除 `api_format`、`openrouter_compat_mode` 等可能冲突的旧字段。

无能力依赖。

---

**Codex CLI**

配置文件：`~/.codex/auth.json` + `~/.codex/config.toml`（+ 可选 `~/.codex/nyro-models.json`）

`auth.json`：

```json
{
  "OPENAI_API_KEY": "nyro-sk-xxxx"
}
```

`config.toml` 动态字段：

| 字段 | 生成规则 |
|------|---------|
| `model` | 路由绑定的 target_model |
| `model_context_window` | 从 `ModelCapabilities.context_window` 填入（有能力数据时） |
| `model_reasoning_effort` | `reasoning = true` → `"high"`，`false` → 省略此行 |

`config.toml` 生成示例（reasoning=true，context_window=1000000）：

```toml
model_provider = "nyro"
model = "MiniMax-M2.5"
model_reasoning_effort = "high"
model_context_window = 1000000
disable_response_storage = true
model_catalog_json = "/Users/{user}/.codex/nyro-models.json"

[model_providers.nyro]
name = "Nyro Gateway"
base_url = "http://localhost:{port}/v1"
wire_api = "responses"
requires_openai_auth = true
```

`config.toml` 生成示例（reasoning=false，无 context_window 数据）：

```toml
model_provider = "nyro"
model = "gpt-4o"
disable_response_storage = true

[model_providers.nyro]
name = "Nyro Gateway"
base_url = "http://localhost:{port}/v1"
wire_api = "responses"
requires_openai_auth = true
```

`nyro-models.json`（可选增强，有 ModelCapabilities 时生成）：

```json
{
  "models": [
    {
      "slug": "{model_id}",
      "display_name": "{model_id}",
      "supported_reasoning_levels": [],
      "shell_type": "shell_command",
      "visibility": "list",
      "supported_in_api": true,
      "priority": 1,
      "supports_reasoning_summaries": false,
      "support_verbosity": false,
      "apply_patch_tool_type": "freeform",
      "supports_parallel_tool_calls": false,
      "context_window": 200000
    }
  ]
}
```

> 文件名使用 `nyro-models.json` 而非 `custom-models.json`，避免与 Codex 自身配置混淆。
> 当 `nyro-models.json` 生成时，`config.toml` 需追加 `model_catalog_json` 指向该文件。

---

**Gemini CLI**

配置文件：`~/.gemini/.env` + `~/.gemini/settings.json`

`.env` 写入：

```bash
GEMINI_API_KEY=nyro-sk-xxxx
GEMINI_MODEL={model}
GOOGLE_GEMINI_BASE_URL=http://localhost:{port}
```

> base URL 环境变量名为 `GOOGLE_GEMINI_BASE_URL`（非 `GEMINI_BASE_URL`）。
> `.env` 文件权限设为 `0600`，`.gemini` 目录权限设为 `0700`（Unix）。

`settings.json` 写入 `selectedType`（merge 模式）：

```json
{
  "security": {
    "auth": {
      "selectedType": "gemini-api-key"
    }
  }
}
```

无能力依赖，需两个文件同时写入。

---

**OpenCode**

配置文件：`~/.config/opencode/opencode.json`

写入独立 `nyro` provider 块（merge 模式）：

```json
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "nyro": {
      "name": "Nyro Gateway",
      "npm": "@ai-sdk/openai-compatible",
      "options": {
        "baseURL": "http://localhost:{port}/v1",
        "apiKey": "nyro-sk-xxxx",
        "model": "{model}"
      },
      "models": {
        "{model}": {
          "name": "{model}"
        }
      }
    }
  }
}
```

无能力依赖。

---

### 10.3 同步流程

```
用户点击「同步配置」
        ↓
读取所选路由 + API Key → 解析 host / apiKey / model
        ↓
查询 ModelCapabilities（用于 Codex 的 context_window / reasoning）
        ↓
按工具类型生成配置内容
        ↓
首次同步时备份原配置文件到 {app_data_dir}/cli-sync-backups.json
        ↓
原子写入新配置（写临时文件 → rename）
        ↓
返回写入的文件路径列表
```

### 10.4 Tauri Command 接口

```rust
/// 检测工具安装状态（通过配置目录是否存在判断）
#[tauri::command]
async fn detect_cli_tools() -> Result<HashMap<String, bool>, String>

/// CLI 同步时传入的能力数据（可选）
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
struct CliModelCapabilities {
    context_window: Option<u64>,
    reasoning: Option<bool>,
}

/// 同步配置
/// capabilities 由前端先调 get_model_capabilities 获取后传入
/// Codex CLI 根据 capabilities 动态生成 config.toml
/// 其他工具忽略 capabilities
#[tauri::command]
async fn sync_cli_config(
    app: tauri::AppHandle,
    tool_id: String,    // "claude-code" | "codex-cli" | "gemini-cli" | "opencode"
    host: String,
    api_key: String,
    model: String,
    capabilities: Option<CliModelCapabilities>,
) -> Result<Vec<String>, String>

/// 恢复备份
#[tauri::command]
async fn restore_cli_config(
    app: tauri::AppHandle,
    tool_id: String,
) -> Result<Vec<String>, String>
```

> 前端在调用 `sync_cli_config` 前，先调用 `get_model_capabilities` 获取能力数据，
> 将 `context_window` 和 `reasoning` 提取后通过 `capabilities` 参数传入。
> Codex CLI 根据这些数据决定是否写入 `model_reasoning_effort` 和 `model_context_window`。
> 其他工具（Claude Code / Gemini CLI / OpenCode）传 `None` 即可。

---

## 11. CLI 工具检测机制

通过**配置目录是否存在**判断工具是否「已就绪」：

| 工具 | 检测路径 | 就绪标签 |
|------|---------|---------|
| Claude Code | `~/.claude/` | Ready / 已就绪 |
| Codex CLI | `~/.codex/` | Ready / 已就绪 |
| Gemini CLI | `~/.gemini/` | Ready / 已就绪 |
| OpenCode | `~/.config/opencode/` | Ready / 已就绪 |

---

## 12. 边界情况处理

| 情况 | 处理方式 |
|------|---------|
| models.dev 运行时刷新失败 | 使用本地缓存或打包快照，不报错 |
| 模型在 models.dev 中不存在 | 返回默认 capabilities（tool_call=false，reasoning=false） |
| Ollama /api/show 请求失败 | 返回默认 capabilities，记录 WARN 日志 |
| Ollama 模型不支持 tools 但请求携带 tools | 转发前自动剥离，记录 WARN 日志 |
| OpenRouter API 请求失败 | 返回默认 capabilities，不阻塞路由 |
| OpenRouter pricing 字段为 null 或 "0" | cost 设为 None |
| capabilitiesSource 为空（Auto 模式） | 模糊匹配 models.dev 全量数据，匹配失败返回默认值 |
| CLI 工具目录不存在 | 同步时自动创建目录 |
| 配置文件写入失败 | 返回错误原因，不破坏原有配置（原子写入保证） |
| context_window 为 0 或缺失 | 回退到默认值（云端 128K，Ollama 8K） |
| `ai://` 协议中 key 无效 | 返回默认 capabilities，记录 WARN |
| DB 中已有 `models` 表但未使用 | 模型能力数据纯内存/文件缓存，不入此表 |

---

## 13. 后续扩展方向

- `vision` 能力识别后，路由配置中支持标注「支持视觉」，并在代码接入示例中展示图片上传用法
- `reasoning` 能力识别后，转发层根据模型自动注入合适的 thinking 参数格式（Anthropic vs OpenAI vs Gemini 三套格式不同）
- 路由列表中展示预估费用，辅助用户做成本决策
- Codex CLI 的 `nyro-models.json` 生成逻辑可扩展为通用的「模型元数据导出」功能
- OpenRouter 模型数据可用于在路由页展示「原始厂商」标签（从 model_id 前缀解析）
- `ai://` 协议可扩展新数据源（如 `ai://huggingface/{namespace}`）
- `providers.json` 支持运行时热更新，用户可自行添加 provider 预设
