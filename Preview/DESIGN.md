# Lichen UI 原型 · 设计规格（v0.3 · 已敲定，进入 SwiftUI 实现）

> 对应原型：`Preview/index.html`（单文件自包含 HTML，390 × 844 手机框内四屏切换）。
> 便捷副本：`D:\prflib\coding\swift\LichenPreview.html`（内容一致，便于直接双击打开；
> **Git 受控源仍是仓库内 `Preview/index.html`**，每次视觉变更后同步覆盖副本）。
> token 以 HTML `:root`（明亮）与 `html[data-theme="dark"]`（黑暗）为唯一事实来源；
> 若本摘要与 HTML 不一致，改 HTML 后重新生成本摘要。

## 0. 各版本变更

### v0.3（对应本轮第 3、4 点）

| # | 用户意见 | 落地 |
|---|---|---|
| 3 | 连接选项只有「远程网关」和「SSL」两种，不管局域网形式 | 设置页与连接页的「连接方式」分段控件统一为两档 `data-method="gateway" / "ssl"`，删除「局域网 / 中继 / 手动」及全部局域网文案（grep 命中 **0**）；切到 SSL 时 `#sslFields` 展开（允许自签名证书、验证 TLS 证书），选中态写入 `localStorage['lichen-connect-method']` |
| 4 | 对话页打开连接页后关闭逻辑不对 | 新增 `connectSource` / `connectTrigger` / `connectAnchor` / `connectReturn`；关闭时用 `clip-path: circle()` **反向收拢到触发元素中心**（`getBoundingClientRect()` 动态计算）；来源 `chat` 收拢结束后**恢复 `agentPop` 为打开**，来源 `start` 收拢到底部加号且不恢复浮框；`prefers-reduced-motion` 下直接切换、关闭后无内联样式残留 |

### v0.2（对应用户三条意见）

| # | 用户意见 | 落地 |
|---|---|---|
| 1 | 设置页全屏，不要悬浮 | `#settingsPane` 从抽屉内的第二块 pane 移出，改为独立 `.settings-layer`（`inset:0`，覆盖整个手机屏，从右侧滑入）；不再使用 `.drawer-track` / `is-settings` 左右滑动 |
| 2 | 状态页参考 DeepSeek 手机 app 的动效与形式 | 抽屉 86% → **78%**、去物理阴影只留 scrim、顶部前置搜索胶囊、弱化分组标题、纯文字大行高会话行、底部账户条、底层对话页 **parallax**（右移 18px + 缩放 0.985） |
| 3 | bar/审批配色不喜欢；bar 与对话框描边同色；要明亮+黑暗两套 | 新增 `--composer-line`，`.dock` border 与 `.dock-bar` background **共用同一变量**；审批框由近黑实心改为浅色描边卡片；新增 `html[data-theme="dark"]` 完整暗色 token，顶部调试条 + 设置页「外观」分组双入口切换，`localStorage` 记忆 |

## 1. 设计定调

- 风格名：**Lichen daylight**（明亮）/ **Lichen night**（黑暗）—— 中性纸感或夜色底 +
  苔藓绿（lichen green）**单一交互色**；**命令 / 审批区不再用近黑实心块**，
  改为与整体同色系的浅色卡片 + 描边。
- 界面类别：Monitor / Command·Inspect（终端与会话监控类），**不是**营销式落地页。
- 参考：DeepSeek 手机端（侧栏形式与动效、搜索前置、弱化分组、纯文字列表）、
  RikkaHub（抽屉、provider/model 切换、分组设置）、
  Hermes Desktop（提示词描边方框、正常/粗体区分思考与输出、审批框）。
- 暗色主题**保留苔藓绿设计语言**（accent 提亮），不照抄 DeepSeek 品牌蓝。
- 设备基准：`--phone-w: 390px`、`--phone-h: 844px`、`--status-h: 47px`、`--tap: 44px`。

## 2. 设计 token（CSS 变量 → SwiftUI 映射）

### 两套配色（主色值，完整清单见 HTML）

