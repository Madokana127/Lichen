import XCTest
import Foundation
@testable import LichenCore

final class AgentTests: XCTestCase {
    private func makeConfiguration(_ name: String = "测试网关") -> GatewayConfiguration {
        GatewayConfiguration(
            displayName: name,
            host: "example.invalid",
            port: 8080
        )
    }

    func testDefaultNamesAndBrandMetadata() {
        XCTAssertEqual(Agent.defaultName(brand: .claude, order: 1), "Claude 01")
        XCTAssertEqual(Agent.defaultName(brand: .hermes, order: 2), "Hermes 02")
        XCTAssertEqual(Agent.defaultName(brand: .opencode, order: 12), "OpenCode 12")
        XCTAssertEqual(Agent.defaultName(brand: .custom, order: 5), "自定义 05")

        for brand in AgentBrand.allCases {
            XCTAssertFalse(brand.displayName.isEmpty)
            XCTAssertFalse(brand.symbolName.isEmpty)
        }
    }

    func testAgentUsesDefaultDisplayName() {
        let agent = Agent(brand: .codex, order: 3, configuration: makeConfiguration())

        XCTAssertEqual(agent.displayName, "Codex 03")
        XCTAssertEqual(agent.order, 3)
        XCTAssertFalse(agent.isConnected)
    }

    func testStoreCRUDCurrentAndReorder() async throws {
        let suiteName = "lichen.agent.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = AgentStore(defaults: defaults, storageKey: "agents")
        let first = Agent(brand: .claude, order: 1, configuration: makeConfiguration())
        let second = Agent(brand: .hermes, order: 2, configuration: makeConfiguration())
        let third = Agent(brand: .codex, order: 3, configuration: makeConfiguration())

        await store.add(second)
        await store.add(first)
        await store.add(third)

        let listed = await store.list()
        XCTAssertEqual(listed.map(\.id), [first.id, second.id, third.id])

        let initialCurrent = await store.current
        XCTAssertEqual(initialCurrent?.id, second.id)

        let renamed = await store.rename(id: first.id, to: "  主 Agent  ")
        XCTAssertTrue(renamed)
        let afterRename = await store.list()
        XCTAssertEqual(afterRename.first { $0.id == first.id }?.displayName, "主 Agent")

        let rejectedEmptyRename = await store.rename(id: first.id, to: "   ")
        XCTAssertFalse(rejectedEmptyRename)

        let selected = await store.setCurrent(id: third.id)
        XCTAssertTrue(selected)
        let currentAfterSelection = await store.current
        XCTAssertEqual(currentAfterSelection?.id, third.id)

        let moved = await store.reorder(id: third.id, to: 0)
        XCTAssertTrue(moved)
        let reordered = await store.list()
        XCTAssertEqual(reordered.map(\.id), [third.id, first.id, second.id])
        XCTAssertEqual(reordered.map(\.order), [1, 2, 3])

        let removed = await store.remove(id: third.id)
        XCTAssertTrue(removed)
        let remaining = await store.list()
        XCTAssertEqual(remaining.map(\.id), [first.id, second.id])
        let currentAfterRemoval = await store.current
        XCTAssertEqual(currentAfterRemoval?.id, first.id)

        let missingRemoval = await store.remove(id: UUID())
        XCTAssertFalse(missingRemoval)
        let missingSelection = await store.setCurrent(id: UUID())
        XCTAssertFalse(missingSelection)
    }

    func testStorePersistsAcrossInstances() async throws {
        let suiteName = "lichen.agent.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let key = "agents"
        let store = AgentStore(defaults: defaults, storageKey: key)
        let agent = Agent(
            brand: .cursor,
            order: 1,
            configuration: makeConfiguration("书桌网关")
        )
        await store.add(agent)
        let renamed = await store.rename(id: agent.id, to: "书桌 Agent")
        XCTAssertTrue(renamed)

        let restored = AgentStore(defaults: defaults, storageKey: key)
        let listed = await restored.list()
        XCTAssertEqual(listed.count, 1)
        XCTAssertEqual(listed.first?.id, agent.id)
        XCTAssertEqual(listed.first?.displayName, "书桌 Agent")
        XCTAssertEqual(listed.first?.brand, .cursor)
        XCTAssertEqual(listed.first?.configuration.displayName, "书桌网关")

        let current = await restored.current
        XCTAssertEqual(current?.id, agent.id)
    }
}
