import XCTest
import Foundation
@testable import LichenCore

final class SessionModelTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_000)

    private func makeSession(
        title: String,
        project: String?,
        updatedOffset: TimeInterval,
        id: UUID = UUID()
    ) -> Session {
        Session(
            id: id,
            title: title,
            createdAt: base,
            updatedAt: base.addingTimeInterval(updatedOffset),
            project: project
        )
    }

    private func makeEvent(
        _ type: String,
        sessionID: String? = nil,
        payload: JSONValue? = nil,
        seq: Int? = nil,
        executionGeneration: Int? = nil
    ) -> GatewayEventEnvelope {
        GatewayEventEnvelope(
            type: type,
            sessionID: sessionID,
            payload: payload,
            seq: seq,
            executionGeneration: executionGeneration
        )
    }

    // MARK: 会话模型

    func testLegacyInitializerCompatibility() {
        let session = Session(title: "未命名会话")

        XCTAssertEqual(session.title, "未命名会话")
        XCTAssertEqual(session.updatedAt, session.createdAt)
        XCTAssertNil(session.project)
        XCTAssertNil(session.agentID)
        XCTAssertNil(session.preview)
        XCTAssertEqual(session.messageCount, 0)
        XCTAssertFalse(session.isArchived)
        XCTAssertNil(session.remoteID)
    }

    func testUpdatingCopiesSelectedFields() {
        let original = Session(
            id: UUID(),
            title: "旧标题",
            createdAt: base,
            updatedAt: base,
            project: "Lichen",
            agentID: UUID(),
            preview: "旧预览",
            messageCount: 2,
            isArchived: false,
            remoteID: "remote-1"
        )
        let before = Date()
        let updated = original.updating(
            title: "新标题",
            preview: "新预览",
            messageCount: 5,
            isArchived: true
        )

        XCTAssertEqual(updated.id, original.id)
        XCTAssertEqual(updated.createdAt, original.createdAt)
        XCTAssertEqual(updated.project, "Lichen")
        XCTAssertEqual(updated.agentID, original.agentID)
        XCTAssertEqual(updated.remoteID, "remote-1")
        XCTAssertEqual(updated.title, "新标题")
        XCTAssertEqual(updated.preview, "新预览")
        XCTAssertEqual(updated.messageCount, 5)
        XCTAssertTrue(updated.isArchived)
        XCTAssertGreaterThanOrEqual(updated.updatedAt, before)
    }

    func testGroupedSessionsOrderAndNilProject() {
        let alphaOld = makeSession(title: "A-old", project: "Alpha", updatedOffset: 10)
        let alphaNew = makeSession(title: "A-new", project: "Alpha", updatedOffset: 20)
        let beta = makeSession(title: "B", project: "Beta", updatedOffset: 30)
        let orphan = makeSession(title: "O", project: nil, updatedOffset: 40)
        let blank = makeSession(title: "Blank", project: "   ", updatedOffset: 50)

        let groups = Session.grouped([alphaOld, orphan, beta, alphaNew, blank])

        XCTAssertEqual(groups.map(\.title), ["Alpha", "Beta", "其他"])
        XCTAssertEqual(groups[0].sessions.map(\.id), [alphaNew.id, alphaOld.id])
        XCTAssertEqual(groups[1].sessions.map(\.id), [beta.id])
        XCTAssertEqual(groups[2].sessions.map(\.id), [blank.id, orphan.id])
        XCTAssertEqual(groups[2].id, "其他")
    }

    // MARK: 事件映射

    func testMessageDeltaAndComplete() {
        let sessionID = UUID()
        let delta = SessionMessage.from(
            event: makeEvent(
                GatewayEventType.messageDelta,
                sessionID: sessionID.uuidString,
                payload: .object(["delta": .string("你好")])
            ),
            defaultSessionID: UUID()
        )
        XCTAssertEqual(delta?.role, .assistant)
        XCTAssertEqual(delta?.text, "你好")
        XCTAssertEqual(delta?.sessionID, sessionID)
        XCTAssertEqual(delta?.isEmphasized, false)

        let complete = SessionMessage.from(
            event: makeEvent(
                GatewayEventType.messageComplete,
                payload: .object([
                    "content": .array([
                        .object(["type": .string("text"), "text": .string("完成")])
                    ])
                ])
            ),
            defaultSessionID: sessionID
        )
        XCTAssertEqual(complete?.role, .assistant)
        XCTAssertEqual(complete?.text, "完成")
        XCTAssertEqual(complete?.sessionID, sessionID)
    }

    func testThinkingAndReasoningDeltasAreEmphasized() {
        let sessionID = UUID()
        for type in [GatewayEventType.thinkingDelta, GatewayEventType.reasoningDelta] {
            let message = SessionMessage.from(
                event: makeEvent(type, payload: .object(["text": .string("思考中")])),
                defaultSessionID: sessionID
            )
            XCTAssertEqual(message?.role, .thinking)
            XCTAssertEqual(message?.text, "思考中")
            XCTAssertEqual(message?.isEmphasized, true)
        }
    }

    func testToolEvents() {
        let sessionID = UUID()
        let start = SessionMessage.from(
            event: makeEvent(
                GatewayEventType.toolStart,
                payload: .object([
                    "tool": .string("shell"),
                    "command": .string("ls -la")
                ])
            ),
            defaultSessionID: sessionID
        )
        XCTAssertEqual(start?.role, .tool)
        XCTAssertEqual(start?.toolName, "shell")
        XCTAssertEqual(start?.text, "ls -la")

        let complete = SessionMessage.from(
            event: makeEvent(
                GatewayEventType.toolComplete,
                payload: .object([
                    "tool": .string("shell"),
                    "output": .string("total 0")
                ])
            ),
            defaultSessionID: sessionID
        )
        XCTAssertEqual(complete?.role, .tool)
        XCTAssertEqual(complete?.toolName, "shell")
        XCTAssertEqual(complete?.text, "total 0")
    }

    func testNoticeAndErrorEvents() {
        let sessionID = UUID()
        let notice = SessionMessage.from(
            event: makeEvent(GatewayEventType.notice, payload: .string("已重连")),
            defaultSessionID: sessionID
        )
        XCTAssertEqual(notice?.role, .system)
        XCTAssertEqual(notice?.text, "已重连")

        let error = SessionMessage.from(
            event: makeEvent(
                GatewayEventType.error,
                payload: .object(["error": .object(["message": .string("连接失败")])])
            ),
            defaultSessionID: sessionID
        )
        XCTAssertEqual(error?.role, .system)
        XCTAssertEqual(error?.text, "连接失败")
    }

    func testEventsWithoutTextReturnNil() {
        let sessionID = UUID()

        let emptyDelta = SessionMessage.from(
            event: makeEvent(GatewayEventType.messageDelta, payload: .object(["delta": .string("")])),
            defaultSessionID: sessionID
        )
        XCTAssertNil(emptyDelta)

        let missingPayload = SessionMessage.from(
            event: makeEvent(GatewayEventType.toolComplete),
            defaultSessionID: sessionID
        )
        XCTAssertNil(missingPayload)

        let unrelated = SessionMessage.from(
            event: makeEvent(GatewayEventType.messageStart, payload: .string("x")),
            defaultSessionID: sessionID
        )
        XCTAssertNil(unrelated)
    }

    func testApprovalRequestMapping() {
        let sessionID = UUID()
        let message = SessionMessage.from(
            event: makeEvent(
                GatewayEventType.approvalRequest,
                sessionID: sessionID.uuidString,
                payload: .object([
                    "request_id": .string("srq-123456789abc"),
                    "command": .string("rm -rf build"),
                    "description": .string("删除构建目录"),
                    "choices": .array([.string("once"), .string("deny")]),
                    "execution_generation": .int(7)
                ]),
                seq: 9
            ),
            defaultSessionID: UUID()
        )

        XCTAssertEqual(message?.role, .approval)
        XCTAssertEqual(message?.sessionID, sessionID)
        XCTAssertEqual(message?.text, "rm -rf build")
        XCTAssertEqual(message?.approval?.requestID, "srq-123456789abc")
        XCTAssertEqual(message?.approval?.sessionID, sessionID)
        XCTAssertEqual(message?.approval?.command, "rm -rf build")
        XCTAssertEqual(message?.approval?.description, "删除构建目录")
        XCTAssertEqual(message?.approval?.choices, [.once, .deny])
        XCTAssertEqual(message?.approval?.executionGeneration, "7")
    }

    func testClarifyRequestMappingFallsBackToSequenceID() {
        let sessionID = UUID()
        let message = SessionMessage.from(
            event: makeEvent(
                GatewayEventType.clarifyRequest,
                payload: .object(["question": .string("继续吗？")]),
                seq: 3,
                executionGeneration: 2
            ),
            defaultSessionID: sessionID
        )

        XCTAssertEqual(message?.role, .approval)
        XCTAssertEqual(message?.text, "继续吗？")
        XCTAssertEqual(message?.approval?.requestID, "seq-3")
        XCTAssertEqual(message?.approval?.command, "")
        XCTAssertEqual(message?.approval?.description, "继续吗？")
        XCTAssertEqual(message?.approval?.choices, ApprovalChoice.allCases)
        XCTAssertEqual(message?.approval?.executionGeneration, "2")
        XCTAssertEqual(message?.approval?.sessionID, sessionID)
    }

    // MARK: 存储

    func testInMemoryStoreCRUDMessagesAndGrouping() async throws {
        let store = InMemorySessionStore()
        let first = try await store.createSession(title: "一")
        var updatedFirst = first.updating(title: "一改", preview: "预览", messageCount: 1)
        updatedFirst.project = "Lichen"
        try await store.update(updatedFirst)

        let second = try await store.createSession(title: "二")

        let listed = try await store.listSessions()
        XCTAssertEqual(listed.map(\.id), [second.id, first.id])

        let message = SessionMessage(
            sessionID: first.id,
            role: .assistant,
            text: "hello",
            createdAt: base
        )
        let later = SessionMessage(
            sessionID: first.id,
            role: .user,
            text: "later",
            createdAt: base.addingTimeInterval(1)
        )
        try await store.append(later)
        try await store.append(message)

        let messages = try await store.messages(sessionID: first.id)
        XCTAssertEqual(messages.map(\.id), [message.id, later.id])

        let groups = try await store.groupedSessions()
        XCTAssertEqual(groups.map(\.title), ["Lichen", "其他"])
        XCTAssertEqual(groups.first?.sessions.first?.id, first.id)

        try await store.deleteSession(id: first.id)
        let remaining = try await store.listSessions()
        XCTAssertEqual(remaining.map(\.id), [second.id])
        let deletedMessages = try await store.messages(sessionID: first.id)
        XCTAssertTrue(deletedMessages.isEmpty)
    }

    func testPersistentStoreWritesAndReadsBack() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LichenTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let firstStore = PersistentSessionStore(directoryURL: directory)
        let session = try await firstStore.createSession(title: "持久会话")
        var updated = session.updating(preview: "最后一条", messageCount: 1)
        updated.project = "工作区"
        try await firstStore.update(updated)

        let message = SessionMessage(
            sessionID: session.id,
            role: .user,
            text: "最后一条",
            createdAt: Date()
        )
        try await firstStore.append(message)

        let fileURL = directory.appendingPathComponent("sessions.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        let data = try Data(contentsOf: fileURL)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertNotNil(json["sessions"])
        XCTAssertNotNil(json["messagesBySession"])

        let secondStore = PersistentSessionStore(directoryURL: directory)
        let sessions = try await secondStore.listSessions()
        XCTAssertEqual(sessions.map(\.id), [session.id])
        XCTAssertEqual(sessions.first?.preview, "最后一条")

        let messages = try await secondStore.messages(sessionID: session.id)
        XCTAssertEqual(messages.map(\.id), [message.id])

        let groups = try await secondStore.groupedSessions()
        XCTAssertEqual(groups.map(\.title), ["工作区"])

        try await secondStore.deleteSession(id: session.id)
        let thirdStore = PersistentSessionStore(directoryURL: directory)
        let emptySessions = try await thirdStore.listSessions()
        XCTAssertTrue(emptySessions.isEmpty)
        let emptyMessages = try await thirdStore.messages(sessionID: session.id)
        XCTAssertTrue(emptyMessages.isEmpty)
    }
}
