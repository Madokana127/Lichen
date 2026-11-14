# Lichen — 项目状态说明

> 本文件在**每次更改之后**更新，用于记录项目当前状态，供后续推进（其他 session / 其他模型）直接接手。
> 最近更新：2026-11-14

## 1. 项目定位

**Lichen** 是一个 **iOS 端应用**，定位为**电脑端的远程外壳（remote shell）**：
通过网络连接到电脑端 Agent 暴露的**远程网关**，在 iOS 上提供终端 / 会话交互界面。

当前阶段：**骨架阶段已完成，真实功能与 SwiftUI 界面均已落地**（2026-11-14）。
`LichenCore` 含网关协议、会话 / 消息 / Agent、终端缓冲与 `URLSession` 网络传输层；
`LichenApp` 含设计系统、`AppState` 与开始 / 对话 / 状态 / 连接 / 设置五视图。
全部占位 stub 与 `TODO` 已清零（全项目 0 处），源码内无真实网关地址或凭据。
代码**尚未在有 Xcode 的 macOS 上编译 / 预览**（本机与 WSL 均无 Swift 工具链），见第 11 节。

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

## 4. 当前状态（2026-11-14）

- [x] Git 仓库、`.gitignore`、本文件就位；分支 `main`
- [x] UI 原型 v0.1 → v0.2 → **v0.3 已敲定**：`Preview/index.html` + `Preview/DESIGN.md`
  （明亮 / 黑暗双主题、全屏设置页、DeepSeek 式状态抽屉、两档连接、反向圆形关闭闭环）
- [x] **真实 Swift 功能已落地**（任务 A / A2 / B）：`LichenCore` 含网关契约层、
  会话 / 消息 / Agent / 终端、URLSession 网络传输层与单测；累计约 8,200 行
- [x] **SwiftUI 界面已落地**（任务 C / D）：`LichenApp` 含 `DesignTokens`、`AppState`
  与开始 / 对话 / 状态抽屉 / 连接 / 全屏设置五视图，12 个 `#Preview`
- [x] 关闭闭环五要素齐备：来源记录 / 动态锚点 / 反向圆形收拢 / 恢复 Agent 浮框 /
  `accessibilityReduceMotion` 分支
- [x] 连接方式仅「远程网关 / SSL」两档；全项目无「局域网 / 中继」文案
- [x] 全项目 `TODO` / `fatalError` = **0**；imports 仅
  Foundation / SwiftUI / Observation / LichenCore / XCTest
- [x] 静态自洽核对通过：31 个 Swift 文件括号配平、`DesignTokens.*` / `palette.*` /
  `appState.*` 悬空引用 0、无真实网关地址 / 密钥
- [ ] **未在 Xcode 编译 / 预览**：需在学校机房验证（见第 11 节）

验收边界：以上均为静态文本 / 结构核对与真实浏览器（HTML 原型）实测，
**不包含 Swift 编译、Xcode Preview、真机运行，也不包含与真实 Hermes 网关的端到端联通**。

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

