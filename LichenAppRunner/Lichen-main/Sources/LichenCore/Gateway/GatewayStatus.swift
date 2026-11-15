import Foundation

/// `GET /api/status` 的容错模型。
///
/// 所有字段均允许缺省；缺失或类型不符时回落到默认值，避免网关版本差异导致解码失败。
public struct GatewayStatus: Codable, Sendable, Equatable {
    public var version: String
    public var authRequired: Bool
    public var authProviders: [String]
    public var authFlows: [String]
    public var gatewayRunning: Bool
    public var activeSessions: Int
    public var components: [String: JSONValue]
    public var overall: String

    public init(
        version: String = "",
        authRequired: Bool = false,
        authProviders: [String] = [],
        authFlows: [String] = [],
        gatewayRunning: Bool = false,
        activeSessions: Int = 0,
        components: [String: JSONValue] = [:],
        overall: String = ""
    ) {
        self.version = version
        self.authRequired = authRequired
        self.authProviders = authProviders
        self.authFlows = authFlows
        self.gatewayRunning = gatewayRunning
        self.activeSessions = activeSessions
        self.components = components
        self.overall = overall
    }

    enum CodingKeys: String, CodingKey {
        case version
        case authRequired = "auth_required"
        case authProviders = "auth_providers"
        case authFlows = "auth_flows"
        case gatewayRunning = "gateway_running"
        case activeSessions = "active_sessions"
        case components
        case overall
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = (try? container.decodeIfPresent(String.self, forKey: .version)) ?? ""
        authRequired = (try? container.decodeIfPresent(Bool.self, forKey: .authRequired)) ?? false
        authProviders = (try? container.decodeIfPresent([String].self, forKey: .authProviders)) ?? []
        authFlows = (try? container.decodeIfPresent([String].self, forKey: .authFlows)) ?? []
        gatewayRunning = (try? container.decodeIfPresent(Bool.self, forKey: .gatewayRunning)) ?? false
        activeSessions = (try? container.decodeIfPresent(Int.self, forKey: .activeSessions)) ?? 0
        components = (try? container.decodeIfPresent([String: JSONValue].self, forKey: .components)) ?? [:]
        overall = (try? container.decodeIfPresent(String.self, forKey: .overall)) ?? ""
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(authRequired, forKey: .authRequired)
        try container.encode(authProviders, forKey: .authProviders)
        try container.encode(authFlows, forKey: .authFlows)
        try container.encode(gatewayRunning, forKey: .gatewayRunning)
        try container.encode(activeSessions, forKey: .activeSessions)
        try container.encode(components, forKey: .components)
        try container.encode(overall, forKey: .overall)
    }

    /// 由状态字段推导鉴权模式。
    public var authMode: GatewayAuthMode {
        authRequired ? .oauth : .token
    }

    /// 转换为连接状态使用的运行时信息。
    public var info: GatewayInfo {
        GatewayInfo(
            version: version,
            authRequired: authRequired,
            authProviders: authProviders,
            authFlows: authFlows,
            gatewayRunning: gatewayRunning,
            activeSessions: activeSessions
        )
    }

    /// 解码 `/api/status` 响应体。
    public static func decode(_ data: Data) throws -> GatewayStatus {
        do {
            return try JSONDecoder().decode(GatewayStatus.self, from: data)
        } catch {
            throw GatewayError.decoding("解析 /api/status 失败：\(error.localizedDescription)")
        }
    }
}

/// `POST /api/auth/ws-ticket` 的响应。
public struct WsTicket: Codable, Sendable, Equatable {
    public let ticket: String
    public let ttlSeconds: Int

    public init(ticket: String, ttlSeconds: Int) {
        self.ticket = ticket
        self.ttlSeconds = ttlSeconds
    }

    enum CodingKeys: String, CodingKey {
        case ticket
        case ttlSeconds = "ttl_seconds"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ticket = try container.decode(String.self, forKey: .ticket)
        ttlSeconds = (try? container.decodeIfPresent(Int.self, forKey: .ttlSeconds)) ?? 30
    }
}
