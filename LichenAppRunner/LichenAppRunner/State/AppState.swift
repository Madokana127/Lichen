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

/// 关闭连接表单后恢复的入口。
public enum ConnectSource: String, Sendable {
    case start
    case chat
    case settings
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
/// 网关回调通过有序的事件流进入主 actor。
@MainActor
@Observable
public final class AppState {
    // MARK: 数据

    public private(set) var agents: [Agent]
    public private(set) var currentAgentID: UUID?
    public private(set) var sessions: [Session]
    public private(set) var messages: [UUID: [SessionMessage]]
    public private(set) var selectedSessionID: UUID?

    // MARK: 连接

    public private(set) var connectionState: GatewayConnectionState
    public private(set) var connectedAgentID: UUID?
    public private(set) var lastErrorMessage: String?
    public var operationError: String?

    // MARK: 界面

    public var theme: LichenTheme
    public private(set) var screen: AppScreen
    private(set) var backgroundScreen: AppScreen = .chat
    var isDrawerOpen: Bool { screen == .status }
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

    enum ApprovalStatus {
        case unavailable
        case pending
        case sending
        case sent(ApprovalChoice)
        case failed
        case cancelled
    }

    private struct LiveApproval {
        let rpcID: JSONRPCID
        let aliases: Set<String>
        let sessionID: UUID
        let connectionID: UUID
    }

    private var approvalStatuses: [UUID: ApprovalStatus] = [:]
    private var liveApprovals: [UUID: LiveApproval] = [:]
    private var seenApprovalRPCIDs: Set<JSONRPCID> = []
    private var approvalNotices: [UUID: [String: UUID]] = [:]

    // MARK: 连接页来源

    public private(set) var connectSource: ConnectSource?
    public private(set) var connectAnchor: ConnectAnchor?
    private(set) var editingAgentID: UUID?
    private(set) var editingConnectionMethod: ConnectionMethod?

    // MARK: 依赖

    private let sessionRepository: SessionRepository
    private let agentStore: AgentStore?
    private let credentialStore: (any GatewayCredentialStore)?
    private let injectedGateway: (any GatewayClient)?
    private var gateway: (any GatewayClient)?
    private var connectionID = UUID()
    private var liveConnectionID = UUID()
    private var connectionAgentID: UUID?
    private var observations: [any GatewayStateObservation] = []
    private var gatewayEventsTask: Task<Void, Never>?
    private var connectionRefreshTask: Task<Void, Never>?
    private var credentialsByAgent: [UUID: GatewayCredentials] = [:]
    private var agentSaveTask: Task<Void, Never>?
    private var hasRestoredState = false

    private var streamingMessageIDs: [UUID: [MessageRole: UUID]] = [:]
    private struct ActiveTurn {
        let id: UUID
        let remoteID: String
    }

    private var activeTurns: [UUID: ActiveTurn] = [:]
    private var stoppingSessions: Set<UUID> = []
    private struct Submission {
        let messageID: UUID
        let task: Task<Void, Never>
    }

    private var submissions: [UUID: Submission] = [:]
    private var loadedMessageSessions: Set<UUID> = []
    private var loadingMessageSessions: [UUID: Task<Void, Never>] = [:]
    private var remoteHistory: [UUID: SessionHistorySnapshot] = [:]
    private var remoteHistoryTasks: [UUID: Task<Void, Never>] = [:]
    private var attachedSessions: Set<UUID> = []
    private var modelOptionsByName: [String: HermesGateway.ModelOption] = [:]
    private var remoteSessionSettings: [UUID: RemoteSessionSettings] = [:]

    private struct RemoteSessionSettings {
        var model: String?
        var reasoning: String?
    }

    // MARK: 初始化

    public init(
        gateway: (any GatewayClient)? = nil,
        sessionStore: any SessionStore = InMemorySessionStore(),
        agentStore: AgentStore? = nil,
        credentialStore: (any GatewayCredentialStore)? = nil,
        agents: [Agent] = [],
        currentAgentID: UUID? = nil,
        sessions: [Session] = [],
        selectedSessionID: UUID? = nil,
        messages: [UUID: [SessionMessage]] = [:],
        connectionState: GatewayConnectionState = .disconnected,
        theme: LichenTheme = .system,
        screen: AppScreen = .start,
        modelName: String = "Sonnet 4.5",
        availableModels: [String] = [],
        currentProvider: String? = nil,
        effort: LichenEffort = .medium,
        gitBranch: String = "main",
        keepsSessionInBackground: Bool = true,
        autoReconnect: Bool = true
    ) {
        self.gateway = gateway
        self.injectedGateway = gateway
        self.sessionRepository = SessionRepository(store: sessionStore)
        self.agentStore = agentStore
        self.credentialStore = credentialStore
        self.agents = agents
        self.currentAgentID = currentAgentID ?? agents.first?.id
        self.sessions = sessions
        self.messages = messages
        self.loadedMessageSessions = Set(messages.keys)
        self.selectedSessionID = selectedSessionID
        self.connectionState = connectionState
        self.theme = theme
        self.screen = screen
        self.searchText = ""
        self.modelName = modelName
        self.availableModels = availableModels
        self.currentProvider = currentProvider
        self.effort = effort
        self.gitBranch = gitBranch
        self.keepsSessionInBackground = keepsSessionInBackground
        self.autoReconnect = autoReconnect
        self.lastErrorMessage = nil
        self.connectSource = nil
        self.connectAnchor = nil

        if let gateway {
            connectionAgentID = self.currentAgentID
            if case .connected = connectionState {
                connectedAgentID = connectionAgentID
            }
            subscribe(to: gateway, connectionID: connectionID)
        }
    }