UI 原型任务开始前再次核对（同一任务的延续，非新任务）：`ccms --version` = `0.2.1`、
router 运行中 `127.0.0.1:8788`、五档仍为 `deepseek/deepseek-flash`、
Windows `D:\prflib\CCMS` HEAD `8c0bcf6` 且与 `/root/CCMS` 源码零差异 → **无变化**；
`D:\prflib\CCMS\PROJECT.md` 于 2026-11-12 细化（含「改名 Alkanet / 1.0.0」重构计划），
属文档推进，运行接口未变，命令无需调整。远端仍因网络不可达未刷新。
用户明确「用 DeepSeek 官方 API 就行」，故本轮**未启用**第 7 节备用通道，
`routes.json.pre-uiux.bak` 备份保留；本轮用到的 `ui-ux-pro-max` 技能已装入
`D:\Hermes\skills\ui-ux-pro-max-plus\`。

**UI v0.2 任务（新任务）开始前核对（2026-11-14）**：`ccms --version` = `0.2.1`、
`/root/CCMS/Cargo.toml` = `0.2.1`、Windows `D:\prflib\CCMS` HEAD `8c0bcf6`、
`rev-list --left-right HEAD...origin/RuRe` = `0 0`、Win↔WSL 源码 `diff -rq` 零差异；
**远端 `git ls-remote` 本轮成功**：`refs/heads/RuRe` = `8c0bcf67b01c…` 与本地 HEAD 一致，
此前「远端未刷新」的待办就此补核完成。

**v0.3 / Swift 实现任务（新任务）开始前核对（2026-11-14）**：`ccms --version` = `0.2.1`；
Windows HEAD 与 `/root/CCMS` 源码零差异；`origin/RuRe` 与本地一致；router 运行中，
五档均为官方 `deepseek/deepseek-flash`；`PROJECT.md` 含 Alkanet 1.0.0 规划但代码未动 → 判为无变化。
`PROJECT.md`（2026-11-12 细化）明确 **1.0.0「Alkanet」仍在规划、代码一行未动**，
0.2.1 技术基线全部有效 → **ccms 无变化，命令无需调整**。
router 仍在 `127.0.0.1:8788` 运行，五档 `deepseek/deepseek-flash`（官方通道，未启用备用）。

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
├── Preview/
│   ├── index.html                   # v0.3 四屏自包含 HTML 原型（不进 SwiftPM target）
│   └── DESIGN.md                    # 设计 token / 四屏 / 动效 / SwiftUI 映射规格
├── .gitignore / PROJECT_README.md   # Windows 侧维护
├── Package.swift                    # tools 5.9 / iOS 17 / LichenCore + LichenApp + LichenCoreTests
├── Sources/
│   ├── LichenCore/                  # 纯 Swift 核心（不 import SwiftUI）
│   │   ├── Gateway/                 # Configuration / ConnectionState / JSONRPC / Status
│   │   │                            # GatewayClient / URLSessionGatewayClient / ReconnectPolicy / EventRouter
│   │   ├── Session/                 # Session / SessionMessage / SessionStore（含持久化）
│   │   ├── Agent/                   # Agent / AgentBrand / AgentStore
│   │   └── Terminal/                # TerminalBuffer（带 ANSI 解析的有界缓冲）
│   └── LichenApp/                   # SwiftUI 界面，只依赖 LichenCore 协议
│       ├── LichenApp.swift          # @main 入口（library target 兼容性见第 11 节）
│       ├── RootView.swift           # 全屏层 / 78% 抽屉 / 圆形扩散与反向收拢 / reduceMotion
│       ├── Design/DesignTokens.swift# 两套配色 + 字体 / 间距 / 圆角 / 动效常量
│       ├── State/AppState.swift     # @Observable 状态机（连接 / 会话 / 外观 / 关闭闭环）
│       └── Features/
│           ├── Start/StartView.swift        # 开始页
│           ├── Chat/ChatView.swift          # 对话页（输入框 + bar + 审批卡片）
│           ├── Sessions/SessionsView.swift  # 状态抽屉（分组 / 搜索 / 账户条）
│           ├── Gateway/GatewayView.swift    # 连接页（两档 + SSL 证书区）
│           └── Settings/SettingsView.swift  # 全屏设置页
└── Tests/LichenCoreTests/           # 9 组单测
```

> 用户要求预览产物另放一份：`D:\prflib\coding\swift\LichenPreview.html`
> （与 `Preview/index.html` 内容一致的便捷副本，便于直接双击打开）。
> **Git 受控源仍是仓库内 `Preview/index.html`**，每次视觉变更后同步覆盖该副本。

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
  - 需要在聊天内直接看时用 `::preview{file=...}` 内联预览。
  - 预览产物另存一份到 `D:\prflib\coding\swift\LichenPreview.html`（用户要求），
    与仓库内 `Preview/index.html` 保持一致；仓库内那份是 Git 受控源。
- **v0.1 已落地**：四屏自包含原型 + `Preview/DESIGN.md`（token / 四屏 / 动效规格），
  风格「Lichen daylight」，由 DeepSeek Flash 依 `ui-ux-pro-max` 资源库定稿。
- **v0.2 已落地**（本轮用户三条意见）：设置页全屏层、状态页参考 DeepSeek 形式
  （78% 抽屉 / 搜索胶囊 / 弱化分组 / 纯文字行 / 账户条 / 底层 parallax）、
  bar 与对话框描边共用 `--composer-line`、审批改浅色卡片、
  **明亮 + 黑暗两套完整配色**（顶部调试条与设置页「外观」双入口切换，localStorage 记忆）。
  验收数据见 `Preview/DESIGN.md` 第 6 节；**仍等待用户敲定**，敲定后按第 7 节映射 SwiftUI。

- **v0.3 已落地**（本轮用户第 3、4 点）：连接方式只留「远程网关 / SSL」两档并去掉局域网文案；
  连接页关闭改为反向圆形收拢到触发按钮，从对话页进入时恢复 Agent 列表悬浮页。
  `claude -p` 以 30 轮上限 exit 1 截断，产物经静态 + 浏览器逐项复验（DESIGN.md 第 8 节）。
