import Foundation
import Observation
import LichenCore

// MARK: - 界面枚举

/// 界面主题。
public enum LichenTheme: String, CaseIterable, Sendable {
    case light
    case dark
    case system

    public var displayName: String {
        switch self {
        case .light:
            return "明亮"
        case .dark:
            return "黑暗"
        case .system:
            return "跟随系统"
        }
    }
}

/// 当前屏幕。状态页为抽屉，设置页为全屏覆盖层。
public enum AppScreen: String, Sendable {
    case start
    case chat
    case status
    case connect
    case settings
}

/// 连接页的入口来源；关闭时据此决定收拢目标与是否恢复 Agent 浮框。
public enum ConnectSource: String, Sendable {
    case start
    case chat
}

/// 圆形扩散 / 收拢的锚点（根坐标空间，单位 pt）。
public struct ConnectAnchor: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// 推理强度，对应 Hermes 的七档线缆值。
public enum LichenEffort: String, CaseIterable, Sendable {
    case minimal = "极少"
    case low = "低"
    case medium = "中"
    case high = "高"
    case xhigh = "极高"
    case max = "最大"
    case ultra = "极速"

    /// 发送给 Hermes 的 `reasoning_effort` / `config.set key="reasoning"` 值。
    public var wireValue: String {
        switch self {
        case .minimal:
            return "minimal"
        case .low:
            return "low"
        case .medium:
            return "medium"
        case .high:
            return "high"
        case .xhigh:
            return "xhigh"
        case .max:
            return "max"
        case .ultra:
            return "ultra"
        }
    }
}

// MARK: - 应用状态

/// 全局可观察状态：Agent、会话、消息、连接与导航。
///
/// 所有 UI 状态都在主 actor 上；网关回调通过 `Task { @MainActor }` 回到主线程。
@MainActor
@Observable
public final class AppState {
    // MARK: 数据

    public var agents: [Agent]
    public var currentAgentID: UUID?
    public var sessions: [Session]
    public var messages: [UUID: [SessionMessage]]
    public var selectedSessionID: UUID?

    // MARK: 连接

    public var connectionState: GatewayConnectionState
    public var accessToken: String
    public var additionalHeaders: [String: String]
    public private(set) var lastErrorMessage: String?

    // MARK: 界面

    public var theme: LichenTheme
    public var screen: AppScreen
    public var isAgentPopoverOpen: Bool
    public var isDrawerOpen: Bool
    public var searchText: String
    public var modelName: String
    /// 当前网关返回的模型名称列表；为空时 UI 会回退到默认占位模型。
    public private(set) var availableModels: [String]
    /// 当前模型所属 provider slug；从 `model.options` 中解析。
    public private(set) var currentProvider: String?
    public var effort: LichenEffort
    public var gitBranch: String
    /// 离开应用后是否保持终端连接。
    public var keepsSessionInBackground: Bool
    /// 网络恢复后是否重建网关连接。
    public var autoReconnect: Bool

    // MARK: 审批

    public var pendingApprovals: [ApprovalCard]
    public private(set) var approvalResults: [String: ApprovalChoice]

    // MARK: 连接页来源

    public var connectSource: ConnectSource?
    public var connectAnchor: ConnectAnchor?

    // MARK: 依赖

    private let sessionStore: any SessionStore
    private var gateway: (any GatewayClient)?
    private var stateObservation: (any GatewayStateObservation)?
    private var eventObservation: (any GatewayStateObservation)?
    private var serverRequestObservation: (any GatewayStateObservation)?
    private var isSubscribed = false

    // MARK: 流式累积

    private var streamingMessageIDs: [String: UUID] = [:]
    private var frameCounter = 1

    // MARK: Hermes 模型 / 会话状态

    private var modelProviderByModelName: [String: String] = [:]
    private var remoteSessionModel: [UUID: String] = [:]
    private var remoteSessionReasoning: [UUID: String] = [:]

    // MARK: 初始化

