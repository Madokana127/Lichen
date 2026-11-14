import Foundation

/// Agent 品牌。
public enum AgentBrand: String, Codable, CaseIterable, Sendable {
    case claude
    case hermes
    case codex
    case opencode
    case cursor
    case custom

    /// 展示名（用于默认命名与列表标题）。
    public var displayName: String {
        switch self {
        case .claude:
            return "Claude"
        case .hermes:
            return "Hermes"
        case .codex:
            return "Codex"
        case .opencode:
            return "OpenCode"
        case .cursor:
            return "Cursor"
        case .custom:
            return "自定义"
        }
    }

    /// SF Symbols 名称；Core 层不依赖 SwiftUI。
    public var symbolName: String {
        switch self {
        case .claude:
            return "sparkles"
        case .hermes:
            return "bolt.horizontal.circle"
        case .codex:
            return "chevron.left.forwardslash.chevron.right"
        case .opencode:
            return "curlybraces"
        case .cursor:
            return "cursorarrow.rays"
        case .custom:
            return "puzzlepiece.extension"
        }
    }
}

/// 一个已配置的 Agent。
public struct Agent: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public let brand: AgentBrand
    public var displayName: String
    /// 加入顺序，从 1 开始；`AgentStore.list()` 按此升序返回。
    public var order: Int
    public var configuration: GatewayConfiguration
    public var isConnected: Bool
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        brand: AgentBrand,
        displayName: String? = nil,
        order: Int,
        configuration: GatewayConfiguration,
        isConnected: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.brand = brand
        self.displayName = displayName ?? Agent.defaultName(brand: brand, order: order)
        self.order = order
        self.configuration = configuration
        self.isConnected = isConnected
        self.createdAt = createdAt
    }

    /// 默认命名：「品牌 + 两位顺序号」，如 `Claude 01`。
    public static func defaultName(brand: AgentBrand, order: Int) -> String {
        String(format: "%@ %02d", brand.displayName, order)
    }
}

/// Agent 列表存储：内存状态 + `UserDefaults` JSON 持久化。
public actor AgentStore {
    /// 持久化快照。声明为 internal 而非 private：`private extension` 内的方法
    /// 在文件作用域为 fileprivate，返回 private 嵌套类型会触发访问控制错误。
    internal struct Snapshot: Codable {
        var agents: [Agent]
        var currentID: UUID?
    }

    private let defaults: UserDefaults
    private let storageKey: String
    private var agents: [Agent]
    private var currentID: UUID?

    public init(
        defaults: UserDefaults = .standard,
        storageKey: String = "lichen.agent-store"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey

        let snapshot = Self.readSnapshot(defaults: defaults, storageKey: storageKey)
        self.agents = snapshot.agents
        let ordered = Self.sortedAgents(snapshot.agents)
        if let id = snapshot.currentID, snapshot.agents.contains(where: { $0.id == id }) {
            self.currentID = id
        } else {
            self.currentID = ordered.first?.id
        }
    }

    /// 当前选中的 Agent。
    public var current: Agent? {
        guard let currentID = currentID else { return nil }
        return agents.first { $0.id == currentID }
    }

    /// 按 `order` 升序返回全部 Agent。
    public func list() -> [Agent] {
        Self.sortedAgents(agents)
    }

    /// 新增 Agent；同 id 时覆盖。
    public func add(_ agent: Agent) {
        if let index = agents.firstIndex(where: { $0.id == agent.id }) {
            agents[index] = agent
        } else {
            agents.append(agent)
        }
        if currentID == nil {
            currentID = agent.id
        }
        persist()
    }

    /// 删除 Agent；当前 Agent 被删除时自动切换到剩余第一项。
    @discardableResult
    public func remove(id: UUID) -> Bool {
        guard let index = agents.firstIndex(where: { $0.id == id }) else {
            return false
        }
        agents.remove(at: index)
        if currentID == id {
            currentID = Self.sortedAgents(agents).first?.id
        }
        persist()
        return true
    }

    /// 把指定 Agent 移动到目标位置（从 0 开始），并重排 `order`。
    @discardableResult
    public func reorder(id: UUID, to index: Int) -> Bool {
        var ordered = Self.sortedAgents(agents)
        guard let source = ordered.firstIndex(where: { $0.id == id }) else {
            return false
        }

        let agent = ordered.remove(at: source)
        let destination = min(max(index, 0), ordered.count)
        ordered.insert(agent, at: destination)

        for position in ordered.indices {
            ordered[position].order = position + 1
        }
        agents = ordered
        persist()
        return true
    }

    /// 重命名；空白名称会被拒绝。
    @discardableResult
    public func rename(id: UUID, to name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = agents.firstIndex(where: { $0.id == id }) else {
            return false
        }
        agents[index].displayName = trimmed
        persist()
        return true
    }

    /// 切换当前 Agent；id 不存在时返回 `false`。
    @discardableResult
    public func setCurrent(id: UUID) -> Bool {
        guard agents.contains(where: { $0.id == id }) else { return false }
        currentID = id
        persist()
        return true
    }
}

private extension AgentStore {
    static func readSnapshot(defaults: UserDefaults, storageKey: String) -> Snapshot {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            return Snapshot(agents: [], currentID: nil)
        }
        return decoded
    }

    static func sortedAgents(_ agents: [Agent]) -> [Agent] {
        agents.sorted { lhs, rhs in
            if lhs.order != rhs.order {
                return lhs.order < rhs.order
            }
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            if lhs.displayName != rhs.displayName {
                return lhs.displayName < rhs.displayName
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    func persist() {
        let snapshot = Snapshot(agents: Self.sortedAgents(agents), currentID: currentID)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
