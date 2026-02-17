import Foundation
import SwiftData

@Model
final class UsageTracker {
    var id: String
    var monthKey: String          // "2026-02" format for monthly reset
    var weekKey: String            // "2026-W07" format for weekly reset
    var chatMessagesThisMonth: Int
    var checkInsThisWeek: Int
    var totalInputTokens: Int
    var totalOutputTokens: Int
    var lastUpdated: Date

    init() {
        self.id = "usage-singleton"
        let now = Date()
        self.monthKey = UsageTracker.monthKey(for: now)
        self.weekKey = UsageTracker.weekKey(for: now)
        self.chatMessagesThisMonth = 0
        self.checkInsThisWeek = 0
        self.totalInputTokens = 0
        self.totalOutputTokens = 0
        self.lastUpdated = now
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

    // MARK: - Reset if Needed

    func resetIfNeeded() {
        let now = Date()
        let currentMonth = UsageTracker.monthKey(for: now)
        let currentWeek = UsageTracker.weekKey(for: now)

        if monthKey != currentMonth {
            monthKey = currentMonth
            chatMessagesThisMonth = 0
        }

        if weekKey != currentWeek {
            weekKey = currentWeek
            checkInsThisWeek = 0
        }

        lastUpdated = now
    }

    // MARK: - Tracking

    func recordChatMessage(inputTokens: Int, outputTokens: Int) {
        resetIfNeeded()
        chatMessagesThisMonth += 1
        totalInputTokens += inputTokens
        totalOutputTokens += outputTokens
    }

    func recordCheckIn() {
        resetIfNeeded()
        checkInsThisWeek += 1
    }

    // MARK: - Limit Checks

    func canSendChat(tier: SubscriptionTier) -> Bool {
        resetIfNeeded()
        switch tier {
        case .free:
            return chatMessagesThisMonth < AppConstants.freeChatMessagesPerMonth
        case .pro, .student, .powerUser:
            return true
        }
    }

    func canDoCheckIn(tier: SubscriptionTier) -> Bool {
        resetIfNeeded()
        switch tier {
        case .free:
            return checkInsThisWeek < AppConstants.freeCheckInsPerWeek
        case .pro, .student, .powerUser:
            return true
        }
    }

    var remainingChatMessages: Int {
        max(0, AppConstants.freeChatMessagesPerMonth - chatMessagesThisMonth)
    }

    var remainingCheckIns: Int {
        max(0, AppConstants.freeCheckInsPerWeek - checkInsThisWeek)
    }
}
