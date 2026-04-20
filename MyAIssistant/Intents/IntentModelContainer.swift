import Foundation
import SwiftData

/// Shared ModelContainer accessor for App Intents.
/// App Intents run outside the SwiftUI lifecycle, so they need their own container.
enum IntentModelContainer {
    @MainActor
    static let shared: ModelContainer = {
        let schema = Schema(AppSchema.allModels)
        let config = ModelConfiguration(
            "MyAIssistant",
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            AppLogger.persistence.error("IntentModelContainer init failed: \(error.localizedDescription, privacy: .public). Using local fallback.")
            // Fallback to local-only (no CloudKit)
            let localConfig = ModelConfiguration(
                "MyAIssistant",
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .none
            )
            return (try? ModelContainer(for: schema, configurations: [localConfig]))
                ?? ModelContainer.fallbackInMemory(schema: schema)
        }
    }()
}