| 分组 | 变量 | 明亮 light | 黑暗 dark |
|---|---|---|---|
| 画布 | `--bg-canvas` / `--bg` | `#E7E8E2` / `#F7F7F3` | `#080A08` / `#0E100E` |
| 表面 | `--surface` / `--surface-sunken` | `#FFFFFF` / `#EFEFE9` | `#161A16` / `#1C211C` |
| 文字 | `--ink` / `--ink-3` / `--ink-4` | `#1A1E19` / `#5F675C` / `#969C91` | `#F3F4EE` / `#A2A99B` / `#767E71` |
| 描边 | `--line` / `--line-strong` | `#E3E4DC` / `#CFD2C8` | `#262C26` / `#363D34` |
| 交互色 | `--accent` / `--accent-strong` | `#35614B` / `#274B39` | `#8FC3A0` / `#A9D4B7` |
| **控件描边 / bar** | **`--composer-line`** | `rgba(26,30,25,0.12)` | `rgba(243,244,238,0.12)` |
| 命令面 | `--solid` / `--on-solid` | `#1D211C` / `#F3F4EE` | `#1C211C` / `#F3F4EE` |
| 语义 danger | `--danger` | `#9C3B32` | `#E7A79D` |
| 代码底 | `--code-bg` | `#ECEEE6` | `#20261F` |
| 遮罩 | `--scrim` | 浅色半透明 | `rgba(0,0,0,0.56)` |

> **`--composer-line` 是第 3 条需求的关键**：`.dock` 的 `border` 与 `.dock-bar` 的
> `background` 都引用它，因此 bar 的颜色与对话框描边颜色**字面一致**；
> 文字改用 `--ink-*`，bar 不再是深色实心块。

暗色块还覆盖了玻璃层、设备边框、阴影、toast、switch、seg 等派生变量，
切换时不会出现浅色块突兀或黑字看不见。

### 字体 / 间距 / 圆角 / 阴影

- 字体：`--font-sans` = 系统 SF Pro Text + PingFang SC 回退；`--font-mono` = SF Mono 等宽回退。
  字号阶梯 9/10/11/12/13/14/15/17/20/24/28px；行高 `--lh-tight: 1.18`、`--lh-body: 1.68`。
- 间距：**4px 基数** `--sp-1…--sp-16` = 4/8/12/16/20/24/32/40/48/64px。
- 圆角：`--r-xs…--r-2xl` = 6/8/12/16/22/28px，`--r-pill: 999px`。
- 阴影：`--shadow-1/2/pop/phone` 四级，明暗各一套（暗色用纯黑低透明度）。

### 动效

| 变量 | 值 | 用途 |
|---|---|---|
| `--ease` | `cubic-bezier(0.4, 0, 0.2, 1)` | 常规状态切换 |
| `--ease-out` | `cubic-bezier(0.22, 1, 0.36, 1)` | 进入 / 扩散 / 抽屉 |
| `--ease-spring` | `cubic-bezier(0.22, 1.3, 0.36, 1)` | 轻微回弹 |
| `--dur-1…4` | 140 / 200 / 260 / 300ms | 微交互 → 面板 |
| `--dur-reveal` | **560ms** | 圆形扩散转场 |

## 3. 四屏结构与关键元素

| 屏 | 容器 id | 关键元素 |
|---|---|---|
| 01 开始页 | `screenStart` | Logo 占位、greeting、已连接 Agent 横向滑动卡片（同时露出 3 个）、`fabConnect`（圆形加号） |
| 02 对话页 | `screenChat` | `openDrawer`（三横线）、标题、`agentTrigger`；用户消息=描边方框、AI 输出=正常/粗体 + `thoughtToggle`、审批=**浅色描边卡片**（允许一次 / 始终允许 / 拒绝）；`attachBtn` / `sendBtn`；状态 bar = `.dock-bar`（**与输入框描边同色**，含 `modelChip` / `effortChip` / `branchChip`） |
| 03 状态页 | `drawer` + `drawerScrim` | **78% 宽**、顶部 `drawerSearch` 搜索胶囊（+ 排序图标）、紧凑「当前 Agent」行（`drawerName` 可 `editName` 重命名、`drawerMeta`）、按项目/工作区**弱化的分组标题** + 纯文字大行高 `session-row`、底部账户条（头像 + 名字 + **保留 `openSettings`** + 更多菜单） |
| 设置页（状态页下级） | `settingsPane`（`.settings-layer`） | **全屏层**：全屏头部 + `settingsBack` 返回、连接状态 / 连接方式 / CLAUDE 品牌设置 / 会话 / **外观（明亮 / 黑暗）** 分组；`reconnectBtn` / `settingsModel` / `settingsCwd` 等 id 保持 |
| 04 连接页 | `connectLayer` | 网关地址(Host) / 端口(Port) / 鉴权 / TLS / 超时 / 自定义头 / 能力 / `testStatus` 测试连接 / 保存并启用 / `advancedPanel` 高级项 |

