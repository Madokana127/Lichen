import Foundation

/// 一个远程会话。
///
/// `remoteID` 保存网关侧的 `session_id`，`project` 用于状态页按项目/工作区分组。
public struct Session: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public var title: String
    public let createdAt: Date
    public var updatedAt: Date
    /// 所属项目/工作区；`nil` 表示未归属，分组时归入「其他」。
    public var project: String?
    /// 绑定的 Agent id。
    public var agentID: UUID?
    /// 列表里展示的最后一条消息摘要。
    public var preview: String?
    /// 消息条数缓存，供会话列表展示。
    public var messageCount: Int
    /// 是否已归档（归档会话仍保留在存储中）。
    public var isArchived: Bool
    /// 网关侧 session_id。
    public var remoteID: String?
    /// Hermes 的持久化 ID；恢复时可换取新的运行中会话 ID。
    public var remoteHistoryID: String?

    /// 兼容旧调用方的三参数初始化方法。
    public init(id: UUID = UUID(), title: String, createdAt: Date = Date()) {
        self.init(
            id: id,
            title: title,
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }

    /// 完整初始化方法。
    public init(
        id: UUID,
        title: String,
        createdAt: Date,
        updatedAt: Date,
        project: String? = nil,
        agentID: UUID? = nil,
        preview: String? = nil,
        messageCount: Int = 0,
        isArchived: Bool = false,
        remoteID: String? = nil,
        remoteHistoryID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.project = project
        self.agentID = agentID
        self.preview = preview
        self.messageCount = messageCount
        self.isArchived = isArchived
        self.remoteID = remoteID
        self.remoteHistoryID = remoteHistoryID
    }

    /// 便捷拷贝：仅更新传入的字段，并把 `updatedAt` 置为当前时间。
    ///
    /// 参数为 `nil` 表示保留原值。
    public func updating(
        title: String? = nil,
        preview: String? = nil,
        messageCount: Int? = nil,
        isArchived: Bool? = nil
    ) -> Session {
        var copy = self
        if let title = title { copy.title = title }
        if let preview = preview { copy.preview = preview }
        if let messageCount = messageCount { copy.messageCount = messageCount }
        if let isArchived = isArchived { copy.isArchived = isArchived }
        copy.updatedAt = Date()
        return copy
    }

    /// 按项目分组的会话集合。
    ///
    /// 分组内按 `updatedAt` 降序；`project` 为空时归入「其他」；组按标题升序。
    public static func grouped(_ sessions: [Session]) -> [SessionGroup] {
        let buckets = Dictionary(grouping: sessions) { session -> String in
            let project = session.project?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return project.isEmpty ? "其他" : project
        }

        return buckets.keys.sorted().map { title in
            let items = (buckets[title] ?? []).sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt > rhs.createdAt
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return SessionGroup(id: title, title: title, sessions: items)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case createdAt
        case updatedAt
        case project
        case agentID
        case preview
        case messageCount
        case isArchived
        case remoteID
        case remoteHistoryID
    }

    /// 容忍旧数据缺失新增字段：`updatedAt` 回退到 `createdAt`，其余取默认值。
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        project = try container.decodeIfPresent(String.self, forKey: .project)
        agentID = try container.decodeIfPresent(UUID.self, forKey: .agentID)
        preview = try container.decodeIfPresent(String.self, forKey: .preview)
        messageCount = try container.decodeIfPresent(Int.self, forKey: .messageCount) ?? 0
        isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        remoteID = try container.decodeIfPresent(String.self, forKey: .remoteID)
        remoteHistoryID = try container.decodeIfPresent(String.self, forKey: .remoteHistoryID)
    }
}

/// 按项目/工作区聚合的一组会话。
public struct SessionGroup: Identifiable, Equatable, Sendable {
    /// 分组标识，与分组标题一致。
    public let id: String
    public let title: String
    public let sessions: [Session]

    public init(id: String, title: String, sessions: [Session]) {
        self.id = id
        self.title = title
        self.sessions = sessions
    }
}
