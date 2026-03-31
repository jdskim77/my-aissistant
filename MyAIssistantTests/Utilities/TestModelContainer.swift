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
            HabitItem.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }
}