- **v0.3 → SwiftUI 已落地**（本轮后续批次）：`Sources/LichenApp` 按本规格实现设计系统 /
  `AppState` / 五视图，关闭闭环与两档连接逐项对应；见第 6、10 节与 `DESIGN.md` 第 9 节。

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

### 2026-11-14 · UI 原型 v0.1（本轮，代码改动走 WSL）
- 用户要求参考 DeepSeek 手机端 / RikkaHub / Hermes Desktop，动手前安装 `ui-ux-pro-max`
  技能（catalog 中的 `ui-ux-pro-max-plus`，已装到 `D:\Hermes\skills\`）。
- 任务开始前核对 ccms：无变化（见第 5 节）；用户指定「用 DeepSeek 官方 API 就行」，
  五档保持 `deepseek/deepseek-flash`，未启用备用通道。
- Windows 侧写 `TASK.md`（四屏结构 + 交互 + 工程约束，美学全部下放模型），
  `rsync` Windows → WSL 并把技能参考库复制到 `DesignRefs/`，`claude -p` 生成原型。
- `claude` 因 `--max-turns 25` 达到上限被截断（最终自述未输出），但产物完整：
  进程退出前后文件仍被多次自检修订（127391 → 126192 → 126130 字节），
  以最后一次为准再同步回 Windows。
- 验收（真实浏览器 + 静态检查）：0 外链、`node --check` JS 语法通过、
  `prefers-reduced-motion` / `clip-path: circle()` 齐备、四屏均可渲染、
  圆形扩散（`circle(658px→832px)`）/ 左滑抽屉 / 液态悬浮框三动效实测触发、
  0 JS 错误；连接页含网关地址 / 端口 / TLS / 超时 / 自定义头 / 测试连接，
  不含任何 LLM provider 字段；`PROJECT_README.md` 与 `.gitignore` md5 未变。
- 新增 `Preview/DESIGN.md`（设计规格摘要，供 SwiftUI 映射）；更新本文件；
  `git add / commit`。
- 踩坑：视觉模型对截图的描述存在幻觉（把 Agent 名说错、把网关连接页说成
  「配置 GPT-4o / api.openai.com」），**以 `grep` 源码关键词为准**，不采信截图口述。

### 2026-11-14 · UI 原型 v0.2（本轮，代码改动走 WSL）
- 用户三条意见：① 设置页全屏不要悬浮；② 状态页参考 DeepSeek 手机 app 的动效与形式；
  ③ bar/审批配色不喜欢，bar 颜色须与对话框描边一致、整体协调，并提供明亮+黑暗两套配色；
  另要求 preview 产物放到 `D:\prflib\coding\swift`。
- 新任务开始前核对 ccms：无变化，且**远端 ls-remote 本轮成功**，
  `origin/RuRe` = `8c0bcf6` 与本地一致（详见第 5 节）。
- 用户发来两张 DeepSeek 手机 app 截图；因路由到 `deepseek-flash`（文本模型），
  把截图人工观察写成 `REFERENCE.md`（抽屉宽度 / scrim / 搜索框前置 / 弱化分组 /
  纯文字大行高 / 底部账户条 / 左滑入），与 `TASK.md`（定点修改、禁止重写全文件）
  一起作为模型输入。
- `claude -p --max-turns 40` 仍因达到上限以 exit 1 截断（最终自述未输出），
  但产物完整：126130 → 136026 字节，四类改动全部落盘并经实测确认。
- 验收（真实浏览器 + 静态检查）：0 外链、`node --check` 通过、
  设置层 `inset:0` 且宽高 = 父容器（全屏）、`settingsBack` 可返回；
  抽屉 78% / `max-width:78%` / `box-shadow:none`、搜索胶囊存在；
  `.dock` border 与 `.dock-bar` background 在明亮/暗色下**像素级同色**
  （`rgba(26,30,25,0.12)` / `rgba(243,244,238,0.12)`）；
  审批卡片明亮 `rgb(255,255,255)`、暗色 `rgb(22,26,22)`；
  主题切换 body 背景 `rgb(231,232,226)` → `rgb(8,10,8)`、`localStorage=lichen-theme`；
  圆形扩散（`circle(727px→832px)`）/ 抽屉 / Agent 浮框仍触发、0 JS 错误；
  两份文档 md5 未变。四张放大截图视觉复核通过。
- 已知无害残留：token 定义块外仍有 1 处 `linear-gradient(... rgba(...,0) ...)`
  渐变起点（alpha=0，完全透明），暗色下无视觉影响；下次有代码任务时顺手变量化。
- 更新 `Preview/DESIGN.md` 为 v0.2、更新本文件；
  复制便捷副本 `D:\prflib\coding\swift\LichenPreview.html`；`git add / commit`。

### 2026-11-14 · UI 原型 v0.3 + 进入 SwiftUI 实现阶段
- 用户确认 v0.2 风格「差不多了」，要求：① Swift 真实功能；② SwiftUI 界面；
  ③ 连接选项只有远程网关和 SSL；④ 修复对话页打开连接页后的关闭逻辑。
- 连接选项含义经确认采用「两档分段控件」形式（去掉局域网 / 中继 / 手动）。
- 「远程网关和 SSL 参考 Hermes 的实现方法」→ 查本机 `D:/Hermes/hermes-agent/` 源码：
  `connection-config.ts` 给出 URL 规范化、`ws(s)://host/api/ws?token=|?ticket=`、
  token / OAuth ticket 双鉴权模型，作为 Swift 网络层依据。
