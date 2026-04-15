import Foundation
import Security

// MARK: - Engine / Reusable
//
// Generic Keychain wrapper with shared access group support (so Watch, Widgets,
// and iOS app can read the same keys). Domain-neutral — stores arbitrary
// string values under arbitrary account keys.
//
// Reusable: yes, in any iOS app with a shared Watch or extension target.
// Dependencies: Security framework only.
// Watch-compatible: yes.
//
// Fork notes:
// - `accessGroup` below is a Thrivn-specific App Group identifier. A fork MUST
//   replace this with its own `group.com.<yourapp>.shared` identifier and
//   update entitlements on every target (iOS, Watch, Widgets, Intents).
// - The fallback path (read without access group, re-save with it) handles
//   migration from older Thrivn versions; a fresh fork can delete it.

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

    /// Save a value to the Keychain.
    ///
    /// - Parameters:
    ///   - key: Account/key identifier
    ///   - value: Value to store
    ///   - protection: Keychain access class. Default is `.afterFirstUnlock` so the
    ///     Watch extension can read shared keys in the background. For sensitive
    ///     bearer tokens (auth JWTs, OAuth refresh tokens), pass
    ///     `.whenUnlockedThisDeviceOnly` so they don't migrate to other devices via
    ///     iCloud Keychain backup.
    @discardableResult
    func save(
        key: String,
        value: String,
        protection: KeychainProtection = .afterFirstUnlock
    ) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        // Delete existing item first
        delete(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrAccessGroup as String: accessGroup,
            kSecValueData as String: data,
            kSecAttrAccessible as String: protection.attributeValue
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

    /// BYOK keys are user secrets — never sync them to other devices via iCloud
    /// Keychain backup. Watch needs them, so the App Group access group still
    /// applies (Watch shares the same iCloud account, same physical device).
    func saveAnthropicAPIKey(_ key: String) -> Bool {
        save(key: AppConstants.anthropicAPIKeyKey, value: key, protection: .whenUnlockedThisDeviceOnly)
    }

    func openAIAPIKey() -> String? {
        read(key: AppConstants.openAIAPIKeyKey)
    }

    func saveOpenAIAPIKey(_ key: String) -> Bool {
        save(key: AppConstants.openAIAPIKeyKey, value: key, protection: .whenUnlockedThisDeviceOnly)
    }
}

/// Keychain item protection class.
/// Determines when the item is accessible and whether it migrates to other
/// devices via iCloud Keychain backup.
enum KeychainProtection {
    /// Available after first unlock post-boot, including in the background.
    /// Migrates to other devices via iCloud Keychain backup.
    /// Use for: shared data needed by extensions (Watch app), non-sensitive caches.
    case afterFirstUnlock

    /// Available only when the device is unlocked, and **does not migrate**
    /// to other devices via iCloud Keychain backup.
    /// Use for: bearer tokens, refresh tokens, OAuth credentials, anything
    /// that should not survive iCloud restore to a different device.
    case whenUnlockedThisDeviceOnly

    var attributeValue: CFString {
        switch self {
        case .afterFirstUnlock:
            return kSecAttrAccessibleAfterFirstUnlock
        case .whenUnlockedThisDeviceOnly:
            return kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }
    }
}
