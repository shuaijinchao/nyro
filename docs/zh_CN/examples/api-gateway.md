# API 网关配置示例

> 以下示例展示纯 API 网关场景 (不涉及 AI 协议转换)。

---

## 1. 最简 — URL 直连代理

将所有请求转发到 httpbin.org:

```yaml
version: "1.0"

services:
  - name: httpbin
    url: http://httpbin.org

routes:
  - name: proxy
    service: httpbin
    paths:
      - /*
```

```bash
curl http://localhost:8080/anything/hello
```

---

## 2. 带路径前缀

只代理 `/api/v1/*` 路径:

```yaml
services:
  - name: backend
    url: http://192.168.1.100:3000

routes:
  - name: api-v1
    service: backend
    paths:
      - /api/v1/*
    methods: ["GET", "POST", "PUT", "DELETE"]
```

---

## 3. 带客户端认证

使用 `key-auth` 插件验证客户端身份:

```yaml
plugins:
  - key-auth

consumers:
  - name: web-client
    credentials:
      key-auth:
        key: "nyro-sk-web-001"

  - name: mobile-client
    credentials:
      key-auth:
        key: "nyro-sk-mobile-002"

services:
  - name: backend
    url: http://192.168.1.100:3000

routes:
  - name: api
    service: backend
    paths:
      - /api/*
    plugins:
      - id: key-auth
```

```bash
curl -H "apikey: nyro-sk-web-001" http://localhost:8080/api/users
```

---

## 4. 带限流

```yaml
plugins:
  - key-auth
  - limit-req

consumers:
  - name: app
    credentials:
      key-auth:
        key: "nyro-sk-001"

services:
  - name: backend
    url: http://192.168.1.100:3000

routes:
  - name: api
    service: backend
    paths:
      - /api/*
    plugins:
      - id: key-auth
      - id: limit-req
        config:
          rate: 10
          burst: 5
```

---

## 5. 多后端负载均衡

使用 `backends` 实现 roundrobin 负载均衡:

```yaml
backends:
  - name: app-pool
    algorithm: roundrobin
    timeout:
      connect: 3000
      read: 10000
      send: 3000
    endpoints:
      - address: "192.168.1.101"
        port: 3000
        weight: 100
      - address: "192.168.1.102"
        port: 3000
        weight: 100

services:
  - name: app
    backend: app-pool

routes:
  - name: api
    service: app
    paths:
      - /api/*
```

---

## 6. HTTPS 后端 + 负载均衡

后端是 HTTPS 服务时, 需在 service 上指定 `scheme: https`:

```yaml
backends:
  - name: secure-pool
    algorithm: roundrobin
    endpoints:
      - address: "backend1.example.com"
        port: 443
        weight: 100
      - address: "backend2.example.com"
        port: 443
        weight: 100

services:
  - name: secure-app
    scheme: https
    backend: secure-pool

routes:
  - name: api
    service: secure-app
    paths:
      - /api/*
```

---

## 7. Host 路由

通过域名区分不同后端:

```yaml
services:
  - name: user-service
    url: http://192.168.1.101:3000

  - name: order-service
    url: http://192.168.1.102:3000

routes:
  - name: users
    hosts: ["user.api.example.com"]
    service: user-service
    paths:
      - /*

  - name: orders
    hosts: ["order.api.example.com"]
    service: order-service
    paths:
      - /*
```

```bash
curl -H "Host: user.api.example.com" http://localhost:8080/v1/list
curl -H "Host: order.api.example.com" http://localhost:8080/v1/list
```
