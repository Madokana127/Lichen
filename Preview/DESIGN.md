# Lichen UI 原型 · 设计规格（v0.1 · 待用户敲定）

> 对应原型：`Preview/index.html`（单文件自包含 HTML，390 × 844 手机框内四屏切换）。
> 本文件是它的规格摘要，用于「敲定设计 → 映射 SwiftUI」这一步。
> **token 以 HTML `:root` 为唯一事实来源**；若两者不一致，改 HTML 后重新生成本摘要。

## 1. 设计定调

- 风格名：**Lichen daylight** —— 中性纸感底色 + 苔藓绿（lichen green）单一交互色，
  命令/审批区用近黑实心块形成视觉重量。
- 界面类别：Monitor / Command·Inspect（终端与会话监控类），**不是**营销式落地页，
  无 hero + 三卡片。
- 参考：DeepSeek 手机端（克制的白/浅灰、单一交互色、200ms 缓动、可见「思考」状态）、
  RikkaHub（Material 3 式抽屉、provider/model 切换、分组设置）、
  Hermes Desktop（用户提示词描边方框、正常/粗体区分思考与输出、实心审批方框）。
- 设备基准：`--phone-w: 390px`、`--phone-h: 844px`、`--status-h: 47px`、
  `--tap: 44px`（最小点击区）。

## 2. 设计 token（CSS 变量 → SwiftUI 映射）

### 颜色

| 分组 | 变量 | 值 | SwiftUI 建议 |
|---|---|---|---|
| 底色 | `--bg-canvas` / `--bg` / `--bg-deep` | `#E7E8E2` / `#F7F7F3` / `#F1F2EC` | `Color("Canvas")` 等 Asset Catalog |
| 表面 | `--surface` / `--surface-warm` / `--surface-sunken` / `--surface-hover` | `#FFFFFF` / `#FBFBF7` / `#EFEFE9` / `#F3F4EE` | 同上 |
| 文字 | `--ink` / `-2` / `-3` / `-4` | `#1A1E19` / `#3E453C` / `#5F675C` / `#969C91` | primary → quaternary |
| 描边 | `--line` / `--line-strong` | `#E3E4DC` / `#CFD2C8` | `Color.secondary.opacity` |
| 交互色 | `--accent` / `--accent-strong` / `--accent-soft` / `--accent-ink` | `#35614B` / `#274B39` / `#E7EFE8` / `#F7FBF6` | `Color.accentColor` |
| 命令面 | `--solid` / `--solid-raised` / `--solid-hover` / `--on-solid` | `#1D211C` / `#292E27` / `#30362E` / `#F3F4EE` | 审批框、实心状态 bar |
| 语义 | `--ok` / `--warn` / `--warn-bright` / `--danger` / `--danger-soft` | `#35614B` / `#8A5A12` / `#E4BB74` / `#9C3B32` / `#F4E8E5` | 状态点、审批按钮 |
| 代码底 | `--code-bg` | `#ECEEE6` | 代码片段背景 |

### 字体 / 间距 / 圆角 / 阴影

- 字体：`--font-sans` = 系统 SF Pro Text + PingFang SC 回退；`--font-mono` = SF Mono 等宽回退。
  字号阶梯 9/10/11/12/13/14/15/17/20/24/28px；行高 `--lh-tight: 1.18`、`--lh-body: 1.68`。
  → SwiftUI 用 `Font.system(.body, design: .default)` + 自定义 size 常量，不硬编码字体名。
- 间距：**4px 基数** `--sp-1…--sp-16` = 4/8/12/16/20/24/32/40/48/64px。
- 圆角：`--r-xs…--r-2xl` = 6/8/12/16/22/28px，`--r-pill: 999px`。
- 阴影：`--shadow-1/2/pop/phone` 四级，均为低透明度冷灰（不用彩色投影）。

### 动效

