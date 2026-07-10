# Audit — Schema V2 cost analysis
**Run:** /overnight 2026-05-04 pass 3
**Question:** if you had to ship a V2 migration tomorrow, what's the cost?

## Current state

- **`SchemaV1`** is the single baseline. `versionIdentifier = Schema.Version(1, 0, 0)`.
- **19 `@Model` types** registered (count verified — every `@Model` in `MyAIssistant/Models/` is in the V1 array).
- **`AppMigrationPlan.stages = []`** — no migration stages defined.
- **CloudKit-synced ModelContainer** with in-memory fallback (per [MyAIssistantApp.swift](MyAIssistant/MyAIssistantApp.swift) construction).

The header of [SchemaVersioning.swift](MyAIssistant/Models/SchemaVersioning.swift) is one of the best-documented files in the codebase. It includes a step-by-step recipe for adding V2 correctly:

> 1. DO NOT add properties to existing @Model classes in the main module.
> 2. Duplicate the current @Model classes into a nested namespace under a new `SchemaV2` type (`SchemaV2.TaskItem`, …) — this freezes V1's live shape.
> 3. Add your new properties to the duplicated V2 types.
> 4. Add both `SchemaV1.self` and `SchemaV2.self` to `AppMigrationPlan.schemas` and write a `MigrationStage.custom` (or `.lightweight` if it's purely additive) for V1 → V2.
> 5. Update `AppSchema.allModels` to point at `SchemaV2.models`.
> 6. Test with an existing TestFlight build's store before shipping.

This recipe is correct AND it explicitly warns against the prior footgun: "**Never** reference the same live @Model type from both V1.models and V2.models."

## Cost breakdown — additive-only V2

If V2 only **adds** properties (e.g. `var newField: String = ""` on TaskItem) with sensible defaults:

| Step | Cost |
|---|---|
| Duplicate the 1-3 affected `@Model` types into `SchemaV2.TaskItem`, etc. | 30 min per type |
| Add new properties to the V2 versions | per design |
| Add `SchemaV2.self` to `AppMigrationPlan.schemas` | 5 min |
| Write `MigrationStage.lightweight` from V1 to V2 | 15 min |
| Update `AppSchema.allModels` to V2 | 2 min |
| Update CloudKit schema in dashboard for any new fields | 30 min — needs CloudKit access |
| Test against a TestFlight build's store | 1-2h |
| **Total** | **~3-4h** for a clean additive V2 |

Today's session shipped one such additive change: `ChatMessage.isSafetyResource: Bool = false`. Per the file header, additive Bool with default is *lightweight* against V1 — no migration stage needed. **This is why it was safe.**

## Cost breakdown — V2 with a real migration

If V2 needs to:
- Rename a property
- Change a type (e.g. `Int` → `Decimal`)
- Split one model into two
- Merge two models into one
- Remove a property

Then it needs `MigrationStage.custom`:

| Step | Cost |
|---|---|
| Duplicate affected `@Model` types into V2 namespace | 30 min × N |
| Define V2 types with new shape | per design |
| Write `MigrationStage.custom` with `willMigrate` / `didMigrate` closures | 1-2h per non-trivial migration |
| Manual data transformation logic (e.g. iterate V1 records, derive V2 values, write back) | 2-4h depending on complexity |
| CloudKit schema update + deploy through the CK dashboard | 1h |
| Test path: stand up a V1 store, write known data, run V2 binary, verify migrated state | 2-3h |
| Edge case coverage: partial migration crash, app killed mid-migration, CloudKit conflict during migration | 2-3h |
| **Total** | **8-15h** for a single non-trivial migration |

## Risks specific to this codebase

### R1. CloudKit schema is not in source control
The CloudKit schema lives in Apple's CK dashboard. Source-controlled `@Model` types must match the dashboard schema or sync silently breaks. Without dashboard access the migration can't be validated end-to-end on the local-dev path.

**Mitigation:** the iOS team needs CloudKit access to validate schema changes. For solo-dev workflow, the developer is the iOS team — make sure access is set up before V2 is needed.

### R2. CloudKit and SwiftData migrations interact non-trivially
SwiftData's local migration runs on first launch of the new binary. CloudKit's schema migration must happen on the dashboard FIRST (preferably with backwards-compatible field additions). If a user's device is on V2 binary but the dashboard is still V1, sync errors result.

**Mitigation:** **deploy CloudKit schema changes BEFORE shipping the V2 binary.** Document this in the V2 recipe.

### R3. Existing TestFlight users have an active V1 store
Migration testing must include "user with real V1 data installs V2 binary" — not just "fresh install on V2 binary." The recipe step 6 mentions this; make sure the actual test happens.

### R4. UsageTracker has integrity check
[UsageTracker.swift](MyAIssistant/Models/UsageTracker.swift) has a `computeHash` + `integrityKey` that signs usage counts. If V2 changes any signed field, the integrity check breaks for migrated rows. Custom migration must re-compute the hash with V2's input set.

**Action:** when V2 touches UsageTracker, the migration MUST include hash re-computation. Don't rely on lightweight migration — it'll leave existing rows with V1 hashes that fail validation under V2 logic.

### R5. CheckInBehavior, CheckInPreference, CheckInSuggestion are tightly coupled to CheckInRecord
4-table check-in subsystem. Any migration that touches one needs to think about consistency across all 4. They use string-ID cross-references (per CLAUDE.md "no @Relationship anywhere"), so the migration is data-coordination not schema-relationship — but it's still 4 tables to keep consistent.

## Recommended action

### Before V2 is needed
1. **Verify CloudKit dashboard access** for the iOS dev account. ~5 min sanity check.
2. **Document the CloudKit schema in source** as a `.json` snapshot under `Models/CloudKitSchemaSnapshot.json` so source tracks it. ~30 min.
3. **Add a CI lane** that builds V1 from source, opens it against a fixture store, and asserts no warnings. ~1h. Catches accidental V1 schema changes before they ship.

### When V2 lands
4. Follow the file-header recipe **literally**. Don't skip steps.
5. Add a `MigrationLogTests.swift` that exercises the migration path with synthetic V1 data. ~3h once.
6. Run on a TestFlight binary's installed store before shipping. **Required.**

### Anti-pattern to never repeat
The file header explicitly warns about a prior failure mode: V1 and V2 sharing the same `models` array (so V1→V2 was a no-op). **Don't do this.** When you write V2, verify `SchemaV1.models` and `SchemaV2.models` reference DIFFERENT type lists.

## Today's session-related note

`ChatMessage.isSafetyResource: Bool = false` (added today) is one of the changes that's safe under the single-baseline / lightweight policy. No V2 needed. But if a SECOND additive property arrives that doesn't have a sensible default (e.g. a non-optional new field with no obvious zero), V2 becomes mandatory.

Watch list for properties that may need V2 soon:
- Any new `@Model` type — V1 array must be updated AND ModelContainer rebuilt at relaunch (which works automatically).
- A non-Bool, non-optional, no-default new property on an existing model — needs V2.
- A type change on an existing property — needs V2.

## Critical takeaway

**The architecture is right.** The single-baseline policy + clear V2 recipe + CloudKit warning are all in the file header. The V1 model array is complete and matches the @Model types in source. Today's `isSafetyResource: Bool = false` addition followed the policy correctly.

The biggest risk is **forgetting** the recipe when V2 is finally needed. Adding a CI lane that asserts schema consistency would lock that in. Otherwise, the cost estimate stands: ~3-4h for a clean additive V2, ~8-15h for a real migration.
