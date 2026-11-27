import Foundation
import LichenCore
import Security

public protocol GatewayCredentialStore {
    func load(for agentID: UUID) throws -> GatewayCredentials?
    func save(_ credentials: GatewayCredentials, for agentID: UUID) throws
}

struct KeychainGatewayCredentialStore: GatewayCredentialStore {
    private struct Entry: Codable {
        let token: String?
        let additionalHeaders: [String: String]
    }

    func load(for agentID: UUID) throws -> GatewayCredentials? {
        var query = item(for: agentID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        try check(status)
        guard let data = value as? Data else { throw KeychainError(status: errSecDecode) }
        let entry = try JSONDecoder().decode(Entry.self, from: data)
        return GatewayCredentials(token: entry.token, additionalHeaders: entry.additionalHeaders)
    }

    func save(_ credentials: GatewayCredentials, for agentID: UUID) throws {
        let entry = Entry(token: credentials.token, additionalHeaders: credentials.additionalHeaders)
        let data = try JSONEncoder().encode(entry)
        let query = item(for: agentID)
        let attributes = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        guard status == errSecItemNotFound else {
            try check(status)
            return
        }

        var newItem = query
        newItem[kSecValueData as String] = data
        newItem[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let added = SecItemAdd(newItem as CFDictionary, nil)
        if added == errSecDuplicateItem {
            try check(SecItemUpdate(query as CFDictionary, attributes as CFDictionary))
        } else {
            try check(added)
        }
    }

    private func item(for agentID: UUID) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.Madokanapersonalteam.LichenAppRunner.gateway",
            kSecAttrAccount as String: agentID.uuidString
        ]
        #if os(macOS)
        query[kSecUseDataProtectionKeychain as String] = true
        #endif
        return query
    }

    private func check(_ status: OSStatus) throws {
        if status != errSecSuccess { throw KeychainError(status: status) }
    }

    private struct KeychainError: LocalizedError {
        let status: OSStatus

        var errorDescription: String? {
            SecCopyErrorMessageString(status, nil) as String? ?? "Keychain (\(status))"
        }
    }
}
