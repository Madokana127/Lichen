# Lichen — 项目状态说明

> 本文件在**每次更改之后**更新，用于记录项目当前状态，供后续推进（其他 session / 其他模型）直接接手。
> 最近更新：2026-11-07

## 1. 项目定位

**Lichen** 是一个 **iOS 端应用**，定位为**电脑端的远程外壳（remote shell）**：
通过网络连接到电脑端 Agent 暴露的**远程网关**，在 iOS 上提供终端 / 会话交互界面。

本次目标：**只搭建应用框架（skeleton），不实现任何具体功能**（不写真实网络、
不写网关协议、不写鉴权、不写终端仿真）。所有具体实现均为协议 + 占位 / stub + `TODO`。

## 2. 环境与约定

| 项 | 值 |
|---|---|
| Windows 仓库（Git 管理副本） | `D:\prflib\coding\swift\Lichen.swiftpm` |
| Git 分支 | `main` |
| WSL 临时工作区 | `/root/lichen-build/Lichen.swiftpm`（一次性，`--delete` 覆盖） |
| 代码任务执行方 | WSL 内 `claude -p`（Claude Code 2.1.318），模型经 ccms 路由到 **DeepSeek Flash** |
| 同步方式 | `rsync -a --delete --exclude .git`：Windows → WSL → Windows |
| 工程形态 | SwiftPM 清单 + SwiftUI iOS app 骨架 |
| 平台限制 | WSL / Windows 均无 Swift 与 Xcode，**无法编译 iOS 工程**；验证只做结构 / 语法人工核对 |

> 目录名带 `.swiftpm` 后缀，按 Swift Playgrounds / SwiftPM 包形态搭建；
> `Package.swift` 使工程可在 Xcode 中作为 Swift Package 打开。后续如需生成
> `.xcodeproj` 或 Swift Playgrounds App 包装，再单独处理（见「待办」）。

## 3. 工作流约定（后续 session 必读）

1. 每次开始**新任务前**，先确认 ccms 有没有变化（见第 5 节）。
2. 代码改动一律走 WSL：`rsync` 复制一份到临时目录 → `claude -p` 完成 →
   `rsync` 同步回 Windows → Windows 侧 `git add / commit`。
3. `PROJECT_README.md` 与 `.gitignore` 由 Windows 侧维护，**不交给 Claude Code 修改**；
   回同步时显式排除。
4. `.git` 不参与同步；WSL 临时目录每次以 `--delete` 覆盖，视为一次性工作区，
   `TASK.md` / `claude_*.log` 等脚手架文件不进仓库（`.gitignore` 已覆盖）。
5. 密钥不进仓库：API key 只写入 ccms 加密密钥库（`keys.enc`），不落到任何源码 / 文档 / 日志。
6. WSL 默认 shell 是 fish、默认用户 root：非交互命令一律写成 **bash 脚本文件**执行，
   密钥等敏感值作为**命令行参数**传入（不写进脚本文件）；避免在 `bash -c` 里用 `${...}`
   这类 fish 不认识的语法（会被截获报错）。
7. UI 设计先走 HTML 预览（见第 8 节）：HTML 原型敲定后才写 SwiftUI；把敲定的原型与
   设计 token 作为 Claude Code 的输入，不让模型凭空发挥视觉。

## 4. 当前状态

- [x] Git 仓库初始化（分支 `main`），`.gitignore`、`PROJECT_README.md` 就位
- [x] ccms 状态核对（本轮）：无变化，详见第 5 节
- [x] **iOS 应用框架骨架（本次任务，已完成）**：13 个 Swift 文件，结构见第 6 节
- [x] 备用模型通道准备（本轮用户追加要求）：详见第 7 节
- [x] 后续开发方法约定（本轮）：HTML 预览工作流 + 跨平台框架 / 桥接层方向（见第 8、9 节）
- [ ] 具体功能：网关连接 / 会话 / 终端 / 设置（**后续任务，本次不做**）

