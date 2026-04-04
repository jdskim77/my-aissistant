import Foundation
import SwiftData

/// Shared ModelContainer for App Intents.
enum IntentModelContainer {
    @MainActor
    static let shared: ModelContainer = {
        let modelTypes: [any PersistentModel.Type] = [
            TaskItem.self, ChatMessage.self, CheckInRecord.self,
            DailySnapshot.self, UserProfile.self, UsageTracker.self,
            CalendarLink.self, ActivityEntry.self, AlarmEntry.self,
            FocusSession.self, HabitItem.self, DailyBalanceCheckIn.self,
            SeasonGoal.self, UserDimensionPreference.self, ActivityPattern.self
        ]
        let schema = Schema(modelTypes)
        let config = ModelConfiguration("MyAIssistant", schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            let memConfig = ModelConfiguration(isStoredInMemoryOnly: true)
            return try! ModelContainer(for: schema, configurations: [memConfig])
        }
    }()
}
