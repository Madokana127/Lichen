import Foundation

/// 一个远程会话（占位）。
public struct Session: Identifiable, Equatable {
    public let id: UUID
    public var title: String
    public let createdAt: Date

    // TODO: 后续任务补充终端缓冲区引用。
    // TODO: 后续任务补充消息流（用户输入 / Agent 输出）。
    public init(id: UUID = UUID(), title: String, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
    }
}
