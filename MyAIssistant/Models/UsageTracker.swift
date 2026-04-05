import Foundation
import SwiftData
import CryptoKit

@Model
final class UsageTracker {
    var id: String
    var monthKey: String          // "2026-02" format for monthly reset
    var weekKey: String            // "2026-W07" format for weekly reset (legacy, kept for schema)
    var dayKey: String             // "2026-04-01" format for daily reset
    var chatMessagesThisMonth: Int
    var checkInsThisWeek: Int      // legacy — kept for schema compatibility
    var checkInsToday: Int
    var totalInputTokens: Int
    var totalOutputTokens: Int
    var lastUpdated: Date
    /// HMAC signature of counters — verified against Keychain-stored key to detect tampering
    var integrityHash: String

    init() {
        self.id = "usage-singleton"
        let now = Date()
        self.monthKey = UsageTracker.monthKey(for: now)
        self.weekKey = UsageTracker.weekKey(for: now)
        self.dayKey = UsageTracker.dayKey(for: now)
        self.chatMessagesThisMonth = 0
        self.checkInsThisWeek = 0
        self.checkInsToday = 0
        self.totalInputTokens = 0
        self.totalOutputTokens = 0
        self.lastUpdated = now
        self.integrityHash = ""
    }

    // MARK: - Period Keys

    static func monthKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: date)
    }

    static func weekKey(for date: Date) -> String {
        let calendar = Calendar.current
        let year = calendar.component(.yearForWeekOfYear, from: date)
        let week = calendar.component(.weekOfYear, from: date)
        return String(format: "%04d-W%02d", year, week)
    }

    static func dayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    // MARK: - Reset if Needed

    func resetIfNeeded() {
        let now = Date()
        let currentMonth = UsageTracker.monthKey(for: now)
        let currentDay = UsageTracker.dayKey(for: now)
        var didReset = false

        if monthKey != currentMonth {
            monthKey = currentMonth
            chatMessagesThisMonth = 0
            didReset = true
        }

        if dayKey != currentDay {
            dayKey = currentDay
            checkInsToday = 0
            didReset = true
        }

        lastUpdated = now
        if didReset { updateIntegrityHash() }
    }

    // MARK: - Tracking

    func recordChatMessage(inputTokens: Int, outputTokens: Int) {
        resetIfNeeded()
        chatMessagesThisMonth += 1
        totalInputTokens += inputTokens
        totalOutputTokens += outputTokens
        updateIntegrityHash()
    }

    func recordCheckIn() {
        resetIfNeeded()
        checkInsToday += 1
        updateIntegrityHash()
    }

    // MARK: - Limit Checks

    func canSendChat(tier: SubscriptionTier) -> Bool {
        if AppConstants.isDeveloperMode { return true }
        resetIfNeeded()
        switch tier {
        case .free:
            return chatMessagesThisMonth < AppConstants.freeChatMessagesPerMonth
        case .pro, .student, .powerUser:
            return true
        }
    }

    func canDoCheckIn(tier: SubscriptionTier) -> Bool {
        if AppConstants.isDeveloperMode { return true }
        resetIfNeeded()
        switch tier {
        case .free:
            return checkInsToday < AppConstants.freeCheckInsPerDay
        case .pro, .student, .powerUser:
            return true
        }
    }

    var remainingChatMessages: Int {
        max(0, AppConstants.freeChatMessagesPerMonth - chatMessagesThisMonth)
    }

    var remainingCheckIns: Int {
        max(0, AppConstants.freeCheckInsPerDay - checkInsToday)
    }

    // MARK: - Integrity Verification

    /// Computes HMAC-SHA256 over the mutable counter fields using a Keychain-stored secret.
    /// If the DB is edited outside the app, the hash won't match and counters are treated as exhausted.
    func updateIntegrityHash() {
        integrityHash = Self.computeHash(
            monthKey: monthKey,
            dayKey: dayKey,
            chat: chatMessagesThisMonth,
            checkIns: checkInsToday
        )
    }

    func verifyIntegrity() -> Bool {
        // Empty hash means fresh install or DB was recreated — recompute and trust
        if integrityHash.isEmpty {
            updateIntegrityHash()
            return true
        }
        let expected = Self.computeHash(
            monthKey: monthKey,
            dayKey: dayKey,
            chat: chatMessagesThisMonth,
            checkIns: checkInsToday
        )
        return integrityHash == expected
    }

    private static func computeHash(monthKey: String, dayKey: String, chat: Int, checkIns: Int) -> String {
        let payload = "\(monthKey)|\(dayKey)|\(chat)|\(checkIns)"
        guard let payloadData = payload.data(using: .utf8) else { return "" }
        let key = integrityKey()
        let signature = HMAC<SHA256>.authenticationCode(for: payloadData, using: key)
        return Data(signature).base64EncodedString()
    }

    /// Returns a per-install symmetric key stored in the Keychain.
    /// The key lives in Keychain (not in the SQLite DB), so editing the DB alone won't help.
    private static func integrityKey() -> SymmetricKey {
        let keychainKey = "com.myaissistant.usage-integrity-key"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data {
            return SymmetricKey(data: data)
        }
        // Generate and persist a new key
        let newKey = SymmetricKey(size: .bits256)
        let keyData = newKey.withUnsafeBytes { Data($0) }
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKey,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
        return newKey
    }
}
