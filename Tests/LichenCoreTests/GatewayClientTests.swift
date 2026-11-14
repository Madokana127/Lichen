import XCTest
import Foundation
@testable import LichenCore

final class GatewayClientTests: XCTestCase {
    // MARK: - 连接与鉴权

    func testConnectTokenModeUsesTokenURLAndSendsCapabilities() async throws {
        let http = FakeHTTPPerformer()
        http.stub(path: "/api/status", body: statusJSON(authRequired: false))

        let socket = FakeWebSocket()
        let requestedURL = LockedBox<URL?>(nil)
        let client = makeClient(http: http, socket: socket, requestedURL: requestedURL)
        addTeardownBlock { await client.disconnect() }

        socket.enqueue(readyFrame())
        try await client.connect(to: configuration())

        XCTAssertEqual(http.requestedPaths, ["/api/status"])
        XCTAssertTrue(socket.wasResumed)

        let url = try XCTUnwrap(requestedURL.current)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.path, "/api/ws")
        XCTAssertEqual(components.percentEncodedQuery, "token=token-abc")

        guard case .connected(let info) = client.currentState else {
            return XCTFail("期望 connected，实际为 \(client.currentState)")
        }
        XCTAssertEqual(info.version, "0.4.2")
        XCTAssertEqual(info.activeSessions, 2)
        XCTAssertEqual(client.replayEpoch, "epoch-1")

        let capabilities = try decodeRequest(
            from: try await socket.waitForSentText(containing: GatewayMethod.clientCapabilities)
        )
        XCTAssertEqual(capabilities.method, GatewayMethod.clientCapabilities)
        XCTAssertEqual(capabilities.params?["server_requests"]?.boolValue, true)

