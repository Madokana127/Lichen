import Foundation
import LichenCore

/// Adapts Hermes RPC payloads to the data used by the app.
struct HermesGateway {
    struct ModelOption: Equatable {
        let name: String
        let provider: String?
    }

    struct ModelCatalog {
        let options: [ModelOption]
        let currentName: String?
        let currentProvider: String?
    }

    struct RemoteSession {
        let id: String
        let title: String?
        let model: String?
        let storedID: String?
        var history: [JSONValue]? = nil
    }

    struct HistoryRow {
        let role: MessageRole
        let text: String
        let date: Date?
        let toolName: String?
    }

    let client: any GatewayClient

    func models() async throws -> ModelCatalog {
        let result = try await client.request(method: GatewayMethod.modelOptions)
        let options = (result["providers"]?.arrayValue ?? []).flatMap { provider -> [ModelOption] in
            let slug = provider["slug"]?.stringValue
            return (provider["models"]?.arrayValue ?? []).compactMap { value in
                guard let name = value.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !name.isEmpty else { return nil }
                return ModelOption(name: name, provider: slug)
            }
        }
        return ModelCatalog(
            options: options,
            currentName: result["model"]?.stringValue,
            currentProvider: result["provider"]?.stringValue
        )
    }

    func sessions(profile: String?) async throws -> [RemoteSession] {
        var params: [String: JSONValue] = [:]
        if let profile { params["profile"] = .string(profile) }

        let live = try await client.request(method: GatewayMethod.sessionList, params: .object(params))
        var sessions = try decodeList(live)
        var knownIDs = Set(sessions.map(\.id))
        // Older Hermes versions return saved sessions from the unscoped call.
        params["scope"] = .string("stored")
        var cursors: Set<String> = []
        while true {
            try Task.checkCancellation()
            let page: JSONValue
            do {
                page = try await client.request(method: GatewayMethod.sessionList, params: .object(params))
            } catch GatewayError.server(let code, _) where cursors.isEmpty && [-32602, 4002].contains(code) {
                return sessions
            }
            sessions.append(contentsOf: try decodeList(page).filter { knownIDs.insert($0.id).inserted })
            guard let cursor = page["next_cursor"]?.stringValue, !cursor.isEmpty else { return sessions }
            guard cursors.insert(cursor).inserted else {
                throw GatewayError.decoding("Hermes session.list 重复返回同一分页游标")
            }
            params["cursor"] = .string(cursor)
        }
    }

    private func decodeList(_ result: JSONValue) throws -> [RemoteSession] {
        guard let entries = result.arrayValue ?? result["sessions"]?.arrayValue else {
            throw GatewayError.decoding("Hermes session.list 未返回会话列表")
        }
        return entries.compactMap { entry in
            guard let id = entry["stored_session_id"]?.stringValue ?? entry["session_id"]?.stringValue ?? entry["id"]?.stringValue,
                  !id.isEmpty else { return nil }
            return RemoteSession(id: id, title: entry["title"]?.stringValue, model: nil, storedID: id)
        }
    }

    func transcript(sessionID: String, profile: String?) async throws -> [HistoryRow] {
        var params: [String: JSONValue] = ["session_id": .string(sessionID), "order": .string("oldest")]
        if let profile { params["profile"] = .string(profile) }
        var cursors: Set<String> = []
        var rows: [JSONValue] = []
        var restarted = false
        while true {
            try Task.checkCancellation()
            let page = try await client.request(method: GatewayMethod.sessionTranscript, params: .object(params))
            guard let slice = page["rows"]?.arrayValue else {
                throw GatewayError.decoding("Hermes session.transcript 未返回消息")
            }
            if params["cursor"] != nil, page["reset"]?.boolValue == true {
                guard !restarted else { throw GatewayError.decoding("远端会话历史在读取期间持续变化") }
                rows.removeAll()
                cursors.removeAll()
                restarted = true
            }
            rows.append(contentsOf: slice)
            guard !slice.isEmpty, let cursor = page["next_cursor"]?.stringValue, !cursor.isEmpty else {
                return decodeHistory(rows)
            }
            guard cursors.insert(cursor).inserted else {
                throw GatewayError.decoding("Hermes session.transcript 重复返回同一分页游标")
            }
            params["cursor"] = .string(cursor)
        }
    }

