import Foundation

/// 连接方式。仅保留网关直连与 TLS 两档。
public enum ConnectionMethod: String, Codable, CaseIterable, Sendable {
    /// 明文 HTTP / WS 直连。
    case gateway
    /// HTTPS / WSS 直连。
    case ssl
}

/// 网关鉴权模式。
public enum GatewayAuthMode: String, Codable, Sendable {
    /// 会话 token 模式（`auth_required = false`）。
    case token
    /// OAuth 模式（`auth_required = true`），WebSocket 连接前需换取一次性票据。
    case oauth
}

/// 远程网关连接配置。
///
/// `host` 允许携带 scheme、路径前缀与端口；未携带 scheme 时由 `method` 推导。
/// 配置本身不保存任何凭据，token / cookie 在建立连接时单独提供。
public struct GatewayConfiguration: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var displayName: String
    /// 可含 scheme、路径前缀与端口的主机描述。
    public var host: String
    /// 显式端口；URL 已带端口时不覆盖。
    public var port: Int?
    public var method: ConnectionMethod
    public var authMode: GatewayAuthMode
    /// 仅在 `.ssl` 下生效；当前实现不做证书绕过，保留字段用于上层提示。
    public var allowSelfSignedCertificate: Bool
    /// 请求超时（秒）。
    public var timeout: TimeInterval
    /// 远程网关 profile 标识，可为空。
    public var remoteProfile: String?

    public init(
        id: UUID = UUID(),
        displayName: String,
        host: String,
        port: Int? = nil,
        method: ConnectionMethod = .gateway,
        authMode: GatewayAuthMode = .token,
        allowSelfSignedCertificate: Bool = false,
        timeout: TimeInterval = 8,
        remoteProfile: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.host = host
        self.port = port
        self.method = method
        self.authMode = authMode
        self.allowSelfSignedCertificate = allowSelfSignedCertificate
        self.timeout = timeout
        self.remoteProfile = remoteProfile
    }

    /// 兼容既有调用方的快捷初始化方法。
    public init(host: String, port: Int, displayName: String) {
        self.init(displayName: displayName, host: host, port: port)
    }
}

// MARK: - URL 派生

public extension GatewayConfiguration {
    /// 规范化后的 HTTP(S) base URL。
    ///
    /// 处理内容：补 scheme、校验协议、移除 query / fragment、去掉路径尾部斜杠，
    /// 并在 URL 未显式携带端口时补上配置端口。
    func normalizedBaseURL() throws -> URL {
        try validate()

        var input = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else {
            throw GatewayError.invalidURL("host 不能为空")
        }

        if !input.contains("://") {
            input = (method == .ssl ? "https://" : "http://") + input
        }

        guard var components = URLComponents(string: input) else {
            throw GatewayError.invalidURL("无法解析 host：\(host)")
        }

        guard let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            throw GatewayError.invalidURL("仅支持 http/https，实际为 \(components.scheme ?? "空")")
        }
        components.scheme = scheme

        guard let parsedHost = components.host, !parsedHost.isEmpty else {
            throw GatewayError.invalidURL("host 缺少有效主机名：\(host)")
        }

        if components.port == nil, let port = port {
            guard (1...65535).contains(port) else {
                throw GatewayError.invalidURL("端口必须在 1...65535 之间，实际为 \(port)")
            }
            components.port = port
        }

        components.query = nil
        components.fragment = nil
        components.path = Self.trimTrailingSlashes(components.path)

        guard let url = components.url else {
            throw GatewayError.invalidURL("无法生成合法 URL：\(input)")
        }
        return url
    }

    /// 派生 WebSocket URL：`ws(s)://host<pathPrefix>/api/ws?token=|?ticket=`。
    ///
    /// - Parameters:
    ///   - credential: token 或一次性票据。
    ///   - isTicket: 为 `true` 时使用 `ticket` 查询参数，否则使用 `token`。
    func webSocketURL(credential: String, isTicket: Bool = false) throws -> URL {
        let base = try normalizedBaseURL()

        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            throw GatewayError.invalidURL("无法从 base URL 派生 WebSocket URL")
        }

        components.scheme = base.scheme?.lowercased() == "https" ? "wss" : "ws"
        components.query = nil
        components.fragment = nil

        var path = components.path
        while path.hasSuffix("/") {
            path.removeLast()
        }
        components.path = path + "/api/ws"

        let encodedCredential = try Self.percentEncodeQueryValue(credential)
        let queryKey = isTicket ? "ticket" : "token"
        components.percentEncodedQuery = "\(queryKey)=\(encodedCredential)"

        guard let url = components.url else {
            throw GatewayError.invalidURL("无法生成 WebSocket URL")
        }
        return url
    }

    /// 按鉴权模式生成 REST 请求头。
    func restHeaders(token: String?) -> [String: String] {
        guard let token = token, !token.isEmpty else { return [:] }
        switch authMode {
        case .token:
            return ["X-Hermes-Session-Token": token]
        case .oauth:
            return ["Authorization": "Bearer \(token)"]
        }
    }

    /// `/api/status`（免认证）。
    func statusURL() throws -> URL {
        try appendingPath("/api/status")
    }

    /// `/api/auth/ws-ticket`（OAuth 模式下换取 WS 票据）。
    func wsTicketURL() throws -> URL {
        try appendingPath("/api/auth/ws-ticket")
    }

    /// `/api/auth/me`（校验当前登录身份）。
    func authMEURL() throws -> URL {
        try appendingPath("/api/auth/me")
    }

    /// 校验配置的基本合法性。
    func validate() throws {
        if host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw GatewayError.invalidURL("host 不能为空")
        }
        if let port = port, !(1...65535).contains(port) {
            throw GatewayError.invalidURL("端口必须在 1...65535 之间，实际为 \(port)")
        }
    }
}

