import Foundation
import SwiftData

/// Shared ModelContainer accessor for App Intents.
///
/// App Intents run out-of-process when invoked from Siri / Shortcuts /
/// widgets, so they need their own container. **Critical:** the config must
/// point at the same App Group SQLite file the main app, widgets, and share
/// extension all use — otherwise intent writes land in a separate database
/// and never reach the user's data until CloudKit eventually reconciles them.
///
/// Mirrors the resolution pattern in `MyAIssistantApp.createCloudContainer`
/// so all four surfaces (app / widgets / share ext / intents) open the
/// exact same store URL.
enum IntentModelContainer {
    private static let appGroupID = "group.com.myaissistant.shared"
    private static let storeFilename = "MyAIssistant.store"

    /// Same URL that `MyAIssistantApp.appGroupStoreURL()` returns.
    /// Duplicated here because App Intents run out-of-process and can't
    /// reach the app's internal statics.
    private static func appGroupStoreURL() -> URL? {
        let fm = FileManager.default
        guard let containerURL = fm.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) else {
            return nil
        }
        let appSupport = containerURL.appendingPathComponent(
            "Library/Application Support", isDirectory: true
        )
        do {
            try fm.createDirectory(at: appSupport, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        return appSupport.appendingPathComponent(storeFilename)
    }

    @MainActor
    static let shared: ModelContainer = {
        let schema = Schema(AppSchema.allModels)
        let cloudConfig: ModelConfiguration
        if let url = appGroupStoreURL() {
            cloudConfig = ModelConfiguration(
                "MyAIssistant",
                schema: schema,
                url: url,
                cloudKitDatabase: .automatic
            )
        } else {
            // Fallback when the App Group container isn't available
            // (should not happen on a correctly-entitled build).
            cloudConfig = ModelConfiguration(
                "MyAIssistant",
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .automatic
            )
        }

        do {
            return try ModelContainer(for: schema, configurations: [cloudConfig])
        } catch {
            AppLogger.persistence.error(
                "IntentModelContainer init failed: \(error.localizedDescription, privacy: .public). Using local fallback."
            )
            // Local-only fallback still uses the App Group URL so intents
            // and the main app continue sharing the same store even if
            // CloudKit is the thing that broke.
            let localConfig: ModelConfiguration
            if let url = appGroupStoreURL() {
                localConfig = ModelConfiguration(
                    "MyAIssistant",
                    schema: schema,
                    url: url,
                    cloudKitDatabase: .none
                )
            } else {
                localConfig = ModelConfiguration(
                    "MyAIssistant",
                    isStoredInMemoryOnly: false,
                    cloudKitDatabase: .none
                )
            }
            return (try? ModelContainer(for: schema, configurations: [localConfig]))
                ?? ModelContainer.fallbackInMemory(schema: schema)
        }
    }()
}
