import Foundation

/// 会话列表的读写抽象（占位）。
public protocol SessionStore {
    // TODO: 后续任务实现会话持久化与从网关拉取会话列表。
    func listSessions() async throws -> [Session]

    // TODO: 后续任务定义新增会话参数（是否接收网关侧生成的会话 id）。
    func createSession(title: String) async throws -> Session

    // TODO: 后续任务定义删除语义（仅本地删除还是同步通知网关）。
    func deleteSession(id: UUID) async throws
}
