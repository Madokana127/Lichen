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

## 4. 当前状态

- [x] Git 仓库初始化（分支 `main`），`.gitignore`、`PROJECT_README.md` 就位
- [x] ccms 状态核对（本轮）：无变化，详见第 5 节
- [x] **iOS 应用框架骨架（本次任务，已完成）**：13 个 Swift 文件，结构见第 6 节
- [x] 备用模型通道准备（本轮用户追加要求）：详见第 7 节
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

## 8. 变更记录

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

## 9. 待办 / 后续

- [ ] 具体功能：网关连接 / 会话 / 终端 / 设置（后续任务）
- [ ] 明确远程网关协议（WebSocket / HTTP / 自定义？）与鉴权方式
- [ ] 确定工程最终形态：保持 SwiftPM 包、还是补 `.xcodeproj` / Swift Playgrounds App
- [ ] 在有 Xcode 的 macOS 上做真实编译与模拟器运行验证
- [ ] 网络恢复后补做 ccms 远端 `git ls-remote` 核对；若 ccms 升级，重新核对第 5 节并按需调整命令
- [ ] 后续任务开始前重新核对 ccms（含第 7 节备用通道）；若官方仍繁忙按第 7 节切换
