import Foundation

// MARK: - 可注入传输抽象

/// HTTP 请求执行抽象；默认实现包装 `URLSession`。
public protocol GatewayHTTPPerforming {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

/// 创建 WebSocket 任务；默认实现包装 `URLSession.webSocketTask(with:)`。
public typealias GatewayWebSocketFactory = (URLRequest) -> GatewayWebSocketTasking

/// WebSocket 任务的发送 / 接收 / 关闭抽象。
public protocol GatewayWebSocketTasking: AnyObject {
    func resume()
    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?)
    func send(_ message: URLSessionWebSocketTask.Message) async throws
    func receive() async throws -> URLSessionWebSocketTask.Message
}

/// 基于 `URLSession` 的默认 HTTP 实现。
public final class URLSessionHTTPPerformer: GatewayHTTPPerforming, @unchecked Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}

/// 基于 `URLSessionWebSocketTask` 的默认 WebSocket 实现。
public final class URLSessionWebSocketAdapter: GatewayWebSocketTasking, @unchecked Sendable {
    private let task: URLSessionWebSocketTask

    public init(task: URLSessionWebSocketTask) {
        self.task = task
    }

    public func resume() {
        task.resume()
    }

    public func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        task.cancel(with: closeCode, reason: reason)
    }

    public func send(_ message: URLSessionWebSocketTask.Message) async throws {
        try await task.send(message)
    }

    public func receive() async throws -> URLSessionWebSocketTask.Message {
        try await task.receive()
    }
}

// MARK: - 连接参数

/// 建立连接时使用的凭据。
///
/// `token` 在 token 模式作为会话 token、在 oauth 模式作为访问 token；
/// `additionalHeaders` 会追加到 REST 请求（如自定义网关头）。
public struct GatewayCredentials: Sendable, Equatable {
    public var token: String?
    public var additionalHeaders: [String: String]

    public init(token: String? = nil, additionalHeaders: [String: String] = [:]) {
        self.token = token
        self.additionalHeaders = additionalHeaders
    }
}

/// 可调协议节奏，主要供测试缩短等待。
public struct GatewayTimings: Sendable, Equatable {
    /// `/api/status` 探测超时（秒）。
    public var statusTimeout: TimeInterval
    /// 等待 `gateway.ready` 的超时（秒）。
    public var handshakeTimeout: TimeInterval
    /// 心跳发送间隔（秒）。
    public var heartbeatInterval: TimeInterval
    /// 无入站帧判定掉线的阈值（秒）。
    public var deadInterval: TimeInterval
    /// 连接稳定多久后重置重连阶梯（秒）。
    public var stableConnectionInterval: TimeInterval

    public init(
        statusTimeout: TimeInterval = 8,
        handshakeTimeout: TimeInterval = 8,
        heartbeatInterval: TimeInterval = 15,
        deadInterval: TimeInterval = 45,
        stableConnectionInterval: TimeInterval = 5
    ) {
        self.statusTimeout = statusTimeout
        self.handshakeTimeout = handshakeTimeout
        self.heartbeatInterval = heartbeatInterval
        self.deadInterval = deadInterval
        self.stableConnectionInterval = stableConnectionInterval
    }
}

// MARK: - 客户端

/// 基于 `URLSession` / `URLSessionWebSocketTask` 的完整网关客户端。
///
/// 连接流程：`GET /api/status` 探测鉴权模式 →（oauth 时）`POST /api/auth/ws-ticket`
/// → 派生 WS URL → 等 `gateway.ready` → 发送 `client.capabilities` 与 `session.list`
/// → 进入 `.connected`，随后维持心跳、接收循环与断线重连。
/// 所有可变状态由内部 `NSLock` 保护，可安全地从多个线程调用。
public final class URLSessionGatewayClient: NSObject, GatewayClient, URLSessionWebSocketDelegate, URLSessionDelegate, @unchecked Sendable {
    // MARK: 注入依赖

    private let credentials: GatewayCredentials
    private let automaticallyReconnects: Bool
    private let timings: GatewayTimings
    private var reconnectPolicy: GatewayReconnectPolicy
    private let httpOverride: GatewayHTTPPerforming?
    private let webSocketFactoryOverride: GatewayWebSocketFactory?

    private lazy var ownedSession: URLSession = URLSession(
        configuration: .default,
        delegate: self,
        delegateQueue: nil
    )

    private var http: GatewayHTTPPerforming {
        if let httpOverride {
            return httpOverride
        }
        return URLSessionHTTPPerformer(session: ownedSession)
    }

