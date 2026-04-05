import Foundation
import SwiftData

// MARK: - App Schema (Synced + Local)

/// All models in a single CloudKit-synced store.
/// UsageTracker is included but its per-device integrity is enforced via
/// Keychain-bound HMAC — even if synced, each device recomputes its own hash.
///
/// When adding a new @Model type, add it to allModels.
enum AppSchema {
    static let allModels: [any PersistentModel.Type] = [
        TaskItem.self,
        ChatMessage.self,
        CheckInRecord.self,
        DailySnapshot.self,
        UserProfile.self,
        UsageTracker.self,
        CalendarLink.self,
        ActivityEntry.self,
        ActivityPattern.self,
        AlarmEntry.self,
        FocusSession.self,
        HabitItem.self,
        DailyBalanceCheckIn.self,
        SeasonGoal.self,
        UserDimensionPreference.self,
    ]
}
