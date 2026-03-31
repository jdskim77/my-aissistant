import Foundation
import SwiftData

// MARK: - Schema V1 (Initial Release)

/// Defines the initial schema for My AIssistant.
/// When adding new properties or models in future versions:
/// 1. Copy the current models into SchemaV1 as nested types (freezing them)
/// 2. Create SchemaV2 referencing the updated standalone models
/// 3. Add a MigrationStage to MyAIssistantMigrationPlan.stages
enum SchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
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
        ]
    }
}

// MARK: - Migration Plan

enum MyAIssistantMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self]
    }

    static var stages: [MigrationStage] {
        // No migrations yet — V1 is the initial schema.
        // Future migrations go here, e.g.:
        // migrateV1toV2
        []
    }

    // MARK: - Future Migration Stages
    //
    // Example for a V2 migration:
    //
    // static let migrateV1toV2 = MigrationStage.lightweight(
    //     fromVersion: SchemaV1.self,
    //     toVersion: SchemaV2.self
    // )
    //
    // For complex migrations that need data transformation:
    //
    // static let migrateV1toV2 = MigrationStage.custom(
    //     fromVersion: SchemaV1.self,
    //     toVersion: SchemaV2.self,
    //     willMigrate: { context in
    //         // Pre-migration data transforms
    //     },
    //     didMigrate: { context in
    //         // Post-migration data transforms
    //         try context.save()
    //     }
    // )
}
