import Foundation

/// 一个远程会话。
public struct Session: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public var title: String
    public let createdAt: Date

    public init(id: UUID = UUID(), title: String, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
    }
}