    private var webSocketFactory: GatewayWebSocketFactory {
        if let webSocketFactoryOverride {
            return webSocketFactoryOverride
        }
        let session = ownedSession
        return { request in
            URLSessionWebSocketAdapter(task: session.webSocketTask(with: request))
        }
    }

    // MARK: 同步状态

    private let lock = NSLock()

    private var state: GatewayConnectionState = .disconnected
    private var stateObservers: [UUID: @Sendable (GatewayConnectionState) -> Void] = [:]
    private var eventObservers: [UUID: @Sendable (GatewayEventEnvelope) -> Void] = [:]
    private var serverRequestObservers: [UUID: @Sendable (ServerRequest) -> Void] = [:]

    private var currentConfiguration: GatewayConfiguration?
    private var pendingInfo: GatewayInfo?
    private var webSocketTask: GatewayWebSocketTasking?

    private var receiveTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var stabilityTask: Task<Void, Never>?

    private var pendingCalls: [JSONRPCID: PendingCall] = [:]
    private var pendingServerRequests: [JSONRPCID: ServerRequest] = [:]

    private var nextRequestID = 1
    private var lastInboundAt = Date.distantPast
    private var connectionGeneration = 0
    private var manuallyDisconnected = true
    private var hasEstablishedConnection = false

    private var currentReplayEpoch: String?
    private var lastSeqBySession: [String: Int] = [:]

    private var handshakeOutcome: HandshakeOutcome?
    private var handshakeContinuation: CheckedContinuation<Void, Error>?

    // MARK: 初始化

    public init(
        credentials: GatewayCredentials = GatewayCredentials(),
        timings: GatewayTimings = GatewayTimings(),
        reconnectPolicy: GatewayReconnectPolicy = GatewayReconnectPolicy(),
        automaticallyReconnects: Bool = true,
        http: GatewayHTTPPerforming? = nil,
        webSocketFactory: GatewayWebSocketFactory? = nil
    ) {
        self.credentials = credentials
        self.automaticallyReconnects = automaticallyReconnects
        self.timings = timings
        self.reconnectPolicy = reconnectPolicy
        self.httpOverride = http
        self.webSocketFactoryOverride = webSocketFactory
        super.init()
    }

    // MARK: GatewayClient

    /// 当前连接状态快照。
    public var currentState: GatewayConnectionState {
        lock.lock()
        defer { lock.unlock() }
        return state
    }

    /// 最近一次 `gateway.ready` 记录的补播纪元。
    public var replayEpoch: String? {
        lock.lock()
        defer { lock.unlock() }
        return currentReplayEpoch
    }

    /// 订阅状态；注册时立即以当前状态回调一次。
    public func observeState(
        _ handler: @escaping @Sendable (GatewayConnectionState) -> Void
    ) -> GatewayStateObservation {
        let identifier = UUID()
        lock.lock()
        stateObservers[identifier] = handler
        let snapshot = state
        lock.unlock()
        handler(snapshot)
        return GatewayCallbackObservation<GatewayConnectionState>(handler: handler) { [weak self] in
            self?.removeStateObserver(identifier)
        }
    }

    /// 订阅服务端事件。
    public func observeEvents(
        _ handler: @escaping @Sendable (GatewayEventEnvelope) -> Void
    ) -> GatewayStateObservation {
        let identifier = UUID()
        lock.lock()
        eventObservers[identifier] = handler
        lock.unlock()
        return GatewayCallbackObservation<GatewayEventEnvelope>(handler: handler) { [weak self] in
            self?.removeEventObserver(identifier)
        }
    }

    /// 订阅服务端请求（`approval` / `clarify`）。
    public func observeServerRequests(
        _ handler: @escaping @Sendable (ServerRequest) -> Void
    ) -> GatewayStateObservation {
        let identifier = UUID()
        lock.lock()
        serverRequestObservers[identifier] = handler
        lock.unlock()
        return GatewayCallbackObservation<ServerRequest>(handler: handler) { [weak self] in
            self?.removeServerRequestObserver(identifier)
        }
    }

