import Foundation

// MARK: - 通用 JSON 值

/// 可承载任意 JSON 结构的类型安全值。
public enum JSONValue: Codable, Sendable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null
    case object([String: JSONValue])
    case array([JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
            return
        }
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
            return
        }
        if let value = try? container.decode(Int.self) {
            self = .int(value)
            return
        }
        if let value = try? container.decode(Double.self) {
            self = .double(value)
            return
        }
        if let value = try? container.decode(String.self) {
            self = .string(value)
            return
        }
        if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
            return
        }
        if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
            return
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "不支持的 JSON 值")
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        }
    }

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var intValue: Int? {
        if case .int(let value) = self { return value }
        return nil
    }

    public var doubleValue: Double? {
        switch self {
        case .double(let value):
            return value
        case .int(let value):
            return Double(value)
        default:
            return nil
        }
    }

    public var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    public var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    public var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    public subscript(key: String) -> JSONValue? {
        objectValue?[key]
    }

    /// 将当前值重新解码为指定 `Decodable` 类型。
    public func decoded<T: Decodable>(as type: T.Type) throws -> T {
        let data: Data
        do {
            data = try JSONEncoder().encode(self)
        } catch {
            throw GatewayError.encoding("JSON 值无法重新编码：\(error.localizedDescription)")
        }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw GatewayError.decoding("JSON 值无法解码为 \(String(describing: type))：\(error.localizedDescription)")
        }
    }

    /// 序列化为紧凑 JSON 文本。
    ///
    /// 非有限浮点按 `null` 输出，保证该方法不抛错；其余值均生成合法 JSON。
    public func jsonString() -> String {
        switch self {
        case .string(let value):
            return Self.quoted(value)
        case .int(let value):
            return String(value)
        case .double(let value):
            return value.isFinite ? String(value) : "null"
        case .bool(let value):
            return value ? "true" : "false"
        case .null:
            return "null"
        case .object(let value):
            let pairs = value.sorted { $0.key < $1.key }.map { entry in
                Self.quoted(entry.key) + ":" + entry.value.jsonString()
            }
            return "{" + pairs.joined(separator: ",") + "}"
        case .array(let value):
            return "[" + value.map { $0.jsonString() }.joined(separator: ",") + "]"
        }
    }
}

private extension JSONValue {
    static func quoted(_ string: String) -> String {
        var result = "\""
        for scalar in string.unicodeScalars {
            switch scalar.value {
            case 0x22:
                result += "\\\""
            case 0x5C:
                result += "\\\\"
            case 0x08:
                result += "\\b"
            case 0x0C:
                result += "\\f"
            case 0x0A:
                result += "\\n"
            case 0x0D:
                result += "\\r"
            case 0x09:
                result += "\\t"
            case 0x00..<0x20:
                result += String(format: "\\u%04x", scalar.value)
            default:
                result.unicodeScalars.append(scalar)
            }
        }
        result += "\""
        return result
    }
}

// MARK: - JSON-RPC 标识

/// JSON-RPC 请求 id，允许整数或字符串。
public enum JSONRPCID: Codable, Sendable, Equatable, Hashable {
    case int(Int)
    case string(String)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Int.self) {
            self = .int(value)
            return
        }
        if let value = try? container.decode(String.self) {
            self = .string(value)
            return
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "JSON-RPC id 必须是整数或字符串")
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .int(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        }
    }

    public init?(jsonValue: JSONValue) {
        switch jsonValue {
        case .int(let value):
            self = .int(value)
        case .string(let value):
            self = .string(value)
        default:
            return nil
        }
    }

    public var jsonValue: JSONValue {
        switch self {
        case .int(let value):
            return .int(value)
        case .string(let value):
            return .string(value)
        }
    }
}

// MARK: - JSON-RPC 报文模型

/// 客户端发起的 JSON-RPC 请求。
public struct JSONRPCRequest: Codable, Sendable, Equatable {
    public var jsonrpc: String
    public var id: JSONRPCID
    public var method: String
    public var params: JSONValue?

    public init(id: JSONRPCID, method: String, params: JSONValue? = nil) {
        self.jsonrpc = "2.0"
        self.id = id
        self.method = method
        self.params = params
    }
}

/// JSON-RPC 错误对象。
public struct JSONRPCError: Codable, Sendable, Equatable {
    public var code: Int
    public var message: String
    public var data: JSONValue?

    public init(code: Int, message: String, data: JSONValue? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }
}

/// JSON-RPC 响应。
public struct JSONRPCResponse: Codable, Sendable, Equatable {
    public var jsonrpc: String
    public var id: JSONRPCID
    public var result: JSONValue?
    public var error: JSONRPCError?

