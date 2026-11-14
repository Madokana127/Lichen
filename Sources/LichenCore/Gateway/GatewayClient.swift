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
