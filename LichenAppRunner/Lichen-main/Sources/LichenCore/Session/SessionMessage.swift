import Foundation

/// 会话消息的角色，决定视图中的字体与排版。
public enum MessageRole: String, Codable, Sendable {
    case user
    case assistant
    case thinking
    case tool
    case system
    case approval
}

public enum MessageDelivery: String, Codable, Sendable {
    case sending
    case sent
    case failed
}

/// 一条会话消息。
///
/// `isEmphasized` 对应原型里「正常字重 + 粗体区分思考与输出」：思考类消息使用粗体。
public struct SessionMessage: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public let sessionID: UUID
    public let role: MessageRole
    public var text: String
    public let createdAt: Date
    public var isEmphasized: Bool
    /// 工具类消息对应的工具名。
    public var toolName: String?
    /// 审批类消息附带的卡片数据。
    public var approval: ApprovalCard?
    public var delivery: MessageDelivery?

    public init(
        id: UUID = UUID(),
        sessionID: UUID,
        role: MessageRole,
        text: String,
        createdAt: Date = Date(),
        isEmphasized: Bool = false,
        toolName: String? = nil,
        approval: ApprovalCard? = nil,
        delivery: MessageDelivery? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.role = role
        self.text = text
        self.createdAt = createdAt
        self.isEmphasized = isEmphasized
        self.toolName = toolName
        self.approval = approval
        self.delivery = delivery
    }

    /// 把网关事件映射为可展示的消息。
    ///
    /// 只处理文本类与审批类事件；没有可用文本、或事件与消息无关时返回 `nil`。
    /// `event.sessionID` 能解析为 UUID 时优先使用，否则回退到 `defaultSessionID`。
    public static func from(
        event: GatewayEventEnvelope,
        defaultSessionID: UUID
    ) -> SessionMessage? {
        let sessionID = resolvedSessionID(for: event, fallback: defaultSessionID)

        switch event.type {
        case GatewayEventType.messageDelta, GatewayEventType.messageComplete:
            guard let text = extractedText(from: event.payload) else { return nil }
            return SessionMessage(sessionID: sessionID, role: .assistant, text: text)

        case GatewayEventType.thinkingDelta, GatewayEventType.reasoningDelta:
            guard let text = extractedText(from: event.payload) else { return nil }
            return SessionMessage(
                sessionID: sessionID,
                role: .thinking,
                text: text,
                isEmphasized: true
            )

        case GatewayEventType.toolStart, GatewayEventType.toolComplete:
            let name = toolName(from: event.payload)
            let text = extractedText(from: event.payload) ?? name
            guard let text = text, !text.isEmpty else { return nil }
            return SessionMessage(
                sessionID: sessionID,
                role: .tool,
                text: text,
                toolName: name
            )

        case GatewayEventType.notice:
            guard let text = extractedText(from: event.payload) else { return nil }
            return SessionMessage(sessionID: sessionID, role: .system, text: text)

        case GatewayEventType.error:
            guard let text = extractedText(from: event.payload) else { return nil }
            return SessionMessage(sessionID: sessionID, role: .system, text: text)

        case GatewayEventType.approvalRequest, GatewayEventType.clarifyRequest:
            return approvalMessage(for: event, sessionID: sessionID)

        default:
            return nil
        }
    }
}

/// 审批卡片：命令、说明与可选答复。
public struct ApprovalCard: Equatable, Codable, Sendable {
    /// 服务端请求 id，或 canonical 事件里的 `prompt_id`。
    public let requestID: String
    public let sessionID: UUID?
    public let command: String
    public let description: String
    public let choices: [ApprovalChoice]
    /// 网关执行代次；事件里是整数，卡片侧统一存字符串。
    public let executionGeneration: String?

    public init(
        requestID: String,
        sessionID: UUID? = nil,
        command: String,
        description: String,
        choices: [ApprovalChoice] = ApprovalChoice.allCases,
        executionGeneration: String? = nil
    ) {
        self.requestID = requestID
        self.sessionID = sessionID
        self.command = command
        self.description = description
        self.choices = choices
        self.executionGeneration = executionGeneration
    }
}

