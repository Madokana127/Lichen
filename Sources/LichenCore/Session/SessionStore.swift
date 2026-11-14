import Foundation

/// 会话及其消息的读写接口。
public protocol SessionStore: Sendable {
    /// 返回全部会话，按 `updatedAt` 降序排列。
    func listSessions() async throws -> [Session]

    /// 创建会话；id 由存储侧生成。
    func createSession(title: String) async throws -> Session

    /// 删除会话及其消息；不存在时为空操作。
    func deleteSession(id: UUID) async throws

    /// 返回指定会话的消息，按 `createdAt` 升序排列。
    func messages(sessionID: UUID) async throws -> [SessionMessage]

    /// 追加一条消息；不会改动会话的摘要/计数元数据。
    func append(_ message: SessionMessage) async throws

    /// 写入会话（不存在时插入），用于更新标题、摘要、计数与归档状态。
    func update(_ session: Session) async throws

    /// 返回按项目分组后的会话。
    func groupedSessions() async throws -> [SessionGroup]
}

/// 进程内会话存储，可直接用于预览与测试。
public actor InMemorySessionStore: SessionStore {
    private var sessions: [UUID: Session]
    private var messagesBySession: [UUID: [SessionMessage]]

    public init(initial: [Session] = [], messages: [SessionMessage] = []) {
        var sessionStorage: [UUID: Session] = [:]
        for session in initial {
            sessionStorage[session.id] = session
        }
        self.sessions = sessionStorage

        var messageStorage: [UUID: [SessionMessage]] = [:]
        for message in messages {
            messageStorage[message.sessionID, default: []].append(message)
        }
        self.messagesBySession = messageStorage
    }

    public func listSessions() async throws -> [Session] {
        sortedSessions(Array(sessions.values))
    }

    public func createSession(title: String) async throws -> Session {
        let now = Date()
        let session = Session(
            id: UUID(),
            title: title,
            createdAt: now,
            updatedAt: now
        )
        sessions[session.id] = session
        return session
    }

    public func deleteSession(id: UUID) async throws {
        sessions.removeValue(forKey: id)
        messagesBySession.removeValue(forKey: id)
    }

    public func messages(sessionID: UUID) async throws -> [SessionMessage] {
        sortedMessages(messagesBySession[sessionID] ?? [])
    }

    public func append(_ message: SessionMessage) async throws {
        messagesBySession[message.sessionID, default: []].append(message)
    }

    public func update(_ session: Session) async throws {
        sessions[session.id] = session
    }

    public func groupedSessions() async throws -> [SessionGroup] {
        Session.grouped(Array(sessions.values))
    }
}

/// 基于 JSON 文件的会话存储。
///
/// 数据保存在 `<directoryURL>/sessions.json`，默认目录为
/// `Application Support/Lichen/`。写入采用临时文件 + `replaceItemAt` 的原子替换，
/// 避免进程中断时留下半截 JSON。
public actor PersistentSessionStore: SessionStore {
    /// 默认存储目录。
    public static var defaultDirectoryURL: URL {
        let manager = FileManager.default
        if let base = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            return base.appendingPathComponent("Lichen", isDirectory: true)
        }
        return manager.temporaryDirectory.appendingPathComponent("Lichen", isDirectory: true)
    }

    private struct Snapshot: Codable {
        var sessions: [Session]
        var messagesBySession: [String: [SessionMessage]]
    }

    private let directoryURL: URL
    private let fileURL: URL
    private var sessions: [UUID: Session]
    private var messagesBySession: [UUID: [SessionMessage]]

    public init() {
        let directory = Self.defaultDirectoryURL
        let file = directory.appendingPathComponent("sessions.json")
        self.directoryURL = directory
        self.fileURL = file

        let snapshot = Self.readSnapshot(at: file)
        self.sessions = Self.indexSessions(snapshot.sessions)
        self.messagesBySession = Self.indexMessages(snapshot.messagesBySession)
    }

    /// 测试或自定义容器可注入存储目录。
    public init(directoryURL: URL) {
        let file = directoryURL.appendingPathComponent("sessions.json")
        self.directoryURL = directoryURL
        self.fileURL = file

        let snapshot = Self.readSnapshot(at: file)
        self.sessions = Self.indexSessions(snapshot.sessions)
        self.messagesBySession = Self.indexMessages(snapshot.messagesBySession)
    }

    public func listSessions() async throws -> [Session] {
        sortedSessions(Array(sessions.values))
    }

    public func createSession(title: String) async throws -> Session {
        let now = Date()
        let session = Session(
            id: UUID(),
            title: title,
            createdAt: now,
            updatedAt: now
        )
        sessions[session.id] = session
        try persist()
        return session
    }

    public func deleteSession(id: UUID) async throws {
        guard sessions.removeValue(forKey: id) != nil else { return }
        messagesBySession.removeValue(forKey: id)
        try persist()
    }

    public func messages(sessionID: UUID) async throws -> [SessionMessage] {
        sortedMessages(messagesBySession[sessionID] ?? [])
    }

    public func append(_ message: SessionMessage) async throws {
        messagesBySession[message.sessionID, default: []].append(message)
        try persist()
    }

    public func update(_ session: Session) async throws {
        sessions[session.id] = session
        try persist()
    }

    public func groupedSessions() async throws -> [SessionGroup] {
        Session.grouped(Array(sessions.values))
    }
}

private extension PersistentSessionStore {
    static func readSnapshot(at fileURL: URL) -> Snapshot {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            return Snapshot(sessions: [], messagesBySession: [:])
        }
        return decoded
    }

    static func indexSessions(_ sessions: [Session]) -> [UUID: Session] {
        var storage: [UUID: Session] = [:]
        for session in sessions {
            storage[session.id] = session
        }
        return storage
    }

    static func indexMessages(
        _ messages: [String: [SessionMessage]]
    ) -> [UUID: [SessionMessage]] {
        var storage: [UUID: [SessionMessage]] = [:]
        for (key, value) in messages {
            guard let sessionID = UUID(uuidString: key) else { continue }
            storage[sessionID] = value
        }
        return storage
    }

    func makeSnapshot() -> Snapshot {
        var messages: [String: [SessionMessage]] = [:]
        for (sessionID, value) in messagesBySession {
            messages[sessionID.uuidString] = sortedMessages(value)
        }
        return Snapshot(
            sessions: sortedSessions(Array(sessions.values)),
            messagesBySession: messages
        )
    }

    /// 写入临时文件后原子替换目标文件。
    func persist() throws {
        let manager = FileManager.default
        try manager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(makeSnapshot())

        let temporaryURL = directoryURL.appendingPathComponent(
            ".sessions-\(UUID().uuidString).json"
        )
        try data.write(to: temporaryURL, options: .atomic)
        defer { try? manager.removeItem(at: temporaryURL) }

        if manager.fileExists(atPath: fileURL.path) {
            _ = try manager.replaceItemAt(fileURL, withItemAt: temporaryURL)
        } else {
            try manager.moveItem(at: temporaryURL, to: fileURL)
        }
    }
}

/// 会话按 `updatedAt` 降序；时间相同时按 `createdAt` 降序、id 升序兜底。
private func sortedSessions(_ sessions: [Session]) -> [Session] {
    sessions.sorted { lhs, rhs in
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt > rhs.createdAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

/// 消息按 `createdAt` 升序；时间相同时按 id 升序兜底。
private func sortedMessages(_ messages: [SessionMessage]) -> [SessionMessage] {
    messages.sorted { lhs, rhs in
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
