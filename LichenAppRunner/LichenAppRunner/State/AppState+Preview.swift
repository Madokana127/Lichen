import Foundation
import LichenCore

extension AppState {
    /// Xcode Preview 使用的假数据，不依赖网络与持久化。
    public static func preview() -> AppState {
        preview(screen: .start)
    }

    /// 指定首屏的预览状态。
    public static func preview(screen: AppScreen) -> AppState {
        let claudeID = UUID()
        let hermesID = UUID()
        let codexID = UUID()
        let openCodeID = UUID()
        let primarySessionID = UUID()
        let designSessionID = UUID()
        let now = Date()

        let agents = [
            Agent(
                id: claudeID,
                brand: .claude,
                displayName: "Claude 01",
                order: 1,
                configuration: GatewayConfiguration(
                    displayName: "Claude 01",
                    host: "agent.example.invalid",
                    port: 9119
                ),
                isConnected: true
            ),
            Agent(
                id: hermesID,
                brand: .hermes,
                displayName: "Hermes 02",
                order: 2,
                configuration: GatewayConfiguration(
                    displayName: "Hermes 02",
                    host: "studio.example.invalid",
                    port: 9119
                ),
                isConnected: true
            ),
            Agent(
                id: codexID,
                brand: .codex,
                displayName: "Codex 03",
                order: 3,
                configuration: GatewayConfiguration(
                    displayName: "Codex 03",
                    host: "remote.example.invalid",
                    port: 443,
                    method: .ssl
                ),
                isConnected: true
            ),
            Agent(
                id: openCodeID,
                brand: .opencode,
                displayName: "OpenCode 04",
                order: 4,
                configuration: GatewayConfiguration(
                    displayName: "OpenCode 04",
                    host: "local.example.invalid",
                    port: 9119
                ),
                isConnected: true
            )
        ]

        let sessions = [
            Session(
                id: primarySessionID,
                title: "Git 分支检查",
                createdAt: now.addingTimeInterval(-900),
                updatedAt: now.addingTimeInterval(-60),
                project: "Lichen.swiftpm",
                agentID: claudeID,
                preview: "当前在 main 分支，工作区干净。",
                messageCount: 5,
                remoteID: primarySessionID.uuidString
            ),
            Session(
                id: designSessionID,
                title: "映射设计 token 到 SwiftUI",
                createdAt: now.addingTimeInterval(-7200),
                updatedAt: now.addingTimeInterval(-3600),
                project: "Lichen.swiftpm",
                agentID: claudeID,
                preview: "把设计 token 收敛到 DesignTokens。",
                messageCount: 2,
                remoteID: designSessionID.uuidString
            )
        ]

        let approval = ApprovalCard(
            requestID: "preview-approval",
            sessionID: primarySessionID,
            command: "swift test --filter SessionStoreTests",
            description: "Claude 请求运行过滤后的测试，只读执行。",
            choices: ApprovalChoice.allCases
        )

        let messages: [UUID: [SessionMessage]] = [
            primarySessionID: [
                SessionMessage(
                    sessionID: primarySessionID,
                    role: .user,
                    text: "帮我看一下 Lichen.swiftpm 现在在哪个分支，然后跑一下测试，把失败的用例贴出来。",
                    createdAt: now.addingTimeInterval(-420)
                ),
                SessionMessage(
                    sessionID: primarySessionID,
                    role: .thinking,
                    text: "先确认分支和工作区状态，再决定测试范围。",
                    createdAt: now.addingTimeInterval(-400),
                    isEmphasized: true
                ),
                SessionMessage(
                    sessionID: primarySessionID,
                    role: .thinking,
                    text: "读取仓库状态：当前分支、未提交变更、未跟踪文件；再列出可用 target。",
                    createdAt: now.addingTimeInterval(-380),
                    isEmphasized: true
                ),
                SessionMessage(
                    sessionID: primarySessionID,
                    role: .assistant,
                    text: "当前在 main 分支，工作区干净。12 项测试通过 11 项，只有 SessionStoreTests.testStaleSessionPrunes 超时。这更像是时间竞态，把等待窗口放宽到 2s 吗？",
                    createdAt: now.addingTimeInterval(-300)
                ),
                SessionMessage(
                    sessionID: primarySessionID,
                    role: .approval,
                    text: approval.command,
                    createdAt: now.addingTimeInterval(-240),
                    approval: approval
                )
            ],
            designSessionID: [
                SessionMessage(
                    sessionID: designSessionID,
                    role: .user,
                    text: "把原型里的颜色和圆角映射成 SwiftUI token。",
                    createdAt: now.addingTimeInterval(-6000)
                ),
                SessionMessage(
                    sessionID: designSessionID,
                    role: .assistant,
                    text: "已按明亮 / 黑暗两套配色整理，composer 描边与 bar 共用同一个颜色。",
                    createdAt: now.addingTimeInterval(-5900)
                )
            ]
        ]

        return AppState(
            sessionStore: InMemorySessionStore(initial: sessions),
            agents: agents,
            currentAgentID: claudeID,
            sessions: sessions,
            selectedSessionID: screen == .start ? nil : primarySessionID,
            messages: messages,
            connectionState: .connected(
                GatewayInfo(
                    version: "0.9.0",
                    gatewayRunning: true,
                    activeSessions: 2
                )
            ),
            theme: .system,
            screen: screen,
            modelName: "Hermes",
            availableModels: ["Hermes", "Claude", "OpenCode"],
            currentProvider: "hermes",
            effort: .medium
        )
    }
}