private extension SessionMessage {
    static func resolvedSessionID(
        for event: GatewayEventEnvelope,
        fallback: UUID
    ) -> UUID {
        guard let raw = event.sessionID, let parsed = UUID(uuidString: raw) else {
            return fallback
        }
        return parsed
    }

    /// 从事件载荷中抽取可展示文本。
    ///
    /// 兼容字符串载荷、`content` 文本块数组以及常见字段名；空白字符串视为无文本。
    static func extractedText(from value: JSONValue?) -> String? {
        guard let value = value else { return nil }

        switch value {
        case .string(let text):
            return text.isEmpty ? nil : text
        case .int(let number):
            return String(number)
        case .double(let number):
            return String(number)
        case .bool(let flag):
            return flag ? "true" : "false"
        case .null:
            return nil
        case .array(let items):
            let parts = items.compactMap { extractedText(from: $0) }
            return parts.isEmpty ? nil : parts.joined()
        case .object(let object):
            let keys = [
                "text", "delta", "content", "message", "output",
                "result", "summary", "command", "description", "error"
            ]
            for key in keys {
                if let text = extractedText(from: object[key]) {
                    return text
                }
            }
            return nil
        }
    }

    /// 读取工具名，兼容 `tool` 字符串与 `tool.name` 对象形态。
    static func toolName(from payload: JSONValue?) -> String? {
        guard let object = payload?.objectValue else { return nil }

        if let value = object["tool"] {
            if let name = value.stringValue, !name.isEmpty {
                return name
            }
            if let name = value["name"]?.stringValue, !name.isEmpty {
                return name
            }
        }
        for key in ["tool_name", "name"] {
            if let name = object[key]?.stringValue, !name.isEmpty {
                return name
            }
        }
        return nil
    }

    static func approvalMessage(
        for event: GatewayEventEnvelope,
        sessionID: UUID
    ) -> SessionMessage {
        var fields = event.payload?.objectValue ?? [:]
        for nestingKey in ["approval", "clarify", "request"] {
            if let nested = fields[nestingKey]?.objectValue {
                for (key, value) in nested {
                    fields[key] = value
                }
            }
        }

        let requestID = firstString(
            in: fields,
            keys: ["request_id", "requestID", "prompt_id", "promptID", "id"]
        ) ?? event.seq.map { "seq-\($0)" }
            ?? "\(event.type)-\(sessionID.uuidString)"

        let command = firstString(
            in: fields,
            keys: ["command", "tool", "tool_name"]
        ) ?? ""
        let description = firstString(
            in: fields,
            keys: ["description", "question", "prompt", "text"]
        ) ?? ""

        let executionGeneration: String?
        if let generation = event.executionGeneration {
            executionGeneration = String(generation)
        } else {
            executionGeneration = firstString(in: fields, keys: ["execution_generation"])
        }

        let card = ApprovalCard(
            requestID: requestID,
            sessionID: sessionID,
            command: command,
            description: description,
            choices: approvalChoices(from: fields["choices"]),
            executionGeneration: executionGeneration
        )

        let text: String
        if !command.isEmpty {
            text = command
        } else if !description.isEmpty {
            text = description
        } else {
            text = "需要审批"
        }

        return SessionMessage(
            sessionID: sessionID,
            role: .approval,
            text: text,
            approval: card
        )
    }

    static func firstString(in fields: [String: JSONValue], keys: [String]) -> String? {
        for key in keys {
            guard let value = fields[key] else { continue }
            if let text = value.stringValue, !text.isEmpty {
                return text
            }
            if let number = value.intValue {
                return String(number)
            }
        }
        return nil
    }

    /// 归一化审批选项；未知或缺失时回退到全部选项。
    static func approvalChoices(from value: JSONValue?) -> [ApprovalChoice] {
        guard let items = value?.arrayValue else { return ApprovalChoice.allCases }

        var result: [ApprovalChoice] = []
        for item in items {
            let raw: String?
            if let text = item.stringValue {
                raw = text
            } else {
                raw = item["value"]?.stringValue
                    ?? item["choice"]?.stringValue
                    ?? item["id"]?.stringValue
            }
            guard let raw = raw,
                  let choice = ApprovalChoice(rawValue: raw),
                  !result.contains(choice) else { continue }
            result.append(choice)
        }
        return result.isEmpty ? ApprovalChoice.allCases : result
    }
}
