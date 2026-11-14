import XCTest
import Foundation
@testable import LichenCore

final class GatewayConfigurationTests: XCTestCase {
    func testMissingSchemeUsesHTTPForGateway() throws {
        let configuration = GatewayConfiguration(
            displayName: "网关",
            host: "example.invalid",
            port: 9119,
            method: .gateway
        )

        let url = try configuration.normalizedBaseURL()
        XCTAssertEqual(url.scheme, "http")
        XCTAssertEqual(url.host, "example.invalid")
        XCTAssertEqual(url.port, 9119)
        XCTAssertEqual(url.path, "")
    }

    func testMissingSchemeUsesHTTPSForSSL() throws {
        let configuration = GatewayConfiguration(
            displayName: "TLS 网关",
            host: "example.invalid",
            port: 443,
            method: .ssl
        )

        let url = try configuration.normalizedBaseURL()
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.port, 443)
    }

    func testPathPrefixAndQueryFragmentAreNormalized() throws {
        let configuration = GatewayConfiguration(
            displayName: "带前缀",
            host: "https://example.invalid/gateway/prefix/?a=1#section",
            method: .ssl
        )

        let url = try configuration.normalizedBaseURL()
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "example.invalid")
        XCTAssertEqual(url.path, "/gateway/prefix")
        XCTAssertNil(url.query)
        XCTAssertNil(url.fragment)
    }

    func testExplicitURLPortWinsOverConfiguredPort() throws {
        let configuration = GatewayConfiguration(
            displayName: "端口覆盖",
            host: "example.invalid:8443",
            port: 9119,
            method: .gateway
        )

        let url = try configuration.normalizedBaseURL()
        XCTAssertEqual(url.port, 8443)
    }

    func testNonHTTPSchemeThrows() {
        let configuration = GatewayConfiguration(
            displayName: "非法协议",
            host: "ftp://example.invalid",
            method: .gateway
        )

        XCTAssertThrowsError(try configuration.normalizedBaseURL()) { error in
            guard let gatewayError = error as? GatewayError,
                  case .invalidURL = gatewayError else {
                return XCTFail("期望 invalidURL，实际为 \(error)")
            }
        }
    }

    func testEmptyHostAndInvalidPortThrow() {
        let emptyHost = GatewayConfiguration(displayName: "空", host: "   ")
        XCTAssertThrowsError(try emptyHost.validate())

        let invalidPort = GatewayConfiguration(displayName: "端口", host: "example.invalid", port: 70_000)
        XCTAssertThrowsError(try invalidPort.validate())
    }

    func testWebSocketSchemeAndPathDerivation() throws {
        let gateway = GatewayConfiguration(
            displayName: "明文",
            host: "example.invalid/base/",
            port: 9119,
            method: .gateway
        )
        let gatewayWS = try gateway.webSocketURL(credential: "token-value")
        XCTAssertEqual(gatewayWS.scheme, "ws")
        XCTAssertEqual(gatewayWS.host, "example.invalid")
        XCTAssertEqual(gatewayWS.port, 9119)
        XCTAssertEqual(gatewayWS.path, "/base/api/ws")

        let ssl = GatewayConfiguration(
            displayName: "TLS",
            host: "https://example.invalid/base",
            method: .ssl
        )
        let sslWS = try ssl.webSocketURL(credential: "ticket-value", isTicket: true)
        XCTAssertEqual(sslWS.scheme, "wss")
        XCTAssertEqual(sslWS.path, "/base/api/ws")
    }

    func testCredentialIsPercentEncoded() throws {
        let configuration = GatewayConfiguration(
            displayName: "编码",
            host: "example.invalid",
            method: .gateway
        )

        let credential = "a b&c/d?e=f+g@~"
        let tokenURL = try configuration.webSocketURL(credential: credential)
        let tokenComponents = try XCTUnwrap(URLComponents(url: tokenURL, resolvingAgainstBaseURL: false))
        XCTAssertEqual(tokenComponents.percentEncodedQuery, "token=a%20b%26c%2Fd%3Fe%3Df%2Bg%40~")

        let ticketURL = try configuration.webSocketURL(credential: credential, isTicket: true)
        let ticketComponents = try XCTUnwrap(URLComponents(url: ticketURL, resolvingAgainstBaseURL: false))
        XCTAssertEqual(ticketComponents.percentEncodedQuery, "ticket=a%20b%26c%2Fd%3Fe%3Df%2Bg%40~")
    }

    func testRESTHeadersFollowAuthMode() {
        let tokenConfiguration = GatewayConfiguration(
            displayName: "token",
            host: "example.invalid",
            authMode: .token
        )
        XCTAssertEqual(
            tokenConfiguration.restHeaders(token: "abc"),
            ["X-Hermes-Session-Token": "abc"]
        )
        XCTAssertEqual(tokenConfiguration.restHeaders(token: nil), [:])

        let oauthConfiguration = GatewayConfiguration(
            displayName: "oauth",
            host: "example.invalid",
            authMode: .oauth
        )
        XCTAssertEqual(
            oauthConfiguration.restHeaders(token: "abc"),
            ["Authorization": "Bearer abc"]
        )
    }

    func testDerivedEndpointURLs() throws {
        let configuration = GatewayConfiguration(
            displayName: "端点",
            host: "https://example.invalid/prefix/",
            method: .ssl
        )

        XCTAssertEqual(try configuration.statusURL().path, "/prefix/api/status")
        XCTAssertEqual(try configuration.wsTicketURL().path, "/prefix/api/auth/ws-ticket")
        XCTAssertEqual(try configuration.authMEURL().path, "/prefix/api/auth/me")
    }

    func testConfigurationStorePersistsAndManagesCurrent() throws {
        let suiteName = "lichen.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let key = "configurations"
        let store = GatewayConfigurationStore(defaults: defaults, storageKey: key)
        let first = GatewayConfiguration(displayName: "A", host: "a.example.invalid")
        let second = GatewayConfiguration(displayName: "B", host: "b.example.invalid")

        store.add(first)
        store.add(second)
        XCTAssertEqual(store.configurations.count, 2)
        XCTAssertEqual(store.current?.id, first.id)
        XCTAssertTrue(store.setCurrent(id: second.id))
        XCTAssertEqual(store.current?.id, second.id)

        var updated = second
        updated.displayName = "B2"
        XCTAssertTrue(store.update(updated))

        let reloaded = GatewayConfigurationStore(defaults: defaults, storageKey: key)
        XCTAssertEqual(reloaded.current?.id, second.id)
        XCTAssertEqual(reloaded.configurations.count, 2)
        XCTAssertEqual(reloaded.current?.displayName, "B2")

        XCTAssertTrue(reloaded.remove(id: first.id))
        XCTAssertFalse(reloaded.remove(id: first.id))
        XCTAssertEqual(reloaded.current?.id, second.id)
    }
}
