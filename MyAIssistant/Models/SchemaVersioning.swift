import Foundation
import SwiftData

// MARK: - Flat Schema (All Current Models)

/// Single flat list of all @Model types in the app.
/// VersionedSchema was abandoned — models evolved past V1 without frozen copies.
/// This flat approach is simpler and avoids schema/model drift.
///
/// When adding a new @Model type, add it to this list.
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
