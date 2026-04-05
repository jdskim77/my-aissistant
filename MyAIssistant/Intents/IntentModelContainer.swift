import Foundation
import SwiftData

/// Shared ModelContainer accessor for App Intents.
/// App Intents run outside the SwiftUI lifecycle, so they need their own container.
/// Mirrors the dual-config setup from the main app (CloudKit synced + local-only).
enum IntentModelContainer {
    @MainActor
    static let shared: ModelContainer = {
        let schema = Schema(AppSchema.allModels)
        let cloudConfig = ModelConfiguration(
            "MyAIssistant",
            schema: Schema(AppSchema.syncedModels),
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )
        let localConfig = ModelConfiguration(
            "MyAIssistant-local",
            schema: Schema(AppSchema.localModels),
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(for: schema, configurations: [cloudConfig, localConfig])
        } catch {
            #if DEBUG
            print("[IntentModelContainer] Failed: \(error.localizedDescription). Using in-memory fallback.")
            #endif
            return ModelContainer.fallbackInMemory(schema: schema)
        }
    }()
}
