import XCTest
import Foundation
@testable import LichenCore

final class JSONRPCTests: XCTestCase {
    private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func text(_ data: Data) -> String {
        String(decoding: data, as: UTF8.self)
    }

    func testJSONValueRoundTripsAllSevenCases() throws {
        let values: [JSONValue] = [
            .string("文本"),
            .int(42),
            .double(3.5),
            .bool(true),
            .null,
            .object(["a": .int(1), "b": .array([.string("x")])]),
            .array([.string("x"), .bool(false), .null])
        ]

        for value in values {
            XCTAssertEqual(try roundTrip(value), value)
        }
    }

    func testJSONValueSubscriptAndComputedAccessors() {
        let value = JSONValue.object([
            "text": .string("hello"),
            "count": .int(7),
            "enabled": .bool(true),
            "items": .array([.int(1), .int(2)])
        ])

        XCTAssertEqual(value["text"]?.stringValue, "hello")
        XCTAssertEqual(value["count"]?.intValue, 7)
        XCTAssertEqual(value["enabled"]?.boolValue, true)
        XCTAssertEqual(value["items"]?.arrayValue?.count, 2)
        XCTAssertNil(value["missing"])
    }

    func testJSONValueStringEscaping() {
        let value = JSONValue.object(["quote": .string("a\"b\nc\\d")])
        XCTAssertEqual(value.jsonString(), #"{"quote":"a\"b\nc\\d"}"#)
    }

    func testJSONRPCIDRoundTrip() throws {
        let identifiers: [JSONRPCID] = [.int(7), .string("srq-0123456789ab")]
        for identifier in identifiers {
            XCTAssertEqual(try roundTrip(identifier), identifier)
        }
    }

    func testRequestResponseAndNotificationRoundTrip() throws {
        let request = JSONRPCRequest(
            id: .int(1),
            method: GatewayMethod.clientCapabilities,
            params: .object(["server_requests": .bool(true)])
        )
        XCTAssertEqual(try roundTrip(request), request)

        let response = JSONRPCResponse(
            id: .string("srq-1"),
            result: .object(["choice": .string("once")])
        )
        XCTAssertEqual(try roundTrip(response), response)

        let notification = JSONRPCNotification(
            method: GatewayMethod.event,
            params: .object(["type": .string(GatewayEventType.gatewayReady)])
        )
        XCTAssertEqual(try roundTrip(notification), notification)
    }

    func testApprovalChoiceLiterals() {
        XCTAssertEqual(ApprovalChoice.allCases.map(\.rawValue), ["once", "session", "always", "deny"])
        for choice in ApprovalChoice.allCases {
            XCTAssertEqual(ApprovalChoice(rawValue: choice.rawValue), choice)
        }
    }

    func testGatewayReadyEventParsing() throws {
        let frame = Data("""
        {"jsonrpc":"2.0","method":"event","params":{"type":"gateway.ready","session_id":"s-1","seq":4,"replay_epoch":"epoch-1","execution_generation":2,"payload":{"heartbeat":true,"replay_epoch":"epoch-1","session_authority":true}}}
        """.utf8)

        let inbound = try GatewayJSONRPCParser.parse(frame)
        guard case .event(let event) = inbound else {
            return XCTFail("期望 event，实际为 \(inbound)")
        }

        XCTAssertEqual(event.type, GatewayEventType.gatewayReady)
        XCTAssertEqual(event.sessionID, "s-1")
        XCTAssertEqual(event.seq, 4)
        XCTAssertEqual(event.replayEpoch, "epoch-1")
        XCTAssertEqual(event.executionGeneration, 2)
        XCTAssertEqual(event.payload?["heartbeat"]?.boolValue, true)
        XCTAssertEqual(event.payload?["session_authority"]?.boolValue, true)
    }

    func testApprovalServerRequestParsing() throws {
        let frame = Data("""
        {"jsonrpc":"2.0","id":"srq-0123456789ab","method":"approval","params":{"session_id":"s-1","request_id":"r-1","command":"rm -rf build","description":"清理构建目录","choices":["once","session","always","deny"],"allow_permanent":true}}
        """.utf8)

        let inbound = try GatewayJSONRPCParser.parse(frame)
        guard case .serverRequest(let request) = inbound else {
            return XCTFail("期望 serverRequest，实际为 \(inbound)")
        }

        XCTAssertEqual(request.id, .string("srq-0123456789ab"))
        XCTAssertEqual(request.method, GatewayMethod.approval)

        let params = try XCTUnwrap(request.approvalParams)
        XCTAssertEqual(params.sessionID, "s-1")
        XCTAssertEqual(params.requestID, "r-1")
        XCTAssertEqual(params.command, "rm -rf build")
        XCTAssertEqual(params.description, "清理构建目录")
        XCTAssertEqual(params.choices, [.once, .session, .always, .deny])
        XCTAssertTrue(params.allowPermanent)
    }

    func testApprovalResponseEchoesSameID() throws {
        let frame = GatewayJSONRPC.approvalRespond(requestID: "srq-0123456789ab", choice: .session)
        XCTAssertTrue(text(frame).hasSuffix("\n"))

        let inbound = try GatewayJSONRPCParser.parse(frame)
        guard case .response(let response) = inbound else {
            return XCTFail("期望 response，实际为 \(inbound)")
        }

        XCTAssertEqual(response.jsonrpc, "2.0")
        XCTAssertEqual(response.id, .string("srq-0123456789ab"))
        XCTAssertEqual(response.result?["choice"]?.stringValue, "session")
        XCTAssertNil(response.error)
    }

    func testPingFrameContents() throws {
        let frame = GatewayJSONRPC.ping(id: .int(9))
        XCTAssertTrue(text(frame).hasSuffix("\n"))

        let request = try JSONDecoder().decode(JSONRPCRequest.self, from: frame)
        XCTAssertEqual(request.jsonrpc, "2.0")
        XCTAssertEqual(request.id, .int(9))
        XCTAssertEqual(request.method, GatewayMethod.ping)
        XCTAssertNil(request.params)
    }

    func testCapabilitiesAdvertisesServerRequests() throws {
        let frame = GatewayJSONRPC.capabilities(id: .int(1))
        let request = try JSONDecoder().decode(JSONRPCRequest.self, from: frame)

        XCTAssertEqual(request.method, GatewayMethod.clientCapabilities)
        XCTAssertEqual(request.params?["server_requests"]?.boolValue, true)
    }

    func testAllRequestFactoriesProduceDecodableFrames() throws {
        let frames: [(Data, String)] = [
            (GatewayJSONRPC.sessionList(id: .int(2), profile: "default"), GatewayMethod.sessionList),
            (GatewayJSONRPC.sessionCreate(id: .int(3), title: "新会话"), GatewayMethod.sessionCreate),
            (GatewayJSONRPC.sessionResume(id: .int(4), sessionID: "s-1"), GatewayMethod.sessionResume),
            (GatewayJSONRPC.promptSubmit(id: .int(5), sessionID: "s-1", text: "你好"), GatewayMethod.promptSubmit),
            (GatewayJSONRPC.approvalRespond(id: .int(6), choice: .always), GatewayMethod.approvalRespond),
            (GatewayJSONRPC.eventsSince(id: .int(7), sessionID: "s-1", lastSeen: 12), GatewayMethod.sessionEventsSince)
        ]

        for (data, expectedMethod) in frames {
            XCTAssertTrue(text(data).hasSuffix("\n"))
            let request = try JSONDecoder().decode(JSONRPCRequest.self, from: data)
            XCTAssertEqual(request.jsonrpc, "2.0")
            XCTAssertEqual(request.method, expectedMethod)
        }

        let list = try JSONDecoder().decode(
            JSONRPCRequest.self,
            from: GatewayJSONRPC.sessionList(id: .int(2), profile: "default")
        )
        XCTAssertEqual(list.params?["profile"]?.stringValue, "default")

        let since = try JSONDecoder().decode(
            JSONRPCRequest.self,
            from: GatewayJSONRPC.eventsSince(id: .int(7), sessionID: "s-1", lastSeen: 12)
        )
        XCTAssertEqual(since.params?["session_id"]?.stringValue, "s-1")
        XCTAssertEqual(since.params?["last_seen"]?.intValue, 12)
    }

    func testUnknownFramesAreClassifiedAsUnknown() throws {
        XCTAssertEqual(try GatewayJSONRPCParser.parse(Data("[]".utf8)), .unknown)
        XCTAssertEqual(try GatewayJSONRPCParser.parse(Data(#"{"jsonrpc":"2.0"}"#.utf8)), .unknown)

        let clientMethod = Data(#"{"jsonrpc":"2.0","id":1,"method":"session.list","params":{}}"#.utf8)
        XCTAssertEqual(try GatewayJSONRPCParser.parse(clientMethod), .unknown)
    }

    func testMalformedFrameThrows() {
        XCTAssertThrowsError(try GatewayJSONRPCParser.parse(Data("{".utf8))) { error in
            guard let gatewayError = error as? GatewayError,
                  case .decoding = gatewayError else {
                return XCTFail("期望 decoding，实际为 \(error)")
            }
        }
    }
}
