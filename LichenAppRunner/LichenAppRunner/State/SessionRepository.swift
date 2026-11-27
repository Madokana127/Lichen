import Foundation
import LichenCore

/// Enqueues snapshots in the order the app produced them, including when a write fails.
@MainActor
final class SessionRepository {
    private let store: any SessionStore
    private var pendingWrite: Task<Void, Error>?

    init(store: any SessionStore) {
        self.store = store
    }

    func sessions() async throws -> [Session] {
        try await store.listSessions()
    }

    func messages(for sessionID: UUID) async throws -> [SessionMessage] {
        try await store.messages(sessionID: sessionID)
    }

    func remoteHistory(for sessionID: UUID) async throws -> SessionHistorySnapshot? {
        try await store.remoteHistory(sessionID: sessionID)
    }

    func save(_ session: Session, message: SessionMessage? = nil) -> Task<Void, Error> {
        enqueueWrite { store in
            if let message {
                try await store.save(session, message: message)
            } else {
                try await store.update(session)
            }
        }
    }

    func saveRemoteHistory(_ history: SessionHistorySnapshot, sessionID: UUID) -> Task<Void, Error> {
        enqueueWrite { try await $0.saveRemoteHistory(history, sessionID: sessionID) }
    }

    private func enqueueWrite(_ write: @escaping (any SessionStore) async throws -> Void) -> Task<Void, Error> {
        let previous = pendingWrite
        let task = Task { [store] in
            _ = await previous?.result
            try await write(store)
        }
        pendingWrite = task
        return task
    }
}