    public init(id: JSONRPCID, result: JSONValue? = nil, error: JSONRPCError? = nil) {
        self.jsonrpc = "2.0"
        self.id = id
        self.result = result
        self.error = error
    }
}

/// 不带 id 的 JSON-RPC 通知（服务端事件固定使用 `method == "event"`）。
public struct JSONRPCNotification: Codable, Sendable, Equatable {
    public var jsonrpc: String
    public var method: String
    public var params: JSONValue?

    public init(method: String = GatewayMethod.event, params: JSONValue? = nil) {
        self.jsonrpc = "2.0"
        self.method = method
        self.params = params
    }
}

/// `event` 通知的 params 载荷。
public struct GatewayEventEnvelope: Codable, Sendable, Equatable {
    public var type: String
    public var sessionID: String?
    public var payload: JSONValue?
    public var seq: Int?
    public var replayEpoch: String?
    public var executionGeneration: Int?

    public init(
        type: String,
        sessionID: String? = nil,
        payload: JSONValue? = nil,
        seq: Int? = nil,
        replayEpoch: String? = nil,
        executionGeneration: Int? = nil
    ) {
        self.type = type
        self.sessionID = sessionID
        self.payload = payload
        self.seq = seq
        self.replayEpoch = replayEpoch
        self.executionGeneration = executionGeneration
    }

    enum CodingKeys: String, CodingKey {
        case type
        case sessionID = "session_id"
        case payload
        case seq
        case replayEpoch = "replay_epoch"
        case executionGeneration = "execution_generation"
    }
}

/// 审批选项，字面量与协议一致。
public enum ApprovalChoice: String, Codable, CaseIterable, Sendable {
    case once
    case session
    case always
    case deny
}

/// 审批请求参数，同时兼容 canonical 事件与直接服务端请求。
public struct ApprovalRequestParams: Codable, Sendable, Equatable {
    public var sessionID: String?
    public var requestID: String?
    public var promptID: String?
    public var executionGeneration: Int?
    public var command: String?
    public var description: String?
    public var choices: [ApprovalChoice]
    public var allowPermanent: Bool

    public init(
        sessionID: String? = nil,
        requestID: String? = nil,
        promptID: String? = nil,
        executionGeneration: Int? = nil,
        command: String? = nil,
        description: String? = nil,
        choices: [ApprovalChoice] = ApprovalChoice.allCases,
        allowPermanent: Bool = false
    ) {
        self.sessionID = sessionID
        self.requestID = requestID
        self.promptID = promptID
        self.executionGeneration = executionGeneration
        self.command = command
        self.description = description
        self.choices = choices
        self.allowPermanent = allowPermanent
    }

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case requestID = "request_id"
        case promptID = "prompt_id"
        case executionGeneration = "execution_generation"
        case command
        case description
        case choices
        case allowPermanent = "allow_permanent"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try? container.decodeIfPresent(String.self, forKey: .sessionID)
        requestID = try? container.decodeIfPresent(String.self, forKey: .requestID)
        promptID = try? container.decodeIfPresent(String.self, forKey: .promptID)
        executionGeneration = try? container.decodeIfPresent(Int.self, forKey: .executionGeneration)
        command = try? container.decodeIfPresent(String.self, forKey: .command)
        description = try? container.decodeIfPresent(String.self, forKey: .description)

        let rawChoices = (try? container.decodeIfPresent([String].self, forKey: .choices)) ?? []
        let mapped = rawChoices.compactMap(ApprovalChoice.init(rawValue:))
        choices = mapped.isEmpty ? ApprovalChoice.allCases : mapped
        allowPermanent = (try? container.decodeIfPresent(Bool.self, forKey: .allowPermanent)) ?? false
    }
}

/// 服务端发往客户端的请求（`approval` / `clarify`）。
public struct ServerRequest: Codable, Sendable, Equatable {
    public var jsonrpc: String
    public var id: JSONRPCID
    public var method: String
    public var params: JSONValue?

    public init(id: JSONRPCID, method: String, params: JSONValue? = nil) {
        self.jsonrpc = "2.0"
        self.id = id
        self.method = method
        self.params = params
    }

    /// 仅当方法为 `approval` 时解析审批参数。
    public var approvalParams: ApprovalRequestParams? {
        guard method == GatewayMethod.approval, let params = params else { return nil }
        return try? params.decoded(as: ApprovalRequestParams.self)
    }
}

/// 审批应答结果体。
public struct ApprovalResult: Codable, Sendable, Equatable {
    public var choice: ApprovalChoice

    public init(choice: ApprovalChoice) {
        self.choice = choice
    }
}

// MARK: - 协议常量