private extension GatewayConfiguration {
    static let unreservedQueryCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    static func trimTrailingSlashes(_ path: String) -> String {
        var result = path
        while result.count > 1 && result.hasSuffix("/") {
            result.removeLast()
        }
        return result == "/" ? "" : result
    }

    static func percentEncodeQueryValue(_ value: String) throws -> String {
        guard let encoded = value.addingPercentEncoding(withAllowedCharacters: unreservedQueryCharacters) else {
            throw GatewayError.encoding("凭据无法进行 percent-encode")
        }
        return encoded
    }

    func appendingPath(_ suffix: String) throws -> URL {
        let base = try normalizedBaseURL()
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            throw GatewayError.invalidURL("无法派生 URL 路径：\(suffix)")
        }

        var path = components.path
        while path.hasSuffix("/") {
            path.removeLast()
        }
        components.path = path + suffix

        guard let url = components.url else {
            throw GatewayError.invalidURL("无法生成 URL：\(suffix)")
        }
        return url
    }
}

// MARK: - 配置持久化

/// 基于 `UserDefaults` 的网关配置存储。
///
/// 同时保存当前选中的配置与多 Agent 配置列表；所有读写由内部锁保护。
public final class GatewayConfigurationStore: @unchecked Sendable {
    /// 持久化快照。
    public struct Snapshot: Codable, Equatable, Sendable {
        public var currentID: UUID?
        public var configurations: [GatewayConfiguration]

        public init(currentID: UUID? = nil, configurations: [GatewayConfiguration] = []) {
            self.currentID = currentID
            self.configurations = configurations
        }

        /// 当前配置；`currentID` 不存在于列表时返回 `nil`。
        public var current: GatewayConfiguration? {
            guard let currentID = currentID else { return nil }
            return configurations.first { $0.id == currentID }
        }
    }

    private let defaults: UserDefaults
    private let storageKey: String
    private let lock = NSLock()
    private var snapshot: Snapshot

    public init(
        defaults: UserDefaults = .standard,
        storageKey: String = "lichen.gateway.configuration-store"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.snapshot = Self.readSnapshot(defaults: defaults, key: storageKey)
    }

    /// 从持久化介质重新加载并返回快照。
    @discardableResult
    public func load() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        snapshot = Self.readSnapshot(defaults: defaults, key: storageKey)
        return snapshot
    }

    /// 将当前内存快照写入持久化介质。
    public func save() {
        lock.lock()
        defer { lock.unlock() }
        persistLocked()
    }

    /// 当前选中的配置。
    public var current: GatewayConfiguration? {
        lock.lock()
        defer { lock.unlock() }
        return snapshot.current
    }

    /// 当前选中配置的 id。
    public var currentID: UUID? {
        lock.lock()
        defer { lock.unlock() }
        return snapshot.currentID
    }

    /// 全部配置的副本。
    public var configurations: [GatewayConfiguration] {
        lock.lock()
        defer { lock.unlock() }
        return snapshot.configurations
    }

    /// 新增配置；同 id 时覆盖。可选择同时设为当前配置。
    public func add(_ configuration: GatewayConfiguration, makeCurrent: Bool = false) {
        lock.lock()
        defer { lock.unlock() }
        if let index = snapshot.configurations.firstIndex(where: { $0.id == configuration.id }) {
            snapshot.configurations[index] = configuration
        } else {
            snapshot.configurations.append(configuration)
        }
        if makeCurrent || snapshot.currentID == nil {
            snapshot.currentID = configuration.id
        }
        persistLocked()
    }

    /// 删除指定配置；删除的是当前配置时自动切换到剩余第一项。
    @discardableResult
    public func remove(id: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let index = snapshot.configurations.firstIndex(where: { $0.id == id }) else {
            return false
        }
        snapshot.configurations.remove(at: index)
        if snapshot.currentID == id {
            snapshot.currentID = snapshot.configurations.first?.id
        }
        persistLocked()
        return true
    }

    /// 按 id 更新配置；不存在时返回 `false`。
    @discardableResult
    public func update(_ configuration: GatewayConfiguration) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let index = snapshot.configurations.firstIndex(where: { $0.id == configuration.id }) else {
            return false
        }
        snapshot.configurations[index] = configuration
        persistLocked()
        return true
    }

    /// 切换当前配置；id 不存在时返回 `false`。
    @discardableResult
    public func setCurrent(id: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard snapshot.configurations.contains(where: { $0.id == id }) else {
            return false
        }
        snapshot.currentID = id
        persistLocked()
        return true
    }
}

private extension GatewayConfigurationStore {
    static func readSnapshot(defaults: UserDefaults, key: String) -> Snapshot {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            return Snapshot()
        }
        return decoded
    }

    func persistLocked() {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