    // MARK: 计算属性

    /// 当前 Agent。
    public var currentAgent: Agent? {
        guard let currentAgentID else { return nil }
        return agents.first { $0.id == currentAgentID }
    }

    /// 当前明确打开的会话；没有选择时，发送消息会新建会话。
    public var currentSession: Session? {
        guard let selectedSessionID else { return nil }
        return sessions.first { $0.id == selectedSessionID && $0.agentID == currentAgentID }
    }

    /// 当前会话的消息，按时间升序。
    public var currentMessages: [SessionMessage] {
        guard let sessionID = currentSession?.id else { return [] }
        let local = messages[sessionID] ?? []
        guard let history = remoteHistory[sessionID] else { return local.sorted(by: Self.messageOrder) }
        return (history.messages + local.filter { !history.mirroredLocalIDs.contains($0.id) })
            .sorted(by: Self.messageOrder)
    }

    var isLoadingCurrentRemoteHistory: Bool {
        guard let sessionID = currentSession?.id else { return false }
        return remoteHistoryTasks[sessionID] != nil
    }

    /// 供模型选择 UI 使用的模型列表；网关未返回时回退到默认占位模型。
    public var modelOptions: [String] {
        availableModels.isEmpty || !isConnected ? Self.defaultModelNames : availableModels
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
            .filter { $0.agentID == currentAgentID }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// 当前连接是否在线。
    public var isConnected: Bool {
        guard case .connected = connectionState else { return false }
        return connectedAgentID != nil && connectedAgentID == currentAgentID
    }

    // MARK: Agent 动作

    /// 新增 Agent 并设为当前。
    public func addAgent(_ agent: Agent) {
        saveAgentInList(agent, selecting: true)
    }

    private func saveAgentInList(_ agent: Agent, selecting: Bool) {
        if let index = agents.firstIndex(where: { $0.id == agent.id }) {
            agents[index] = agent
        } else {
            agents.append(agent)
        }
        if selecting { chooseAgent(agent.id) }
        saveAgent(agent)
    }

    /// 选择 Agent 并进入对话页。
    public func selectAgent(_ agent: Agent) {
        chooseAgent(agent.id)
        saveAgent()
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
        saveAgent(agents[index])
    }

    func editConnection(from source: ConnectSource, method: ConnectionMethod? = nil) {
        guard let agent = currentAgent else { return }
        openConnect(from: source)
        editingAgentID = agent.id
        editingConnectionMethod = method
    }

    private func chooseAgent(_ id: UUID?) {
        if currentAgentID != id {
            currentAgentID = id
            selectedSessionID = nil
        }
    }

    private func saveAgent(_ agent: Agent? = nil) {
        guard let agentStore else { return }
        let previous = agentSaveTask
        let selection = currentAgentID
        agentSaveTask = Task {
            await previous?.value
            if var agent {
                agent.isConnected = false
                await agentStore.add(agent)
            }
            if let selection { await agentStore.setCurrent(id: selection) }
        }
    }

    func restore() async {
        guard !hasRestoredState else { return }
        hasRestoredState = true
        let startupConnectionID = connectionID
        let initialSelection = currentAgentID
        var restoredSelection: UUID?
        if let agentStore {
            let restored = await agentStore.list()
            let selected = await agentStore.current?.id
            agents.append(contentsOf: restored.filter { agent in
                !agents.contains { $0.id == agent.id }
            }.map { agent in
                var agent = agent
                agent.isConnected = false
                return agent
            })
            if currentAgentID == nil { chooseAgent(selected) }
            restoredSelection = selected
        }
        await loadLocalSessions()

        // A connection or selection made while loading takes precedence over startup.
        guard !Task.isCancelled, startupConnectionID == connectionID, initialSelection == nil,
              let agent = currentAgent, agent.id == restoredSelection,
              let credentials = savedCredentials(for: agent.id) else { return }
        await connect(agent: agent, credentials: credentials, persistCredentials: false)
    }

    var isCurrentSessionActive: Bool {
        guard isConnected, let sessionID = currentSession?.id else { return false }
        return activeTurns[sessionID] != nil || stoppingSessions.contains(sessionID)
    }

    var isStoppingCurrentSession: Bool {
        guard let sessionID = currentSession?.id else { return false }
        return stoppingSessions.contains(sessionID)
    }

    // MARK: 会话动作

    /// 先保存完整的本地会话，首次发送再绑定 Hermes 会话。
    public func createSession(title: String? = nil) async {
        let title = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let session = makeSession(title: title.isEmpty ? "新的会话" : title, agentID: currentAgentID)
        selectedSessionID = session.id
        screen = .chat
        await reportPersistence(sessionRepository.save(session))
    }

    public func selectSession(_ session: Session) {
        chooseAgent(session.agentID)
        selectedSessionID = session.id
        if loadRemoteHistory(for: session) == nil {
            Task { await loadMessages(session.id) }
        }
        saveAgent()
        screen = .chat
    }

    public func submitPrompt(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, screen == .start || !isStoppingCurrentSession else { return }
        let existingSession = screen == .start ? nil : currentSession
        let session = existingSession ?? makeSession(title: "新的会话", agentID: currentAgentID)
        selectedSessionID = session.id
        screen = .chat

        let message = SessionMessage(sessionID: session.id, role: .user, text: text, delivery: .sending)
        guard let save = record(message) else { return }
        let previous = submissions[session.id]?.task
        let attempt = liveConnectionID
        let model = modelOptionsByName[modelName]
        let reasoning = effort.wireValue
        let task = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            var result = message
            do {
                try await save.value
                try await self.sendPrompt(message, connectionID: attempt, model: model, reasoning: reasoning)
                result.delivery = .sent
            } catch {
                result.delivery = .failed
                self.operationError = Self.describe(error)
            }
            if let saveResult = self.record(result, updatesPreview: false) {
                await self.reportPersistence(saveResult)
            }
            if self.submissions[session.id]?.messageID == message.id {
                self.submissions[session.id] = nil
            }
        }
        submissions[session.id] = Submission(messageID: message.id, task: task)
    }

