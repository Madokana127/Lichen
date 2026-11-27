import Foundation

/// Last synchronized remote transcript, kept separate from locally recorded messages.
public struct SessionHistorySnapshot: Codable, Equatable, Sendable {
    public let messages: [SessionMessage]
    public let mirroredLocalIDs: Set<UUID>

    public init(messages: [SessionMessage], mirroredLocalIDs: Set<UUID>) {
        self.messages = messages
        self.mirroredLocalIDs = mirroredLocalIDs
    }
}

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

    /// 按消息 ID 插入或更新一条消息；不会改动会话的摘要/计数元数据。
    func append(_ message: SessionMessage) async throws

    /// 写入会话（不存在时插入），用于更新标题、摘要、计数与归档状态。
    func update(_ session: Session) async throws

    /// 按消息 ID 写入或更新消息，并保存对应的会话摘要。
    func save(_ session: Session, message: SessionMessage) async throws

    func remoteHistory(sessionID: UUID) async throws -> SessionHistorySnapshot?
    func saveRemoteHistory(_ history: SessionHistorySnapshot, sessionID: UUID) async throws

    /// 返回按项目分组后的会话。
    func groupedSessions() async throws -> [SessionGroup]
}

/// 进程内会话存储，可直接用于预览与测试。
public actor InMemorySessionStore: SessionStore {
    private var sessions: [UUID: Session]
    private var messagesBySession: [UUID: [SessionMessage]]
    private var remoteHistoryBySession: [UUID: SessionHistorySnapshot] = [:]

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
        remoteHistoryBySession.removeValue(forKey: id)
    }

    public func messages(sessionID: UUID) async throws -> [SessionMessage] {
        sortedMessages(messagesBySession[sessionID] ?? [])
    }

    public func append(_ message: SessionMessage) async throws {
        upsert(message, into: &messagesBySession[message.sessionID, default: []])
    }

    public func update(_ session: Session) async throws {
        sessions[session.id] = session
    }

    public func save(_ session: Session, message: SessionMessage) async throws {
        sessions[session.id] = session
        upsert(message, into: &messagesBySession[session.id, default: []])
    }

    public func remoteHistory(sessionID: UUID) async throws -> SessionHistorySnapshot? {
        remoteHistoryBySession[sessionID]
    }

    public func saveRemoteHistory(_ history: SessionHistorySnapshot, sessionID: UUID) async throws {
        remoteHistoryBySession[sessionID] = history
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

    /// 持久化快照。声明为 internal 而非 private：`private extension` 内的方法
    /// 在文件作用域为 fileprivate，返回 private 嵌套类型会触发访问控制错误。
    internal struct Snapshot: Codable {
        var sessions: [Session]
        var messagesBySession: [String: [SessionMessage]]
        var remoteHistoryBySession: [String: SessionHistorySnapshot]? = nil
    }

    private let directoryURL: URL
    private let fileURL: URL
    private let loadError: (any Error)?
    private var sessions: [UUID: Session]
    private var messagesBySession: [UUID: [SessionMessage]]
    private var remoteHistoryBySession: [String: SessionHistorySnapshot] = [:]

    public init() {
        let directory = Self.defaultDirectoryURL
        let file = directory.appendingPathComponent("sessions.json")
        self.directoryURL = directory
        self.fileURL = file

        do {
            let snapshot = try Self.readSnapshot(at: file)
            self.sessions = Self.indexSessions(snapshot.sessions)
            self.messagesBySession = Self.indexMessages(snapshot.messagesBySession)
            self.remoteHistoryBySession = snapshot.remoteHistoryBySession ?? [:]
            self.loadError = nil
        } catch {
            self.sessions = [:]
            self.messagesBySession = [:]
            self.loadError = error
        }
    }

    /// 测试或自定义容器可注入存储目录。
    public init(directoryURL: URL) {
        let file = directoryURL.appendingPathComponent("sessions.json")
        self.directoryURL = directoryURL
        self.fileURL = file

        do {
            let snapshot = try Self.readSnapshot(at: file)
            self.sessions = Self.indexSessions(snapshot.sessions)
            self.messagesBySession = Self.indexMessages(snapshot.messagesBySession)
            self.remoteHistoryBySession = snapshot.remoteHistoryBySession ?? [:]
            self.loadError = nil
        } catch {
            self.sessions = [:]
            self.messagesBySession = [:]
            self.loadError = error
        }
    }

    public func listSessions() async throws -> [Session] {
        if let loadError { throw loadError }
        return sortedSessions(Array(sessions.values))
    }

    public func createSession(title: String) async throws -> Session {
        if let loadError { throw loadError }
        let now = Date()
        let session = Session(
            id: UUID(),
            title: title,
            createdAt: now,
            updatedAt: now
        )
        try await update(session)
        return session
    }

    public func deleteSession(id: UUID) async throws {
        if let loadError { throw loadError }
        guard let previousSession = sessions.removeValue(forKey: id) else { return }
        let previousMessages = messagesBySession.removeValue(forKey: id)
        let previousHistory = remoteHistoryBySession.removeValue(forKey: id.uuidString)
        do {
            try persist()
        } catch {
            sessions[id] = previousSession
            messagesBySession[id] = previousMessages
            remoteHistoryBySession[id.uuidString] = previousHistory
            throw error
        }
    }

    public func messages(sessionID: UUID) async throws -> [SessionMessage] {
        if let loadError { throw loadError }
        return sortedMessages(messagesBySession[sessionID] ?? [])
    }

    public func append(_ message: SessionMessage) async throws {
        try write(message: message, session: nil)
    }

    public func update(_ session: Session) async throws {
        if let loadError { throw loadError }
        let previous = sessions.updateValue(session, forKey: session.id)
        do {
            try persist()
        } catch {
            sessions[session.id] = previous
            throw error
        }
    }

    public func save(_ session: Session, message: SessionMessage) async throws {
        try write(message: message, session: session)
    }

    public func remoteHistory(sessionID: UUID) async throws -> SessionHistorySnapshot? {
        if let loadError { throw loadError }
        return remoteHistoryBySession[sessionID.uuidString]
    }

    public func saveRemoteHistory(_ history: SessionHistorySnapshot, sessionID: UUID) async throws {
        if let loadError { throw loadError }
        let key = sessionID.uuidString
        let previous = remoteHistoryBySession.updateValue(history, forKey: key)
        do {
            try persist()
        } catch {
            remoteHistoryBySession[key] = previous
            throw error
        }
    }

    private func write(message: SessionMessage, session: Session?) throws {
        if let loadError { throw loadError }
        let sessionID = message.sessionID
        let previousSession = sessions[sessionID]
        let previousMessages = messagesBySession[sessionID]
        if let session { sessions[sessionID] = session }
        upsert(message, into: &messagesBySession[sessionID, default: []])
        do {
            try persist()
        } catch {
            sessions[sessionID] = previousSession
            messagesBySession[sessionID] = previousMessages
            throw error
        }
    }

    public func groupedSessions() async throws -> [SessionGroup] {
        if let loadError { throw loadError }
        return Session.grouped(Array(sessions.values))
    }
}

private extension PersistentSessionStore {
    static func readSnapshot(at fileURL: URL) throws -> Snapshot {
        do {
            return try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: fileURL))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return Snapshot(sessions: [], messagesBySession: [:])
        }
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
            messagesBySession: messages,
            remoteHistoryBySession: remoteHistoryBySession.isEmpty ? nil : remoteHistoryBySession
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
private func upsert(_ message: SessionMessage, into messages: inout [SessionMessage]) {
    if let index = messages.firstIndex(where: { $0.id == message.id }) {
        messages[index] = message
    } else {
        messages.append(message)
    }
}

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
