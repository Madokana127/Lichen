import XCTest
import Foundation
@testable import LichenCore

final class LichenCoreTests: XCTestCase {
    func testSessionDefaultValues() {
        let before = Date()
        let session = Session(title: "未命名会话")
        let after = Date()

        XCTAssertEqual(session.title, "未命名会话")
        XCTAssertGreaterThanOrEqual(session.createdAt, before)
        XCTAssertLessThanOrEqual(session.createdAt, after)
    }

    func testBoundedTerminalBufferTrimsOldestLines() {
        let buffer = BoundedTerminalBuffer(capacity: 2)
        buffer.append("a\nb\nc")

        XCTAssertEqual(buffer.capacity, 2)
        XCTAssertEqual(buffer.lines, ["b", "c"])
        XCTAssertEqual(buffer.snapshot, "b\nc")
    }

    func testBoundedTerminalBufferAppendsRawData() async {
        let buffer = BoundedTerminalBuffer(capacity: 3)
        await buffer.append(Data("one\ntwo".utf8))

        XCTAssertEqual(buffer.lines, ["one", "two"])
        XCTAssertEqual(buffer.snapshot, "one\ntwo")
    }

    func testInMemorySessionStoreLifecycle() async throws {
        let store = InMemorySessionStore()
        let created = try await store.createSession(title: "会话")

        let listed = try await store.listSessions()
        XCTAssertEqual(listed.map(\.id), [created.id])

        try await store.deleteSession(id: created.id)
        let empty = try await store.listSessions()
        XCTAssertTrue(empty.isEmpty)
    }
}
