# 更新日志

Nyro 的所有重要变更均记录在此文件中。

---

## v1.0.1

> 发布于 2026-03-10

#### 改进

- **全平台 ARM64 / aarch64 原生构建**：使用 GitHub Actions ARM runner（`ubuntu-24.04-arm`、`windows-11-arm`、`macos-latest`）原生构建，零交叉编译
  - 桌面端：Linux aarch64 AppImage、Windows ARM64 NSIS 安装包
  - 服务端：Linux aarch64、macOS aarch64、Windows ARM64 二进制
- **macOS Intel 原生构建**：使用 `macos-15-intel` runner 原生编译，不再依赖 ARM 交叉编译
- **Homebrew Cask 支持**：`brew tap shuaijinchao/nyro && brew install --cask nyro`（独立 `homebrew-nyro` tap 仓库，发版自动同步版本）
- **一键安装脚本**：macOS/Linux（`install.sh`）和 Windows（`install.ps1`），macOS 自动移除隔离属性
- **前端 chunk 拆分**：Vite `manualChunks` 拆分 react/query/charts，消除 >500kB 打包警告

#### 修复

- **CI**：`cargo check --workspace` 排除 `nyro-desktop`，避免 Linux CI 依赖 GTK
- **CI**：移除 `cargo tauri build` 不支持的 `--manifest-path` 参数
- **CI**：添加 `pkg-config` 和 `libssl-dev` 依赖

#### 清理

- 移除桌面发布中的 MSI 和 deb 包（仅保留 NSIS + AppImage）
- 移除桌面 SHA256SUMS.txt（updater `.sig` 文件已提供完整性校验）
- Homebrew Cask 迁移至独立 `homebrew-nyro` 仓库
- 修复安装脚本和 README 中 `main` → `master` 分支引用

---

## v1.0.0

> 发布于 2026-03-09

Nyro AI Gateway 首个公开版本 — 从原 OpenResty/Lua API Gateway 完整重构为纯 Rust 本地 AI 协议网关。

#### 功能

- **多协议入口**：支持 OpenAI（`/v1/chat/completions`）、Anthropic（`/v1/messages`）、Gemini（`/v1beta/models/*/generateContent`），全协议支持流式（SSE）和非流式响应
- **任意上游出口**：可路由到任意 OpenAI 兼容、Anthropic、Gemini Provider
- **Provider 管理**：创建、编辑、删除 Provider，含 base URL 和加密 API Key
- **路由规则管理**：基于优先级的路由规则，支持模型覆盖和 Fallback Provider
- **请求日志持久化**：SQLite 存储，含协议、模型、延迟、状态码、Token 用量
- **用量统计看板**：概览仪表盘，含按小时/天图表和 Provider/模型维度分布
- **API Key 加密存储**：AES-256-GCM 加密静态存储
- **Bearer Token 鉴权**：代理层和管理层支持独立鉴权配置
- **桌面应用**：基于 Tauri v2 的跨平台桌面应用（macOS / Windows / Linux）
  - 系统托盘及快捷菜单
  - 可选开机自启
  - 应用内自动更新（Tauri updater）
  - macOS 原生标题栏融合
  - 深色/浅色模式切换
  - 中文/英文语言切换
- **服务端二进制**：独立 `nyro-server` 二进制，支持服务器部署，通过 HTTP 访问 WebUI
  - 代理端口和管理端口独立绑定地址配置
  - CORS 来源白名单配置
  - 非本地绑定时强制要求鉴权 Key
- **CI/CD**：GitHub Actions 自动化构建，支持跨平台桌面安装包和服务端二进制发布
