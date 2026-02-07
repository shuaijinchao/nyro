# NYRO 资源配置指南

本目录包含 NYRO 所有资源类型的配置说明。

## 资源层次

```
plugins (全局插件)
    │
backends (后端集群)
    │
services (服务抽象)
    │
routes (路由规则)

consumers (消费者认证)

certificates (SSL 证书)
```

## 核心规则

1. **route 必须引用 service** - 路由不直接与 backend 关联
2. **service 二选一** - 引用 `backend` 或使用 `url` 直接代理
3. **使用 name 标识** - 所有资源使用 `name` 作为唯一标识

## 资源文档

| 资源 | 说明 | 文档 |
|------|------|------|
| [backends](./backends.md) | 后端服务器集群 | 负载均衡、健康检查 |
| [services](./services.md) | 上游服务抽象 | 引用 backend 或 URL 代理 |
| [routes](./routes.md) | 请求路由规则 | 路径、方法、域名匹配 |
| [consumers](./consumers.md) | API 消费者 | 身份认证、凭证管理 |
| [certificates](./certificates.md) | SSL 证书 | HTTPS 加密 |
| [plugins](./plugins.md) | 功能插件 | 认证、限流、安全 |

## 最小配置

```yaml
version: "1.0"

backends:
  - name: my-backend
    endpoints:
      - address: 127.0.0.1:8080

services:
  - name: my-service
    backend: my-backend

routes:
  - name: my-route
    service: my-service
    paths:
      - /api/*
```

## URL 直接代理

无需定义 backend，直接代理到外部 API：

```yaml
version: "1.0"

services:
  - name: external-api
    url: https://api.example.com

routes:
  - name: proxy-route
    service: external-api
    paths:
      - /external/*
```
