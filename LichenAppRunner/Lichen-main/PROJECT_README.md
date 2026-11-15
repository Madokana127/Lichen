# Lichen — 项目状态说明

> 本文件在**每次更改之后**更新，供后续推进（其他 session / 其他模型）直接接手。
> 最近更新：2026-11-14

## 1. 项目定位

**Lichen** 是 iOS 端应用，定位为电脑端 Agent 的**远程外壳（remote shell）**：
通过网络连接电脑端 Agent 暴露的远程网关，在 iOS 上提供会话 / 终端交互界面。

当前阶段：**真实功能与 SwiftUI 界面均已落地**，占位 stub 与 `TODO` 已清零，
源码内无真实网关地址或凭据。代码尚未在 macOS / Xcode 上完整编译验证，见第 7 节。

> 设计阶段曾使用单文件 HTML 原型敲定视觉，产物已从仓库移除（2026-11-14 用户要求
> 「只上传应用本身的代码」）。当前仓库只含应用工程与项目说明；设计 token 已落在
> `Sources/LichenApp/Design/DesignTokens.swift`，是唯一事实来源。

## 2. 环境与约定

| 项 | 值 |
|---|---|
| Windows 仓库 | `D:\prflib\coding\swift\Lichen.swiftpm` |
| Git 远端 | `https://github.com/Madokana127/Lichen.git`（`main`，PUBLIC，2026-11-14 首次推送） |
| WSL 临时工作区 | `/root/lichen-build/Lichen.swiftpm`（一次性，`--delete` 覆盖） |
| 代码任务执行方 | WSL 内 `claude -p`（Claude Code 2.1.318），模型经 ccms 路由到 DeepSeek Flash |
| 工程形态 | SwiftPM 清单：tools 5.9 / iOS 17；target `LichenCore`、`LichenApp`、`LichenCoreTests`；零第三方依赖 |
| 平台限制 | Windows / WSL 均无 Swift 与 Xcode；编译、Preview 与真机验证在学校机房 macOS 完成 |

工作流约定：

1. 代码改动走 WSL：`rsync -a --delete --exclude .git` Windows → WSL → Windows，
   `claude -p` 在 WSL 执行，Windows 侧 `git add / commit / push`。
2. `PROJECT_README.md` 与 `.gitignore` 由 Windows 侧维护，不交给 Claude Code。
3. 密钥不进仓库：API key 只存在 ccms 加密密钥库，不落任何源码 / 文档 / 日志。
4. WSL 默认 shell 是 fish、默认用户 root：非交互命令一律写成 bash 脚本文件执行，
   敏感值作为命令行参数传入。
5. 每批改动回同步后做静态验收（TODO / imports / 括号 / 悬空引用），再提交。

## 3. 目录结构

```
Lichen.swiftpm/
├── .gitignore                       # Swift/Xcode、密钥、任务脚手架
├── PROJECT_README.md                # 本文件
├── Package.swift                    # tools 5.9 / iOS 17；LichenCore + LichenApp + LichenCoreTests
├── Sources/
│   ├── LichenCore/                  # 纯 Swift 核心（不 import SwiftUI）
│   │   ├── Gateway/                 # Configuration / ConnectionState / JSONRPC / Status
│   │   │                            # GatewayClient / URLSessionGatewayClient / ReconnectPolicy / EventRouter
│   │   ├── Session/                 # Session / SessionMessage / SessionStore（含持久化）
│   │   ├── Agent/                   # Agent / AgentBrand / AgentStore
│   │   └── Terminal/                # TerminalBuffer（带 ANSI 解析的有界缓冲）
│   └── LichenApp/                   # SwiftUI 界面，只依赖 LichenCore 协议
│       ├── LichenApp.swift          # @main 入口（library target 兼容性见第 7 节）
│       ├── RootView.swift           # 全屏层 / 78% 抽屉 / 圆形扩散与反向收拢 / reduceMotion
│       ├── Design/DesignTokens.swift# 明暗两套配色 + 尺寸 / 字体 / 圆角 / 动效常量
│       ├── State/AppState.swift     # @Observable 状态机（连接 / 会话 / 外观 / 关闭闭环）
│       └── Features/
│           ├── Start/StartView.swift        # 开始页
│           ├── Chat/ChatView.swift          # 对话页（输入框 + bar + 审批卡片）
│           ├── Sessions/SessionsView.swift  # 状态抽屉（分组 / 搜索 / 账户条）
│           ├── Gateway/GatewayView.swift    # 连接页（两档 + SSL 证书区）
│           └── Settings/SettingsView.swift  # 全屏设置页
└── Tests/LichenCoreTests/           # 9 组单测
```

## 4. 当前状态与验收边界

- [x] `LichenCore`：网关契约层、`/api/status` 探测、token / OAuth ticket 双鉴权、
  `URLSession` 网络传输层（心跳 / 退避重连 / 事件续传 / TLS）、会话 / 消息 / Agent、
  带 ANSI 的终端缓冲、9 组单测；约 8,200 行
- [x] `LichenApp`：设计系统、`AppState`、开始 / 对话 / 状态抽屉 / 连接 / 全屏设置五视图，
  12 个 `#Preview`；三 tab 占位已移除
- [x] 连接方式仅「远程网关 / SSL」两档；默认端口 `9119`；全项目无「局域网 / 中继」文案
- [x] 关闭闭环五要素：来源记录 / 动态锚点 / 反向圆形收拢 / 恢复 Agent 浮框 /
  `accessibilityReduceMotion` 分支