    /// 建立连接；成功后 `currentState` 为 `.connected`。
    public func connect(to configuration: GatewayConfiguration) async throws {
        try configuration.validate()

        lock.lock()
        manuallyDisconnected = false
        hasEstablishedConnection = false
        connectionGeneration += 1
        let generation = connectionGeneration
        currentConfiguration = configuration
        reconnectPolicy.reset()
        let staleContinuation = handshakeContinuation
        handshakeContinuation = nil
        handshakeOutcome = nil
        lastSeqBySession.removeAll()
        currentReplayEpoch = nil
        pendingInfo = nil
        lock.unlock()

        staleContinuation?.resume(throwing: GatewayError.cancelled)
        resetRuntimeState()

        transition(to: .connecting(try? configuration.normalizedBaseURL()))

        do {
            try await runConnection(configuration: configuration, generation: generation)
        } catch {
            let gatewayError = Self.mapTransportError(error)
            teardownConnection(generation: generation, error: gatewayError)
            if isCurrent(generation) {
                transition(to: .failed(gatewayError))
            }
            throw gatewayError
        }
    }

    /// 主动断开：取消全部计时器与订阅、关闭 WS，并清理未决请求。
    public func disconnect() async {
        lock.lock()
        manuallyDisconnected = true
        hasEstablishedConnection = false
        connectionGeneration += 1

        let receive = receiveTask
        let heartbeat = heartbeatTask
        let reconnect = reconnectTask
        let stability = stabilityTask
        let socket = webSocketTask
        let calls = Array(pendingCalls.values)

        receiveTask = nil
        heartbeatTask = nil
        reconnectTask = nil
        stabilityTask = nil
        webSocketTask = nil
        pendingCalls.removeAll()
        pendingServerRequests.removeAll()
        lastSeqBySession.removeAll()
        currentReplayEpoch = nil

        let continuation = handshakeContinuation
        handshakeContinuation = nil
        if handshakeOutcome == nil {
            handshakeOutcome = .failure(.cancelled)
        }
        lock.unlock()

        receive?.cancel()
        heartbeat?.cancel()
        reconnect?.cancel()
        stability?.cancel()
        socket?.cancel(with: .goingAway, reason: nil)
        for call in calls {
            call.fail(.cancelled)
        }
        continuation?.resume(throwing: GatewayError.cancelled)

        transition(to: .disconnected)
    }

    /// 发送原始文本帧；未连接时抛 `.unreachable`。
    public func send(_ payload: Data) async throws {
        guard isConnected() else {
            throw GatewayError.unreachable("WebSocket 未连接")
        }
        try await sendRaw(payload)
    }

    /// 发起请求并等待同 id 响应，超时抛 `.timeout`。
    public func request(
        method: String,
        params: JSONValue?,
        timeout: TimeInterval
    ) async throws -> JSONValue {
        guard isConnected() else {
            throw GatewayError.unreachable("WebSocket 未连接")
        }

        let identifier = allocateRequestID()
        let frame = try encodeRequest(id: identifier, method: method, params: params)
        let call = PendingCall()
        lock.lock()
        pendingCalls[identifier] = call
        lock.unlock()

        do {
            try await sendRaw(frame)
        } catch {
            removePendingCall(identifier)
            let gatewayError = Self.mapTransportError(error)
            call.fail(gatewayError)
            throw gatewayError
        }

        let timeoutTask: Task<Void, Never>?
        if timeout > 0 {
            timeoutTask = Task { [call] in
                do {
                    try await Task.sleep(nanoseconds: Self.nanoseconds(timeout))
                } catch {
                    return
                }
                call.fail(.timeout)
            }
        } else {
            timeoutTask = nil
        }
        defer { timeoutTask?.cancel() }

        do {
            return try await call.wait()
        } catch {
            removePendingCall(identifier)
            let gatewayError = Self.mapTransportError(error)
            call.fail(gatewayError)
            throw gatewayError
        }
    }

    /// 用服务端请求的同一 id 回送审批结果。
    public func respond(to requestID: JSONRPCID, choice: ApprovalChoice) async throws {
        guard isConnected() else {
            throw GatewayError.unreachable("WebSocket 未连接")
        }
        let frame = GatewayJSONRPC.approvalRespond(requestID: requestID, choice: choice)
        try await sendRaw(frame)
        lock.lock()
        pendingServerRequests.removeValue(forKey: requestID)
        lock.unlock()
    }

    // MARK: TLS 策略

    /// 是否允许自签证书：仅 `.ssl` 且显式开启时成立，默认系统校验。
    public static func allowsSelfSignedCertificate(for configuration: GatewayConfiguration) -> Bool {
        configuration.method == .ssl && configuration.allowSelfSignedCertificate
    }

    /// 仅对显式开启自签放行的 SSL 连接使用服务器信任凭据。
    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        lock.lock()
        let configuration = currentConfiguration
        lock.unlock()