    func stopGenerating() async {
        guard isConnected, let gateway, let sessionID = currentSession?.id,
              let turn = activeTurns[sessionID], stoppingSessions.insert(sessionID).inserted else { return }
        let liveID = liveConnectionID
        defer {
            if liveConnectionID == liveID { stoppingSessions.remove(sessionID) }
        }
        do {
            let alreadyIdle = try await HermesGateway(client: gateway).interrupt(sessionID: turn.remoteID)
            if alreadyIdle, liveConnectionID == liveID, activeTurns[sessionID]?.id == turn.id {
                completeStream(text: "", sessionID: sessionID)
            }
        } catch {
            guard liveConnectionID == liveID, activeTurns[sessionID]?.id == turn.id else { return }
            operationError = "停止远端输出失败：\(Self.describe(error))"
        }
    }

    // MARK: 审批

    func approvalStatus(for messageID: UUID) -> ApprovalStatus {
        approvalStatuses[messageID] ?? .unavailable
    }

    func respondApproval(messageID: UUID, choice: ApprovalChoice) {
        switch approvalStatus(for: messageID) {
        case .pending, .failed: break
        default: return
        }
        guard let approval = liveApprovals[messageID],
              approval.connectionID == liveConnectionID,
              connectedAgentID != nil,
              let gateway else { return }
        approvalStatuses[messageID] = .sending

        Task { [weak self] in
            guard let self, self.liveApprovals[messageID]?.connectionID == approval.connectionID else { return }
            do {
                try await gateway.respond(to: approval.rpcID, choice: choice)
                guard self.liveApprovals[messageID]?.connectionID == approval.connectionID else { return }
                self.liveApprovals[messageID] = nil
                self.approvalStatuses[messageID] = .sent(choice)
                let result = SessionMessage(
                    sessionID: approval.sessionID,
                    role: .system,
                    text: "审批结果：\(Self.approvalLabel(choice))"
                )
                self.appendMessage(result)
            } catch {
                guard self.liveApprovals[messageID]?.connectionID == approval.connectionID else { return }
                self.approvalStatuses[messageID] = .failed
            }
        }
    }

    // MARK: 连接动作

    var selectedConnectionState: GatewayConnectionState {
        connectionAgentID == currentAgentID ? connectionState : .disconnected
    }

    var agentBeingEdited: Agent? {
        agents.first { $0.id == editingAgentID }
    }

    func connectSelectedAgent(from source: ConnectSource) async {
        guard let agent = currentAgent else { return }
        if case .failed(.unauthorized) = selectedConnectionState {
            editConnection(from: source)
            return
        }
        guard let credentials = savedCredentials(for: agent.id) else {
            editConnection(from: source)
            return
        }
        if !(await connect(agent: agent, credentials: credentials, persistCredentials: false)), let lastErrorMessage {
            if currentAgentID == agent.id, case .failed(.unauthorized) = selectedConnectionState {
                editConnection(from: source)
            } else {
                operationError = lastErrorMessage
            }
        }
    }

    private func savedCredentials(for agentID: UUID) -> GatewayCredentials? {
        if let credentials = credentialsByAgent[agentID] { return credentials }
        do {
            return try credentialStore?.load(for: agentID)
        } catch {
            operationError = "读取网关凭据失败：\(Self.describe(error))"
            return nil
        }
    }

