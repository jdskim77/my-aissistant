import Foundation
import SwiftData
@testable import MyAIssistant

enum TestModelContainer {
    @MainActor
    static func create() throws -> ModelContainer {
        let schema = Schema([
            TaskItem.self,
            ChatMessage.self,
            CheckInRecord.self,
            DailySnapshot.self,
            UserProfile.self,
            UsageTracker.self,
            CalendarLink.self,
            ActivityEntry.self,
            AlarmEntry.self,
            FocusSession.self,
            HabitItem.self,
            // Added so DataExportService's full export/import round trip
            // (and anything else that touches these models) can actually be
            // exercised under test — previously missing, so FetchDescriptor
            // calls for these types would throw in a test context.
            DailyBalanceCheckIn.self,
            SeasonGoal.self,
            ActivityPattern.self,
            UserDimensionPreference.self,
            // NudgeEngine persists/fetches Nudge rows; without it every
            // insert/fetch in NudgeEngineTests silently no-ops.
            Nudge.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }
}
