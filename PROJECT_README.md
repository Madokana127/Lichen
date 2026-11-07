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
| WSL 临时工作区 | `/root/lichen-build/Lichen.swiftpm` |
| 代码任务执行方 | WSL 内 `claude -p`（Claude Code 2.1.318），模型经 ccms 路由到 **DeepSeek Flash** |
| 同步方式 | `rsync -a --delete --exclude .git`：Windows → WSL → Windows |
| 工程形态 | SwiftPM 清单 + SwiftUI iOS app 骨架 |
| 平台限制 | WSL / Windows 均无 Swift 与 Xcode，**无法编译 iOS 工程**；验证只做结构 / 语法人工核对 |

> 目录名带 `.swiftpm` 后缀，按 Swift Playgrounds / SwiftPM 包形态搭建；
> `Package.swift` 使工程可在 Xcode 中作为 Swift Package 打开。后续如需生成
> `.xcodeproj` 或 Swift Playgrounds App 包装，再单独处理（见「待办」）。

## 3. 工作流约定（后续 session 必读）

1. 每次开始**新任务前**，先确认 ccms 有没有变化（见第 5 节）。
2. 代码改动一律走 WSL：`rsync` 复制一份到临时目录 → `claude -p` 用 DeepSeek Flash 完成 →
   `rsync` 同步回 Windows → Windows 侧 `git add / commit`。
3. `PROJECT_README.md` 与 `.gitignore` 由 Windows 侧维护，**不交给 Claude Code 修改**。
4. `.git` 不参与同步；WSL 临时目录每次以 `--delete` 覆盖，视为一次性工作区。
5. 密钥不进仓库：DeepSeek API key 只写入 ccms 加密密钥库（`keys.enc`），不落到任何源码 / 文档。

## 4. 当前状态

- [x] Git 仓库初始化（分支 `main`），`.gitignore`、`PROJECT_README.md` 就位
- [x] ccms 状态核对（本轮）：无变化，详见第 5 节
- [ ] iOS 应用框架骨架（本次任务，进行中）
- [ ] 具体功能：网关连接 / 会话 / 终端 / 设置（**后续任务，本次不做**）

## 5. ccms 状态核对（每次新任务前执行）

本轮核对结果（2026-11-07）：

| 检查项 | 结果 |
|---|---|
| 已安装二进制 | `/usr/local/bin/ccms`，`CCMS 0.2.1` |
| 文档版本 | `D:\prflib\CCMS\PROJECT.md` → 0.2.1（Rust 重写），与二进制一致 |
| 本地 Git | 分支 `RuRe`，HEAD `8c0bcf6`，工作区干净，与 `origin/RuRe` 跟踪引用一致 |
| 远端（WSL `git ls-remote`） | `origin/RuRe` = `8c0bcf6` = 本地 HEAD；`origin/main` = `de0d033`（旧 0.1） |
| 结论 | **ccms 自上次记录以来无变化**，CLI 接口按 `Commend.md` 0.2.1 使用即可 |

> 注：Windows 侧 `git ls-remote` 曾因网络 `Connection was reset` 失败，改用 WSL 侧执行成功；
> 后续核对优先在 WSL 侧跑。

本轮为完成代码任务对 ccms 做的**可逆配置改动**（详见第 7 节变更记录）：

- 加密密钥库新增 1 把 `DEEPSEEK_API_KEY`（`ccms --key deepseek --stdin`），未写入明文文件；
- `ccms --route --all deepseek deepseek-flash`：五档全部指向 DeepSeek Flash；
- `ccms --on`：写入 `~/.claude/settings.json` 的 env 并启动本机 router（127.0.0.1:8788）；
- 原 `routes.json` / `settings.json` 已备份为 `*.pre-lichen.bak`，可随时还原。

## 6. 目录结构

（骨架生成后补充）

## 7. 变更记录

### 2026-11-07 · 初始化
- 在 `D:\prflib\coding\swift\Lichen.swiftpm` 执行 `git init -b main`，配置本地提交身份。
- 新增 `.gitignore`（Swift/Xcode、密钥、任务脚手架文件）。
- 新增 `PROJECT_README.md`（本文件），确立「每次更改后更新状态」的约定。
- 核对 ccms：无变化（详见第 5 节）。

## 8. 待办 / 后续

- [ ] 生成 iOS 应用框架骨架（本次）
- [ ] 明确远程网关协议（WebSocket / HTTP / 自定义？）与鉴权方式
- [ ] 确定工程最终形态：保持 SwiftPM 包、还是补 `.xcodeproj` / Swift Playgrounds App
- [ ] 在有 Xcode 的 macOS 上做真实编译与模拟器运行验证
- [ ] ccms 若升级，重新核对第 5 节并按需调整路由命令
