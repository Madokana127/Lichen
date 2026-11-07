import Foundation

/// 远程网关连接配置（占位）。
///
/// 仅承载展示与后续连接所需的字段，不包含地址校验、持久化或鉴权信息。
public struct GatewayConfiguration: Equatable, Codable {
    // TODO: 后续任务补充 host 合法性校验与默认端口策略。
    // TODO: 后续任务补充配置持久化（本地存储）。
    // TODO: 后续任务补充鉴权相关字段（证书、token 引用等，本次不涉及凭据）。
    public var host: String
    public var port: Int
    public var displayName: String

    public init(host: String, port: Int, displayName: String) {
        self.host = host
        self.port = port
        self.displayName = displayName
    }
}