    @discardableResult
    func connect(agent: Agent, credentials: GatewayCredentials, persistCredentials: Bool = true) async -> Bool {
        let oldGateway = gateway
        let selectedAtStart = currentAgentID
        let attempt = replaceConnection(agentID: agent.id)
        lastErrorMessage = nil
        connectionState = .connecting(try? agent.configuration.normalizedBaseURL())
        await oldGateway?.disconnect()
        guard attempt == connectionID else { return false }

        let client = injectedGateway ?? URLSessionGatewayClient(
            credentials: credentials,
            timings: GatewayTimings(
                statusTimeout: max(agent.configuration.timeout, 1),
                handshakeTimeout: max(agent.configuration.timeout, 1)
            ),
            automaticallyReconnects: autoReconnect
        )
        gateway = client
        subscribe(to: client, connectionID: attempt)
        do {
            try await client.connect(to: agent.configuration)
            guard attempt == connectionID else { return false }
            guard client.currentState.lichenIsConnected else { return false }
            credentialsByAgent[agent.id] = credentials
            if persistCredentials {
                do {
                    try credentialStore?.save(credentials, for: agent.id)
                } catch {
                    operationError = "连接成功，但保存网关凭据失败：\(Self.describe(error))"
                }
            }
            var connectedAgent = agent
            connectedAgent.isConnected = true
            saveAgentInList(connectedAgent, selecting: currentAgentID == selectedAtStart)
            applyConnectionState(client.currentState)
            await agentSaveTask?.value
            return attempt == connectionID && connectedAgentID == agent.id
        } catch {
            guard attempt == connectionID else { return false }
            let error = (error as? GatewayError) ?? .unreachable(error.localizedDescription)
            connectionState = .failed(error)
            lastErrorMessage = error.localizedDescription
            return false
        }
    }

    public func disconnect() async {
        let client = gateway
        _ = replaceConnection(agentID: nil)
        connectionState = .disconnected
        await client?.disconnect()
    }

    private func replaceConnection(agentID: UUID?) -> UUID {
        connectionID = UUID()
        connectionAgentID = agentID
        gateway = nil
        observations.forEach { $0.cancel() }
        observations.removeAll()
        gatewayEventsTask?.cancel()
        connectionRefreshTask?.cancel()
        connectionRefreshTask = nil
        invalidateLiveConnection()
        return connectionID
    }

    func testConnection(configuration: GatewayConfiguration, credentials: GatewayCredentials) async -> String {
        let probe = URLSessionGatewayClient(
            credentials: credentials,
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
            await probe.disconnect()
            return "连接失败：\(Self.describe(error))"
        }
    }

    public func refreshSessions() async {
        await loadLocalSessions()
        guard let agentID = currentAgentID, agentID == connectedAgentID else { return }
        await refreshRemoteSessions(agentID: agentID, liveID: liveConnectionID)
        if let session = currentSession { await loadRemoteHistory(for: session)?.value }
    }

    private func refreshRemoteSessions(agentID: UUID, liveID: UUID) async {
        guard liveID == liveConnectionID, connectedAgentID == agentID,
              let gateway, let agent = agents.first(where: { $0.id == agentID }) else { return }
        do {
            let remote = try await HermesGateway(client: gateway).sessions(profile: agent.configuration.remoteProfile)
            guard liveConnectionID == liveID, connectedAgentID == agentID else { return }
            var knownIDs = Set(sessions.filter { $0.agentID == agentID }.flatMap {
                [$0.remoteID, $0.remoteHistoryID].compactMap { $0 }
            })
            let saves = remote.reversed().compactMap { session -> Task<Void, Error>? in
                guard knownIDs.insert(session.id).inserted else { return nil }
                let local = makeSession(
                    title: session.title.flatMap { $0.isEmpty ? nil : $0 } ?? "远程会话",
                    agentID: agentID,
                    remoteHistoryID: session.id
                )
                return sessionRepository.save(local)
            }
            for save in saves { await reportPersistence(save) }
        } catch {
            guard liveConnectionID == liveID, connectedAgentID == agentID,
                  !Task.isCancelled else { return }
            operationError = "刷新远程会话失败：\(Self.describe(error))"
        }
    }

    public func refreshModels() async {
        guard isConnected else { return }
        await refreshModels(liveID: liveConnectionID)
    }