骨架验收（回同步前在 WSL 侧实测）：13 个 Swift 文件、28 处 `TODO`、
全仓无 `URLSession` / `NWConnection` / `WebSocketTask` / `URLRequest` / 明文密钥模式、
`GatewayClient` 仅协议声明无实现、`PROJECT_README.md` 与 `.gitignore` 的 md5 与 Windows 侧
一致（Claude 未改动）、Claude 未执行 git 命令、未写入任何凭据。

## 5. ccms 状态核对（每次新任务前执行）

本轮核对结果（2026-11-07，任务开始前执行）：

| 检查项 | 结果 |
|---|---|
| 已安装二进制 | `/usr/local/bin/ccms`，`CCMS 0.2.1` |
| WSL 工作副本 | `/root/CCMS`，`Cargo.toml` = `0.2.1`；与 Windows `D:\prflib\CCMS` 源码 `diff -rq` 零差异（排除 `target/`、`.git`、`PROJECT.md`、`*.bak`） |
| 文档版本 | `D:\prflib\CCMS\PROJECT.md` → 0.2.1（Rust 重写），与二进制一致 |
| 本地 Git | 分支 `RuRe`，HEAD `8c0bcf6`，工作区干净，与 `origin/RuRe` 跟踪引用一致（`rev-list --left-right` = `0 0`） |
| 远端刷新 | `git fetch` / `git ls-remote` 在 Windows 与 WSL **均因网络不可达失败**（`Failed to connect to github.com:443`），无法确认远端是否有更新 |
| 运行态 | router 运行中 `http://127.0.0.1:8788`；`~/.claude/settings.json` 已由 `ccms --on` 接管；`routes.json` 五档全部指向 `deepseek/deepseek-flash` |
| 结论 | 以本地可得证据判断 **ccms 无变化**，CLI 接口按 0.2.1 `Commend.md` 使用；远端状态待网络恢复后补核 |

本轮与 ccms 相关的其它事实 / 踩坑：

- 官方 DeepSeek key 已在加密库（掩码 `sk-4d4…c76b`），`ccms --test deepseek` 返回上游
  **HTTP 500**（非 401，鉴权正常，属上游繁忙 / 不稳定；router 日志显示历史请求有 200 也有 500，
  ccms 重试可兜住）—— 这也是本轮用户要求准备备用通道的原因。
- `claude -p` 出现 `Claude Code doesn't recognize the model "ccms-sonnet"` 警告：ccms 哨兵模型名的
  正常提示，请求仍经 router 转发到 `deepseek-flash`，不影响任务（退出码 0）。
- WSL 默认用户 root，`claude -p --dangerously-skip-permissions` 被 Claude Code 以
  「cannot be used with root/sudo privileges」拒绝；改为
  `--allowedTools "Read,Write,Edit,Glob,Grep,Bash" --permission-mode acceptEdits` 后正常。
- 本轮之前对 ccms 运行期做的可逆改动（沿用至今）：密钥库 1 把官方 DeepSeek key、
  `ccms --route --all deepseek deepseek-flash`、`ccms --on`；原 `routes.json` / `settings.json`
  已备份为 `*.pre-lichen.bak`（在 `~/.config/ccms/`，不在 Git 仓库内）。

## 6. 目录结构

```
Lichen.swiftpm/
├── .gitignore                       # Swift/Xcode、密钥、任务脚手架（Windows 侧维护）
├── PROJECT_README.md                # 本文件（Windows 侧维护）
├── Package.swift                    # tools 5.9 / iOS 17 / LichenCore + LichenApp 两个 library / 3 个 target
├── Sources/
│   ├── LichenApp/
│   │   ├── LichenApp.swift          # @main App 入口，WindowGroup { RootView() }
│   │   ├── RootView.swift           # 三 tab TabView（会话 / 网关 / 设置）
│   │   └── Features/
│   │       ├── Sessions/SessionsView.swift    # 占位列表 + 「暂无会话」
│   │       ├── Gateway/GatewayView.swift      # 占位连接状态（.disconnected）
│   │       └── Settings/SettingsView.swift    # 占位 Form，无配置存储
│   └── LichenCore/
│       ├── Gateway/
│       │   ├── GatewayConfiguration.swift    # host / port / displayName 占位
│       │   ├── GatewayConnectionState.swift  # 4 状态枚举
│       │   └── GatewayClient.swift           # 仅协议 + TODO（无实现）
│       ├── Session/
│       │   ├── Session.swift                 # Identifiable 占位模型
│       │   └── SessionStore.swift            # 仅协议 + TODO
│       └── Terminal/TerminalBuffer.swift      # 仅协议 + TODO（不解析 ANSI）
└── Tests/LichenCoreTests/LichenCoreTests.swift  # 2 个 XCTest 占位测试
```