- 代码改动走 WSL：`claude -p --max-turns 30`（exit 1 截断），`index.html`
  136,026 → 142,614 bytes，同步回 Windows 后静态 + 浏览器验收通过。
- 更新 `Preview/DESIGN.md` 为 v0.3、更新本文件；复制便捷副本；`git add / commit`。

### 2026-11-14 · Swift 真实功能 + SwiftUI 界面（本轮主任务）
- 用户四条要求：① 用 Swift 把功能真正做出来；② 用 SwiftUI 把界面做出来；
  ③ 连接选项只有「远程网关 / SSL」；④ 修复对话页打开连接页后的关闭逻辑。
- 协议依据：研究本机 `D:/Hermes/hermes-agent/` 源码与文档，确认 `/api/status`
  （`auth_required`）、`/api/ws`、token / OAuth ticket 双鉴权、JSON-RPC 2.0 换行分隔帧、
  `gateway.ready`、审批四值、会话 REST 端点、wss 需系统信任证书；结论带文件路径 + 行号。
- 代码改动全部走 WSL `claude -p`，分 A / A2 / B / C / D 五批，每批回同步 + 静态验收 + 提交：
  A 网关契约层 → A2 会话 / 消息 / Agent / 终端 → B 网络传输层 → C 设计系统与五视图 → D 收尾修补。
- 提交序列：`283b702` → `6e75bf1` → `2b4768d` → `ba45dcb` → D 收尾（本次）。
- C 以 45 轮上限 exit 1 截断，但产物完整（9 文件 +4364 行），且顺带完成原属 D 的三屏；
  D 遂改为小修补：补 `accessibilityReduceMotion`、默认端口 `8787 → 9119`、
  核对 `@main` 兼容性并加注释（未改 `Package.swift`）。
- 整体验收 17 项全 OK：TODO=0、imports 合法、31 文件括号配平、悬空引用 0、
  两档 / 关闭五要素 / `composerLine` / 78% 抽屉 / 全屏设置 / 12 个 `#Preview` / 无凭据。
- **未编译**：本机与 WSL 无 Swift / Xcode，仅静态自洽核对；Xcode 验证列入待办。

## 11. 待办 / 后续

- [ ] **在学校机房 macOS / Xcode 打开 `Package.swift`，编译并跑 `#Preview`**（最关键）：
  重点确认 `@main` 在 library target 下是否报错；若报错，按 `LichenApp.swift` 头部注释二选一
  （改 `.executableTarget` + `.executable` product，或去掉 `@main` 仅保留 `App` 结构供 Preview）。
- [ ] 补齐工程最终形态：保持 SwiftPM 包，还是补 `.xcodeproj` / Swift Playgrounds App 包装。
- [ ] 与真实 Hermes 网关端到端联调（token 模式 / OAuth ticket 模式 / wss 自签证书显式开关）。
- [ ] 定稿桥接层契约（命令 / 事件 / DTO）与 IDL 形式，纳入版本管理；框架选型定案（第 9.4 节）。
- [ ] 若下沉 Rust 核心，先在 WSL 编译验证（Rust + uniffi）。
- [ ] HTML 原型 token 块外那处 `alpha=0` 渐变起点变量化（无害残留）。
- [ ] 后续任务开始前重新核对 ccms（第 5 节）与备用通道（第 7 节）。