/// 服务端事件名常量。
public enum GatewayEventType {
    public static let gatewayReady = "gateway.ready"
    public static let messageStart = "message.start"
    public static let messageDelta = "message.delta"
    public static let messageComplete = "message.complete"
    public static let thinkingDelta = "thinking.delta"
    public static let reasoningDelta = "reasoning.delta"
    public static let reasoningAvailable = "reasoning.available"
    public static let statusUpdate = "status.update"
    public static let sessionInfo = "session.info"
    public static let sessionTitle = "session.title"
    public static let sessionUsage = "session.usage"
    public static let sessionsChanged = "sessions.changed"
    public static let toolStart = "tool.start"
    public static let toolGenerating = "tool.generating"
    public static let toolProgress = "tool.progress"
    public static let toolComplete = "tool.complete"
    public static let agentPrint = "agent.print"
    public static let agentTerminalOutput = "agent.terminal.output"
    public static let approvalCancelled = "approval.cancelled"
    public static let approvalRequest = "approval.request"
    public static let clarifyRequest = "clarify.request"
    public static let requestCancel = "request.cancel"
    public static let error = "error"
    public static let notice = "notice"
    public static let todoUpdated = "todo.updated"

    public static let all: [String] = [
        gatewayReady,
        messageStart,
        messageDelta,
        messageComplete,
        thinkingDelta,
        reasoningDelta,
        reasoningAvailable,
        statusUpdate,
        sessionInfo,
        sessionTitle,
        sessionUsage,
        sessionsChanged,
        toolStart,
        toolGenerating,
        toolProgress,
        toolComplete,
        agentPrint,
        agentTerminalOutput,
        approvalCancelled,
        approvalRequest,
        clarifyRequest,
        requestCancel,
        error,
        notice,
        todoUpdated
    ]
}

/// 客户端方法名常量。
public enum GatewayMethod {
    public static let clientCapabilities = "client.capabilities"
    public static let ping = "gateway.ping"
    public static let sessionCreate = "session.create"
    public static let sessionList = "session.list"
    public static let sessionResume = "session.resume"
    public static let sessionActivate = "session.activate"
    public static let promptSubmit = "prompt.submit"
    public static let sessionInterrupt = "session.interrupt"
    public static let sessionHistory = "session.history"
    public static let sessionEventsSince = "session.events.since"
    public static let approvalPending = "approval.pending"
    public static let approvalRespond = "approval.respond"

    // Hermes 已登记：模型目录查询
    public static let modelOptions = "model.options"

    // Hermes 已登记：会话中切模型 / 推理强度 / 快速档
    public static let configSet = "config.set"

    /// 通知帧的方法名。
    public static let event = "event"
    /// 服务端直接请求的审批方法名。
    public static let approval = "approval"
    /// 服务端直接请求的澄清方法名。
    public static let clarify = "clarify"
}

// MARK: - 出站帧工厂

/// 生成换行分隔的 JSON-RPC 文本帧（末尾始终追加 `\n`）。
public enum GatewayJSONRPC {
    public static func ping(id: JSONRPCID) -> Data {
        frame(requestObject(id: id, method: GatewayMethod.ping))
    }

    public static func capabilities(id: JSONRPCID) -> Data {
        frame(requestObject(
            id: id,
            method: GatewayMethod.clientCapabilities,
            params: .object(["server_requests": .bool(true)])
        ))
    }

    public static func sessionList(id: JSONRPCID, profile: String? = nil) -> Data {
        var params: [String: JSONValue] = [:]
        if let profile = profile {
            params["profile"] = .string(profile)
        }
        return frame(requestObject(id: id, method: GatewayMethod.sessionList, params: .object(params)))
    }

    public static func sessionCreate(
        id: JSONRPCID,
        source: String = "local",
        model: String? = nil,
        provider: String? = nil,
        reasoningEffort: String? = nil
    ) -> Data {
        var params: [String: JSONValue] = [
            "source": .string(source)
        ]

        if let model, !model.isEmpty {
            params["model"] = .string(model)
        }

        if let provider, !provider.isEmpty {
            params["provider"] = .string(provider)
        }

        if let reasoningEffort, !reasoningEffort.isEmpty {
            params["reasoning_effort"] = .string(reasoningEffort)
        }

        return frame(requestObject(
            id: id,
            method: GatewayMethod.sessionCreate,
            params: .object(params)
        ))
    }

    public static func sessionResume(id: JSONRPCID, sessionID: String) -> Data {
        frame(requestObject(
            id: id,
            method: GatewayMethod.sessionResume,
            params: .object(["session_id": .string(sessionID)])
        ))
    }

    public static func promptSubmit(
        id: JSONRPCID,
        sessionID: String,
        text: String
    ) -> Data {
        frame(requestObject(
            id: id,
            method: GatewayMethod.promptSubmit,
            params: .object([
                "session_id": .string(sessionID),
                "text": .string(text)
            ])
        ))
    }