## 7. 备用模型通道（本轮用户追加）

官方 DeepSeek API 繁忙时，后续若再需要调用模型，改用**千问 MaaS 平台**上的
`DeepSeek Flash 1017`：

| 项 | 值 |
|---|---|
| provider | `qwen`（ccms `providers.json` 已有） |
| base_url | `https://maas.qianwenaiapi.com/apps/anthropic`（用户纠正后的正确地址） |
| 准确 model ID | **`deepseek-v4.1-flash-1017`** |
| 密钥 | 已通过 `ccms --key qwen --stdin` 写入加密库（掩码 `sk-ws-…bt0M`），**未落任何文件** |
| 实测 | `POST /apps/anthropic/v1/messages` → **HTTP 200**，回复 `OK` |

查证过程记录：

- `GET /compatible-mode/v1/models` 可列出全部模型（用户第一次给的 compatible-mode 地址，
  虽不适合作为 ccms 的 Anthropic 端点，但可用于查模型列表）；`GET /v1/models` 为空。
- `vanchin/deepseek-v4.1-flash-1017` 等带 `vanchin/` 前缀的变体返回
  「The product is not activated」/「does not exist or you do not have access」，**不可用**；
  `deepseek-v4.1-flash`（无 1017 后缀）也可用，但不是本次指定的 1017 版本。
- `ccms --models qwen` 走 `/apps/anthropic/v1/models`，该端点返回 `Not support`；
  `ccms --test qwen` 用 providers.json 的旧默认模型 `qwen3-coder-plus` 会 400
  「Model not exist.」——因此切换时必须显式带 model ID。

**一键切换 / 还原**（`routes.json` mtime 热加载，无需重启 router）：

```bash
ccms --route --all qwen deepseek-v4.1-flash-1017   # 切到备用通道
ccms --route --all deepseek deepseek-flash         # 切回官方
```

> 本轮骨架生成完成后不再调用模型，**当前生效路由未改动**（仍是五档
> `deepseek/deepseek-flash`）；仅完成密钥入库、model ID 实测与命令记录。
> 后续任务开始前请连同本节一起重新核对 ccms 状态（见第 5 节）。

## 8. UI 预览工作流（无苹果设备时的设计闭环）

用户手边没有苹果设备，SwiftUI 的真机 / Preview 验证安排在学校机房的 Xcode 完成。
因此**设计敲定不依赖 Xcode**，闭环如下：

```
设计想法 → HTML/CSS 原型（本机浏览器 / Hermes 内联预览）→ 用户敲定
        → SwiftUI 实现（逐视图对应）→ 学校 Xcode Preview 验证
        → 反馈回 HTML 原型迭代
```

约定：

- `Preview/` 存放静态 HTML 原型，不进 SwiftPM target、不参与 Xcode 构建；
  每个 SwiftUI 视图对应一个原型片段（或单一 `index.html` 内多视图切换），命名与视图对齐。
- 原型是**单文件自包含 HTML**（CSS 变量定义 token、内嵌少量 JS 模拟状态与假数据），
  不引入构建工具、不连真实网关；按 `claude-design` 技能「先定 surface 再定 token」——
  Lichen 属 Monitor / Command·Inspect 类界面，不要营销式 hero + 三卡片。
- 设计 token（颜色 / 间距 / 字体 / 圆角 / 动效）在 CSS `:root` 单一定义，敲定后映射为
  SwiftUI 侧常量（可脚本生成，或落成 `design-md` 的 DESIGN.md 规格），避免两边各改一套。
- 视觉起点可复用 `popular-web-designs` 模板；终端 / 开发者工具调性可参考
  Ollama、OpenCode、x.ai、VoltAgent、Linear、Warp（取设计原则，不抄 proprietary 版式）。
