import SwiftData
import SwiftUI

enum PreviewHelpers {
    @MainActor
    static func createPreviewContainer() -> ModelContainer {
        let schema = Schema([
            TaskItem.self,
            ChatMessage.self,
            CheckInRecord.self,
            DailySnapshot.self,
            UserProfile.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])

        // Seed with sample data
        DataSeeder.seedIfEmpty(context: container.mainContext)

        return container
    }
}
