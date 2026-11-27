import Foundation

/// `/api/status` 中的网关运行时信息。
public struct GatewayInfo: Equatable, Codable, Sendable {
    public var version: String
    public var authRequired: Bool
    public var authProviders: [String]
    public var authFlows: [String]
    public var gatewayRunning: Bool
    public var activeSessions: Int

    public init(
        version: String = "",
        authRequired: Bool = false,
        authProviders: [String] = [],
        authFlows: [String] = [],
        gatewayRunning: Bool = false,
        activeSessions: Int = 0
    ) {
        self.version = version
        self.authRequired = authRequired
        self.authProviders = authProviders
        self.authFlows = authFlows
        self.gatewayRunning = gatewayRunning
        self.activeSessions = activeSessions
    }
}

/// 网关契约层统一错误。
public enum GatewayError: Error, Equatable, Codable, Sendable {
    case invalidURL(String)
    case unreachable(String)
    case unauthorized
    case tlsFailed(String)
    case encoding(String)
    case server(code: Int, message: String)
    case timeout
    case cancelled
    case decoding(String)
}

extension GatewayError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidURL(let detail):
            return "网关地址无效：\(detail)"
        case .unreachable(let detail):
            return "无法连接网关：\(detail)"
        case .unauthorized:
            return "网关鉴权失败，请检查鉴权方式和访问令牌"
        case .tlsFailed(let detail):
            return "TLS 握手失败：\(detail)"
        case .encoding(let detail):
            return "请求编码失败：\(detail)"
        case .server(let code, let message):
            return "网关返回错误 \(code)：\(message)"
        case .timeout:
            return "连接超时"
        case .cancelled:
            return "操作已取消"
        case .decoding(let detail):
            return "响应解码失败：\(detail)"
        }
    }
}

/// 网关连接状态。
public enum GatewayConnectionState: Equatable, Sendable {
    case disconnected
    case connecting(URL?)
    case connected(GatewayInfo)
    case failed(GatewayError)
}

/// 驱动连接状态迁移的事件。
public enum GatewayConnectionEvent: Equatable, Sendable {
    case beginConnect(URL)
    case didConnect(GatewayInfo)
    case didFail(GatewayError)
    case disconnect
}

public extension GatewayConnectionState {
    /// 判断当前状态是否允许迁移到目标状态。
    ///
    /// 允许自迁移，便于重复事件按幂等方式处理；`disconnected` 不能直接跳到 `connected`。
    func canTransition(to next: GatewayConnectionState) -> Bool {
        switch (self, next) {
        case (.disconnected, .disconnected),
             (.disconnected, .connecting(_)),
             (.disconnected, .failed(_)):
            return true
        case (.connecting(_), .connecting(_)),
             (.connecting(_), .connected(_)),
             (.connecting(_), .failed(_)),
             (.connecting(_), .disconnected):
            return true
        case (.connected(_), .connected(_)),
             (.connected(_), .connecting(_)),
             (.connected(_), .failed(_)),
             (.connected(_), .disconnected):
            return true
        case (.failed(_), .failed(_)),
             (.failed(_), .connecting(_)),
             (.failed(_), .disconnected):
            return true
        default:
            return false
        }
    }

    /// 纯函数式状态迁移：非法事件保持原状态不变。
    func applying(event: GatewayConnectionEvent) -> GatewayConnectionState {
        switch event {
        case .beginConnect(let url):
            let next = GatewayConnectionState.connecting(url)
            return canTransition(to: next) ? next : self
        case .didConnect(let info):
            let next = GatewayConnectionState.connected(info)
            return canTransition(to: next) ? next : self
        case .didFail(let error):
            let next = GatewayConnectionState.failed(error)
            return canTransition(to: next) ? next : self
        case .disconnect:
            return canTransition(to: .disconnected) ? .disconnected : self
        }
    }
}
