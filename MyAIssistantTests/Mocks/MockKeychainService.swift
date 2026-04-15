import Foundation
@testable import MyAIssistant

final class MockKeychainService: KeychainService, @unchecked Sendable {
    private var store: [String: String] = [:]

    override func read(key: String) -> String? {
        store[key]
    }

    @discardableResult
    override func save(key: String, value: String, protection: KeychainProtection = .afterFirstUnlock) -> Bool {
        store[key] = value
        return true
    }

    @discardableResult
    override func delete(key: String) -> Bool {
        store.removeValue(forKey: key)
        return true
    }

    // Convenience for tests
    func setAnthropicKey(_ key: String) {
        save(key: AppConstants.anthropicAPIKeyKey, value: key)
    }

    func setOpenAIKey(_ key: String) {
        save(key: AppConstants.openAIAPIKeyKey, value: key)
    }
}
