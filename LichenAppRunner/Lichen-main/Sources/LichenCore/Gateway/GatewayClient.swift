import Foundation

/// 远程网关客户端的传输层接口。
///
/// 实现方负责 HTTP / WebSocket 连接、鉴权握手与状态广播；契约层只依赖此接口。
public protocol GatewayClient: AnyObject {
    /// 使用给定配置建立连接，并完成 `gateway.ready` / `client.capabilities` 握手。
    func connect(to configuration: GatewayConfiguration) async throws

    /// 主动断开连接并释放底层资源。
    func disconnect() async

    /// 发送一个已编码的换行分隔 JSON-RPC 文本帧。
    func send(_ payload: Data) async throws

    /// 订阅连接状态变化，返回可取消的观察句柄。
    func observeState(_ handler: @escaping @Sendable (GatewayConnectionState) -> Void) -> GatewayStateObservation

    /// 发起 JSON-RPC 请求并等待同 id 响应。
    ///
    /// - Parameters:
    ///   - method: 网关方法名。
    ///   - params: 可选参数。
    ///   - timeout: 等待响应的秒数；`<= 0` 表示不设超时。
    func request(method: String, params: JSONValue?, timeout: TimeInterval) async throws -> JSONValue

    /// 订阅服务端事件（`event` 通知）。
    func observeEvents(_ handler: @escaping @Sendable (GatewayEventEnvelope) -> Void) -> GatewayStateObservation

    /// 订阅服务端请求（`approval` / `clarify`）。
    func observeServerRequests(_ handler: @escaping @Sendable (ServerRequest) -> Void) -> GatewayStateObservation

    /// 用服务端请求的同一 id 回送审批结果。
    func respond(to requestID: JSONRPCID, choice: ApprovalChoice) async throws

    /// 当前连接状态快照。
    var currentState: GatewayConnectionState { get }

    /// 最近一次 `gateway.ready` 建立的补播纪元。
    var replayEpoch: String? { get }
}

public extension GatewayClient {
    /// 使用默认 8 秒超时发起请求的便捷重载。
    func request(method: String, params: JSONValue? = nil) async throws -> JSONValue {
        try await request(method: method, params: params, timeout: 8)
    }
}

/// 连接状态订阅句柄。
public protocol GatewayStateObservation: AnyObject {
    /// 取消订阅；重复调用应当无副作用。
    func cancel()
}

/// 基于闭包的观察句柄实现，供传输层直接复用。
public final class GatewayStateObservationToken: GatewayStateObservation, @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable (GatewayConnectionState) -> Void)?

    public init(handler: @escaping @Sendable (GatewayConnectionState) -> Void) {
        self.handler = handler
    }

    /// 将状态分发给订阅者；取消后调用为空操作。
    public func deliver(_ state: GatewayConnectionState) {
        lock.lock()
        let current = handler
        lock.unlock()
        current?(state)
    }

    public func cancel() {
        lock.lock()
        handler = nil
        lock.unlock()
    }
}

/// 泛型可取消观察句柄，供事件、服务端请求等任意载荷类型复用。
public final class GatewayCallbackObservation<Value: Sendable>: GatewayStateObservation, @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable (Value) -> Void)?
    private var onCancel: (@Sendable () -> Void)?
    private var isCancelled = false

    public init(
        handler: @escaping @Sendable (Value) -> Void,
        onCancel: (@Sendable () -> Void)? = nil
    ) {
        self.handler = handler
        self.onCancel = onCancel
    }

    /// 向订阅者分发一次载荷；取消后为空操作。
    public func deliver(_ value: Value) {
        lock.lock()
        let current = handler
        lock.unlock()
        current?(value)
    }

    public func cancel() {
        lock.lock()
        guard !isCancelled else {
            lock.unlock()
            return
        }
        isCancelled = true
        handler = nil
        let action = onCancel
        onCancel = nil
        lock.unlock()
        action?()
    }
}
