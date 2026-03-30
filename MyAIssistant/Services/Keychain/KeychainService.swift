import Foundation
import Security

class KeychainService: @unchecked Sendable {
    private let accessGroup = "group.com.myaissistant.shared"

    // MARK: - Read

    func read(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrAccessGroup as String: accessGroup,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess, let data = result as? Data,
           let string = String(data: data, encoding: .utf8) {
            return string
        }

        // Fallback: try reading without access group (migrates old keys)
        let fallbackQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var fallbackResult: AnyObject?
        let fallbackStatus = SecItemCopyMatching(fallbackQuery as CFDictionary, &fallbackResult)
        if fallbackStatus == errSecSuccess, let data = fallbackResult as? Data,
           let string = String(data: data, encoding: .utf8) {
            // Re-save with shared access group so Watch can access it
            _ = save(key: key, value: string)
            return string
        }

        return nil
    }

    // MARK: - Write

    @discardableResult
    func save(key: String, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        // Delete existing item first
        delete(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrAccessGroup as String: accessGroup,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    // MARK: - Delete

    @discardableResult
    func delete(key: String) -> Bool {
        // Delete from shared group
        let sharedQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrAccessGroup as String: accessGroup
        ]
        SecItemDelete(sharedQuery as CFDictionary)

        // Also delete from default group (legacy cleanup)
        let defaultQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        let status = SecItemDelete(defaultQuery as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - Convenience

    func anthropicAPIKey() -> String? {
        read(key: AppConstants.anthropicAPIKeyKey)
    }

    func saveAnthropicAPIKey(_ key: String) -> Bool {
        save(key: AppConstants.anthropicAPIKeyKey, value: key)
    }

    func openAIAPIKey() -> String? {
        read(key: AppConstants.openAIAPIKeyKey)
    }

    func saveOpenAIAPIKey(_ key: String) -> Bool {
        save(key: AppConstants.openAIAPIKeyKey, value: key)
    }
}