- [x] 全项目 `TODO` / `fatalError` = 0；imports 仅 Foundation / SwiftUI / Observation /
  LichenCore / XCTest；31 个 Swift 文件括号配平；悬空引用 0
- [ ] **Xcode 编译 / 预览验证未完成**：首轮编译（2026-11-14 机房）报 3 处访问控制错误，
  已修复（`b19f0e9`），**修复后尚未复编**

验收边界：以上多为静态文本 / 结构核对。**机房 Xcode 首轮编译确实抓出了静态检查漏掉的
访问控制错误（3 处，已修）**，说明静态自洽核对不能替代编译；修复后仍待复编，
且不包含 Xcode Preview、真机运行或与真实 Hermes 网关的端到端联通。

## 5. 远程网关协议要点

依据本机 `D:/Hermes/hermes-agent/` 源码核对（结论带文件路径 + 行号，见该项目源码）：

- HTTP 默认 `127.0.0.1:9119`（CLI `--port` / `--host`；config.yaml 无 port/host 键）；
  `GET /api/status` 公开，含 `auth_required` / `auth_providers` / `auth_flows`。
- `auth_required=false` → loopback 静态 token 模式：REST 头 `X-Hermes-Session-Token`，
  WS `?token=`；`true` → OAuth 闸门：REST 用 cookie / Bearer，WS 每次连接前
  `POST /api/auth/ws-ticket` 取 30s 单次 `?ticket=`。
- WS 固定 `/api/ws`；换行分隔 JSON-RPC 2.0；连接后首帧 `gateway.ready`
  （含 heartbeat / replay_epoch / session_authority）；随后发 `client.capabilities`
  `{"server_requests": true}`，否则审批请求会被立即拒绝。
- 常用方法：`session.create` / `session.list` / `session.resume` / `session.activate` /
  `prompt.submit` / `session.events.since` / `approval.respond`；审批 choice 四值
  `once` / `session` / `always` / `deny`。发消息无 REST 端点，只能走 WS `prompt.submit`。
- 客户端心跳 15s、45s 无入站判定断线；重连全抖动退避 300ms→15s，稳定 5s 重置，
  单次 connect 超时 15s。
- TLS：Hermes 服务端不内置 TLS，靠反向代理终止；`https:` → `wss:`，证书必须系统信任。
  Lichen 的「SSL」档另设显式自签证书开关（走 `URLSessionDelegate`），属 Lichen 扩展。

## 6. 架构演进与桥接层（方向，未定案）

当前分层：`LichenCore`（纯 Swift 协议 / 模型）+ `LichenApp`（SwiftUI），
UI 只依赖 `GatewayClient` / `SessionStore` / `TerminalBuffer` 协议，不 import 核心实现细节。

- 通用核心候选：**Rust + uniffi**（倾向）、Kotlin Multiplatform、TS + WASM、C/C++ + C ABI。
- 通用 UI 候选：**Flutter**（倾向）、Tauri 2 / Capacitor + Web UI、React Native、Compose MP。
- 桥接契约按通用程度递增：Swift protocol → uniffi / C ABI → protobuf → WIT(WASM)。
- 不论哪条路：先定稿「命令 + 事件流 + DTO」契约并纳入版本管理，再写实现。

## 7. Xcode 验证与待办

- [ ] **取最新提交后 Cmd+B 复编**（首轮 3 处访问控制错误已修 `b19f0e9`）；
  若有新错误，继续发 Issue Navigator 截图。
- [ ] 确认 `@main` 在 library target 下是否导致「无法作为 App 运行」：若报错，按
  `LichenApp.swift` 头部注释二选一（改 `.executableTarget` + `.executable` product，
  或去掉 `@main` 仅保留 `App` 结构供 Preview）。`#Preview` 画布不依赖 executable target。
- [ ] 与真实 Hermes 网关端到端联调（token / OAuth ticket / wss 自签证书显式开关）。
- [ ] 定稿桥接层契约与 IDL 形式；框架选型定案；若下沉 Rust 核心，先在 WSL 编译验证。
- [ ] 补齐工程最终形态：保持 SwiftPM 包，还是补 `.xcodeproj` / Swift Playgrounds App。

## 8. 变更记录（简表）

| 日期 | 提交 | 内容 |
|---|---|---|
| 2026-11-07 | `8f5ed28` | 仓库初始化（`.gitignore` + 状态说明） |
| 2026-11-07 | `9eca0de` | SwiftPM + SwiftUI 骨架（协议 + stub） |
| 2026-11-07 | `8f6a954` | 文档：开发工作流与跨平台框架方向 |
| 2026-11-14 | `b536d24` `7fa54ee` `785e86c` | HTML 设计原型 v0.1 → v0.3（**产物已于本次移除**） |
| 2026-11-14 | `283b702` | 任务 A：LichenCore 网关契约层 + 单测 |
| 2026-11-14 | `6e75bf1` | 任务 A2：Session / 消息 / Agent / Terminal 真实实现 |
| 2026-11-14 | `2b4768d` | 任务 B：URLSession 网关传输层 + 单测 |
| 2026-11-14 | `ba45dcb` | 任务 C：SwiftUI 设计系统、AppState 与五视图 |
| 2026-11-14 | `ab6f24c` | 任务 D：reduceMotion、默认端口对齐、`@main` 兼容性注释 |
| 2026-11-14 | `b19f0e9` | 修复 Xcode 首轮编译的 3 处访问控制错误（两处 `Snapshot` 提升为 internal） |
| 2026-11-14 | `c27304a` | 记录 Xcode 首轮编译反馈；首次推送 GitHub |
| 2026-11-14 | 本次 | 移除预览性质产物，仓库只保留应用工程 |