    private func refreshModels(liveID: UUID) async {
        guard liveID == liveConnectionID, let gateway else { return }
        do {
            let catalog = try await HermesGateway(client: gateway).models()
            guard liveConnectionID == liveID, connectedAgentID != nil, !Task.isCancelled else { return }
            currentProvider = catalog.currentProvider
            modelOptionsByName.removeAll()
            var names: [String] = []
            for option in catalog.options {
                if modelOptionsByName[option.name] == nil { names.append(option.name) }
                if modelOptionsByName[option.name] == nil || option.provider == currentProvider {
                    modelOptionsByName[option.name] = option
                }
            }
            availableModels = names
            if !names.contains(modelName) {
                modelName = names.first { $0 == catalog.currentName } ?? names.first ?? Self.defaultModelNames[0]
            }
        } catch {
            guard liveConnectionID == liveID, connectedAgentID != nil, !Task.isCancelled else { return }
            operationError = "读取网关模型失败：\(Self.describe(error))"
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
        editingAgentID = nil
        editingConnectionMethod = nil
        screen = .connect
    }

    /// 转场结束后返回表单的入口。
    public func closeConnect() {
        let source = connectSource ?? .start
        switch source {
        case .start: screen = .start
        case .chat: screen = .chat
        case .settings: screen = .settings
        }
        editingAgentID = nil
        editingConnectionMethod = nil
        connectSource = nil
        connectAnchor = nil
    }

    public func openDrawer() {
        guard screen == .start || screen == .chat else { return }
        backgroundScreen = screen
        screen = .status
    }

    public func closeDrawer() {
        if screen == .status { screen = backgroundScreen }
    }

    public func openSettings() {
        screen = .settings
    }

    public func closeSettings() {
        screen = .status
    }

    // MARK: 网关订阅

    private enum GatewayUpdate: Sendable {
        case state(GatewayConnectionState)
        case event(GatewayEventEnvelope)
        case request(ServerRequest)
    }

    private func subscribe(to gateway: any GatewayClient, connectionID: UUID) {
        let (updates, continuation) = AsyncStream<GatewayUpdate>.makeStream()
        let alreadyConnected = gateway.currentState.lichenIsConnected
        observations = [
            gateway.observeState { continuation.yield(.state($0)) },
            gateway.observeEvents { continuation.yield(.event($0)) },
            gateway.observeServerRequests { continuation.yield(.request($0)) }
        ]

        gatewayEventsTask = Task { [weak self] in
            defer { continuation.finish() }
            var receivedHandshake = alreadyConnected
            for await update in updates {
                guard let self, self.connectionID == connectionID, !Task.isCancelled else { return }
                switch update {
                case .state(let state):
                    // The explicit connect handles its own initial failure. Skip handshake snapshots
                    // that could be queued before the connect call returns to the main actor.
                    guard receivedHandshake || state.lichenIsConnected else { continue }
                    receivedHandshake = true
                    self.applyConnectionState(state)
                case .event(let event):
                    if self.connectedAgentID != nil { self.handle(event) }
                case .request(let request):
                    if self.connectedAgentID != nil { self.handleServerRequest(request) }
                }
            }
        }
    }

    private func applyConnectionState(_ state: GatewayConnectionState) {
        if case .connected = state, let agentID = connectionAgentID,
           !agents.contains(where: { $0.id == agentID }) { return }
        connectionState = state
        if case .connected = state, let agentID = connectionAgentID {
            guard connectedAgentID != agentID else { return }
            connectedAgentID = agentID
            if let index = agents.firstIndex(where: { $0.id == agentID }) {
                agents[index].isConnected = true
            }
            let liveID = liveConnectionID
            connectionRefreshTask = Task { [weak self] in
                guard let self else { return }
                async let models: Void = self.refreshModels(liveID: liveID)
                await self.loadLocalSessions()
                if self.liveConnectionID == liveID, let session = self.currentSession {
                    await self.loadRemoteHistory(for: session)?.value
                }
                await models
            }
        } else {
            connectionRefreshTask?.cancel()
            invalidateLiveConnection()
        }
    }

    private func invalidateLiveConnection() {
        liveConnectionID = UUID()
        if let index = agents.firstIndex(where: { $0.id == connectedAgentID }) {
            agents[index].isConnected = false
        }
        connectedAgentID = nil
        availableModels.removeAll()
        currentProvider = nil
        modelOptionsByName.removeAll()
        remoteSessionSettings.removeAll()
        streamingMessageIDs.removeAll()
        activeTurns.removeAll()
        stoppingSessions.removeAll()
        for id in liveApprovals.keys { approvalStatuses[id] = .cancelled }
        liveApprovals.removeAll()
        seenApprovalRPCIDs.removeAll()
        approvalNotices.removeAll()
        attachedSessions.removeAll()
        remoteHistoryTasks.values.forEach { $0.cancel() }
        remoteHistoryTasks.removeAll()
    }

    // MARK: 事件处理

    private func handle(_ event: GatewayEventEnvelope) {
        if event.type == GatewayEventType.messageStart {
            let remoteID = event.sessionID ?? event.payload?["session_id"]?.stringValue
            if let remoteID, let sessionID = resolveSessionID(remoteID) {
                beginTurn(sessionID: sessionID, remoteID: remoteID)
            }
            return
        }
        switch GatewayEventRouter.classify(event) {
        case .messageDelta(let text, let sessionID):
            appendStream(delta: text, role: .assistant, remoteID: sessionID)
        case .thinkingDelta(let text, let sessionID):
            appendStream(delta: text, role: .thinking, remoteID: sessionID)
        case .messageComplete(let text, let sessionID):
            if let sessionID = resolveSessionID(sessionID) {
                completeStream(text: text, sessionID: sessionID)
            }
        case .sessionInfo(let remoteID, let payload):
            guard let sessionID = resolveSessionID(remoteID),
                  let index = sessions.firstIndex(where: { $0.id == sessionID }),
                  let storedID = payload?["stored_session_id"]?.stringValue,
                  !storedID.isEmpty, sessions[index].remoteHistoryID != storedID else { return }
            sessions[index].remoteHistoryID = storedID
            persist(sessions[index])
        case .toolOutput(let toolName, let text, let remoteID):
            guard let sessionID = resolveSessionID(remoteID), let text, !text.isEmpty else { return }
            appendMessage(SessionMessage(sessionID: sessionID, role: .tool, text: text, toolName: toolName))
        case .approvalRequest(let params, let requestID, let remoteID):
            guard let sessionID = resolveSessionID(remoteID ?? params?.sessionID),
                  let identifier = params?.requestID ?? params?.promptID ?? requestID,
                  approvalNotices[sessionID]?[identifier] == nil,
                  !liveApprovals.values.contains(where: {
                      $0.sessionID == sessionID && $0.aliases.contains(identifier)
                  }) else { return }
            approvalNotices[sessionID, default: [:]][identifier] = recordApproval(
                params: params, identifier: identifier, sessionID: sessionID
            )
        case .approvalCancelled(let requestID, let remoteID):
            guard let requestID else { return }
            let sessionID = resolveSessionID(remoteID)
            guard remoteID == nil || sessionID != nil else { return }
            let matches = liveApprovals.filter { _, approval in
                approval.aliases.contains(requestID) && (sessionID == nil || approval.sessionID == sessionID)
            }
            for id in matches.keys {
                liveApprovals[id] = nil
                approvalStatuses[id] = .cancelled
            }
        case .notice(let text):
            let remoteID = event.sessionID ?? event.payload?["session_id"]?.stringValue
            guard let sessionID = resolveSessionID(remoteID), let text, !text.isEmpty else { return }
            appendMessage(SessionMessage(sessionID: sessionID, role: .system, text: text))
        case .sessionsChanged, .statusUpdate, .ignored:
            break
        }
    }

    private func handleServerRequest(_ request: ServerRequest) {
        guard let params = request.approvalParams,
              let sessionID = resolveSessionID(params.sessionID),
              seenApprovalRPCIDs.insert(request.id).inserted else { return }
        let identifier: String
        switch request.id {
        case .int(let value): identifier = String(value)
        case .string(let value): identifier = value
        }
        let aliases = Set([params.requestID, params.promptID, identifier].compactMap { $0 })
        let notice = [params.requestID, params.promptID, identifier].compactMap { $0 }
            .compactMap { approvalNotices[sessionID]?[$0] }.first {
                if case .unavailable = approvalStatus(for: $0) { return true }
                return false
            }
        let messageID = recordApproval(
            params: params, identifier: identifier, sessionID: sessionID, messageID: notice
        )
        for alias in aliases { approvalNotices[sessionID, default: [:]][alias] = messageID }
        liveApprovals[messageID] = LiveApproval(
            rpcID: request.id, aliases: aliases, sessionID: sessionID, connectionID: liveConnectionID
        )
        approvalStatuses[messageID] = .pending
    }

    private func recordApproval(
        params: ApprovalRequestParams?, identifier: String, sessionID: UUID, messageID: UUID? = nil
    ) -> UUID {
        let previous = messages[sessionID]?.first { $0.id == messageID }
        let card = ApprovalCard(
            requestID: identifier,
            sessionID: sessionID,
            command: params?.command ?? previous?.approval?.command ?? "",
            description: params?.description ?? previous?.approval?.description ?? "",
            choices: params?.choices ?? previous?.approval?.choices ?? ApprovalChoice.allCases,
            executionGeneration: params?.executionGeneration.map(String.init) ?? previous?.approval?.executionGeneration
        )
        let text = [card.command, card.description, previous?.text ?? ""].first { !$0.isEmpty } ?? "需要审批"
        let message = SessionMessage(
            id: messageID ?? UUID(),
            sessionID: sessionID,
            role: .approval,
            text: text,
            createdAt: previous?.createdAt ?? Date(),
            approval: card
        )
        if let save = record(message, updatesPreview: previous == nil) { observePersistence(save) }
        return message.id
    }

    private func appendStream(delta: String, role: MessageRole, remoteID: String?) {
        guard !delta.isEmpty, let remoteID, let sessionID = resolveSessionID(remoteID) else { return }
        beginTurn(sessionID: sessionID, remoteID: remoteID)
        if let messageID = streamingMessageIDs[sessionID]?[role],
           let index = messages[sessionID]?.firstIndex(where: { $0.id == messageID }) {
            messages[sessionID]?[index].text += delta
            return
        }

        let message = SessionMessage(
            sessionID: sessionID, role: role, text: delta, isEmphasized: role == .thinking
        )
        messages[sessionID, default: []].append(message)
        streamingMessageIDs[sessionID, default: [:]][role] = message.id
    }

    private func beginTurn(sessionID: UUID, remoteID: String, id: UUID = UUID()) {
        if activeTurns[sessionID] == nil {
            activeTurns[sessionID] = ActiveTurn(id: id, remoteID: remoteID)
        }
    }

    private func completeStream(text: String, sessionID: UUID) {
        let stream = streamingMessageIDs.removeValue(forKey: sessionID) ?? [:]
        activeTurns.removeValue(forKey: sessionID)
        if let thinking = messages[sessionID]?.first(where: { $0.id == stream[.thinking] }) {
            appendMessage(thinking)
        }
        if var assistant = messages[sessionID]?.first(where: { $0.id == stream[.assistant] }) {
            if !text.isEmpty { assistant.text = text }
            appendMessage(assistant)
        } else if !text.isEmpty {
            appendMessage(SessionMessage(sessionID: sessionID, role: .assistant, text: text))
        }
    }

    private func resolveSessionID(_ remoteID: String?) -> UUID? {
        guard let remoteID, !remoteID.isEmpty, let agentID = connectedAgentID else { return nil }
        return sessions.first { $0.agentID == agentID && $0.remoteID == remoteID }?.id
            ?? sessions.first { $0.agentID == agentID && $0.remoteHistoryID == remoteID }?.id
    }

    // MARK: 会话读写

    private func makeSession(
        title: String, agentID: UUID?, remoteHistoryID: String? = nil
    ) -> Session {
        let now = Date()
        let session = Session(
            id: UUID(),
            title: title,
            createdAt: now,
            updatedAt: now,
            project: agents.first { $0.id == agentID }?.displayName,
            agentID: agentID,
            remoteHistoryID: remoteHistoryID
        )
        sessions.insert(session, at: 0)
        loadedMessageSessions.insert(session.id)
        return session
    }

    private func appendMessage(_ message: SessionMessage) {
        if let save = record(message) { observePersistence(save) }
    }

    private func record(_ message: SessionMessage, updatesPreview: Bool = true) -> Task<Void, Error>? {
        guard let index = sessions.firstIndex(where: { $0.id == message.sessionID }) else { return nil }
        if let existing = messages[message.sessionID]?.firstIndex(where: { $0.id == message.id }) {
            messages[message.sessionID]?[existing] = message
        } else {
            messages[message.sessionID, default: []].append(message)
        }
        if updatesPreview {
            sessions[index].preview = String(message.text.prefix(120))
            sessions[index].updatedAt = Date()
            sessions[index].messageCount += 1
        }
        return sessionRepository.save(sessions[index], message: message)
    }

    private func persist(_ session: Session) {
        observePersistence(sessionRepository.save(session))
    }

    private func observePersistence(_ save: Task<Void, Error>) {
        Task { [weak self] in await self?.reportPersistence(save) }
    }

    private func reportPersistence(_ save: Task<Void, Error>) async {
        do {
            try await save.value
        } catch {
            operationError = "保存会话失败：\(Self.describe(error))"
        }
    }

    private func loadLocalSessions() async {
        do {
            let loaded = try await sessionRepository.sessions()
            let knownIDs = Set(sessions.map(\.id))
            sessions.append(contentsOf: loaded.filter { !knownIDs.contains($0.id) })
            if let sessionID = currentSession?.id {
                await loadMessages(sessionID)
            }
        } catch {
            operationError = "读取会话失败：\(Self.describe(error))"
        }
    }

    private func loadRemoteHistory(for session: Session) -> Task<Void, Never>? {
        if let task = remoteHistoryTasks[session.id] { return task }
        guard submissions[session.id] == nil,
              let agentID = session.agentID, agentID == connectedAgentID, let gateway,
              let remoteID = session.remoteHistoryID ?? session.remoteID else { return nil }

        let liveID = liveConnectionID
        let profile = agents.first { $0.id == agentID }?.configuration.remoteProfile
        let task = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.liveConnectionID == liveID { self.remoteHistoryTasks[session.id] = nil }
            }
            let hermes = HermesGateway(client: gateway)
            await self.loadMessages(session.id)
            do {
                try self.checkConnection(liveID, agentID: agentID)
                let rows: [HermesGateway.HistoryRow]
                do {
                    rows = try await hermes.transcript(sessionID: remoteID, profile: profile)
                } catch GatewayError.server(-32601, _) {
                    try self.checkConnection(liveID, agentID: agentID)
                    if !self.attachedSessions.contains(session.id), let storedID = session.remoteHistoryID {
                        let resumed = try await hermes.resumeSession(storedID, profile: profile)
                        try self.checkConnection(liveID, agentID: agentID)
                        try await self.bind(resumed, to: session.id, historyID: storedID)
                        if let history = resumed.history {
                            rows = hermes.decodeHistory(history)
                        } else {
                            rows = try await hermes.liveHistory(sessionID: resumed.id)
                        }
                    } else {
                        let activeID = self.sessions.first { $0.id == session.id }?.remoteID
                        rows = try await hermes.liveHistory(sessionID: activeID ?? remoteID)
                    }
                }
                try self.checkConnection(liveID, agentID: agentID)
                let history = self.mergeRemoteHistory(rows, into: session)
                let save = self.sessionRepository.saveRemoteHistory(history, sessionID: session.id)
                await self.reportPersistence(save)
            } catch {
                guard self.liveConnectionID == liveID, self.selectedSessionID == session.id,
                      !Task.isCancelled else { return }
                self.operationError = "读取远程会话历史失败：\(Self.describe(error))"
            }
        }
        remoteHistoryTasks[session.id] = task
        return task
    }

