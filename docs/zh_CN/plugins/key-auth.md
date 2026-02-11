# key-auth 插件

基于 API Key 的客户端认证插件，与 Nyro 的 consumer/credential 系统集成。

---

## 启用

在 `nyro.yaml` 的插件列表中添加：

```yaml
plugins:
  - key-auth
```

---

## 配置参数

| 参数 | 类型 | 必填 | 默认值 | 说明 |
|------|------|------|--------|------|
| `key_name` | string | 否 | — | 自定义 header/query 参数名。未设置时自动探测 |
| `key_in` | string | 否 | `"header"` | Key 来源: `header` 或 `query` |
| `hide_credentials` | boolean | 否 | `false` | 转发前是否移除客户端凭证 |

---

## Key 提取规则

### 指定 `key_name` 时

从 `key_in` 指定的位置读取 `key_name` 对应的值。

```yaml
# 示例: 从 header X-My-Key 中读取
- id: key-auth
  config:
    key_name: "X-My-Key"
```

```yaml
# 示例: 从 query 参数 api_key 中读取
- id: key-auth
  config:
    key_name: "api_key"
    key_in: "query"
```

### 未指定 `key_name` 时 (自动探测)

按优先级依次检查以下 header：

| 顺序 | Header | 格式 | 对应 SDK |
|------|--------|------|----------|
| 1 | `Authorization` | `Bearer {key}` | OpenAI |
| 2 | `x-api-key` | `{key}` | Anthropic |
| 3 | `x-goog-api-key` | `{key}` | Gemini |
| 4 | `NYRO-KEY-AUTH` | `{key}` | Nyro 默认 |

自动探测模式下，三大 AI SDK 的标准认证头均可直接识别，**无需额外配置**。

---

## Consumer 集成

key-auth 通过 consumer 的 `credentials.key-auth.key` 字段进行凭证匹配。

### Consumer 配置

```yaml
consumers:
  - name: app-1
    credentials:
      key-auth:
        key: "my-app-key-1234567890"

  - name: app-2
    credentials:
      key-auth:
        key: "another-key-0987654321"
```

### 认证流程

```
客户端请求 (带 API Key)
    │
    ▼
key-auth 插件
    ├── 提取 Key (自动探测或指定位置)
    ├── 查找匹配的 consumer
    ├── 认证失败 → 401
    └── 认证成功
         ├── oak_ctx._consumer = consumer 对象
         └── oak_ctx._authenticated_key = 原始 API Key
              │
              ▼
         ai-proxy 插件
              ├── cfg.api_key 已配置 → 使用配置值 (覆盖客户端)
              └── cfg.api_key 未配置 → 透传 _authenticated_key (按目标协议重新注入)
```

---

## 与 ai-proxy 协同

### 场景 1: 后端使用统一 Key (覆盖)

客户端 Key 仅用于认证，转发时使用网关配置的后端 Key。

```yaml
routes:
  - name: chat
    service: openai
    paths: ["/v1/chat/completions"]
    plugins:
      - id: key-auth              # 验证客户端身份
      - id: ai-proxy
        config:
          api_key: "sk-backend"   # 后端 Key, 覆盖客户端
```

### 场景 2: 透传客户端 Key

客户端自带后端 Provider 的 Key，网关仅做认证 + 协议转换。

```yaml
routes:
  - name: chat
    service: openai
    paths: ["/v1/chat/completions"]
    plugins:
      - id: key-auth              # 验证客户端身份
      - id: ai-proxy              # 无 api_key, 透传客户端的 Key
```

此时 ai-proxy 会自动从 `oak_ctx._authenticated_key` 提取客户端 Key，
按目标协议格式重新注入 (如 Anthropic `x-api-key` → OpenAI `Authorization: Bearer`)。

### 场景 3: 无认证, 直接使用后端 Key

不挂 key-auth, ai-proxy 中配置后端 Key。

```yaml
routes:
  - name: chat
    service: openai
    paths: ["/v1/chat/completions"]
    plugins:
      - id: ai-proxy
        config:
          api_key: "sk-backend"
```

---

## 错误响应

| HTTP 状态码 | 场景 |
|-------------|------|
| 401 | 请求中未找到 API Key |
| 401 | Key 不匹配任何 consumer |

响应格式：

```json
{
  "error": {
    "message": "Unauthorized: missing API key"
  }
}
```
