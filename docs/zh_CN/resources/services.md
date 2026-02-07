# Services（服务）

## 作用

`services` 是上游的逻辑抽象，作为 `routes` 和 `backends` 之间的中间层。支持两种模式：
1. **引用 backend**：通过 `backend` 字段关联已定义的后端
2. **URL 直接代理**：通过 `url` 字段直接代理到外部 API

## 配置说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `name` | string | 是 | 服务名称，唯一标识 |
| `backend` | string | 否* | 引用的 backend 名称 |
| `url` | string | 否* | 直接代理的 URL |
| `plugins` | array | 否 | 服务级别插件 |

> *`backend` 和 `url` 二选一

## 使用示例

### 模式一：引用 Backend

```yaml
backends:
  - name: user-backend
    endpoints:
      - address: 192.168.1.10:8080

services:
  - name: user-service
    backend: user-backend
```

### 模式二：URL 直接代理

无需定义 backend，直接代理到外部 API。系统自动从 URL 解析 `protocol`、`host`、`port`、`path`。

```yaml
services:
  # HTTP
  - name: httpbin-service
    url: http://httpbin.org

  # HTTPS
  - name: openai-service
    url: https://api.openai.com/v1

  # 带端口
  - name: internal-api
    url: http://10.0.0.1:9000/api
```

### 带插件的服务

```yaml
services:
  - name: protected-service
    backend: api-backend
    plugins:
      - name: rate-limiting
        config:
          rate: 100
          burst: 50
```

## 关联资源

- 通过 `backend` 引用 `backends`
- 被 `routes` 通过 `service` 字段引用
