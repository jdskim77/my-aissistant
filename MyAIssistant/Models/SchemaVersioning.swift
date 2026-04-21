import Foundation
import SwiftData

// MARK: - Versioned Schema
//
// **Single baseline approach (pre-1.0).** Until we need a breaking schema
// change, every @Model edit lives in the model files themselves and
// SwiftData handles additive changes (new optional properties, new models)
// lightweight-automatically against the single `SchemaV1` version.
//
// **How to add V2 correctly when the time comes** — the old code had V1
// and V2 sharing the same `models` array, which meant the "migration"
// V1 → V2 was a no-op and any property added afterward had no migration
// stage. To avoid that footgun, when you need V2:
//
// 1. DO NOT add properties to existing @Model classes in the main module.
// 2. Duplicate the current @Model classes into a nested namespace under a
//    new `SchemaV2` type (`SchemaV2.TaskItem`, `SchemaV2.HabitItem`, …) —
//    this freezes V1's live shape.
// 3. Add your new properties to the duplicated V2 types.
// 4. Add both `SchemaV1.self` and `SchemaV2.self` to
//    `AppMigrationPlan.schemas` and write a `MigrationStage.custom`
//    (or `.lightweight` if it's purely additive) for V1 → V2.
// 5. Update `AppSchema.allModels` to point at `SchemaV2.models`.
// 6. Test with an existing TestFlight build's store before shipping.
//
// **Never** reference the same live @Model type from both V1.models and
// V2.models. That pattern — present in the previous file — defeats the
// entire VersionedSchema mechanism.

/// V1 baseline. Every @Model type currently shipped lives here.
/// Single source of truth until V2 is introduced per the header protocol.
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
            Nudge.self,
        ]
    }
}

/// Convenience for code that wants the current model list (e.g. the
/// developer-tools "Wipe All Data" action). Always points at the latest
/// schema version's models.
enum AppSchema {
    static var allModels: [any PersistentModel.Type] {
        SchemaV1.models
    }
}

// MARK: - Migration Plan

/// Single-baseline plan — no migrations needed until V2 is introduced
/// (see header of this file for the V2 recipe).
enum AppMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}
