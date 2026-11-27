# Lichen

Lichen 是一个连接远程 [Hermes Agent](https://github.com/NousResearch/hermes-agent) 网关的 SwiftUI 聊天客户端。模型和 Agent 在远端运行，Lichen 提供对话、历史会话和审批界面。

## 功能

- **对话**：新建会话、流式接收回复、停止当前生成，以及选择网关提供的模型和推理强度。
- **阅读与复制**：模型回复支持 Markdown 和常用 LaTeX 数学公式；「复制输出」保留原始 Markdown 和 LaTeX 源码。
- **历史会话**：在会话侧栏手动刷新远程列表，打开会话时拉取正文。已经同步的正文保存在本机，可以离线阅读。
- **连接管理**：管理多个 Agent 配置，支持静态会话令牌和 OAuth 访问令牌。连接成功后，凭据保存在系统钥匙串，应用下次启动时会尝试连接上次选中的 Agent。
- **用户审批**：在收到网关的审批请求时，在对话中查看并答复。

## 快速开始

需要 macOS、能打开当前项目格式的 Xcode（推荐 Xcode 27.2 或更新版本），以及可从设备访问的 Hermes 网关。

```sh
git clone https://github.com/Madokana127/Lichen.git
cd Lichen
open LichenAppRunner/LichenAppRunner.xcodeproj
```

1. 等待 Xcode 解析 Swift Package 依赖，选择 `LichenAppRunner` Scheme 和 iPhone 模拟器，按 `⌘R` 运行。若运行到真机，请先在 **Signing & Capabilities** 中选择自己的开发团队。
2. 在应用顶部打开「Agent 与网关」菜单，选择「添加网关」。
3. 填写网关地址、端口和对应的访问令牌。表单默认端口为 `9119`；如果网关位于反向代理后面，请填写代理实际暴露的地址和端口。使用 HTTPS 时选择「SSL」。
4. 点击「测试连接」检查配置，再保存并连接。在首页发送第一条消息会新建会话；要继续旧对话，请从历史侧栏打开它。

## 运行测试

在 Xcode 中使用 `LichenAppRunner` Scheme 按 `⌘U`。也可以在仓库根目录运行：

```sh
xcodebuild \
  -project LichenAppRunner/LichenAppRunner.xcodeproj \
  -scheme LichenAppRunner \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.2' \
  test
```

如果没有这个模拟器，请换成 Xcode 中已安装的机型和系统版本。测试使用模拟网关覆盖连接、会话同步、消息归档和停止生成；Markdown 与 LaTeX 测试使用聊天页实际采用的渲染器。

## 项目结构

| 路径 | 用途 |
| --- | --- |
| `LichenAppRunner/LichenAppRunner.xcodeproj` | 可运行的 Xcode 工程、共享 Scheme 和 Swift Package 版本锁定 |
| `LichenAppRunner/LichenAppRunner/` | SwiftUI 页面、应用状态、凭据存取和聊天渲染 |
| `LichenAppRunner/Lichen-main/Sources/LichenCore/` | App 使用的网关协议、WebSocket 传输和会话存储 |
| `LichenAppRunner/LichenAppRunnerTests/` | App 的自动化回归测试 |
| `Package.swift`、`Sources/`、`Tests/` | 仓库根目录的独立 Swift Package |