    public static func configSetModel(
        id: JSONRPCID,
        sessionID: String,
        model: String,
        confirmExpensiveModel: Bool = false
    ) -> Data {
        frame(requestObject(
            id: id,
            method: GatewayMethod.configSet,
            params: .object([
                "key": .string("model"),
                "value": .string(model),
                "session_id": .string(sessionID),
                "confirm_expensive_model": .bool(confirmExpensiveModel)
            ])
        ))
    }

    public static func configSetReasoning(
        id: JSONRPCID,
        sessionID: String,
        value: String
    ) -> Data {
        frame(requestObject(
            id: id,
            method: GatewayMethod.configSet,
            params: .object([
                "key": .string("reasoning"),
                "value": .string(value),
                "session_id": .string(sessionID)
            ])
        ))
    }

    /// canonical 网关审批：以 `approval.respond` 方法发送请求。
    public static func approvalRespond(id: JSONRPCID, choice: ApprovalChoice) -> Data {
        frame(requestObject(
            id: id,
            method: GatewayMethod.approvalRespond,
            params: .object(["choice": .string(choice.rawValue)])
        ))
    }

    /// 直接服务端请求：用同一 id 回送 JSON-RPC 响应帧。
    public static func approvalRespond(requestID: JSONRPCID, choice: ApprovalChoice) -> Data {
        frame(responseObject(id: requestID, result: .object([
            "choice": .string(choice.rawValue)
        ])))
    }

    /// 字符串 id 便利重载（服务端请求 id 形如 `srq-<12hex>`）。
    public static func approvalRespond(requestID: String, choice: ApprovalChoice) -> Data {
        approvalRespond(requestID: JSONRPCID.string(requestID), choice: choice)
    }

    public static func eventsSince(id: JSONRPCID, sessionID: String, lastSeen: Int) -> Data {
        frame(requestObject(
            id: id,
            method: GatewayMethod.sessionEventsSince,
            params: .object([
                "session_id": .string(sessionID),
                "last_seen": .int(lastSeen)
            ])
        ))
    }
}

private extension GatewayJSONRPC {
    static func requestObject(
        id: JSONRPCID,
        method: String,
        params: JSONValue? = nil
    ) -> [String: JSONValue] {
        var object: [String: JSONValue] = [
            "jsonrpc": .string("2.0"),
            "id": id.jsonValue,
            "method": .string(method)
        ]
        if let params = params {
            object["params"] = params
        }
        return object
    }

    static func responseObject(id: JSONRPCID, result: JSONValue) -> [String: JSONValue] {
        [
            "jsonrpc": .string("2.0"),
            "id": id.jsonValue,
            "result": result
        ]
    }

    static func frame(_ object: [String: JSONValue]) -> Data {
        Data((JSONValue.object(object).jsonString() + "\n").utf8)
    }
}

// MARK: - 入站帧解析

/// 解析后的入站帧。
public enum GatewayInbound: Equatable, Sendable {
    case response(JSONRPCResponse)
    case event(GatewayEventEnvelope)
    case serverRequest(ServerRequest)
    case unknown
}

/// JSON-RPC 入站帧解析器。
public enum GatewayJSONRPCParser {
    /// 解析一个换行分隔文本帧。
    ///
    /// 判定规则：
    /// - `method == "event"` → 事件；
    /// - 有 `id` 与 `method`，且方法为 `approval` / `clarify` → 服务端请求；
    /// - 有 `id` 无 `method` → 响应；
    /// - 其余 → `.unknown`。
    public static func parse(_ data: Data) throws -> GatewayInbound {
        let value: JSONValue
        do {
            value = try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            throw GatewayError.decoding("JSON-RPC 帧不是合法 JSON：\(error.localizedDescription)")
        }

        guard case .object(let object) = value else {
            return .unknown
        }

        let method = object["method"]?.stringValue
        let id = object["id"].flatMap { JSONRPCID(jsonValue: $0) }

        if method == GatewayMethod.event {
            guard let params = object["params"], params.objectValue != nil else {
                throw GatewayError.decoding("event 帧缺少对象形态的 params")
            }
            do {
                return .event(try params.decoded(as: GatewayEventEnvelope.self))
            } catch {
                throw GatewayError.decoding("event params 解码失败：\(error.localizedDescription)")
            }
        }

        if let id = id, let method = method {
            if method == GatewayMethod.approval || method == GatewayMethod.clarify {
                return .serverRequest(ServerRequest(id: id, method: method, params: object["params"]))
            }
            return .unknown
        }

        if id != nil, method == nil {
            do {
                return .response(try JSONDecoder().decode(JSONRPCResponse.self, from: data))
            } catch {
                throw GatewayError.decoding("JSON-RPC 响应解码失败：\(error.localizedDescription)")
            }
        }

        return .unknown
    }
}
