# Applications（应用）

## 作用

`applications` 定义 API 调用方/消费者，用于身份认证和访问控制。每个应用可配置多种凭证类型和专属插件。

## 配置说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `name` | string | 是 | 应用名称，唯一标识 |
| `credentials` | object | 是 | 凭证配置 |
| `plugins` | array | 否 | 应用级别插件 |

### credentials 配置

支持多种认证方式：

#### key-auth

```yaml
credentials:
  key-auth:
    key: your-api-key
```

#### basic-auth

```yaml
credentials:
  basic-auth:
    username: user
    password: secret
```

#### jwt-auth

```yaml
credentials:
  jwt-auth:
    key: jwt-key-id
    secret: jwt-secret
```

## 使用示例

### 基础配置

```yaml
applications:
  - name: mobile-app
    credentials:
      key-auth:
        key: mobile-app-api-key-123
```

### 多种认证方式

```yaml
applications:
  - name: web-app
    credentials:
      key-auth:
        key: web-app-api-key
      basic-auth:
        username: webapp
        password: webapp-secret
```

### 带插件配置

```yaml
applications:
  - name: partner-api
    credentials:
      key-auth:
        key: partner-api-key
    plugins:
      - name: rate-limiting
        config:
          rate: 100
          burst: 10
      - name: ip-restriction
        config:
          whitelist: ["203.0.113.0/24"]
```

## 认证流程

1. 客户端请求携带凭证（如 API Key、JWT 等）
2. 认证插件（如 `key-auth`）从请求中提取凭证
3. 系统通过凭证查找对应的 application
4. 认证成功后，应用的专属插件生效

## 关联资源

- 被认证类插件（`key-auth`、`jwt-auth` 等）使用
- 应用级插件对该应用的所有请求生效