**浮层交互**：`agentPop`（液态向下展开的 Agent 快捷切换浮框，含 `newSessionBtn`、
`popAddAgent`）；`openDrawer` 从左滑入状态页。

## 4. 已实测的动效（浏览器实测）

- **圆形扩散**：`fabConnect` → `connect-layer.is-open`，`clip-path` 从
  `circle(727px …)` 展开到 `circle(832px at 195px 758.5px)`，560ms。
- **左滑抽屉 + 底层 parallax**：`drawer.is-open` → `translateX(0)`，
  底层对话页 `translateX(18px) scale(0.985)`；scrim 淡入，**无物理阴影**。
- **全屏设置页**：`openSettings` → `settings-layer.is-open`（`inset:0`、宽高 = 手机屏），
  从右侧滑入；`settingsBack` 返回状态页；关闭抽屉 / scrim / Esc 同步关闭。
- **液态悬浮框**：`agent-pop.is-open` → `border-radius: 20px`、opacity 1、transform 归位。
- **主题切换**：`setTheme()` 写 `document.documentElement.dataset.theme` +
  `localStorage['lichen-theme']`，`body` 短过渡；两处入口（顶部调试条、设置页外观分组）联动。
- `prefers-reduced-motion` 已处理；四屏切换 0 JS 错误。

## 5. 原型边界（明确未实现）

- 无真实网络请求、无鉴权、无 token、无终端仿真、无数据持久化（主题选择仅 `localStorage`）；
- 全部为假数据与内存状态，顶部 `01/02/03/04` 导航条与明亮/黑暗切换按钮是**原型调试用**，
  SwiftUI 中不保留（外观设置会在 SwiftUI 设置页里以系统外观选择重新实现）；
- 连接页字段是 UI 占位，不含任何真实网关地址或凭据；
- 搜索框只做视觉与轻量过滤，不接后端。

## 6. 验收记录（v0.2，真实浏览器 + 静态检查）

- 单文件自包含：**0 外链**、1 个 `<style>` + 2 个 `<script>`、`node --check` JS 语法通过；
  硬编码颜色仅存于 `:root`（19-169 行）与 `html[data-theme="dark"]`（174-269 行）两个 token 块内。
- **设置页**：`settings-layer is-open` 时宽高 = 父容器（全屏）、`position:absolute`、
  `top/left:0`、`z-index:64`；`settingsBack` 后 class 恢复为 `settings-layer`。
- **状态页**：抽屉宽 = 父容器 **78%**、`max-width:78%`、`box-shadow:none`、
  圆角 `0 24px 24px 0`；`drawerSearch` 为 `type=search`、占位「搜索会话...」。
- **bar 同色**（computed 像素级）：
  - 明亮：`.dock` border = `.dock-bar` background = `rgba(26, 30, 25, 0.12)` → `same=true`
  - 黑暗：两者同为 `rgba(243, 244, 238, 0.12)` → `same=true`
- **审批卡片**：明亮 `rgb(255,255,255)` 底 / `rgb(26,30,25)` 字；
  暗色 `rgb(22,26,22)` 底 / `rgb(243,244,238)` 字。
- **主题切换**：body 背景 `rgb(231,232,226)` → `rgb(8,10,8)`，
  `dataset.theme=dark`、`localStorage['lichen-theme']='dark'`。
- 圆形扩散（`circle(727px→832px)`）、抽屉、Agent 浮框仍触发；`window.onerror` = **0 错误**。
- 关键 id 全部保留（`fabConnect` `openDrawer` `agentTrigger` `agentPop` `drawer`
  `drawerScrim` `drawerName` `editName` `openSettings` `settingsPane` `settingsBack`
  `connectLayer` `approval` `modelChip` `effortChip` `branchChip` `sendBtn`）。
- `PROJECT_README.md` 与 `.gitignore` md5 与 Windows 侧一致（Claude 未改动）。
- 四张放大截图（明亮对话 / 黑暗对话 / 状态页 / 全屏设置页）视觉复核通过。

> 已知无害残留：token 块外仍有 1 处
> `linear-gradient(to bottom, rgba(247,247,243,0), var(--bg) 22%)` 渐变起点，
> alpha=0 完全透明，暗色下无视觉影响；下次有代码任务时顺手变量化。