    private func mergeRemoteHistory(
        _ rows: [HermesGateway.HistoryRow], into session: Session
    ) -> SessionHistorySnapshot {
        let streamingIDs = streamingMessageIDs[session.id]?.values
        var unmatched = (messages[session.id] ?? []).filter {
            $0.delivery != .sending && $0.delivery != .failed && streamingIDs?.contains($0.id) != true
        }
        var mirrored: Set<UUID> = []
        let previous = remoteHistory[session.id]?.messages ?? []
        let firstDate = rows.lazy.compactMap(\.date).first ?? session.createdAt
        var lastDate = firstDate.addingTimeInterval(-Double(rows.count + 1) / 1000)
        let remote = rows.enumerated().map { index, row in
            // Match locally recorded copies one at a time, so identical prompts can repeat.
            if let match = unmatched.firstIndex(where: { message in
                message.role == row.role && message.text == row.text
                    && (row.date.map { abs($0.timeIntervalSince(message.createdAt)) < 300 } ?? true)
            }) {
                mirrored.insert(unmatched.remove(at: match).id)
            }
            lastDate = max(row.date ?? lastDate, lastDate.addingTimeInterval(0.001))
            let cachedID = previous.indices.contains(index)
                && previous[index].role == row.role && previous[index].text == row.text
                ? previous[index].id : nil
            return SessionMessage(
                id: cachedID ?? UUID(),
                sessionID: session.id, role: row.role, text: row.text, createdAt: lastDate,
                isEmphasized: row.role == .thinking, toolName: row.toolName
            )
        }
        let history = SessionHistorySnapshot(messages: remote, mirroredLocalIDs: mirrored)
        remoteHistory[session.id] = history
        return history
    }