| 变量 | 值 | 用途 |
|---|---|---|
| `--ease` | `cubic-bezier(0.4, 0, 0.2, 1)` | 常规状态切换 |
| `--ease-out` | `cubic-bezier(0.22, 1, 0.36, 1)` | 进入 / 扩散 |
| `--ease-spring` | `cubic-bezier(0.22, 1.3, 0.36, 1)` | 轻微回弹 |
| `--dur-1…4` | 140 / 200 / 260 / 300ms | 微交互 → 面板 |
| `--dur-reveal` | **560ms** | 圆形扩散转场 |

## 3. 四屏结构与关键元素

| 屏 | 容器 id | 关键元素 |
|---|---|---|
| 01 开始页 | `screenStart` | Logo 占位、greeting、已连接 Agent 横向滑动卡片（同时露出 3 个，其余滚动隐藏）、`fabConnect`（圆形加号） |
| 02 对话页 | `screenChat` | `openDrawer`（三横线）、标题、`agentTrigger`（Agent 品牌图标）；用户消息=描边方框、AI 输出=正常/粗体 + `thoughtToggle` 思考折叠、命令审批=实心方框（允许一次 / 始终允许 / 拒绝）；`attachBtn` / `sendBtn` / 实心状态 bar（`modelChip` 模型、`effortChip` 推理强度、`branchChip` Git 分支） |
| 03 状态页 | `drawer` + `drawerScrim` | Agent LOGO + `drawerName`（可自定义，`editName` 重命名）、按项目/工作区分组的 `session-row`、`openSettings` → 设置页（连接状态 / 方式 / 品牌可提供的设置项） |
| 04 连接页 | `connectLayer` | 按功能分块：网关地址(Host) / 端口(Port) / 鉴权 / TLS / 超时 / 自定义头 / 能力 / `testStatus` 测试连接 / 保存并启用 / `advancedPanel` 高级项 |

**浮层交互**：`agentPop`（液态向下展开的 Agent 快捷切换浮框，内含 `newSessionBtn` 新会话
与 `popAddAgent` 连接 Agent）；`openDrawer` 从左滑入状态页。

## 4. 已实测的动效（浏览器实测，非静态推断）

- **圆形扩散**：点击 `fabConnect` → `connect-layer.is-open`，`clip-path` 从
  `circle(658.726px …)` 展开到 `circle(832px at 195px 758.5px)`，`--dur-reveal` 560ms。
- **左滑抽屉**：`drawer.is-open` → `transform: matrix(1,0,0,1,0,0)`，
  圆角 `0 24px 24px 0`；`drawerScrim` 遮罩同步淡入。
- **液态悬浮框**：`agent-pop.is-open` → `border-radius: 20px`、opacity 1、transform 归位。
- `prefers-reduced-motion` 已在 CSS 中处理；四屏切换 0 JS 错误。

## 5. 原型边界（明确未实现）

- 无真实网络请求、无鉴权、无 token、无终端仿真、无数据持久化；
- 全部为假数据与内存状态，顶部 `01/02/03/04` 导航条是**原型调试用**，SwiftUI 中不保留；
- 连接页字段是 UI 占位，不含任何真实网关地址或凭据。

## 6. 验收记录

- 单文件自包含：**0 个外链**（`src`/`href` 无 `http://`）、内嵌 1 个 `<style>` + 1 个 `<script>`；
- `node --check` 抽取 JS 校验通过；`:root` token 单一定义；
- 真实浏览器逐屏切换 + 三动效触发 + `window.onerror` 收集 = 0 错误；
- 连接页关键词 `网关 / 端口 / TLS / 超时 / 自定义头 / 测试连接` 齐备，
  且不含 `api.openai.com` / `GPT-4o` / `chat/completions` 等 LLM provider 字段。

## 7. 敲定后的落地顺序

1. 用户在内联预览中确认或提出修改 → **先改 `index.html` 并复验** → 再更新本摘要。
2. 把第 2 节 token 落成 SwiftUI `DesignTokens` 常量 / Asset Catalog（可脚本生成）。
3. 按第 3 节四屏拆 SwiftUI 视图，替换现有 `Sources/LichenApp` 的三 tab 占位界面；
   视图只依赖 `LichenCore` 协议（见 `PROJECT_README.md` 第 9 节）。
4. 学校机房 Xcode Preview / 模拟器验证，反馈回 HTML 原型迭代。
