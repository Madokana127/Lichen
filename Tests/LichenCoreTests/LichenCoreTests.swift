import XCTest
import Foundation
@testable import LichenCore

// TODO: 后续任务替换为真实单元测试（状态机迁移、会话生命周期、网关同步等）。
final class LichenCoreTests: XCTestCase {
    func testDisconnectedStateCanBeConstructed() {
        let state = GatewayConnectionState.disconnected
        XCTAssertEqual(state, .disconnected)
        XCTAssertNotEqual(state, .connected)
    }

    func testSessionDefaultValues() {
        let before = Date()
        let session = Session(title: "未命名会话")
        let after = Date()

        XCTAssertEqual(session.title, "未命名会话")
        XCTAssertGreaterThanOrEqual(session.createdAt, before)
        XCTAssertLessThanOrEqual(session.createdAt, after)
    }
}