        guard let configuration,
              Self.allowsSelfSignedCertificate(for: configuration),
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }

    // MARK: 连接流水线

    private func runConnection(configuration: GatewayConfiguration, generation: Int) async throws {
        transition(to: .connecting(try? configuration.normalizedBaseURL()))

        let status = try await probeStatus(configuration: configuration)
        try ensureCurrent(generation)

        let credential: String
        let isTicket: Bool
        switch status.authMode(preferred: configuration.authMode) {
        case .token:
            credential = credentials.token ?? ""
            isTicket = false
        case .oauth:
            guard let token = credentials.token, !token.isEmpty else {
                throw GatewayError.unauthorized
            }
            credential = try await fetchTicket(configuration: configuration, token: token)
            try ensureCurrent(generation)
            isTicket = true
        }

        let webSocketURL = try configuration.webSocketURL(credential: credential, isTicket: isTicket)
        try ensureCurrent(generation)

        var request = URLRequest(
            url: webSocketURL,
            timeoutInterval: max(configuration.timeout, 1)
        )
        request.httpMethod = "GET"
        let socket = webSocketFactory(request)

        lock.lock()
        guard generation == connectionGeneration, !manuallyDisconnected else {
            lock.unlock()
            socket.cancel(with: .goingAway, reason: nil)
            throw GatewayError.cancelled
        }
        webSocketTask = socket
        pendingInfo = status.info
        lastInboundAt = Date()
        lock.unlock()

        transition(to: .connecting(webSocketURL))
        socket.resume()
        startReceiveLoop(generation: generation)

        do {
            try await waitForHandshake()
        } catch {
            let gatewayError = Self.mapTransportError(error)
            settleHandshake(.failure(gatewayError))
            teardownConnection(generation: generation, error: gatewayError)
            throw gatewayError
        }
    }

    private func probeStatus(configuration: GatewayConfiguration) async throws -> GatewayStatus {
        var request = URLRequest(
            url: try configuration.statusURL(),
            timeoutInterval: timings.statusTimeout
        )
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await performHTTP(request)
        try Self.validate(response: response, data: data, context: "/api/status")
        return try GatewayStatus.decode(data)
    }

    private func fetchTicket(
        configuration: GatewayConfiguration,
        token: String
    ) async throws -> String {
        var request = URLRequest(
            url: try configuration.wsTicketURL(),
            timeoutInterval: max(configuration.timeout, 1)
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        for (field, value) in credentials.additionalHeaders {
            request.setValue(value, forHTTPHeaderField: field)
        }
        request.httpBody = Data("{}".utf8)

        let (data, response) = try await performHTTP(request)
        try Self.validate(response: response, data: data, context: "/api/auth/ws-ticket")

        do {
            let ticket = try JSONDecoder().decode(WsTicket.self, from: data)
            guard !ticket.ticket.isEmpty else {
                throw GatewayError.decoding("ws-ticket 响应缺少 ticket")
            }
            return ticket.ticket
        } catch let error as GatewayError {
            throw error
        } catch {
            throw GatewayError.decoding("解析 ws-ticket 失败：\(error.localizedDescription)")
        }
    }

    private func performHTTP(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await http.data(for: request)
        } catch {
            throw Self.mapTransportError(error)
        }
    }

    // MARK: 握手

    private func waitForHandshake() async throws {
        let timeout = timings.handshakeTimeout
        let timeoutTask: Task<Void, Never>?
        if timeout > 0 {
            timeoutTask = Task { [weak self] in
                do {
                    try await Task.sleep(nanoseconds: Self.nanoseconds(timeout))
                } catch {
                    return
                }
                self?.settleHandshake(.failure(.timeout))
            }
        } else {
            timeoutTask = nil
        }
        defer { timeoutTask?.cancel() }
        try await awaitHandshake()
    }

    private func awaitHandshake() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            lock.lock()
            if let outcome = handshakeOutcome {
                lock.unlock()
                switch outcome {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            } else {
                handshakeContinuation = continuation
                lock.unlock()
            }
        }
    }

    private func settleHandshake(_ outcome: HandshakeOutcome) {
        lock.lock()
        guard handshakeOutcome == nil else {
            lock.unlock()
            return
        }
        handshakeOutcome = outcome
        let continuation = handshakeContinuation
        handshakeContinuation = nil
        lock.unlock()

        switch outcome {
        case .success:
            continuation?.resume()
        case .failure(let error):
            continuation?.resume(throwing: error)
        }
    }

    // MARK: 接收循环

    private func startReceiveLoop(generation: Int) {
        let task = Task { [weak self] in
            guard let self else { return }
            await self.receiveLoop(generation: generation)
        }
        lock.lock()
        if generation == connectionGeneration {
            receiveTask?.cancel()
            receiveTask = task
        }
        lock.unlock()
    }

    private func receiveLoop(generation: Int) async {
        while !Task.isCancelled {
            guard let socket = activeSocket(generation: generation) else {
                return
            }

            let message: URLSessionWebSocketTask.Message
            do {
                message = try await socket.receive()
            } catch {
                if isCurrent(generation) {
                    handleTransportFailure(
                        generation: generation,
                        error: Self.mapTransportError(error)
                    )
                }
                return
            }

            guard isCurrent(generation) else {
                return
            }
            refreshInbound()

            let data: Data
            switch message {
            case .string(let text):
                data = Data(text.utf8)
            case .data(let binary):
                data = binary
            @unknown default:
                continue
            }
            await processIncoming(data, generation: generation)
        }
    }

    private func processIncoming(_ data: Data, generation: Int) async {
        let text = String(decoding: data, as: UTF8.self)
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            await processLine(Data(trimmed.utf8), generation: generation)
        }
    }

    private func processLine(_ data: Data, generation: Int) async {
        let inbound: GatewayInbound
        do {
            inbound = try GatewayJSONRPCParser.parse(data)
        } catch {
            return
        }

        switch inbound {
        case .response(let response):
            completePendingCall(response)
        case .event(let event):
            await handleEvent(event, generation: generation)
        case .serverRequest(let request):
            registerServerRequest(request)
        case .unknown:
            break
        }
    }

    private func handleEvent(_ event: GatewayEventEnvelope, generation: Int) async {
        updateReplayMetadata(event)
        broadcast(event)

        switch event.type {
        case GatewayEventType.requestCancel:
            cancelPendingApproval(event)
        case GatewayEventType.gatewayReady:
            await handleReady(event, generation: generation)
        default:
            break
        }
    }

    private func handleReady(_ event: GatewayEventEnvelope, generation: Int) async {
        lock.lock()
        let attemptIsCurrent = generation == connectionGeneration && !manuallyDisconnected
        let handshakeAlreadySettled = handshakeOutcome != nil
        let info = pendingInfo ?? GatewayInfo()
        lock.unlock()

        guard attemptIsCurrent, !handshakeAlreadySettled else {
            return
        }

        do {
            let capabilitiesID = allocateRequestID()
            try await sendRaw(GatewayJSONRPC.capabilities(id: capabilitiesID))
        } catch {
            let gatewayError = Self.mapTransportError(error)
            settleHandshake(.failure(gatewayError))
            handleTransportFailure(generation: generation, error: gatewayError)
            return
        }

        let connectedState = GatewayConnectionState.connected(info)

        lock.lock()
        guard handshakeOutcome == nil,
              generation == connectionGeneration,
              !manuallyDisconnected,
              webSocketTask != nil else {
            lock.unlock()
            return
        }
        handshakeOutcome = .success
        let continuation = handshakeContinuation
        handshakeContinuation = nil
        hasEstablishedConnection = true
        let previous = state
        state = connectedState
        let handlers = Array(stateObservers.values)
        lock.unlock()

        if previous != connectedState {
            for handler in handlers {
                handler(connectedState)
            }
        }
        startHeartbeat(generation: generation)
        scheduleStabilityReset(generation: generation)
        continuation?.resume()

        await replayMissedEvents(generation: generation)
    }

    private func updateReplayMetadata(_ event: GatewayEventEnvelope) {
        lock.lock()
        defer { lock.unlock() }

        if let epoch = event.replayEpoch ?? event.payload?["replay_epoch"]?.stringValue,
           !epoch.isEmpty {
            if let existing = currentReplayEpoch, existing != epoch {
                lastSeqBySession.removeAll()
            }
            currentReplayEpoch = epoch
        }

        guard event.type != GatewayEventType.gatewayReady,
              let sessionID = event.sessionID,
              let seq = event.seq else {
            return
        }
        if let previous = lastSeqBySession[sessionID] {
            lastSeqBySession[sessionID] = max(previous, seq)
        } else {
            lastSeqBySession[sessionID] = seq
        }
    }

    private func replayMissedEvents(generation: Int) async {
        lock.lock()
        let targets = lastSeqBySession
        lock.unlock()
        guard !targets.isEmpty else { return }

        for (sessionID, lastSeq) in targets.sorted(by: { $0.key < $1.key }) {
            guard isCurrent(generation) else { return }
            let identifier = allocateRequestID()
            let frame = GatewayJSONRPC.eventsSince(
                id: identifier,
                sessionID: sessionID,
                lastSeen: lastSeq
            )
            do {
                try await sendRaw(frame)
            } catch {
                return
            }
        }
    }

    private func registerServerRequest(_ request: ServerRequest) {
        lock.lock()
        pendingServerRequests[request.id] = request
        let handlers = Array(serverRequestObservers.values)
        lock.unlock()

        for handler in handlers {
            handler(request)
        }
    }

    private func cancelPendingApproval(_ event: GatewayEventEnvelope) {
        guard let identifier = Self.requestIdentifier(in: event.payload) else {
            return
        }
        lock.lock()
        pendingServerRequests.removeValue(forKey: identifier)
        lock.unlock()
    }

    private func broadcast(_ event: GatewayEventEnvelope) {
        lock.lock()
        let handlers = Array(eventObservers.values)
        lock.unlock()

        for handler in handlers {
            handler(event)
        }
    }

    private func completePendingCall(_ response: JSONRPCResponse) {
        lock.lock()
        let call = pendingCalls.removeValue(forKey: response.id)
        lock.unlock()

        guard let call else { return }
        if let error = response.error {
            call.fail(.server(code: error.code, message: error.message))
        } else {
            call.resolve(response.result ?? .null)
        }
    }

    // MARK: 心跳与存活

    private func startHeartbeat(generation: Int) {
        let interval = max(timings.heartbeatInterval, 0.001)
        let deadInterval = max(timings.deadInterval, interval)

        let task = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: Self.nanoseconds(interval))
                } catch {
                    return
                }
                guard let self else { return }
                guard self.isCurrent(generation) else { return }

                if Date().timeIntervalSince(self.lastInboundDate()) >= deadInterval {
                    self.handleTransportFailure(generation: generation, error: .timeout)
                    return
                }

                do {
                    try await self.sendPing(generation: generation)
                } catch {
                    if self.isCurrent(generation) {
                        self.handleTransportFailure(
                            generation: generation,
                            error: Self.mapTransportError(error)
                        )
                    }
                    return
                }
            }
        }

        lock.lock()
        if generation == connectionGeneration {
            heartbeatTask?.cancel()
            heartbeatTask = task
        }
        lock.unlock()
    }

    private func sendPing(generation: Int) async throws {
        lock.lock()
        guard generation == connectionGeneration,
              !manuallyDisconnected,
              webSocketTask != nil else {
            lock.unlock()
            throw GatewayError.cancelled
        }
        let identifier = nextRequestID
        nextRequestID = nextRequestID == Int.max ? 1 : nextRequestID + 1
        lock.unlock()

        try await sendRaw(GatewayJSONRPC.ping(id: .int(identifier)))
    }

    private func refreshInbound() {
        lock.lock()
        lastInboundAt = Date()
        lock.unlock()
    }

    private func lastInboundDate() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return lastInboundAt
    }

    private func scheduleStabilityReset(generation: Int) {
        let interval = max(timings.stableConnectionInterval, 0)
        let task = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: Self.nanoseconds(interval))
            } catch {
                return
            }
            guard let self else { return }
            self.lock.lock()
            if generation == self.connectionGeneration,
               !self.manuallyDisconnected,
               self.hasEstablishedConnection {
                self.reconnectPolicy.recordSuccess()
            }
            self.lock.unlock()
        }

        lock.lock()
        if generation == connectionGeneration {
            stabilityTask?.cancel()
            stabilityTask = task
        }
        lock.unlock()
    }

    // MARK: 失败与重连

    private func handleTransportFailure(generation: Int, error: GatewayError) {
        lock.lock()
        let shouldHandle = generation == connectionGeneration
            && !manuallyDisconnected
            && hasEstablishedConnection
        let configuration = currentConfiguration
        lock.unlock()
        guard shouldHandle else { return }

        guard teardownConnection(generation: generation, error: error) else {
            return
        }
        transition(to: .failed(error))
        if automaticallyReconnects, let configuration {
            scheduleReconnect(configuration: configuration)
        }
    }

    private func scheduleReconnect(configuration: GatewayConfiguration) {
        lock.lock()
        guard !manuallyDisconnected,
              hasEstablishedConnection,
              reconnectTask == nil else {
            lock.unlock()
            return
        }

        reconnectPolicy.recordFailure()
        let delay = reconnectPolicy.nextDelay(
            afterFailureCount: reconnectPolicy.failureCount
        )
        let baseGeneration = connectionGeneration

        let task = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: Self.nanoseconds(delay))
            } catch {
                return
            }
            guard let self else { return }
            await self.performReconnect(
                configuration: configuration,
                baseGeneration: baseGeneration
            )
        }
        reconnectTask = task
        lock.unlock()
    }

    private func performReconnect(
        configuration: GatewayConfiguration,
        baseGeneration: Int
    ) async {
        lock.lock()
        guard baseGeneration == connectionGeneration, !manuallyDisconnected else {
            lock.unlock()
            return
        }
        reconnectTask = nil
        connectionGeneration += 1
        let generation = connectionGeneration
        currentConfiguration = configuration
        handshakeContinuation = nil
        handshakeOutcome = nil
        lock.unlock()

        resetRuntimeState()
        transition(to: .connecting(try? configuration.normalizedBaseURL()))

        do {
            try await runConnection(configuration: configuration, generation: generation)
        } catch {
            let gatewayError = Self.mapTransportError(error)
            teardownConnection(generation: generation, error: gatewayError)
            guard isCurrent(generation) else { return }
            transition(to: .failed(gatewayError))
            scheduleReconnect(configuration: configuration)
        }
    }

    private func teardownConnection(generation: Int, error: GatewayError) -> Bool {
        lock.lock()
        guard generation == connectionGeneration else {
            lock.unlock()
            return false
        }

        let receive = receiveTask
        let heartbeat = heartbeatTask
        let stability = stabilityTask
        let socket = webSocketTask
        let calls = Array(pendingCalls.values)
        let continuation = handshakeContinuation

        receiveTask = nil
        heartbeatTask = nil
        stabilityTask = nil
        webSocketTask = nil
        pendingCalls.removeAll()
        pendingServerRequests.removeAll()
        handshakeContinuation = nil
        if handshakeOutcome == nil {
            handshakeOutcome = .failure(error)
        }
        lock.unlock()

        receive?.cancel()
        heartbeat?.cancel()
        stability?.cancel()
        socket?.cancel(with: .goingAway, reason: nil)
        for call in calls {
            call.fail(error)
        }
        continuation?.resume(throwing: error)
        return true
    }

    /// 清理旧连接的运行时对象；不改变连接状态。
    private func resetRuntimeState() {
        lock.lock()
        let receive = receiveTask
        let heartbeat = heartbeatTask
        let reconnect = reconnectTask
        let stability = stabilityTask
        let socket = webSocketTask
        let calls = Array(pendingCalls.values)

        receiveTask = nil
        heartbeatTask = nil
        reconnectTask = nil
        stabilityTask = nil
        webSocketTask = nil
        pendingCalls.removeAll()
        pendingServerRequests.removeAll()
        lock.unlock()

        receive?.cancel()
        heartbeat?.cancel()
        reconnect?.cancel()
        stability?.cancel()
        socket?.cancel(with: .goingAway, reason: nil)
        for call in calls {
            call.fail(.cancelled)
        }
    }

    // MARK: 状态与观察者

    private func transition(to next: GatewayConnectionState) {
        lock.lock()
        let previous = state
        state = next
        let handlers = Array(stateObservers.values)
        lock.unlock()

        guard previous != next else { return }
        for handler in handlers {
            handler(next)
        }
    }

    private func removeStateObserver(_ identifier: UUID) {
        lock.lock()
        stateObservers.removeValue(forKey: identifier)
        lock.unlock()
    }

    private func removeEventObserver(_ identifier: UUID) {
        lock.lock()
        eventObservers.removeValue(forKey: identifier)
        lock.unlock()
    }

    private func removeServerRequestObserver(_ identifier: UUID) {
        lock.lock()
        serverRequestObservers.removeValue(forKey: identifier)
        lock.unlock()
    }

    // MARK: 辅助

    private func isConnected() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if case .connected = state {
            return true
        }
        return false
    }

    private func isCurrent(_ generation: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return generation == connectionGeneration && !manuallyDisconnected
    }

    private func ensureCurrent(_ generation: Int) throws {
        guard isCurrent(generation) else {
            throw GatewayError.cancelled
        }
    }

    private func activeSocket(generation: Int) -> GatewayWebSocketTasking? {
        lock.lock()
        defer { lock.unlock() }
        guard generation == connectionGeneration else { return nil }
        return webSocketTask
    }

    private func sendRaw(_ data: Data) async throws {
        lock.lock()
        let socket = webSocketTask
        lock.unlock()

        guard let socket else {
            throw GatewayError.unreachable("WebSocket 未连接")
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw GatewayError.encoding("发送帧不是合法 UTF-8")
        }

        do {
            try await socket.send(.string(text))
        } catch {
            throw Self.mapTransportError(error)
        }
    }

    private func allocateRequestID() -> JSONRPCID {
        lock.lock()
        let identifier = nextRequestID
        nextRequestID = nextRequestID == Int.max ? 1 : nextRequestID + 1
        lock.unlock()
        return .int(identifier)
    }

    private func removePendingCall(_ identifier: JSONRPCID) {
        lock.lock()
        pendingCalls.removeValue(forKey: identifier)
        lock.unlock()
    }

    private func encodeRequest(
        id: JSONRPCID,
        method: String,
        params: JSONValue?
    ) throws -> Data {
        let request = JSONRPCRequest(id: id, method: method, params: params)
        do {
            var data = try JSONEncoder().encode(request)
            data.append(0x0A)
            return data
        } catch {
            throw GatewayError.encoding("请求编码失败：\(error.localizedDescription)")
        }
    }
}