    func liveHistory(sessionID: String) async throws -> [HistoryRow] {
        let result = try await client.request(
            method: GatewayMethod.sessionHistory, params: .object(["session_id": .string(sessionID)])
        )
        guard let rows = result["messages"]?.arrayValue else {
            throw GatewayError.decoding("Hermes session.history 未返回消息")
        }
        return decodeHistory(rows)
    }

    func decodeHistory(_ rows: [JSONValue]) -> [HistoryRow] {
        let iso8601 = ISO8601DateFormatter()
        iso8601.formatOptions.insert(.withFractionalSeconds)
        return rows.compactMap { row in
            guard row["display_kind"]?.stringValue != "hidden",
                  row["display_metadata"]?["model_only"]?.boolValue != true,
                  let roleName = row["role"]?.stringValue,
                  let role = MessageRole(rawValue: roleName), role != .approval else { return nil }
            let content = row["content"]
            let blocks = content?.arrayValue?.compactMap { $0["text"]?.stringValue ?? $0.stringValue }
            let text = row["text"]?.stringValue ?? content?.stringValue ?? blocks?.joined(separator: "\n") ?? ""
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let stamp = row["timestamp"]
            let seconds = stamp?.doubleValue ?? stamp?.intValue.map(Double.init)
            let date = seconds.flatMap { $0.isFinite ? Date(timeIntervalSince1970: $0) : nil }
                ?? stamp?.stringValue.flatMap { iso8601.date(from: $0) ?? ISO8601DateFormatter().date(from: $0) }
            return HistoryRow(role: role, text: text, date: date, toolName: row["tool_name"]?.stringValue)
        }
    }

    func createSession(model: ModelOption?, reasoning: String) async throws -> RemoteSession {
        var params: [String: JSONValue] = [
            "source": .string("local"),
            "reasoning_effort": .string(reasoning)
        ]
        if let model {
            params["model"] = .string(model.name)
            if let provider = model.provider, !provider.isEmpty {
                params["provider"] = .string(provider)
            }
        }
        let result = try await client.request(method: GatewayMethod.sessionCreate, params: .object(params))
        return try decodeSession(result, method: GatewayMethod.sessionCreate)
    }

    func resumeSession(_ storedID: String, profile: String? = nil) async throws -> RemoteSession {
        var params: [String: JSONValue] = ["session_id": .string(storedID)]
        if let profile { params["profile"] = .string(profile) }
        let result = try await client.request(
            method: GatewayMethod.sessionResume,
            params: .object(params),
            timeout: 30
        )
        return try decodeSession(result, method: GatewayMethod.sessionResume)
    }

    private func decodeSession(_ result: JSONValue, method: String) throws -> RemoteSession {
        guard let id = result["session_id"]?.stringValue, !id.isEmpty else {
            throw GatewayError.decoding("Hermes \(method) 未返回 session_id")
        }
        return RemoteSession(
            id: id,
            title: result["info"]?["title"]?.stringValue,
            model: result["info"]?["model"]?.stringValue ?? result["model"]?.stringValue,
            storedID: result["stored_session_id"]?.stringValue,
            history: result["display_messages"]?.arrayValue ?? result["messages"]?.arrayValue
        )
    }

    func setModel(_ model: String, sessionID: String) async throws {
        _ = try await client.request(method: GatewayMethod.configSet, params: .object([
            "key": .string("model"),
            "value": .string(model),
            "session_id": .string(sessionID),
            "confirm_expensive_model": .bool(false)
        ]))
    }

    func setReasoning(_ reasoning: String, sessionID: String) async throws {
        _ = try await client.request(method: GatewayMethod.configSet, params: .object([
            "key": .string("reasoning"),
            "value": .string(reasoning),
            "session_id": .string(sessionID)
        ]))
    }

    func submit(_ text: String, sessionID: String) async throws {
        _ = try await client.request(method: GatewayMethod.promptSubmit, params: .object([
            "session_id": .string(sessionID),
            "text": .string(text)
        ]))
    }

    /// 返回网关是否报告当前已无可中断的输出。
    func interrupt(sessionID: String) async throws -> Bool {
        let result = try await client.request(
            method: GatewayMethod.sessionInterrupt,
            params: .object(["session_id": .string(sessionID)])
        )
        return result["status"]?.stringValue == "not_interrupted" || result["interrupted"]?.boolValue == false
    }
}
