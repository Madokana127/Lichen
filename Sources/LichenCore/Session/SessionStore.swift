import Foundation

/// 会话列表的读写接口。
public protocol SessionStore: Sendable {
    /// 返回全部会话，按创建时间升序排列。
    func listSessions() async throws -> [Session]

    /// 创建会话；id 由存储侧生成。
    func createSession(title: String) async throws -> Session

    /// 删除会话；不存在时为空操作。
    func deleteSession(id: UUID) async throws
}

/// 进程内会话存储，可直接用于预览与测试。
public actor InMemorySessionStore: SessionStore {
    private var sessions: [UUID: Session]

    public init(initial: [Session] = []) {
        var storage: [UUID: Session] = [:]
        for session in initial {
            storage[session.id] = session
        }
        self.sessions = storage
    }

    public func listSessions() async throws -> [Session] {
        sessions.values.sorted {
            if $0.createdAt == $1.createdAt {
                return $0.id.uuidString < $1.id.uuidString
            }
            return $0.createdAt < $1.createdAt
        }
    }

    public func createSession(title: String) async throws -> Session {
        let session = Session(title: title)
        sessions[session.id] = session
        return session
    }

    public func deleteSession(id: UUID) async throws {
        sessions.removeValue(forKey: id)
    }
}
