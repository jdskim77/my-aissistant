import Foundation
import SwiftData

// MARK: - App Schema (Synced + Local)

/// Split schema: 14 models sync to iCloud via CloudKit, 1 stays local.
/// UsageTracker is excluded from sync because it tracks per-device usage limits
/// with an HMAC integrity hash tied to a per-install Keychain secret.
///
/// When adding a new @Model type, add it to syncedModels (or localModels if device-specific).
enum AppSchema {
    /// Models that sync to iCloud via CloudKit
    static let syncedModels: [any PersistentModel.Type] = [
        TaskItem.self,
        ChatMessage.self,
        CheckInRecord.self,
        DailySnapshot.self,
        UserProfile.self,
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

    /// Models that stay local to this device (not synced)
    static let localModels: [any PersistentModel.Type] = [
        UsageTracker.self,
    ]

    /// All models — union of synced + local
    static let allModels: [any PersistentModel.Type] = syncedModels + localModels
}