- 每次视觉变更先改 HTML 并在浏览器确认，再改 SwiftUI；SwiftUI 侧调整反向同步回 HTML。
  需要在聊天内直接看时用 `::preview{file=...}` 内联预览。
- 本轮只确立工作流：`Preview/` 尚未建立、未敲定任何视觉设计；下一次 UI 任务按此落地。

## 9. 架构演进与跨平台框架选型（后续，本轮不实施）

当前分层：`LichenCore`（纯 Swift 协议 / 模型）+ `LichenApp`（SwiftUI）。
用户规划：核心逻辑以后可能换成通用（跨平台）框架；UI 可能换目标平台，也可能直接换成
通用 UI 框架；两者之间用**桥接层**连接。
> 术语：这里的「后端」指本地核心逻辑层与远程网关通信，不是云端服务。

### 9.1 分层与桥接层

```
UI 层（可替换）     SwiftUI（现在） / 通用 UI 框架（以后）
      ↕  桥接层：与语言无关的契约（命令 + 事件流 + DTO）
核心层（可替换）     Swift（现在） / 通用框架（以后）
      ↕
电脑端 Agent 网关
```

- 核心不 import SwiftUI / UIKit，只暴露纯数据、命令与状态订阅；UI 只依赖契约。
- **当前骨架已预留桥接位置**：`GatewayClient` / `SessionStore` / `TerminalBuffer` 都是协议，
  未来换核心只需写新适配器实现这些协议，UI 层不用重写。
- 状态映射：桥接层把核心事件流适配成 SwiftUI 的 `@Observable` / `ObservableObject`；
  换 UI 框架时只换适配器。
- 契约形式按「通用程度」递增：Swift protocol → `uniffi` / C ABI 生成的绑定
  → protobuf / Cap'n Proto 消息 → WIT（WASM）接口。

### 9.2 通用核心框架候选

| 方案 | 优点 | 代价 / 适用 |
|---|---|---|
| **Rust + uniffi**（首选） | 终端仿真、协议编解码、加密性能好且内存安全；uniffi 自动生成 Swift / Kotlin / TS 绑定；本机 WSL 已有 Rust 工具链（ccms 即 Rust） | 需维护 FFI 与绑定生成；适合把 `LichenCore` 逐步下沉 |
| **Kotlin Multiplatform (KMP)** | iOS 一等公民，直接产出 Swift 可调用的 framework；业务逻辑共享，UI 仍可留 SwiftUI；与 Compose MP 可渐进衔接 | 引入 Gradle / Kotlin 工具链 |
| **TypeScript + WASM / WASI（或 Capacitor）** | 与 HTML 预览同语言，设计产物可复用；生态大 | 终端与低延迟场景需额外原生模块，运行时体积较大 |
| **C / C++ + C ABI** | 最通用，任何平台都能调；可复用 libvterm 等成熟 C 库 | 开发效率低、内存安全自负 |

### 9.3 通用 UI 框架候选（若 UI 也要跨平台）

| 方案 | 优点 | 代价 / 适用 |
|---|---|---|
| **Flutter** | 单代码库覆盖 iOS / Android / 桌面 / Web，渲染性能足够终端类界面；Dart 与 Rust 核心经 FFI 衔接成熟 | 放弃 SwiftUI 原生观感；学校 Xcode 预览环节改为 Flutter 预览 |
| **React Native / Expo，或 Web UI + Tauri 2 / Capacitor** | 最大程度复用 HTML 预览产物；Tauri 2 支持 iOS，前端接近设计稿 | RN 需原生模块做终端 / 网关；纯 Web 方案在 iOS 后台与体验受限 |
| **Compose Multiplatform** | 与 KMP 同语言，核心与 UI 一起跨平台 | iOS 端成熟度仍在推进；SwiftUI 预览工作流需重做 |

### 9.4 推荐路径（供决策，未定案）

1. **近期**：保持 Swift 核心 + SwiftUI，但严格执行「协议即桥接层」——
   UI 只依赖 `LichenCore` 协议，不碰实现；同时把第 8 节 HTML 预览跑起来。