        let list = try decodeRequest(
            from: try await socket.waitForSentText(containing: GatewayMethod.sessionList)
        )
        XCTAssertEqual(list.method, GatewayMethod.sessionList)
    }

    func testOAuthFetchesTicketAndUsesTicketQuery() async throws {
        let http = FakeHTTPPerformer()
        http.stub(path: "/api/status", body: statusJSON(authRequired: true))
        http.stub(
            path: "/api/auth/ws-ticket",
            body: #"{"ticket":"ticket-xyz","ttl_seconds":30}"#
        )

        let socket = FakeWebSocket()
        let requestedURL = LockedBox<URL?>(nil)
        let client = makeClient(http: http, socket: socket, requestedURL: requestedURL)
        addTeardownBlock { await client.disconnect() }

        socket.enqueue(readyFrame())
        try await client.connect(to: configuration())

        XCTAssertEqual(http.requestedPaths, ["/api/status", "/api/auth/ws-ticket"])
        XCTAssertEqual(
            http.headers(forPath: "/api/auth/ws-ticket")?["Authorization"],
            "Bearer token-abc"
        )

        let url = try XCTUnwrap(requestedURL.current)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.percentEncodedQuery, "ticket=ticket-xyz")
    }

    func testStatusProbeFailureMapsToUnreachable() async throws {
        let http = FakeHTTPPerformer()
        http.fail(path: "/api/status", with: URLError(.cannotConnectToHost))

        let socket = FakeWebSocket()
        let client = makeClient(http: http, socket: socket)
        addTeardownBlock { await client.disconnect() }

        do {
            try await client.connect(to: configuration())
            XCTFail("探测失败时应抛错")
        } catch {
            guard let gatewayError = error as? GatewayError,
                  case .unreachable = gatewayError else {
                return XCTFail("期望 unreachable，实际为 \(error)")
            }
        }

        guard case .failed(let stateError) = client.currentState,
              case .unreachable = stateError else {
            return XCTFail("期望 failed(unreachable)，实际为 \(client.currentState)")
        }
    }

    func testTicketFailureMapsToUnauthorized() async throws {
        let http = FakeHTTPPerformer()
        http.stub(path: "/api/status", body: statusJSON(authRequired: true))
        http.stub(path: "/api/auth/ws-ticket", statusCode: 401, body: "{}")

        let socket = FakeWebSocket()
        let client = makeClient(http: http, socket: socket)
        addTeardownBlock { await client.disconnect() }

        do {
            try await client.connect(to: configuration())
            XCTFail("ticket 失败时应抛错")
        } catch {
            guard let gatewayError = error as? GatewayError else {
                return XCTFail("期望 GatewayError，实际为 \(error)")
            }
            XCTAssertEqual(gatewayError, .unauthorized)
        }

        guard case .failed(let stateError) = client.currentState else {
            return XCTFail("期望 failed，实际为 \(client.currentState)")
        }
        XCTAssertEqual(stateError, .unauthorized)
    }

    func testHandshakeTimeoutFailsConnection() async throws {
        let http = FakeHTTPPerformer()
        http.stub(path: "/api/status", body: statusJSON(authRequired: false))

        let socket = FakeWebSocket()
        var timings = GatewayTimings()
        timings.handshakeTimeout = 0.05
        let client = makeClient(http: http, socket: socket, timings: timings)
        addTeardownBlock { await client.disconnect() }

        do {
            try await client.connect(to: configuration())
            XCTFail("首帧超时应抛错")
        } catch {
            guard let gatewayError = error as? GatewayError else {
                return XCTFail("期望 GatewayError，实际为 \(error)")
            }
            XCTAssertEqual(gatewayError, .timeout)
        }

        XCTAssertEqual(client.currentState, .failed(.timeout))
        XCTAssertTrue(socket.isCancelled)
    }

    // MARK: - 请求 / 服务端请求 / 心跳

    func testRequestMatchesResponseByID() async throws {
        let http = FakeHTTPPerformer()
        http.stub(path: "/api/status", body: statusJSON(authRequired: false))
        let socket = FakeWebSocket()
        let client = makeClient(http: http, socket: socket)
        addTeardownBlock { await client.disconnect() }

        socket.enqueue(readyFrame())
        try await client.connect(to: configuration())

        let requestTask = Task {
            try await client.request(
                method: GatewayMethod.sessionHistory,
                params: .object(["session_id": .string("s-1")]),
                timeout: 1
            )
        }

        let sent = try await socket.waitForSentText(containing: GatewayMethod.sessionHistory)
        let request = try decodeRequest(from: sent)
        socket.enqueue(responseFrame(id: request.id, result: .object(["ok": .bool(true)])))

        let result = try await requestTask.value
        XCTAssertEqual(result["ok"]?.boolValue, true)
    }

    func testApprovalServerRequestIsBroadcastAndAnsweredWithSameID() async throws {
        let http = FakeHTTPPerformer()
        http.stub(path: "/api/status", body: statusJSON(authRequired: false))
        let socket = FakeWebSocket()
        let client = makeClient(http: http, socket: socket)
        addTeardownBlock { await client.disconnect() }

        socket.enqueue(readyFrame())
        try await client.connect(to: configuration())

        let expectation = expectation(description: "服务端审批请求")
        let received = LockedBox<ServerRequest?>(nil)
        let observation = client.observeServerRequests { request in
            received.set(request)
            expectation.fulfill()
        }
        addTeardownBlock { observation.cancel() }

        socket.enqueue(approvalFrame())
        await fulfillment(of: [expectation], timeout: 1)
        observation.cancel()

        XCTAssertEqual(received.current?.id, .string("srq-0123456789ab"))
        XCTAssertEqual(received.current?.method, GatewayMethod.approval)

        try await client.respond(to: .string("srq-0123456789ab"), choice: .session)

        let sent = try await socket.waitForSentText(containing: "srq-0123456789ab")
        guard case .response(let response) = try GatewayJSONRPCParser.parse(Data(sent.utf8)) else {
            return XCTFail("期望 response 帧，实际为 \(sent)")
        }
        XCTAssertEqual(response.id, .string("srq-0123456789ab"))
        XCTAssertEqual(response.result?["choice"]?.stringValue, "session")
    }

    func testHeartbeatSendsPingFrames() async throws {
        let http = FakeHTTPPerformer()
        http.stub(path: "/api/status", body: statusJSON(authRequired: false))
        let socket = FakeWebSocket()

        var timings = GatewayTimings()
        timings.handshakeTimeout = 1
        timings.heartbeatInterval = 0.02
        timings.deadInterval = 5
        let client = makeClient(http: http, socket: socket, timings: timings)
        addTeardownBlock { await client.disconnect() }

        socket.enqueue(readyFrame())
        try await client.connect(to: configuration())

        let pingText = try await socket.waitForSentText(
            containing: GatewayMethod.ping,
            timeout: 1
        )
        let ping = try decodeRequest(from: pingText)
        XCTAssertEqual(ping.method, GatewayMethod.ping)
        XCTAssertNil(ping.params)
    }

    func testEventObservationReceivesBroadcast() async throws {
        let http = FakeHTTPPerformer()
        http.stub(path: "/api/status", body: statusJSON(authRequired: false))
        let socket = FakeWebSocket()
        let client = makeClient(http: http, socket: socket)
        addTeardownBlock { await client.disconnect() }

        socket.enqueue(readyFrame())
        try await client.connect(to: configuration())

        let expectation = expectation(description: "消息增量事件")
        let received = LockedBox<GatewayEventEnvelope?>(nil)
        let observation = client.observeEvents { event in
            guard event.type == GatewayEventType.messageDelta else { return }
            received.set(event)
            expectation.fulfill()
        }
        addTeardownBlock { observation.cancel() }

        socket.enqueue(
            JSONValue.object([
                "jsonrpc": .string("2.0"),
                "method": .string(GatewayMethod.event),
                "params": .object([
                    "type": .string(GatewayEventType.messageDelta),
                    "session_id": .string("s-1"),
                    "seq": .int(9),
                    "payload": .object(["text": .string("你好")])
                ])
            ]).jsonString() + "\n"
        )

        await fulfillment(of: [expectation], timeout: 1)
        observation.cancel()
        let event = try XCTUnwrap(received.current)
        XCTAssertEqual(event.payload?.objectValue?["text"]?.stringValue, "你好")
        XCTAssertEqual(event.seq, 9)
    }

    // MARK: - 断开与订阅

    func testDisconnectResetsStateAndCancelsObservation() async throws {
        let http = FakeHTTPPerformer()
        http.stub(path: "/api/status", body: statusJSON(authRequired: false))
        let socket = FakeWebSocket()
        let client = makeClient(http: http, socket: socket)
        addTeardownBlock { await client.disconnect() }

        let cancelledRecorder = StateRecorder()
        let cancelledToken = client.observeState { state in
            cancelledRecorder.record(state)
        }
        cancelledToken.cancel()
        XCTAssertEqual(cancelledRecorder.states, [.disconnected])

        let activeRecorder = StateRecorder()
        let activeToken = client.observeState { state in
            activeRecorder.record(state)
        }
        addTeardownBlock { activeToken.cancel() }

        socket.enqueue(readyFrame())
        try await client.connect(to: configuration())

        await client.disconnect()

        XCTAssertEqual(client.currentState, .disconnected)
        XCTAssertTrue(socket.isCancelled)
        XCTAssertEqual(cancelledRecorder.states, [.disconnected])

        XCTAssertEqual(activeRecorder.states.first, .disconnected)
        XCTAssertTrue(activeRecorder.states.contains { state in
            if case .connected = state { return true }
            return false
        })
        XCTAssertEqual(activeRecorder.states.last, .disconnected)
    }

    // MARK: - 退避与 TLS 策略

    func testReconnectBackoffSequenceWithFullJitter() {
        var policy = GatewayReconnectPolicy(
            baseDelay: 0.3,
            maximumDelay: 15,
            stableConnectionInterval: 5,
            randomUnit: { 1.0 }
        )

        var delays: [TimeInterval] = []
        for _ in 0..<8 {
            policy.recordFailure()
            delays.append(policy.nextDelay(afterFailureCount: policy.failureCount))
        }

        let expected: [TimeInterval] = [0.3, 0.6, 1.2, 2.4, 4.8, 9.6, 15, 15]
        for (delay, value) in zip(delays, expected) {
            XCTAssertEqual(delay, value, accuracy: 0.0001)
        }

        policy.recordSuccess()
        XCTAssertEqual(policy.failureCount, 0)
        XCTAssertEqual(policy.nextDelay(afterFailureCount: 1), 0.3, accuracy: 0.0001)
    }

    func testReconnectBackoffAppliesInjectedRandomUnit() {
        var half = GatewayReconnectPolicy(
            baseDelay: 0.3,
            maximumDelay: 15,
            randomUnit: { 0.5 }
        )
        half.recordFailure()
        half.recordFailure()
        XCTAssertEqual(half.nextDelay(afterFailureCount: 2), 0.3, accuracy: 0.0001)

        var zero = GatewayReconnectPolicy(
            baseDelay: 0.3,
            maximumDelay: 15,
            randomUnit: { 0.0 }
        )
        zero.recordFailure()
        XCTAssertEqual(zero.nextDelay(afterFailureCount: 1), 0, accuracy: 0.0001)
    }

    func testSelfSignedCertificateRequiresSSLAndExplicitOptIn() {
        var gateway = configuration()
        gateway.allowSelfSignedCertificate = true
        XCTAssertFalse(URLSessionGatewayClient.allowsSelfSignedCertificate(for: gateway))

        var ssl = configuration()
        ssl.method = .ssl
        ssl.allowSelfSignedCertificate = false
        XCTAssertFalse(URLSessionGatewayClient.allowsSelfSignedCertificate(for: ssl))

        ssl.allowSelfSignedCertificate = true
        XCTAssertTrue(URLSessionGatewayClient.allowsSelfSignedCertificate(for: ssl))
    }

    // MARK: - 事件路由

    func testEventRouterClassifiesSemanticEvents() {
        let delta = GatewayEventEnvelope(
            type: GatewayEventType.messageDelta,
            sessionID: "s-1",
            payload: .object(["text": .string("你好")]),
            seq: 3
        )
        XCTAssertEqual(
            GatewayEventRouter.classify(delta),
            .messageDelta(text: "你好", sessionID: "s-1")
        )

        let thinking = GatewayEventEnvelope(
            type: GatewayEventType.thinkingDelta,
            payload: .object(["delta": .string("考虑中")])
        )
        XCTAssertEqual(
            GatewayEventRouter.classify(thinking),
            .thinkingDelta(text: "考虑中", sessionID: nil)
        )

        let tool = GatewayEventEnvelope(
            type: GatewayEventType.toolStart,
            sessionID: "s-1",
            payload: .object(["tool": .string("Bash"), "command": .string("ls")])
        )
        XCTAssertEqual(
            GatewayEventRouter.classify(tool),
            .toolOutput(toolName: "Bash", text: "ls", sessionID: "s-1")
        )

        let approval = GatewayEventEnvelope(
            type: GatewayEventType.approvalRequest,
            sessionID: "s-1",
            payload: .object([
                "request_id": .string("srq-1"),
                "command": .string("rm -rf build"),
                "choices": .array([.string("once"), .string("deny")])
            ])
        )
        guard case .approvalRequest(let params, let requestID, let sessionID) =
                GatewayEventRouter.classify(approval) else {
            return XCTFail("期望 approvalRequest")
        }
        XCTAssertEqual(requestID, "srq-1")
        XCTAssertEqual(sessionID, "s-1")
        XCTAssertEqual(params?.command, "rm -rf build")
        XCTAssertEqual(params?.choices, [.once, .deny])

        let cancelled = GatewayEventEnvelope(
            type: GatewayEventType.requestCancel,
            payload: .object(["request_id": .string("srq-1")])
        )
        XCTAssertEqual(
            GatewayEventRouter.classify(cancelled),
            .approvalCancelled(requestID: "srq-1", sessionID: nil)
        )

        XCTAssertEqual(
            GatewayEventRouter.classify(
                GatewayEventEnvelope(type: GatewayEventType.gatewayReady)
            ),
            .ignored
        )
        XCTAssertEqual(
            GatewayEventRouter.classify(GatewayEventEnvelope(type: "unknown.event")),
            .ignored
        )
    }

    // MARK: - 辅助

    private func configuration() -> GatewayConfiguration {
        GatewayConfiguration(
            displayName: "测试网关",
            host: "example.invalid",
            port: 9119,
            method: .gateway,
            authMode: .token,
            timeout: 1
        )
    }

    private func makeClient(
        http: FakeHTTPPerformer,
        socket: FakeWebSocket,
        credentials: GatewayCredentials = GatewayCredentials(token: "token-abc"),
        timings: GatewayTimings = GatewayTimings(),
        requestedURL: LockedBox<URL?>? = nil
    ) -> URLSessionGatewayClient {
        URLSessionGatewayClient(
            credentials: credentials,
            timings: timings,
            reconnectPolicy: GatewayReconnectPolicy(randomUnit: { 1.0 }),
            http: http,
            webSocketFactory: { request in
                requestedURL?.set(request.url)
                return socket
            }
        )
    }

    private func statusJSON(authRequired: Bool) -> String {
        """
        {"version":"0.4.2","auth_required":\(authRequired),"gateway_running":true,"active_sessions":2}
        """
    }

    private func readyFrame(epoch: String = "epoch-1") -> String {
        JSONValue.object([
            "jsonrpc": .string("2.0"),
            "method": .string(GatewayMethod.event),
            "params": .object([
                "type": .string(GatewayEventType.gatewayReady),
                "seq": .int(1),
                "replay_epoch": .string(epoch),
                "payload": .object(["heartbeat": .bool(true)])
            ])
        ]).jsonString() + "\n"
    }

    private func approvalFrame() -> String {
        JSONValue.object([
            "jsonrpc": .string("2.0"),
            "id": .string("srq-0123456789ab"),
            "method": .string(GatewayMethod.approval),
            "params": .object([
                "session_id": .string("s-1"),
                "request_id": .string("r-1"),
                "command": .string("ls"),
                "description": .string("列目录"),
                "choices": .array([
                    .string("once"), .string("session"),
                    .string("always"), .string("deny")
                ])
            ])
        ]).jsonString() + "\n"
    }

    private func responseFrame(id: JSONRPCID, result: JSONValue) -> String {
        JSONValue.object([
            "jsonrpc": .string("2.0"),
            "id": id.jsonValue,
            "result": result
        ]).jsonString() + "\n"
    }

    private func decodeRequest(from text: String) throws -> JSONRPCRequest {
        try JSONDecoder().decode(JSONRPCRequest.self, from: Data(text.utf8))
    }
}