## 7. 落地顺序（已执行，2026-11-14）

1. [x] v0.3 敲定（用户「我觉得差不多了」）→ 进入 Swift / SwiftUI 实现；
   后续视觉反馈仍**先改 `index.html` 并复验** → 再更新本摘要与便捷副本。
2. [x] 第 2 节 token 落成 SwiftUI `DesignTokens` 常量：明暗两套 `ColorPalette`
   + 字体 / 间距 / 圆角 / 动效常量（见第 9 节）。
3. [x] 第 3 节四屏拆 SwiftUI 视图，替换 `Sources/LichenApp` 三 tab 占位界面；
   `TabView` 已移除，视图只依赖 `LichenCore` 协议。
4. [ ] 学校机房 Xcode Preview / 模拟器验证，反馈回 HTML 原型迭代（**待办**）。

## 8. v0.3 验收（2026-11-14）

- 静态：142,614 bytes；`局域网` **0** 命中、`远程网关`/`SSL` 各 9 处、`中继` 0、
  旧「手动」档 0；`getBoundingClientRect` 3 处、`circle(` 3 处、
  `prefers-reduced-motion` 2 处；0 外链；内嵌 JS `node --check` 通过；
  关键 id、`--composer-line`、`html[data-theme="dark"]`、`.settings-layer` 全部保留。
- 关闭闭环（浏览器实测）：对话页 `agentTrigger` → `popAddAgent` 扩散锚点
  `352px 73.5px`；点 `connectBack` 后收拢中间态 `circle(708.772px at 352px 73.5px)`，
  结束后 `agentPop` 恢复 `is-open`、`connectLayer` 隐藏且 `pointer-events:none`、
  屏幕中心命中测试穿透到 `agent-tile`、内联样式 `None`（无残留）。
- 两档联动：`data-method="gateway"/"ssl"`；切到 SSL 时 `#sslFields`
  `display:none → block`，`localStorage['lichen-connect-method']='ssl'`；
  可见文本不含「局域网」。
- `window.onerror` = **0 错误**；`claude -p --max-turns 30` 仍以 exit 1 截断
  （最终自述缺失），产物完整并逐项复验，不重跑。

## 9. SwiftUI 落地映射（2026-11-14，任务 C / D）

| 本规格 | SwiftUI 实现 |
|---|---|
| `:root` / `html[data-theme="dark"]` 双 token | `Design/DesignTokens.swift`：`ColorPalette` 明暗两套 + `DesignTokens` 常量 |
| `--composer-line` 共用 | `ChatView` 输入框描边（:321）与 bar 背景（:392）同用 `palette.composerLine` |
| 三 tab 占位 → 四屏 | `TabView` 移除；`RootView` 按 `AppState.screen` 切换，状态页为 78% 抽屉，连接页为圆形扩散全屏层 |
| 78% 抽屉 + parallax | `size.width * 0.78`、底层 `scaleEffect(0.985)` + `offset(x: 18)` |
| 全屏设置页 | `RootView` 直接叠加（`zIndex(3)` / `.move(edge: .trailing)`），全项目无 `.sheet` / `.popover` |
| 两档连接 | `ConnectionMethod` 仅 `gateway` / `ssl`；`GatewayView` 与 `SettingsView` 分段控件一致，SSL 展开证书字段 |
| 反向收拢 + 恢复浮框 | `AppState.ConnectSource` / `ConnectAnchor` + `RootView` 的 `GeometryReader` / `connectProgress`；`closeConnect()` 对话页来源恢复 `isAgentPopoverOpen = true` |
| `prefers-reduced-motion` | `RootView` 的 `@Environment(\.accessibilityReduceMotion)`：为 true 时跳过扩散 / 收拢与 panel 动画 |
| 假数据 → 可预览 | 6 个视图共 **12 个 `#Preview`**，`AppState.preview()` / `preview(screen:)` 提供假数据 |

静态验收（Windows 侧，31 个 Swift 文件）：`TODO` / `fatalError` = 0、imports 仅
Foundation / SwiftUI / Observation / LichenCore / XCTest、括号配平、
`DesignTokens.*` / `palette.*` / `appState.*` 悬空引用 0、无「局域网 / 中继」、无真实凭据。

**本机与 WSL 均无 Swift / Xcode：以上未编译、未跑 Xcode Preview**，
需在学校机房按 `PROJECT_README.md` 第 11 节验证。
