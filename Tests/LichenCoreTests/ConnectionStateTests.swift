import XCTest
import Foundation
@testable import LichenCore

final class ConnectionStateTests: XCTestCase {
    private let url = URL(string: "https://example.invalid/prefix")!
    private let info = GatewayInfo(
        version: "1.0.0",
        authRequired: true,
        authProviders: ["cookie"],
        authFlows: ["cookie"],
        gatewayRunning: true,
        activeSessions: 2
    )

    func testLegalTransitionChain() {
        var state = GatewayConnectionState.disconnected
        XCTAssertTrue(state.canTransition(to: .connecting(url)))

        state = state.applying(event: .beginConnect(url))
        XCTAssertEqual(state, .connecting(url))

        state = state.applying(event: .didConnect(info))
        XCTAssertEqual(state, .connected(info))

        state = state.applying(event: .disconnect)
        XCTAssertEqual(state, .disconnected)
    }

    func testFailureAndRetryChain() {
        let connecting = GatewayConnectionState.disconnected.applying(event: .beginConnect(url))
        let failed = connecting.applying(event: .didFail(.timeout))
        XCTAssertEqual(failed, .failed(.timeout))
        XCTAssertTrue(failed.canTransition(to: .connecting(url)))

        let retrying = failed.applying(event: .beginConnect(url))
        XCTAssertEqual(retrying, .connecting(url))
        XCTAssertEqual(retrying.applying(event: .didConnect(info)), .connected(info))
    }

    func testIllegalTransitionsKeepCurrentState() {
        let disconnected = GatewayConnectionState.disconnected
        XCTAssertFalse(disconnected.canTransition(to: .connected(info)))
        XCTAssertEqual(disconnected.applying(event: .didConnect(info)), .disconnected)
        XCTAssertEqual(disconnected.applying(event: .disconnect), .disconnected)
    }

    func testConnectedCanReconnectAndFail() {
        let connected = GatewayConnectionState.connected(info)
        XCTAssertTrue(connected.canTransition(to: .connecting(url)))
        XCTAssertTrue(connected.canTransition(to: .failed(.unreachable("连接中断"))))

        let reconnecting = connected.applying(event: .beginConnect(url))
        XCTAssertEqual(reconnecting, .connecting(url))

        let failed = connected.applying(event: .didFail(.unauthorized))
        XCTAssertEqual(failed, .failed(.unauthorized))
    }

    func testSelfTransitionsAreIdempotent() {
        XCTAssertTrue(GatewayConnectionState.disconnected.canTransition(to: .disconnected))
        XCTAssertTrue(GatewayConnectionState.connecting(url).canTransition(to: .connecting(nil)))
        XCTAssertTrue(GatewayConnectionState.connected(info).canTransition(to: .connected(info)))
        XCTAssertTrue(GatewayConnectionState.failed(.cancelled).canTransition(to: .failed(.cancelled)))
    }

    func testErrorDescriptionsAreNonEmpty() {
        let errors: [GatewayError] = [
            .invalidURL("bad"),
            .unreachable("down"),
            .unauthorized,
            .tlsFailed("cert"),
            .encoding("json"),
            .server(code: 500, message: "boom"),
            .timeout,
            .cancelled,
            .decoding("body")
        ]

        for error in errors {
            XCTAssertFalse(error.errorDescription?.isEmpty ?? true)
        }
    }
}