// MARK: - 测试替身

private final class FakeHTTPPerformer: GatewayHTTPPerforming, @unchecked Sendable {
    private struct Stub {
        var statusCode: Int
        var body: Data
    }

    private let lock = NSLock()
    private var stubs: [String: Stub] = [:]
    private var failures: [String: Error] = [:]
    private var recorded: [(path: String, headers: [String: String])] = []

    func stub(path: String, statusCode: Int = 200, body: String) {
        lock.lock()
        stubs[path] = Stub(statusCode: statusCode, body: Data(body.utf8))
        lock.unlock()
    }

    func fail(path: String, with error: Error) {
        lock.lock()
        failures[path] = error
        lock.unlock()
    }

    var requestedPaths: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recorded.map { $0.path }
    }

    func headers(forPath path: String) -> [String: String]? {
        lock.lock()
        defer { lock.unlock() }
        return recorded.last(where: { $0.path == path })?.headers
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let path = request.url?.path ?? ""

        lock.lock()
        recorded.append((path: path, headers: request.allHTTPHeaderFields ?? [:]))
        let failure = failures[path]
        let stub = stubs[path]
        lock.unlock()

        if let failure {
            throw failure
        }
        guard let stub else {
            throw URLError(.badURL)
        }
        guard let url = request.url,
              let response = HTTPURLResponse(
                url: url,
                statusCode: stub.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: nil
              ) else {
            throw URLError(.badServerResponse)
        }
        return (stub.body, response)
    }
}