    public init(
        gateway: (any GatewayClient)? = nil,
        sessionStore: any SessionStore = InMemorySessionStore(),
        agents: [Agent] = [],
        currentAgentID: UUID? = nil,
        sessions: [Session] = [],
        messages: [UUID: [SessionMessage]] = [:],
        connectionState: GatewayConnectionState = .disconnected,
        theme: LichenTheme = .system,
        screen: AppScreen = .start,
        pendingApprovals: [ApprovalCard] = [],
        modelName: String = "Sonnet 4.5",
        availableModels: [String] = [],
        currentProvider: String? = nil,
        effort: LichenEffort = .medium,
        gitBranch: String = "main",
        keepsSessionInBackground: Bool = true,
        autoReconnect: Bool = true,
        additionalHeaders: [String: String] = [:]
    ) {
        self.gateway = gateway
        self.sessionStore = sessionStore
        self.agents = agents
        self.currentAgentID = currentAgentID ?? agents.first?.id
        self.sessions = sessions
        self.messages = messages
        self.selectedSessionID = sessions.first?.id
        self.connectionState = connectionState
        self.theme = theme
        self.screen = screen
        self.isAgentPopoverOpen = false
        self.isDrawerOpen = false
        self.searchText = ""
        self.modelName = modelName
        self.availableModels = availableModels
        self.currentProvider = currentProvider
        self.effort = effort
        self.gitBranch = gitBranch
        self.keepsSessionInBackground = keepsSessionInBackground
        self.autoReconnect = autoReconnect
        self.pendingApprovals = pendingApprovals
        self.approvalResults = [:]
        self.lastErrorMessage = nil
        self.connectSource = nil
        self.connectAnchor = nil
        self.accessToken = ""
        self.additionalHeaders = additionalHeaders

        if let gateway {
            subscribe(to: gateway)
        }
    }

    // MARK: 计算属性

    /// 当前 Agent。
    public var currentAgent: Agent? {
        guard let currentAgentID else { return nil }
        return agents.first { $0.id == currentAgentID }
    }

    /// 当前会话；优先手动选择，其次当前 Agent 最近更新的会话。
    public var currentSession: Session? {
        if let selectedSessionID,
           let session = sessions.first(where: { $0.id == selectedSessionID }) {
            return session
        }
        return currentAgentSessions.first
    }

    /// 当前会话的消息，按时间升序。
    public var currentMessages: [SessionMessage] {
        guard let sessionID = currentSession?.id else { return [] }
        return (messages[sessionID] ?? []).sorted(by: Self.messageOrder)
    }

    /// 供模型选择 UI 使用的模型列表；网关未返回时回退到默认占位模型。
    public var modelOptions: [String] {
        availableModels.isEmpty ? Self.defaultModelNames : availableModels
    }

    /// 按项目聚合的会话（已过滤搜索与归档）。
    public var groupedSessions: [SessionGroup] {
        Session.grouped(sessionsMatchingSearch())
    }

    /// 已连接的 Agent。
    public var connectedAgents: [Agent] {
        agents.filter(\.isConnected)
    }

