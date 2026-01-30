# APIOAK 架构升级需求文档

> 版本: v1.1  
> 日期: 2026-01-30  
> 状态: **开发中** (Phase 1 & 2 已完成)

---

## 目录

1. [概述](#概述)
2. [实施进度](#实施进度)
3. [当前架构分析](#当前架构分析)
4. [需求一：重构路由引擎](#需求一重构路由引擎)
5. [需求二：移除 Consul 依赖](#需求二移除-consul-依赖)
6. [需求三：AI Proxy 能力](#需求三ai-proxy-能力)
7. [技术路线图](#技术路线图)
8. [配置文件设计](#配置文件设计)

---

## 概述

本次架构升级旨在提升 APIOAK 的性能、简化部署复杂度、并增加对 AI 场景的支持。主要包含三大核心改动：

| 序号 | 需求 | 目标 |
|------|------|------|
| 1 | 重构路由引擎 | 使用 Radix Tree 实现高性能路由，支持多种匹配模式 |
| 2 | 移除 Consul 依赖 | 实现 DB Less / Hybrid 模式，降低部署复杂度 |
| 3 | AI Proxy 能力 | 支持 LLM 协议标准化、多 Key 管理、故障转移 |

---

## 实施进度

### 总体进度

| 阶段 | 状态 | 完成日期 |
|------|------|----------|
| Step 1: 存储抽象与 DB Less | ✅ **已完成** | 2026-01-30 |
| Step 2: 路由引擎重构 | ✅ **已完成** | 2026-01-30 |
| Step 3: 系统集成与启动流程 | ✅ **已完成** | 2026-01-30 |
| Step 4: Consul 移除与清理 | ✅ **已完成** | 2026-01-30 |
| Step 5: Hybrid 模式 | ⏳ 待开发 | - |
| Step 6: AI Proxy 插件 | ⏳ 待开发 | - |

### 已完成工作详情

#### 1. FFI 路由引擎 (Rax + Khash)

选择了 **方案 B: 自行封装 Rax FFI**，实现了基于 C 的高性能路由引擎。

**新增文件:**

| 文件 | 说明 |
|------|------|
| `deps/apioak/apioak_router.h` | C 头文件，定义路由引擎接口 |
| `deps/apioak/apioak_router.c` | C 实现，基于 Rax (Radix Tree) + Khash |
| `deps/apioak/Makefile` | C 库编译脚本 |
| `deps/rax/rax.h` | Rax 库头文件 |
| `deps/rax/rax.c` | Rax 库实现 |
| `apioak/sys/router/ffi.lua` | LuaJIT FFI 绑定定义 |
| `apioak/sys/router/matcher.lua` | Lua 封装层，提供面向对象 API |
| `apioak/sys/router/init.lua` | 路由模块入口 |

**支持的匹配类型:**

| 类型 | 示例 | 实现状态 |
|------|------|----------|
| 精确匹配 | `/api/v1/users` | ✅ 已实现 |
| 参数匹配 | `/api/v1/users/{id}` | ✅ 已实现 |
| 前缀匹配 | `/static/*` | ✅ 已实现 |
| 正则匹配 | `^/api/v[0-9]+/.*` | ⏳ 待实现 |

**测试验证:**

```bash
# 运行路由引擎测试
resty t/router_test.lua
# 结果: 所有测试通过 ✅
```

#### 2. Store 抽象层 (DB Less 模式)

实现了存储抽象层，支持从 YAML 文件声明式加载配置。

**新增文件:**

| 文件 | 说明 |
|------|------|
| `apioak/store/init.lua` | Store 抽象层入口 |
| `apioak/store/adapter/yaml.lua` | YAML 适配器 (DB Less 模式) |
| `conf/config.yaml` | 声明式配置文件 |

**Store 接口:**

```lua
store.init(config)        -- 初始化
store.get_services()      -- 获取服务列表
store.get_routes()        -- 获取路由列表
store.get_upstreams()     -- 获取上游列表
store.get_plugins()       -- 获取插件列表
store.get_certificates()  -- 获取证书列表
store.get_version()       -- 获取配置版本
store.reload()            -- 重新加载配置
```

**测试验证:**

```bash
# 运行 Store 测试
resty t/store_test.lua
# 结果: 所有测试通过 ✅
```

#### 3. 系统集成

将新的路由引擎和 Store 层集成到系统启动流程。

**修改文件:**

| 文件 | 改动内容 |
|------|---------|
| `apioak/sys/router.lua` | 完全重写，使用 FFI 路由引擎 + Store |
| `apioak/sys/balancer.lua` | 重写，使用 Store 获取 upstream 数据 |
| `apioak/sys/dao.lua` | 重写，使用 Store 初始化 |
| `apioak/sys/admin.lua` | 重写，standalone 模式下禁用 Admin API |
| `apioak/cmd/env.lua` | 移除 Consul 检查，添加 Store 配置验证 |

#### 4. Consul 移除

彻底移除 Consul 依赖，保留向后兼容的存根模块。

**改动汇总:**

| 文件 | 操作 |
|------|------|
| `apioak/pdk/consul.lua` | 重写为存根模块 (向后兼容) |
| `apioak/pdk.lua` | 保留 consul 引用 (存根) |
| `apioak/pdk/const.lua` | 移除 Consul 常量，添加兼容别名 |
| `conf/apioak.yaml` | 移除 Consul 配置，使用 Store 配置 |
| `rockspec/apioak-master-0.rockspec` | 移除 `lua-resty-consul` 依赖 |

#### 5. 编译与构建

更新 Makefile 集成 C 库编译。

**编译命令:**

```bash
# 开发环境编译
make dev

# 生产环境安装
make install
```

**生成产物:**

- `libapioak_router.dylib` (macOS)
- `libapioak_router.so` (Linux)

### 验证结果

#### 启动测试

```bash
$ ./bin/apioak start
OpenResty PATH         ...OK
OpenResty Version      ...OK
Config Loading         ...OK
Config Parse           ...OK
Config Store Mode      ...OK (standalone)
Config File            ...OK (conf/config.yaml)
Config Routes          ...OK (4 routes)
Plugin Check           ...OK (7 plugins)
----------------------------
Apioak started successfully!
```

#### 请求测试

```bash
# 启动后端服务 (8080 端口)
$ python3 -c "from http.server import HTTPServer, BaseHTTPRequestHandler; ..."

# 测试路由匹配
$ curl -H "Host: api.example.com" http://127.0.0.1:10080/api/v1/users
{"path": "/api/v1/users", "message": "Hello from backend!", "port": 8080}

# 日志确认
upstream: "http://127.0.0.1:8080/api/v1/users"  ✅ 路由正确
```

### 待完成工作

1. **Hybrid 模式**
   - Control Plane 实现
   - Data Plane HTTP Long Polling
   - MongoDB 集成

2. **AI Proxy 插件**
   - Phase 1: 协议标准化
   - Phase 2: 多 Key 管理
   - Phase 3: Token 估算

3. **增强功能**
   - 正则匹配支持
   - 健康检查
   - 更多插件适配

---

## 当前架构分析

### 技术栈

- **核心引擎**: OpenResty (Nginx + LuaJIT)
- **路由库**: `lua-resty-oakrouting` (纯 Lua 实现)
- **配置存储**: Consul KV Store
- **配置同步**: 定时轮询 + `worker.events` 广播

### 核心模块

```
apioak/
├── apioak/
│   ├── admin/          # 管理 API 模块
│   │   ├── dao/        # 数据访问层 (Consul 操作)
│   │   ├── router.lua  # 路由 CRUD
│   │   ├── service.lua # 服务 CRUD
│   │   └── ...
│   ├── pdk/            # 开发工具包
│   │   ├── consul.lua  # Consul 客户端封装
│   │   └── ...
│   ├── plugin/         # 插件系统
│   ├── sys/            # 系统核心模块
│   │   ├── router.lua  # 路由匹配核心
│   │   ├── balancer.lua # 负载均衡
│   │   ├── plugin.lua  # 插件管理
│   │   └── ...
│   └── apioak.lua      # 主入口
└── conf/
    └── apioak.yaml     # 配置文件
```

### Consul 依赖分布

| 文件 | 依赖类型 |
|------|---------|
| `apioak/pdk/consul.lua` | Consul 客户端封装 |
| `apioak/admin/dao/common.lua` | 所有 KV 操作 (get/put/delete/list) |
| `apioak/admin/router.lua` | 路由 CRUD |
| `apioak/admin/service.lua` | 服务 CRUD |
| `apioak/admin/plugin.lua` | 插件 CRUD |
| `apioak/admin/upstream.lua` | 上游 CRUD |
| `apioak/admin/upstream_node.lua` | 上游节点 CRUD |
| `apioak/admin/certificate.lua` | 证书 CRUD |
| `apioak/cmd/env.lua` | 环境检查 |
| `conf/apioak.yaml` | Consul 连接配置 |

### 当前数据流

```
请求到达 → http_access() → 路由匹配 → 插件执行 → 负载均衡 → 转发到上游

配置变更 → Consul KV 更新 → Worker 定时同步 → worker.events 通知 → 更新内存路由表
```

---

## 需求一：重构路由引擎

### 背景

当前使用的 `lua-resty-oakrouting` 是纯 Lua 实现，在大量路由场景下性能有限。需要升级为基于 Radix Tree 的高性能路由引擎。

### 目标

基于 **Rax (Radix Tree)** 实现高性能路由引擎，支持四种匹配模式。

### 匹配类型设计

| 匹配类型 | 示例 | 优先级 | 实现策略 |
|---------|------|-------|---------|
| **精确匹配 (Exact)** | `/api/v1/users` | 最高 (4) | Radix Tree 完整路径查找 |
| **前缀匹配 (Prefix)** | `/api/v1/*` | 高 (3) | Radix Tree 最长前缀匹配 |
| **参数匹配 (Parameter)** | `/user/:id/profile` | 中 (2) | 特殊节点 (`:` 或 `*`) + 参数提取 |
| **正则匹配 (Regex)** | `^/api/v[0-9]+/.*` | 最低 (1) | 前缀索引 + 正则列表回退 |

### 技术选型

#### 方案 A: 集成 lua-resty-radixtree

- **优点**: APISIX 核心路由库，久经考验，功能完善
- **缺点**: 引入外部依赖

#### 方案 B: 自行封装 Rax FFI ✅ **已选择**

- **优点**: 轻量化，可针对 APIOAK 配置结构优化
- **缺点**: 开发成本高
- **状态**: **已实现** - 基于 Rax + Khash 实现高性能路由引擎

#### 方案 C: 纯 Lua 实现轻量版 Radix Tree

- **优点**: 零 C 依赖，易于维护
- **缺点**: 性能不如 FFI 方案

### 实现架构

```
┌─────────────────────────────────────────────────────────────┐
│                    Lua Layer (LuaJIT)                       │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  apioak/sys/router/init.lua     (模块入口)          │   │
│  ├─────────────────────────────────────────────────────┤   │
│  │  apioak/sys/router/matcher.lua  (面向对象封装)      │   │
│  ├─────────────────────────────────────────────────────┤   │
│  │  apioak/sys/router/ffi.lua      (FFI 定义)          │   │
│  └─────────────────────────────────────────────────────┘   │
│                            │                                │
│                       FFI 调用                              │
│                            ▼                                │
├─────────────────────────────────────────────────────────────┤
│                     C Layer (libapioak_router)              │
│  ┌───────────────────┐    ┌───────────────────┐            │
│  │   Rax (Radix Tree) │    │  Khash (Hash Table)│            │
│  │   - 路径索引       │    │  - Host 索引      │            │
│  │   - 前缀匹配       │    │  - 快速查找       │            │
│  └───────────────────┘    └───────────────────┘            │
└─────────────────────────────────────────────────────────────┘
```

### 改造范围

| 文件 | 改动内容 |
|------|---------|
| `apioak/sys/router.lua` | 核心路由匹配逻辑重构 |
| `apioak/sys/admin.lua` | Admin API 路由适配 |
| `apioak/sys/certificate.lua` | SSL SNI 匹配适配 |
| `rockspec/apioak-master-0.rockspec` | 依赖库变更 |

### 优先级仲裁规则

当多条路由可能匹配同一请求时，按以下顺序决定：

1. **精确匹配** (优先级最高)
2. **前缀匹配** (最长前缀优先)
3. **参数匹配**
4. **正则匹配** (通常作为兜底)

---

## 需求二：移除 Consul 依赖

### 背景

移除 Consul 依赖，转向 **DB Less (声明式)** 和 **Hybrid (控制面/数据面分离)** 模式，是云原生网关的主流演进方向。

### 目标

- 降低部署复杂度（不需要维护外部 KV 存储）
- 更好的 GitOps 集成
- 保留高性能集群管理能力

### 模式一：DB Less (Standalone)

#### 架构图

```
┌─────────────────────────────────────────────────┐
│                   APIOAK Node                   │
│  ┌───────────┐    ┌──────────────────────────┐ │
│  │apioak.yaml│───▶│  ngx.shared.DICT (内存)  │ │
│  └───────────┘    └──────────────────────────┘ │
│        │                      │                 │
│   HUP Signal ────────────▶ 热加载              │
└─────────────────────────────────────────────────┘
```

#### 核心逻辑

1. **配置载体**: 定义标准的 `apioak.yaml` 配置文件
2. **启动加载**: 在 `init_by_lua` 阶段解析 YAML → 校验 Schema → 写入 `ngx.shared.DICT`
3. **热更新**:
   - 方案 A (信号): 发送 HUP 信号触发重新加载
   - 方案 B (Admin API): 提供 `/v1/schema/reload` 接口

#### 技术要点

- **原子性更新**: 构建新的路由表树，然后原子替换全局变量引用
- **本地缓存**: Worker 将 `shared.DICT` 配置反序列化为 Lua Table 缓存，仅当版本号变化时重新拉取
- **YAML 解析**: 引入 `lyaml` 或类似库

#### 适用场景

- K8s Ingress
- Ansible/SaltStack 管理
- GitOps 工作流

### 模式二：Hybrid (CP/DP 分离 + MongoDB)

#### 架构图

```
┌─────────────────┐        ┌─────────────────────────────┐
│  Control Plane  │        │        Data Plane           │
│  ┌───────────┐  │        │  ┌───────────────────────┐  │
│  │ Admin API │  │        │  │   ngx.shared.DICT     │  │
│  └─────┬─────┘  │        │  └───────────▲───────────┘  │
│        │        │        │              │              │
│  ┌─────▼─────┐  │◀───────│──────HTTP Long Polling──────│
│  │  MongoDB  │  │        │                             │
│  └───────────┘  │        │  ┌───────────────────────┐  │
│                 │        │  │  Local Config Dump    │  │
│  (JSON Native)  │        │  │  (容灾备份)           │  │
└─────────────────┘        └──┴───────────────────────┴──┘
```

#### 角色分工

| 角色 | 职责 |
|------|------|
| **Control Plane (CP)** | 暴露 Admin API，独占 MongoDB 连接，管理配置 |
| **Data Plane (DP)** | 处理流量，通过 HTTP Long Polling 从 CP 同步配置 |

#### 为什么选择 MongoDB

| 特性 | MongoDB | Redis | Etcd |
|------|---------|-------|------|
| 数据结构 | 完美 (JSON Document) | 差 (需序列化为 String) | 中 (需打散 Key) |
| 复杂查询 | 强 (多字段过滤、分页) | 弱 (需手工维护索引) | 弱 |
| 局部更新 | 支持 ($set, $push) | 不支持 (需全量覆盖) | 支持 |
| Watch 机制 | Change Streams | Pub/Sub | 原生 Watch |
| 运维成本 | 中 | 低 | 高 |

**结论**: MongoDB 的 JSON Native 特性与 API 网关配置数据结构天然匹配。

#### 通信协议 (HTTP Long Polling)

```
1. DP -> CP: GET /v1/sync?version=100 (带上当前版本号)
2. CP: 检查当前配置版本
   - 有新版本 (e.g., 101): 立即返回全量或增量配置
   - 无新版本: 挂起请求等待 60 秒
3. DP: 收到响应 -> 更新 ngx.shared.DICT -> 发起下一次 Long Polling
```

#### 容灾设计

- DP 必须在本地磁盘缓存最新配置 (`config_dump.yaml`)
- CP 挂掉时，DP 启动时加载本地 Dump 文件
- 保证数据面服务不中断

#### 数据模型示例 (MongoDB)

```javascript
// Collection: routes
{
    "_id": "route_xyz",
    "uri": "/api/v1/*",
    "methods": ["GET", "POST"],
    "upstream_id": "upstream_abc",
    "plugins": {
        "limit-req": {
            "rate": 100,
            "burst": 50
        },
        "jwt-auth": {
            "enabled": true
        }
    },
    "status": 1,
    "create_time": ISODate("...")
}
```

### Store 抽象层设计

```lua
-- apioak/sys/store.lua (新增)
local _M = {}

-- 适配器模式，解耦具体存储实现
function _M.get_routes()
    if config.mode == "standalone" then
       return yaml_adapter.get_routes()     -- DB Less
    elseif config.mode == "hybrid" then
       return sync_adapter.get_routes()     -- 从 CP 同步
    end
end

function _M.get_services()
    -- ...
end

function _M.get_plugins()
    -- ...
end

return _M
```

---

## 需求三：AI Proxy 能力

### 背景

AI Proxy 是目前 API 网关最火热的场景，本质是七层流量治理在 LLM 场景下的特化。

### 目标

提供标准化的 AI 接口与治理能力，让用户可以用任意 OpenAI 兼容客户端无缝连接各种 LLM Provider。

### Phase 1: 协议标准化 (The Unifier)

#### 架构图

```
┌──────────────────┐     ┌─────────────────────────────────┐
│  任意 OpenAI     │     │         APIOAK (ai-proxy)       │
│  兼容客户端      │────▶│  /v1/chat/completions           │
│  (NextChat等)    │     │         │                       │
└──────────────────┘     │    ┌────▼────┐                  │
                         │    │ Request │                  │
                         │    │Transformer                 │
                         │    └────┬────┘                  │
                         │    ┌────▼────────────────────┐  │
                         │    │  Claude / Gemini /      │  │
                         │    │  DeepSeek / GPT         │  │
                         │    └─────────────────────────┘  │
                         └─────────────────────────────────┘
```

#### 核心功能

| 功能 | 描述 |
|------|------|
| 对外接口 | 统一暴露 OpenAI 兼容接口 (`/v1/chat/completions`) |
| 请求转换 | 将请求适配为各厂商格式 (Anthropic, Google, DeepSeek 等) |
| 流式处理 | 统一 SSE (Server-Sent Events) 响应格式 |

#### 支持的 Provider

| Provider | API 格式 | 流式支持 |
|----------|---------|---------|
| OpenAI | OpenAI | ✅ |
| Anthropic (Claude) | Messages API | ✅ |
| Google (Gemini) | GenerativeAI API | ✅ |
| DeepSeek | OpenAI 兼容 | ✅ |
| 通义千问 | OpenAI 兼容 | ✅ |

### Phase 2: 算力调度与高可用

| 功能 | 描述 |
|------|------|
| **多 Key 轮询** | 配置多个 API Key，支持 Round-Robin 或加权轮询 |
| **智能重试** | 针对 429 (Too Many Requests) / 503 (Overloaded) 自动重试 |
| **故障转移** | Provider 级别 Fallback (DeepSeek 挂 → ChatGPT) |

#### 用户场景

> "我有 3 个 Key，一个是免费的，两个是付费的，优先用免费的，挂了再切付费的。"

### Phase 3: 成本控制与可观测性 (可选迭代)

| 功能 | 实现方案 |
|------|---------|
| **Token 估算限流** | 简易估算法 (1 中文 ≈ 0.6 token, 1 英文单词 ≈ 0.75 token) |
| **语义缓存** | 对 `messages` 内容做 Hash → Redis 缓存 |
| **用量统计** | 记录每个 Key/Provider 的 Token 消耗 |

### 插件配置示例

```yaml
# 路由配置
- uri: /v1/chat/completions
  methods: [POST]
  plugins:
    ai-proxy:
      model: gpt-4
      providers:
        - name: deepseek
          priority: 1
          api_key: ${DEEPSEEK_API_KEY}
          endpoint: https://api.deepseek.com
        - name: openai
          priority: 2
          api_key: ${OPENAI_API_KEY}
          endpoint: https://api.openai.com
      retry:
        count: 3
        codes: [429, 503]
      fallback:
        enabled: true
```

---

## 技术路线图

### 执行顺序

```
┌────────────────────────────────────────────────────────────────┐
│  Step 1: 存储抽象与 DB Less                        ✅ 已完成   │
│  ├── ✅ 定义 Store 抽象接口                                    │
│  ├── ✅ 实现 YAML Parser (tinyyaml)                            │
│  ├── ✅ 实现 yaml_adapter                                      │
│  ├── ✅ 热加载机制 (Signal / Admin API)                        │
│  └── ✅ 版本控制 + Worker 独立初始化                           │
├────────────────────────────────────────────────────────────────┤
│  Step 2: 路由引擎重构                              ✅ 已完成   │
│  ├── ✅ 自实现 Rax FFI (deps/apioak/)                          │
│  ├── ✅ 实现精确匹配                                           │
│  ├── ✅ 实现前缀匹配                                           │
│  ├── ✅ 实现参数匹配 + 参数提取 ({id} 格式)                    │
│  ├── ⏳ 实现正则匹配 (待开发)                                  │
│  └── ✅ 定义优先级仲裁规则                                     │
├────────────────────────────────────────────────────────────────┤
│  Step 3: 系统集成与 Consul 清理                    ✅ 已完成   │
│  ├── ✅ 集成 Store 到系统启动流程                              │
│  ├── ✅ 集成 FFI 路由引擎到请求处理                            │
│  ├── ✅ Balancer 模块适配 Store                                │
│  ├── ✅ 移除 Consul 检查 (cmd/env.lua)                         │
│  ├── ✅ 创建 Consul 存根模块 (向后兼容)                        │
│  └── ✅ 更新依赖配置 (rockspec)                                │
├────────────────────────────────────────────────────────────────┤
│  Step 4: Hybrid 模式 + MongoDB                     ⏳ 待开发   │
│  ├── ⏳ 集成 lua-resty-mongol                                  │
│  ├── ⏳ 实现 CP Admin API (CRUD → MongoDB)                     │
│  ├── ⏳ 实现 DP HTTP Long Polling 同步                         │
│  ├── ⏳ 版本控制机制 (global_config_version)                   │
│  └── ⏳ 本地 Config Dump 容灾                                  │
├────────────────────────────────────────────────────────────────┤
│  Step 5: AI Proxy 插件                             ⏳ 待开发   │
│  ├── ⏳ Phase 1: 协议标准化 + SSE 流式处理                     │
│  ├── ⏳ Phase 2: 多 Key 管理 + 故障转移                        │
│  └── ⏳ Phase 3: Token 估算 + 缓存 (可选)                      │
└────────────────────────────────────────────────────────────────┘
```

### 依赖关系

```
Step 1 (存储抽象) ✅ ──┬──▶ Step 2 (路由引擎) ✅
                      │
                      └──▶ Step 3 (系统集成 + Consul 清理) ✅
                                       │
                                       ├──▶ Step 4 (Hybrid) ⏳
                                       │
                                       └──▶ Step 5 (AI Proxy) ⏳
```

### 当前可用功能

| 功能 | 状态 | 说明 |
|------|------|------|
| DB Less 模式 | ✅ 可用 | 从 `conf/config.yaml` 加载配置 |
| 精确路由匹配 | ✅ 可用 | `/api/v1/users` |
| 参数路由匹配 | ✅ 可用 | `/api/v1/users/{id}` |
| 前缀路由匹配 | ✅ 可用 | `/static/*` |
| 负载均衡 | ✅ 可用 | Roundrobin, Chash |
| 请求代理 | ✅ 可用 | 完整代理流程 |
| Hybrid 模式 | ⏳ 待开发 | CP/DP 分离 |
| AI Proxy | ⏳ 待开发 | LLM 协议标准化 |

---

## 配置文件设计

### 新版 apioak.yaml

```yaml
# APIOAK 配置文件

# 运行模式: standalone (DB Less) | hybrid (CP/DP 分离)
mode: standalone

# ============================================================
# Standalone 模式配置 (DB Less)
# ============================================================
standalone:
  # 配置文件路径 (包含 routes, services, upstreams 等)
  config_file: /etc/apioak/config.yaml
  
  # 热加载方式: signal | admin_api
  reload_method: signal

# ============================================================
# Hybrid 模式配置 (CP/DP 分离)
# ============================================================
hybrid:
  # 节点角色: cp (Control Plane) | dp (Data Plane)
  role: dp
  
  # Control Plane 配置 (仅 CP 节点需要)
  control_plane:
    listen:
      host: 0.0.0.0
      port: 9080
    
    # MongoDB 配置
    mongodb:
      uri: mongodb://localhost:27017
      database: apioak
      # 连接池配置
      pool_size: 10
      connect_timeout: 5000
      read_timeout: 10000
  
  # Data Plane 配置 (仅 DP 节点需要)
  data_plane:
    # CP 节点列表 (支持多个 CP 做高可用)
    control_plane_endpoints:
      - http://cp-1.apioak.local:9080
      - http://cp-2.apioak.local:9080
    
    # 同步配置
    sync:
      # 长轮询超时 (秒)
      long_polling_timeout: 60
      # 重试间隔 (秒)
      retry_interval: 5
    
    # 本地配置备份路径
    config_dump_path: /var/lib/apioak/config_dump.yaml

# ============================================================
# 插件配置
# ============================================================
plugins:
  - cors
  - mock
  - key-auth
  - jwt-auth
  - limit-req
  - limit-conn
  - limit-count
  - ai-proxy        # 新增: AI Proxy 插件

# ============================================================
# 日志配置
# ============================================================
logging:
  level: info       # debug | info | warn | error
  path: /var/log/apioak/

# ============================================================
# 性能配置
# ============================================================
performance:
  # Worker 进程数 (auto = CPU 核心数)
  worker_processes: auto
  # 共享内存大小
  shared_dict_size: 64m
```

### 声明式配置文件 (config.yaml)

```yaml
# 声明式配置文件 (用于 Standalone 模式)

# 服务定义
services:
  - id: svc_user
    name: user-service
    hosts:
      - api.example.com
    protocols:
      - http
      - https
    plugins:
      - id: plg_jwt
      - id: plg_limit

# 路由定义
routes:
  - id: rt_users
    name: get-users
    service_id: svc_user
    paths:
      - /api/v1/users
      - /api/v1/users/:id
    methods:
      - GET
      - POST
    upstream_id: ups_user
    plugins:
      - id: plg_cors

  - id: rt_ai
    name: ai-chat
    paths:
      - /v1/chat/completions
    methods:
      - POST
    plugins:
      - id: plg_ai_proxy

# 上游定义
upstreams:
  - id: ups_user
    name: user-upstream
    algorithm: roundrobin    # roundrobin | chash | random
    nodes:
      - host: 127.0.0.1
        port: 8080
        weight: 10
      - host: 127.0.0.1
        port: 8081
        weight: 5
    health_check:
      enabled: true
      interval: 5
      timeout: 3

# 插件定义
plugins:
  - id: plg_jwt
    name: jwt-auth
    key: jwt-auth
    config:
      secret: your-secret-key
      algorithm: HS256

  - id: plg_limit
    name: rate-limit
    key: limit-req
    config:
      rate: 100
      burst: 50

  - id: plg_cors
    name: cors
    key: cors
    config:
      allow_origins: "*"
      allow_methods: "GET,POST,PUT,DELETE"

  - id: plg_ai_proxy
    name: ai-proxy
    key: ai-proxy
    config:
      model: gpt-4
      providers:
        - name: deepseek
          priority: 1
          api_key: ${DEEPSEEK_API_KEY}
          endpoint: https://api.deepseek.com
        - name: openai
          priority: 2
          api_key: ${OPENAI_API_KEY}
          endpoint: https://api.openai.com
      retry:
        count: 3
        codes: [429, 503]

# SSL 证书定义
certificates:
  - id: cert_example
    name: example-cert
    sni: "*.example.com"
    cert: /etc/ssl/certs/example.crt
    key: /etc/ssl/private/example.key
```

---

## 附录

### 参考项目

- [Apache APISIX](https://github.com/apache/apisix) - 路由引擎参考
- [lua-resty-radixtree](https://github.com/api7/lua-resty-radixtree) - Radix Tree 实现
- [Kong](https://github.com/Kong/kong) - Hybrid 模式参考

### 相关 RFC

- RFC 8259: JSON 数据交换格式
- RFC 7540: HTTP/2
- RFC 8895: Server-Sent Events

---

*文档结束*
