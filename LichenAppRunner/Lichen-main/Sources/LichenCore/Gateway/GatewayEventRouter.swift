import Foundation

/// 网关事件的高层语义。
///
/// UI 层只依赖这些语义事件，避免直接解析 JSON-RPC 载荷或散落事件名字符串。
public enum GatewaySemanticEvent: Sendable, Equatable {
    /// 助手正文增量。
    case messageDelta(text: String, sessionID: String?)
    /// 思考/推理增量。
    case thinkingDelta(text: String, sessionID: String?)
    /// 一条助手消息完成。
    case messageComplete(text: String, sessionID: String?)
    /// 会话元信息（`session.info` / `session.title` / `session.usage`）。
    case sessionInfo(sessionID: String?, payload: JSONValue?)
    /// 会话列表发生变化。
    case sessionsChanged(sessionID: String?)
    /// 工具或终端输出。
    case toolOutput(toolName: String?, text: String?, sessionID: String?)
    /// 需要用户审批（canonical 事件）。
    case approvalRequest(params: ApprovalRequestParams?, requestID: String?, sessionID: String?)
    /// 审批被服务端取消（`approval.cancelled` / `request.cancel`）。
    case approvalCancelled(requestID: String?, sessionID: String?)
    /// 会话状态刷新。
    case statusUpdate(payload: JSONValue?)
    /// 普通通知或错误提示。
    case notice(text: String?)
    /// 与 UI 无关或暂未支持的事件。
    case ignored
}

/// 把 `GatewayEventEnvelope` 归类为 `GatewaySemanticEvent` 的纯函数路由。
public enum GatewayEventRouter {
    /// 归类一个事件；未知类型返回 `.ignored`。
    public static func classify(_ envelope: GatewayEventEnvelope) -> GatewaySemanticEvent {
        let text = extractedText(from: envelope.payload)

        switch envelope.type {
        case GatewayEventType.messageDelta:
            return .messageDelta(text: text ?? "", sessionID: envelope.sessionID)

        case GatewayEventType.thinkingDelta, GatewayEventType.reasoningDelta:
            return .thinkingDelta(text: text ?? "", sessionID: envelope.sessionID)

        case GatewayEventType.messageComplete:
            return .messageComplete(text: text ?? "", sessionID: envelope.sessionID)

        case GatewayEventType.sessionInfo,
             GatewayEventType.sessionTitle,
             GatewayEventType.sessionUsage:
            return .sessionInfo(sessionID: envelope.sessionID, payload: envelope.payload)

        case GatewayEventType.sessionsChanged:
            return .sessionsChanged(sessionID: envelope.sessionID)

        case GatewayEventType.toolStart,
             GatewayEventType.toolGenerating,
             GatewayEventType.toolProgress,
             GatewayEventType.toolComplete,
             GatewayEventType.agentPrint,
             GatewayEventType.agentTerminalOutput:
            return .toolOutput(
                toolName: toolName(from: envelope.payload),
                text: text,
                sessionID: envelope.sessionID
            )

        case GatewayEventType.approvalRequest, GatewayEventType.clarifyRequest:
            let fields = flattenedFields(from: envelope.payload)
            return .approvalRequest(
                params: params(from: fields),
                requestID: firstString(in: fields, keys: requestIDKeys),
                sessionID: envelope.sessionID
            )

        case GatewayEventType.approvalCancelled, GatewayEventType.requestCancel:
            let fields = flattenedFields(from: envelope.payload)
            return .approvalCancelled(
                requestID: firstString(in: fields, keys: requestIDKeys),
                sessionID: envelope.sessionID
            )

        case GatewayEventType.statusUpdate:
            return .statusUpdate(payload: envelope.payload)

        case GatewayEventType.notice, GatewayEventType.error:
            return .notice(text: text)

        default:
            return .ignored
        }
    }
}

private extension GatewayEventRouter {
    static let requestIDKeys = [
        "request_id", "requestID", "prompt_id", "promptID", "id"
    ]

    /// 合并事件载荷里常见的嵌套审批容器，便于统一取值。
    static func flattenedFields(from payload: JSONValue?) -> [String: JSONValue] {
        var fields = payload?.objectValue ?? [:]
        for nestingKey in ["approval", "clarify", "request"] {
            if let nested = fields[nestingKey]?.objectValue {
                for (key, value) in nested {
                    fields[key] = value
                }
            }
        }
        return fields
    }

    static func params(from fields: [String: JSONValue]) -> ApprovalRequestParams? {
        try? JSONValue.object(fields).decoded(as: ApprovalRequestParams.self)
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

    /// 从常见字段抽取可展示文本；数组载荷按顺序拼接。
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
                "result", "summary", "command", "description", "error",
                "chunk", "data", "stdout", "stderr"
            ]
            for key in keys {
                if let text = extractedText(from: object[key]) {
                    return text
                }
            }
            return nil
        }
    }
}
