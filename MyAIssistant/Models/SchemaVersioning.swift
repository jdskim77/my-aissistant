import Foundation
import SwiftData

// MARK: - Versioned Schema

/// V1 baseline. Every @Model type currently shipped lives here.
///
/// **CRITICAL**: when adding, removing, renaming, or changing the type of any
/// @Model property — or adding a new @Model class — you MUST create a new
/// `SchemaV2` (then V3, etc.) AND add a `MigrationStage` to `AppMigrationPlan`.
/// Lightweight stages cover most additive changes; renames and type changes
/// require a custom stage.
///
/// Without a versioned baseline, SwiftData has nothing to migrate FROM and
/// will silently fail (or wipe the store) on the first non-trivial change.
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
            ActivityPattern.self,
            AlarmEntry.self,
            FocusSession.self,
            HabitItem.self,
            DailyBalanceCheckIn.self,
            SeasonGoal.self,
            UserDimensionPreference.self,
            CheckInPreference.self,
            CheckInBehavior.self,
            CheckInSuggestion.self,
        ]
    }
}

/// V2: added `HabitItem.missedDatesRaw` (additive, default ""). Lightweight
/// migration from V1 — SwiftData adds the column with its default on existing
/// stores so no data is lost.
enum SchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 1, 0)

    static var models: [any PersistentModel.Type] {
        SchemaV1.models
    }
}

/// Convenience for code that wants the current model list (e.g. the
/// developer-tools "Wipe All Data" action). Always points at the latest
/// schema version's models.
enum AppSchema {
    static var allModels: [any PersistentModel.Type] {
        SchemaV2.models
    }
}

// MARK: - Migration Plan

/// Migrations in order: V1 → V2 (lightweight for `missedDatesRaw` addition).
enum AppMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self)
        ]
    }
}