2. **中期**：若确定跨平台，优先 **Rust + uniffi** 下沉 `LichenCore`（网关协议 / 会话 / 终端缓冲），
   SwiftUI 侧只留薄适配器实现现有协议；Rust 部分可直接在 WSL 编译验证。
3. **若连 UI 也换**：优先 **Flutter**（配 Rust 核心）；若希望 HTML 设计产物直接复用，
   选 **Tauri 2 / Capacitor + Web UI**。
4. **不论哪条路**：先定稿桥接层契约（命令 + 事件 + DTO）并纳入版本管理，再写实现，
   避免各语言手写漂移。

> 本轮只记录方向与候选：**不做选型定案、不引入任何依赖、不改现有代码**。

## 10. 变更记录

### 2026-11-07 · 初始化（commit `8f5ed28`）
- 在 `D:\prflib\coding\swift\Lichen.swiftpm` 执行 `git init -b main`，配置本地提交身份。
- 新增 `.gitignore`（Swift/Xcode、密钥、任务脚手架文件）。
- 新增 `PROJECT_README.md`（本文件），确立「每次更改后更新状态」的约定。
- 核对 ccms：无变化；完成 router / 密钥 / 五档路由的准备工作。

### 2026-11-07 · iOS 应用框架骨架（本次任务）
- 任务开始前重新核对 ccms：无变化（详见第 5 节；远端因网络不可达未刷新）。
- `rsync -a --delete --exclude .git` Windows → WSL `/root/lichen-build/Lichen.swiftpm`，
  覆盖上一轮失败残留；`TASK.md` 由 Windows 侧 scratch 复制到工作区。
- WSL 内 `claude -p`（ccms → DeepSeek Flash）生成 13 个 Swift 文件，`claude` 退出码 0；
  按技能用 print mode，因 root 限制改用 `--allowedTools` + `acceptEdits`。
- 验收：13 文件 / 28 TODO / 无真实网络与鉴权实现 / 两份文档 md5 未变 / 未执行 git / 无凭据落盘。
- `rsync -a --delete` WSL → Windows，排除 `.git`、`TASK.md`、`claude_*.log`、
  `PROJECT_README.md`、`.gitignore`。
- 用户中途追加：官方 DeepSeek 繁忙，准备千问 MaaS 备用通道（密钥入加密库、
  `deepseek-v4.1-flash-1017` 实测 200、切换命令见第 7 节）；当前生效路由未改。
- 更新本文件为真实状态；`git add -A && git commit`。

### 2026-11-07 · 后续开发方法约定（本轮，仅文档）
- 用户明确：手边无苹果设备，SwiftUI 预览在学校机房 Xcode 完成。
- 新增第 8 节：HTML 原型敲定设计 → SwiftUI 实现 → 学校 Xcode Preview 验证的闭环与 `Preview/` 约定。
- 新增第 9 节：跨平台核心框架候选（Rust+uniffi / KMP / TS+WASM / C ABI）、通用 UI 框架候选（Flutter / RN+Tauri / Compose MP）、「协议即桥接层」与推荐路径。
- 本轮**不做选型定案、不引入依赖、不改任何代码**。

## 11. 待办 / 后续

- [ ] 具体功能：网关连接 / 会话 / 终端 / 设置（后续任务）
- [ ] 建立 `Preview/` 与最小 HTML 原型（对应当前三 tab 占位视图），跑通第 8 节工作流
- [ ] 定稿桥接层契约（命令 / 事件 / DTO）与 IDL 形式，纳入版本管理
- [ ] 框架选型定案（第 9.4 节）；若下沉 Rust 核心，先在 WSL 编译验证
- [ ] 明确远程网关协议（WebSocket / HTTP / 自定义？）与鉴权方式
- [ ] 确定工程最终形态：保持 SwiftPM 包、还是补 `.xcodeproj` / Swift Playgrounds App
- [ ] 在有 Xcode 的 macOS 上做真实编译与模拟器运行验证
- [ ] 网络恢复后补做 ccms 远端 `git ls-remote` 核对；若 ccms 升级，重新核对第 5 节并按需调整命令
- [ ] 后续任务开始前重新核对 ccms（含第 7 节备用通道）；若官方仍繁忙按第 7 节切换