// MARK: - 映射与工具

private extension URLSessionGatewayClient {
    static func validate(response: URLResponse, data: Data, context: String) throws {
        guard let http = response as? HTTPURLResponse else {
            throw GatewayError.unreachable("\(context) 返回非 HTTP 响应")
        }
        switch http.statusCode {
        case 200..<300:
            return
        case 401, 403:
            throw GatewayError.unauthorized
        default:
            let body = String(decoding: data.prefix(200), as: UTF8.self)
            throw GatewayError.server(
                code: http.statusCode,
                message: body.isEmpty ? context : body
            )
        }
    }

    static func mapTransportError(_ error: Error) -> GatewayError {
        if let gatewayError = error as? GatewayError {
            return gatewayError
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return .timeout
            case .cancelled:
                return .cancelled
            case .secureConnectionFailed,
                 .serverCertificateHasBadDate,
                 .serverCertificateUntrusted,
                 .serverCertificateHasUnknownRoot,
                 .serverCertificateNotYetValid,
                 .clientCertificateRejected,
                 .clientCertificateRequired:
                return .tlsFailed(urlError.localizedDescription)
            default:
                return .unreachable(urlError.localizedDescription)
            }
        }
        return .unreachable(error.localizedDescription)
    }

    static func requestIdentifier(in payload: JSONValue?) -> JSONRPCID? {
        var fields = payload?.objectValue ?? [:]
        for nestingKey in ["approval", "clarify", "request"] {
            if let nested = fields[nestingKey]?.objectValue {
                for (key, value) in nested {
                    fields[key] = value
                }
            }
        }

        for key in ["request_id", "requestID", "prompt_id", "promptID", "id"] {
            guard let value = fields[key] else { continue }
            if let string = value.stringValue {
                return .string(string)
            }
            if let number = value.intValue {
                return .int(number)
            }
        }
        return nil
    }

    static func nanoseconds(_ interval: TimeInterval) -> UInt64 {
        guard interval.isFinite, interval > 0 else { return 0 }
        let clamped = min(interval, 3600)
        return UInt64(clamped * 1_000_000_000)
    }
}

// MARK: - 未决请求

/// 握手结算结果，成功 / 失败只落地一次。
private enum HandshakeOutcome {
    case success
    case failure(GatewayError)
}

/// 一个等待同 id 响应的请求；成功 / 失败只结算一次。
private final class PendingCall: @unchecked Sendable {
    private enum Outcome {
        case value(JSONValue)
        case failure(GatewayError)
    }

    private let lock = NSLock()
    private var outcome: Outcome?
    private var continuation: CheckedContinuation<JSONValue, Error>?

    func wait() async throws -> JSONValue {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<JSONValue, Error>) in
            lock.lock()
            if let outcome {
                lock.unlock()
                switch outcome {
                case .value(let value):
                    continuation.resume(returning: value)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            } else {
                self.continuation = continuation
                lock.unlock()
            }
        }
    }

    func resolve(_ value: JSONValue) {
        settle(.value(value))
    }

    func fail(_ error: GatewayError) {
        settle(.failure(error))
    }

    private func settle(_ outcome: Outcome) {
        lock.lock()
        guard self.outcome == nil else {
            lock.unlock()
            return
        }
        self.outcome = outcome
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()

        guard let continuation else { return }
        switch outcome {
        case .value(let value):
            continuation.resume(returning: value)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}