    /// 当前 Agent 的会话，按更新时间降序。
    public var currentAgentSessions: [Session] {
        sessions
            .filter { $0.agentID == nil || $0.agentID == currentAgentID }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// 当前连接是否在线。
    public var isConnected: Bool {
        if case .connected = connectionState { return true }
        return false
    }

    // MARK: Agent 动作

    /// 新增 Agent 并设为当前。
    public func addAgent(_ agent: Agent) {
        if let index = agents.firstIndex(where: { $0.id == agent.id }) {
            agents[index] = agent
        } else {
            agents.append(agent)
        }
        currentAgentID = agent.id
        if let existing = sessions.first(where: { $0.agentID == agent.id }) {
            selectedSessionID = existing.id
        }
    }

    /// 选择 Agent 并进入对话页。
    public func selectAgent(_ agent: Agent) {
        currentAgentID = agent.id
        selectedSessionID = sessions
            .filter { $0.agentID == agent.id }
            .max(by: { $0.updatedAt < $1.updatedAt })?
            .id
        isAgentPopoverOpen = false
        isDrawerOpen = false
        screen = .chat
    }

    /// 重命名当前 Agent。
    public func renameCurrentAgent(to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let currentAgentID,
              let index = agents.firstIndex(where: { $0.id == currentAgentID }) else {
            return
        }
        agents[index].displayName = trimmed
    }

    // MARK: 会话动作

    /// 新建会话并切换到对话页。
    ///
    /// 如果已连接 Hermes，会先调用 `session.create` 并携带当前模型 / provider / 推理强度。
    public func createSession(title: String? = nil) async {
        let agent = currentAgent
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolvedTitle = trimmed.isEmpty ? "新的会话" : trimmed

        var remoteID: String?
        var remoteModel: String?

        if let gateway {
            do {
                var params: [String: JSONValue] = [
                    "source": .string("local")
                ]

                if !availableModels.isEmpty, availableModels.contains(modelName) {
                    params["model"] = .string(modelName)

                    if let provider = modelProviderByModelName[modelName] ?? currentProvider,
                       !provider.isEmpty {
                        params["provider"] = .string(provider)
                    }
                }

                params["reasoning_effort"] = .string(effort.wireValue)

                let result = try await gateway.request(
                    method: GatewayMethod.sessionCreate,
                    params: .object(params)
                )

                remoteID = result["session_id"]?.stringValue
                remoteModel = Self.modelFromSessionCreateResult(result)
            } catch {
                lastErrorMessage = Self.describe(error)
            }
        }

        do {
            var session = try await sessionStore.createSession(title: resolvedTitle)
            session.agentID = agent?.id
            session.project = agent?.displayName
            session.preview = nil
            session.messageCount = 0
            session.remoteID = remoteID
            try? await sessionStore.update(session)
            sessions.insert(session, at: 0)
            messages[session.id] = []
            selectedSessionID = session.id

            if let remoteModel {
                remoteSessionModel[session.id] = remoteModel
            }
            remoteSessionReasoning[session.id] = effort.wireValue
        } catch {
            let now = Date()
            let session = Session(
                id: UUID(),
                title: resolvedTitle,
                createdAt: now,
                updatedAt: now,
                project: agent?.displayName,
                agentID: agent?.id,
                remoteID: remoteID
            )
            sessions.insert(session, at: 0)
            messages[session.id] = []
            selectedSessionID = session.id
            lastErrorMessage = error.localizedDescription

            if let remoteModel {
                remoteSessionModel[session.id] = remoteModel
            }
            remoteSessionReasoning[session.id] = effort.wireValue
        }

        screen = .chat
        isAgentPopoverOpen = false
        isDrawerOpen = false
    }

    /// 选中会话；抽屉关闭并进入对话页。
    public func selectSession(_ session: Session) {
        selectedSessionID = session.id
        if let agentID = session.agentID,
           agents.contains(where: { $0.id == agentID }) {
            currentAgentID = agentID
        }
        loadMessagesIfNeeded(session.id)
        screen = .chat
        isDrawerOpen = false
        isAgentPopoverOpen = false
    }

    /// 提交用户提示词：先本地落一条消息，再异步写入存储并发往网关。
    public func submitPrompt(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let session = ensureCurrentSession()
        let message = SessionMessage(
            sessionID: session.id,
            role: .user,
            text: trimmed
        )
        messages[session.id, default: []].append(message)
        touchSession(session.id, preview: trimmed)
        screen = .chat

        Task { [weak self] in
            guard let self else { return }
            try? await self.sessionStore.append(message)
            await self.sendPromptToGateway(trimmed, sessionID: session.id)
        }
    }

    // MARK: 审批

    /// 回送审批结果，并从待审批队列移除。
    public func respondApproval(_ card: ApprovalCard, choice: ApprovalChoice) {
        pendingApprovals.removeAll { $0.requestID == card.requestID }
        approvalResults[card.requestID] = choice

        let sessionID = card.sessionID ?? ensureCurrentSession().id
        let result = SessionMessage(
            sessionID: sessionID,
            role: .system,
            text: "审批结果：\(Self.approvalLabel(choice))"
        )
        appendMessage(result)

        let requestID = card.requestID
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.gateway?.respond(to: .string(requestID), choice: choice)
            } catch {
                self.lastErrorMessage = Self.describe(error)
            }
        }
    }

    // MARK: 连接动作

    /// 使用当前 Agent 的配置重新连接。
    public func connect() async {
        guard let configuration = currentAgent?.configuration else { return }
        await connect(configuration: configuration)
    }

    /// 使用给定配置连接网关；首次连接时若没有注入客户端则创建 URLSession 实现。
    public func connect(configuration: GatewayConfiguration) async {
        let client: any GatewayClient
        if let existing = gateway {
            client = existing
        } else {
            let created = URLSessionGatewayClient(
                credentials: GatewayCredentials(
                    token: accessToken.isEmpty ? nil : accessToken,
                    additionalHeaders: additionalHeaders
                )
            )
            gateway = created
            subscribe(to: created)
            client = created
        }

        connectionState = .connecting(try? configuration.normalizedBaseURL())
        do {
            try await client.connect(to: configuration)
            connectionState = client.currentState
            markCurrentAgentConnected(true)
            await refreshSessions()
            await refreshModels()
        } catch {
            let gatewayError = (error as? GatewayError) ?? .unreachable(error.localizedDescription)
            connectionState = .failed(gatewayError)
            lastErrorMessage = gatewayError.localizedDescription
        }
    }

    /// 断开网关。
    public func disconnect() async {
        await gateway?.disconnect()
        connectionState = .disconnected
        markCurrentAgentConnected(false)
    }

    /// 用临时客户端探测配置，不改变主连接状态。
    public func testConnection(configuration: GatewayConfiguration) async -> String {
        let probe = URLSessionGatewayClient(
            credentials: GatewayCredentials(
                token: accessToken.isEmpty ? nil : accessToken,
                additionalHeaders: additionalHeaders
            ),
            timings: GatewayTimings(
                statusTimeout: max(configuration.timeout, 1),
                handshakeTimeout: max(configuration.timeout, 1)
            )
        )

        do {
            try await probe.connect(to: configuration)
            let state = probe.currentState
            await probe.disconnect()
            if case .connected(let info) = state, !info.version.isEmpty {
                return "连接成功 · 网关 \(info.version)"
            }
            return "连接成功"
        } catch {
            return "连接失败：\(Self.describe(error))"
        }
    }

    /// 拉取会话列表与缺失的消息。
    public func refreshSessions() async {
        guard let loaded = try? await sessionStore.listSessions() else { return }
        if !loaded.isEmpty {
            sessions = loaded
        }
        if selectedSessionID == nil {
            selectedSessionID = loaded.first?.id
        }
        for session in loaded where messages[session.id] == nil {
            if let stored = try? await sessionStore.messages(sessionID: session.id) {
                messages[session.id] = stored
            }
        }
    }

    /// 从当前网关刷新可用模型列表与 provider 映射。
    ///
    /// Hermes 只登记了 `model.options`；未登记方法会返回 `-32601`。
    public func refreshModels() async {
        guard let gateway else { return }

        do {
            let result = try await gateway.request(method: GatewayMethod.modelOptions)
            let names = Self.modelNamesFromHermesModelOptions(result)
            guard !names.isEmpty else { return }

            availableModels = names
            modelProviderByModelName = Self.modelProviderMapFromHermesModelOptions(result)
            currentProvider = Self.currentProviderFromHermesModelOptions(result)

            if availableModels.contains(modelName) {
                // 保留用户已选模型。
            } else if let current = Self.currentModelNameFromHermesModelOptions(result),
                      availableModels.contains(current) {
                modelName = current
            } else if let first = availableModels.first {
                modelName = first
            }
        } catch {
            lastErrorMessage = Self.describe(error)
        }
    }

    // MARK: 主题与导航

    public func setTheme(_ theme: LichenTheme) {
        self.theme = theme
    }

    /// 打开连接页；记录来源与触发点，关闭时反向收拢。
    public func openConnect(from source: ConnectSource) {
        openConnect(from: source, anchor: nil)
    }

    /// 打开连接页并记录触发点坐标。
    public func openConnect(from source: ConnectSource, anchor: ConnectAnchor?) {
        connectSource = source
        connectAnchor = anchor
        isAgentPopoverOpen = false
        isDrawerOpen = false
        screen = .connect
    }

    /// 关闭连接页；对话页入口会在收拢结束后恢复 Agent 浮框。
    public func closeConnect() {
        let source = connectSource ?? .start
        screen = source == .chat ? .chat : .start
        if source == .chat {
            isAgentPopoverOpen = true
        }
        connectSource = nil
        connectAnchor = nil
    }

    /// 打开状态抽屉。
    public func openDrawer() {
        isDrawerOpen = true
        isAgentPopoverOpen = false
        screen = .status
    }

    /// 关闭状态抽屉。
    public func closeDrawer() {
        isDrawerOpen = false
        if screen == .status {
            screen = .chat
        }
    }

    /// 从状态抽屉进入全屏设置页。
    public func openSettings() {
        isDrawerOpen = false
        screen = .settings
    }

    /// 设置页返回状态抽屉。
    public func closeSettings() {
        screen = .status
        isDrawerOpen = true
    }

    // MARK: 网关订阅

    private func subscribe(to gateway: any GatewayClient) {
        guard !isSubscribed else { return }
        isSubscribed = true

        stateObservation = gateway.observeState { [weak self] state in
            Task { @MainActor [weak self] in
                self?.applyConnectionState(state)
            }
        }

        eventObservation = gateway.observeEvents { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handle(event)
            }
        }

        serverRequestObservation = gateway.observeServerRequests { [weak self] request in
            Task { @MainActor [weak self] in
                self?.handleServerRequest(request)
            }
        }
    }

    private func applyConnectionState(_ state: GatewayConnectionState) {
        connectionState = state
        switch state {
        case .connected:
            markCurrentAgentConnected(true)
            Task { [weak self] in
                await self?.refreshSessions()
                await self?.refreshModels()
            }
        case .disconnected, .failed:
            for index in agents.indices {
                agents[index].isConnected = false
            }
        case .connecting:
            break
        }
    }

    // MARK: 事件处理

    private func handle(_ event: GatewayEventEnvelope) {
        switch GatewayEventRouter.classify(event) {
        case .messageDelta(let text, let sessionID):
            appendStream(delta: text, role: .assistant, sessionRaw: sessionID)

        case .thinkingDelta(let text, let sessionID):
            appendStream(delta: text, role: .thinking, sessionRaw: sessionID)

        case .messageComplete(let text, let sessionID):
            completeAssistantMessage(text: text, sessionRaw: sessionID)

        case .sessionInfo, .sessionsChanged:
            Task { [weak self] in
                await self?.refreshSessions()
            }

        case .toolOutput(let toolName, let text, let sessionID):
            guard let text, !text.isEmpty else { return }
            let sessionID = resolveSessionID(sessionID)
            appendMessage(
                SessionMessage(
                    sessionID: sessionID,
                    role: .tool,
                    text: text,
                    toolName: toolName
                )
            )

        case .approvalRequest(let params, let requestID, let sessionID):
            handleApproval(params: params, requestID: requestID, sessionRaw: sessionID)

        case .approvalCancelled(let requestID, _):
            guard let requestID else { return }
            pendingApprovals.removeAll { $0.requestID == requestID }

        case .notice(let text):
            guard let text, !text.isEmpty else { return }
            let sessionID = resolveSessionID(nil)
            appendMessage(
                SessionMessage(sessionID: sessionID, role: .system, text: text)
            )

        case .statusUpdate, .ignored:
            break
        }
    }

    private func handleServerRequest(_ request: ServerRequest) {
        guard request.method == GatewayMethod.approval,
              let params = request.approvalParams else {
            return
        }
        let requestID: String
        switch request.id {
        case .int(let value):
            requestID = String(value)
        case .string(let value):
            requestID = value
        }
        handleApproval(
            params: params,
            requestID: params.requestID ?? params.promptID ?? requestID,
            sessionRaw: params.sessionID
        )
    }

    private func appendStream(delta: String, role: MessageRole, sessionRaw: String?) {
        guard !delta.isEmpty else { return }
        let sessionID = resolveSessionID(sessionRaw)
        let key = "\(role.rawValue)-\(sessionID.uuidString)"

        if let messageID = streamingMessageIDs[key],
           let index = messages[sessionID]?.firstIndex(where: { $0.id == messageID }) {
            messages[sessionID]?[index].text += delta
            return
        }

        let message = SessionMessage(
            sessionID: sessionID,
            role: role,
            text: delta,
            isEmphasized: role == .thinking
        )
        messages[sessionID, default: []].append(message)
        streamingMessageIDs[key] = message.id
    }

    private func completeAssistantMessage(text: String, sessionRaw: String?) {
        let sessionID = resolveSessionID(sessionRaw)
        let key = "\(MessageRole.assistant.rawValue)-\(sessionID.uuidString)"

        if let messageID = streamingMessageIDs[key],
           let index = messages[sessionID]?.firstIndex(where: { $0.id == messageID }) {
            let current = messages[sessionID]?[index].text ?? ""
            if !text.isEmpty, !current.hasSuffix(text) {
                messages[sessionID]?[index].text = current + text
            }
            streamingMessageIDs[key] = nil
        } else if !text.isEmpty {
            let message = SessionMessage(
                sessionID: sessionID,
                role: .assistant,
                text: text
            )
            messages[sessionID, default: []].append(message)
        }

        let preview = messages[sessionID]?.last?.text
        touchSession(sessionID, preview: preview)
    }

    private func handleApproval(
        params: ApprovalRequestParams?,
        requestID: String?,
        sessionRaw: String?
    ) {
        let sessionID = resolveSessionID(sessionRaw)
        let resolvedID = params?.requestID
            ?? params?.promptID
            ?? requestID
            ?? "approval-\(sessionID.uuidString)-\(pendingApprovals.count)"

        let card = ApprovalCard(
            requestID: resolvedID,
            sessionID: sessionID,
            command: params?.command ?? "",
            description: params?.description ?? "",
            choices: params?.choices ?? ApprovalChoice.allCases,
            executionGeneration: params?.executionGeneration.map { String($0) }
        )

        if !pendingApprovals.contains(where: { $0.requestID == card.requestID }) {
            pendingApprovals.append(card)
        }

        let alreadyRecorded = messages[sessionID]?.contains {
            $0.approval?.requestID == card.requestID
        } ?? false
        guard !alreadyRecorded else { return }

        let text: String
        if !card.command.isEmpty {
            text = card.command
        } else if !card.description.isEmpty {
            text = card.description
        } else {
            text = "需要审批"
        }

        appendMessage(
            SessionMessage(
                sessionID: sessionID,
                role: .approval,
                text: text,
                approval: card
            )
        )
    }

    private func appendMessage(_ message: SessionMessage) {
        messages[message.sessionID, default: []].append(message)
        touchSession(message.sessionID, preview: message.text)
        Task { [weak self] in
            try? await self?.sessionStore.append(message)
        }
    }

    // MARK: 会话辅助

    @discardableResult
    private func ensureCurrentSession() -> Session {
        if let currentSession {
            selectedSessionID = currentSession.id
            if messages[currentSession.id] == nil {
                messages[currentSession.id] = []
            }
            return currentSession
        }

        let now = Date()
        let session = Session(
            id: UUID(),
            title: "新的会话",
            createdAt: now,
            updatedAt: now,
            project: currentAgent?.displayName,
            agentID: currentAgentID
        )
        sessions.insert(session, at: 0)
        messages[session.id] = []
        selectedSessionID = session.id
        Task { [weak self] in
            try? await self?.sessionStore.update(session)
        }
        return session
    }

    private func resolveSessionID(_ raw: String?) -> UUID {
        if let raw, let parsed = UUID(uuidString: raw) {
            if !sessions.contains(where: { $0.id == parsed }) {
                let now = Date()
                let session = Session(
                    id: parsed,
                    title: "远程会话",
                    createdAt: now,
                    updatedAt: now,
                    project: currentAgent?.displayName,
                    agentID: currentAgentID,
                    remoteID: raw
                )
                sessions.insert(session, at: 0)
            }
            if selectedSessionID == nil {
                selectedSessionID = parsed
            }
            return parsed
        }
        if let selectedSessionID {
            return selectedSessionID
        }
        return ensureCurrentSession().id
    }

    private func touchSession(_ sessionID: UUID, preview: String?) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else {
            return
        }
        if let preview, !preview.isEmpty {
            sessions[index].preview = String(preview.prefix(120))
        }
        sessions[index].updatedAt = Date()
        sessions[index].messageCount = messages[sessionID]?.count ?? sessions[index].messageCount
        let session = sessions[index]
        Task { [weak self] in
            try? await self?.sessionStore.update(session)
        }
    }

    private func loadMessagesIfNeeded(_ sessionID: UUID) {
        guard messages[sessionID] == nil else { return }
        Task { [weak self] in
            guard let self,
                  let stored = try? await self.sessionStore.messages(sessionID: sessionID) else {
                return
            }
            self.messages[sessionID] = stored
        }
    }

    private func sessionsMatchingSearch() -> [Session] {
        let active = sessions.filter { !$0.isArchived }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return active }
        return active.filter { session in
            session.title.localizedCaseInsensitiveContains(query)
                || (session.project?.localizedCaseInsensitiveContains(query) ?? false)
                || (session.preview?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    private func sendPromptToGateway(_ text: String, sessionID: UUID) async {
        guard let gateway else {
            print("❌ sendPromptToGateway: gateway is nil")
            return
        }

        guard let session = sessions.first(where: { $0.id == sessionID }) else {
            print("❌ sendPromptToGateway: no session for \(sessionID)")
            return
        }

        let remoteID: String
        if let existingRemoteID = session.remoteID {
            remoteID = existingRemoteID
        } else if let createdRemoteID = await ensureRemoteHermesSession(for: sessionID) {
            remoteID = createdRemoteID
        } else {
            print("❌ sendPromptToGateway: unable to create remote session")
            return
        }

        print("✅ sendPromptToGateway: remoteID=\(remoteID) model=\(modelName) reasoning=\(effort.wireValue)")

        do {
            if !availableModels.isEmpty {
                let selectedModel = modelName

                if remoteSessionModel[sessionID] != selectedModel {
                    print("✅ sendPromptToGateway: calling config.set model=\(selectedModel)")
                    _ = try await gateway.request(
                        method: GatewayMethod.configSet,
                        params: .object([
                            "key": .string("model"),
                            "value": .string(selectedModel),
                            "session_id": .string(remoteID),
                            "confirm_expensive_model": .bool(false)
                        ])
                    )
                    remoteSessionModel[sessionID] = selectedModel
                }

                let selectedReasoning = effort.wireValue
                if remoteSessionReasoning[sessionID] != selectedReasoning {
                    print("✅ sendPromptToGateway: calling config.set reasoning=\(selectedReasoning)")
                    _ = try await gateway.request(
                        method: GatewayMethod.configSet,
                        params: .object([
                            "key": .string("reasoning"),
                            "value": .string(selectedReasoning),
                            "session_id": .string(remoteID)
                        ])
                    )
                    remoteSessionReasoning[sessionID] = selectedReasoning
                }
            }

            let frame = GatewayJSONRPC.promptSubmit(
                id: nextRequestID(),
                sessionID: remoteID,
                text: text
            )
            print("✅ sendPromptToGateway: frame=\(String(data: frame, encoding: .utf8) ?? "")")
            try await gateway.send(frame)
            print("✅ sendPromptToGateway: sent")
        } catch {
            print("❌ sendPromptToGateway error: \(error)")
            lastErrorMessage = Self.describe(error)
        }
    }

    /// 如果本地会话还没有 Hermes live session，则先调用 `session.create`。
    ///
    /// 成功后会更新本地 `Session.remoteID` 并返回远端 live id。
    private func ensureRemoteHermesSession(for sessionID: UUID) async -> String? {
        guard let gateway else {
            print("❌ ensureRemoteHermesSession: gateway is nil")
            return nil
        }

        var params: [String: JSONValue] = [
            "source": .string("local")
        ]

        if !availableModels.isEmpty, availableModels.contains(modelName) {
            params["model"] = .string(modelName)

            if let provider = modelProviderByModelName[modelName] ?? currentProvider,
               !provider.isEmpty {
                params["provider"] = .string(provider)
            }
        }

        params["reasoning_effort"] = .string(effort.wireValue)

        do {
            let result = try await gateway.request(
                method: GatewayMethod.sessionCreate,
                params: .object(params)
            )

            guard let remoteID = result["session_id"]?.stringValue else {
                print("❌ ensureRemoteHermesSession: result missing session_id: \(result)")
                lastErrorMessage = "Hermes session.create 未返回 session_id"
                return nil
            }

            if let index = sessions.firstIndex(where: { $0.id == sessionID }) {
                sessions[index].remoteID = remoteID
                let updated = sessions[index]
                try? await sessionStore.update(updated)
            }

            if let infoModel = Self.modelFromSessionCreateResult(result) {
                remoteSessionModel[sessionID] = infoModel
            }

            remoteSessionReasoning[sessionID] = effort.wireValue

            print("✅ ensureRemoteHermesSession: created \(remoteID) reasoning=\(effort.wireValue)")
            return remoteID
        } catch {
            print("❌ ensureRemoteHermesSession error: \(error)")
            lastErrorMessage = Self.describe(error)
            return nil
        }
    }

    private func nextRequestID() -> JSONRPCID {
        let identifier = frameCounter
        frameCounter = frameCounter == Int.max ? 1 : frameCounter + 1
        return .int(identifier)
    }

    private func markCurrentAgentConnected(_ connected: Bool) {
        guard let currentAgentID,
              let index = agents.firstIndex(where: { $0.id == currentAgentID }) else {
            return
        }
        agents[index].isConnected = connected
    }

    // MARK: 工具

    private static let defaultModelNames = [
        "Sonnet 4.5", "Opus 4.5", "Haiku 4.5"
    ]

    /// 从 Hermes `model.options` result 中提取全部模型名。
    ///
    /// 响应结构：
    /// `{"providers":[{"models":["deepseek-flash", ...]}, ...], "model": "...", "provider": "..."}`
    private static func modelNamesFromHermesModelOptions(_ value: JSONValue) -> [String] {
        guard let providers = value["providers"]?.arrayValue else { return [] }

        var names: [String] = []
        var seen = Set<String>()

        for provider in providers {
            guard let models = provider["models"]?.arrayValue else { continue }

            for model in models {
                guard let raw = model.stringValue else { continue }
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
                names.append(trimmed)
            }
        }

        return names
    }

    /// 从 Hermes `model.options` result 中读取当前模型名。
    private static func currentModelNameFromHermesModelOptions(_ value: JSONValue) -> String? {
        guard let raw = value["model"]?.stringValue else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// 从 Hermes `model.options` result 中读取当前 provider slug。
    private static func currentProviderFromHermesModelOptions(_ value: JSONValue) -> String? {
        guard let raw = value["provider"]?.stringValue else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// 建立模型名 → provider slug 的映射，用于 `session.create`。
    private static func modelProviderMapFromHermesModelOptions(_ value: JSONValue) -> [String: String] {
        guard let providers = value["providers"]?.arrayValue else { return [:] }

        var map: [String: String] = [:]
        for provider in providers {
            guard let models = provider["models"]?.arrayValue else { continue }
            guard let providerSlug = provider["slug"]?.stringValue else { continue }

            for model in models {
                guard let modelName = model.stringValue else { continue }
                let trimmedModel = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedProvider = providerSlug.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedModel.isEmpty, !trimmedProvider.isEmpty else { continue }
                map[trimmedModel] = trimmedProvider
            }
        }

        return map
    }

    private static func modelFromSessionCreateResult(_ value: JSONValue) -> String? {
        if let model = value["info"]?["model"]?.stringValue, !model.isEmpty {
            return model
        }
        return value["model"]?.stringValue
    }

    private static func providerFromSessionCreateResult(_ value: JSONValue) -> String? {
        if let provider = value["info"]?["provider"]?.stringValue, !provider.isEmpty {
            return provider
        }
        return value["provider"]?.stringValue
    }

    // MARK: 预览数据

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
            pendingApprovals: [approval],
            modelName: "Hermes",
            availableModels: ["Hermes", "Claude", "OpenCode"],
            currentProvider: "hermes",
            effort: .medium
        )
    }

    private static func messageOrder(_ lhs: SessionMessage, _ rhs: SessionMessage) -> Bool {
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func approvalLabel(_ choice: ApprovalChoice) -> String {
        switch choice {
        case .once:
            return "允许一次"
        case .session:
            return "本会话允许"
        case .always:
            return "始终允许"
        case .deny:
            return "拒绝"
        }
    }

    private static func describe(_ error: Error) -> String {
        if let gatewayError = error as? GatewayError {
            return gatewayError.localizedDescription
        }
        return error.localizedDescription
    }
}

// MARK: - 连接状态展示

public extension GatewayConnectionState {
    /// 简短中文状态名。
    var lichenStatusText: String {
        switch self {
        case .disconnected:
            return "未连接"
        case .connecting:
            return "连接中"
        case .connected:
            return "已连接"
        case .failed:
            return "连接失败"
        }
    }

    /// 是否处于已连接状态。
    var lichenIsConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    /// 供状态栏 / 设置页使用的说明文字。
    var lichenSummary: String {
        switch self {
        case .disconnected:
            return "远程网关 · 未连接"
        case .connecting(let url):
            return "正在连接 \(url?.host ?? "网关")"
        case .connected(let info):
            return info.version.isEmpty ? "远程网关 · 已连接" : "远程网关 · 已连接 · \(info.version)"
        case .failed(let error):
            return "连接失败 · \(error.localizedDescription)"
        }
    }
}