private final class FakeWebSocket: GatewayWebSocketTasking, @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [Result<URLSessionWebSocketTask.Message, Error>] = []
    private var receiver: CheckedContinuation<URLSessionWebSocketTask.Message, Error>?
    private var sent: [String] = []
    private var cancelled = false
    private var resumed = false

    func enqueue(_ text: String) {
        lock.lock()
        if let receiver {
            self.receiver = nil
            lock.unlock()
            receiver.resume(returning: .string(text))
        } else {
            queue.append(.success(.string(text)))
            lock.unlock()
        }
    }

    var wasResumed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return resumed
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    var sentTexts: [String] {
        lock.lock()
        defer { lock.unlock() }
        return sent
    }

    func waitForSentText(containing needle: String, timeout: TimeInterval = 1) async throws -> String {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let text = sentTexts.first(where: { $0.contains(needle) }) {
                return text
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        throw GatewayError.timeout
    }

    func resume() {
        lock.lock()
        resumed = true
        lock.unlock()
    }

    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        lock.lock()
        cancelled = true
        let receiver = self.receiver
        self.receiver = nil
        lock.unlock()
        receiver?.resume(throwing: URLError(.cancelled))
    }

    func send(_ message: URLSessionWebSocketTask.Message) async throws {
        lock.lock()
        switch message {
        case .string(let text):
            sent.append(text)
        case .data(let data):
            sent.append(String(decoding: data, as: UTF8.self))
        @unknown default:
            break
        }
        lock.unlock()
    }

    func receive() async throws -> URLSessionWebSocketTask.Message {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if !queue.isEmpty {
                let next = queue.removeFirst()
                lock.unlock()
                continuation.resume(with: next)
                return
            }
            if cancelled {
                lock.unlock()
                continuation.resume(throwing: URLError(.cancelled))
                return
            }
            receiver = continuation
            lock.unlock()
        }
    }
}

private final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    var current: Value {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set(_ newValue: Value) {
        lock.lock()
        value = newValue
        lock.unlock()
    }
}

private final class StateRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [GatewayConnectionState] = []

    func record(_ state: GatewayConnectionState) {
        lock.lock()
        storage.append(state)
        lock.unlock()
    }

    var states: [GatewayConnectionState] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
