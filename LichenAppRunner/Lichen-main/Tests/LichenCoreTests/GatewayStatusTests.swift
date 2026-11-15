import XCTest
import Foundation
@testable import LichenCore

final class GatewayStatusTests: XCTestCase {
    func testDecodesFullStatusWithOAuth() throws {
        let json = """
        {
          "version": "0.4.2",
          "auth_required": true,
          "auth_providers": ["cookie", "native_pkce"],
          "auth_flows": ["cookie"],
          "gateway_running": true,
          "active_sessions": 3,
          "components": {"chat": {"status": "ok"}},
          "overall": "degraded"
        }
        """

        let status = try GatewayStatus.decode(Data(json.utf8))
        XCTAssertEqual(status.version, "0.4.2")
        XCTAssertTrue(status.authRequired)
        XCTAssertEqual(status.authMode, .oauth)
        XCTAssertEqual(status.authProviders, ["cookie", "native_pkce"])
        XCTAssertEqual(status.authFlows, ["cookie"])
        XCTAssertTrue(status.gatewayRunning)
        XCTAssertEqual(status.activeSessions, 3)
        XCTAssertEqual(status.components["chat"]?["status"]?.stringValue, "ok")
        XCTAssertEqual(status.overall, "degraded")

        let info = status.info
        XCTAssertEqual(info.version, "0.4.2")
        XCTAssertTrue(info.authRequired)
        XCTAssertEqual(info.activeSessions, 3)
    }

    func testDecodesMinimalStatusWithDefaults() throws {
        let status = try GatewayStatus.decode(Data("{}".utf8))
        XCTAssertEqual(status.version, "")
        XCTAssertFalse(status.authRequired)
        XCTAssertEqual(status.authMode, .token)
        XCTAssertEqual(status.authProviders, [])
        XCTAssertEqual(status.authFlows, [])
        XCTAssertFalse(status.gatewayRunning)
        XCTAssertEqual(status.activeSessions, 0)
        XCTAssertEqual(status.components.count, 0)
        XCTAssertEqual(status.overall, "")
    }

    func testMalformedFieldsFallBackToDefaults() throws {
        let json = """
        {
          "version": 123,
          "auth_required": "yes",
          "auth_providers": "cookie",
          "active_sessions": "many"
        }
        """

        let status = try GatewayStatus.decode(Data(json.utf8))
        XCTAssertEqual(status.version, "")
        XCTAssertFalse(status.authRequired)
        XCTAssertEqual(status.authProviders, [])
        XCTAssertEqual(status.activeSessions, 0)
    }

    func testInvalidStatusJSONThrowsDecodingError() {
        XCTAssertThrowsError(try GatewayStatus.decode(Data("not-json".utf8))) { error in
            guard let gatewayError = error as? GatewayError,
                  case .decoding = gatewayError else {
                return XCTFail("期望 decoding，实际为 \(error)")
            }
        }
    }

    func testWsTicketDecoding() throws {
        let json = Data(#"{"ticket":"ticket-1","ttl_seconds":30}"#.utf8)
        let ticket = try JSONDecoder().decode(WsTicket.self, from: json)
        XCTAssertEqual(ticket.ticket, "ticket-1")
        XCTAssertEqual(ticket.ttlSeconds, 30)

        let missingTTL = try JSONDecoder().decode(WsTicket.self, from: Data(#"{"ticket":"ticket-2"}"#.utf8))
        XCTAssertEqual(missingTTL.ttlSeconds, 30)
    }
}
