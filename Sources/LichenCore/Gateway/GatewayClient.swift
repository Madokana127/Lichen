import Foundation

/// 远程网关客户端抽象（占位）。
///
/// 本任务只声明未来传输层需要满足的接口形状，不提供任何实现。
public protocol GatewayClient: AnyObject {
    // TODO: 后续任务实现真实传输层（WebSocket/HTTP）与鉴权握手。
    func connect(to configuration: GatewayConfiguration) async throws

    // TODO: 后续任务定义断开语义（是否等待在途消息完成、是否区分主动/被动断开）。
    func disconnect() async

    // TODO: 后续任务定义消息载荷类型以及分片、重传、排序策略。
    func send(_ payload: Data) async throws

    // TODO: 后续任务实现状态订阅与取消订阅的生命周期管理。
    func observeState(_ handler: @escaping @Sendable (GatewayConnectionState) -> Void) -> GatewayStateObservation
}

/// 连接状态订阅句柄（占位）。
public protocol GatewayStateObservation: AnyObject {
    // TODO: 后续任务实现取消订阅。
    func cancel()
}
