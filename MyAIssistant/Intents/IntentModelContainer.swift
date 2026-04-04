import Foundation
import SwiftData

/// Shared ModelContainer accessor for App Intents.
/// App Intents run outside the SwiftUI lifecycle, so they need their own container.
enum IntentModelContainer {
    @MainActor
    static let shared: ModelContainer = {
        let schema = Schema(AppSchema.allModels)
        let config = ModelConfiguration("MyAIssistant", isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            print("[IntentModelContainer] Failed: \(error.localizedDescription). Using in-memory fallback.")
            return ModelContainer.fallbackInMemory(schema: schema)
        }
    }()
}
