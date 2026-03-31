import Foundation
import SwiftData

/// Shared ModelContainer accessor for App Intents.
/// App Intents run outside the SwiftUI lifecycle, so they need their own container.
enum IntentModelContainer {
    @MainActor
    static let shared: ModelContainer = {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let config = ModelConfiguration("MyAIssistant", isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: MyAIssistantMigrationPlan.self,
                configurations: [config]
            )
        } catch {
            return ModelContainer.fallbackInMemory(schema: schema)
        }
    }()
}