    private func loadMessages(_ sessionID: UUID) async {
        guard !loadedMessageSessions.contains(sessionID) else { return }
        if let read = loadingMessageSessions[sessionID] {
            await read.value
            return
        }
        let read = Task { await readLocalMessages(sessionID) }
        loadingMessageSessions[sessionID] = read
        await read.value
        loadingMessageSessions[sessionID] = nil
    }

    private func readLocalMessages(_ sessionID: UUID) async {
        do {
            let stored = try await sessionRepository.messages(for: sessionID)
            let cachedHistory = try await sessionRepository.remoteHistory(for: sessionID)
            let knownIDs = Set((messages[sessionID] ?? []).map(\.id))
            messages[sessionID, default: []].append(contentsOf: stored.compactMap { message in
                guard !knownIDs.contains(message.id) else { return nil }
                var message = message
                if message.delivery == .sending { message.delivery = .failed }
                return message
            })
            if let cachedHistory, remoteHistory[sessionID] == nil {
                remoteHistory[sessionID] = cachedHistory
            }
            loadedMessageSessions.insert(sessionID)
        } catch {
            operationError = "读取消息失败：\(Self.describe(error))"
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

    private func sendPrompt(
        _ message: SessionMessage, connectionID: UUID, model: HermesGateway.ModelOption?, reasoning: String
    ) async throws {
        let sessionID = message.sessionID
        await remoteHistoryTasks[sessionID]?.value
        guard let session = sessions.first(where: { $0.id == sessionID }),
              let agentID = session.agentID, let gateway else {
            throw GatewayError.unreachable("请先连接此会话所属的 Agent")
        }
        try checkConnection(connectionID, agentID: agentID)
        let hermes = HermesGateway(client: gateway)
        let remoteID: String
        if let storedID = session.remoteHistoryID, !attachedSessions.contains(sessionID) {
            let profile = agents.first { $0.id == agentID }?.configuration.remoteProfile
            let resumed = try await hermes.resumeSession(storedID, profile: profile)
            try checkConnection(connectionID, agentID: agentID)
            try await bind(resumed, to: sessionID, historyID: storedID)
            try checkConnection(connectionID, agentID: agentID)
            remoteID = resumed.id
        } else if let existing = session.remoteID {
            remoteID = existing
        } else {
            let created = try await hermes.createSession(model: model, reasoning: reasoning)
            try checkConnection(connectionID, agentID: agentID)
            try await bind(created, to: sessionID)
            try checkConnection(connectionID, agentID: agentID)
            remoteSessionSettings[sessionID] = RemoteSessionSettings(
                model: created.model ?? model?.name, reasoning: reasoning
            )
            remoteID = created.id
        }

        var settings = remoteSessionSettings[sessionID] ?? RemoteSessionSettings()
        if let model, settings.model != model.name {
            try await hermes.setModel(model.name, sessionID: remoteID)
            try checkConnection(connectionID, agentID: agentID)
            settings.model = model.name
            remoteSessionSettings[sessionID] = settings
        }
        if settings.reasoning != reasoning {
            try await hermes.setReasoning(reasoning, sessionID: remoteID)
            try checkConnection(connectionID, agentID: agentID)
            settings.reasoning = reasoning
            remoteSessionSettings[sessionID] = settings
        }
        guard !stoppingSessions.contains(sessionID) else {
            throw GatewayError.unreachable("当前会话正在停止输出，请稍后再发送")
        }
        beginTurn(sessionID: sessionID, remoteID: remoteID, id: message.id)
        do {
            try await hermes.submit(message.text, sessionID: remoteID)
        } catch {
            if activeTurns[sessionID]?.id == message.id, streamingMessageIDs[sessionID] == nil {
                activeTurns[sessionID] = nil
            }
            throw error
        }
    }

    private func bind(_ remote: HermesGateway.RemoteSession, to sessionID: UUID, historyID: String? = nil) async throws {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else {
            throw GatewayError.unreachable("本地会话已不可用")
        }
        sessions[index].remoteID = remote.id
        sessions[index].remoteHistoryID = remote.storedID ?? historyID ?? sessions[index].remoteHistoryID
        attachedSessions.insert(sessionID)
        try await sessionRepository.save(sessions[index]).value
    }

    private func checkConnection(_ attempt: UUID, agentID: UUID) throws {
        guard liveConnectionID == attempt, connectedAgentID == agentID else {
            throw GatewayError.unreachable("请先连接此会话所属的 Agent")
        }
    }

    private static let defaultModelNames = ["Sonnet 4.5", "Opus 4.5", "Haiku 4.5"]

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
