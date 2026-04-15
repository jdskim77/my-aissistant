# SETUP

Bundle IDs, entitlements, capabilities, and signing setup for Thrivn — and a
fork checklist for spinning up a new app from this codebase.

## Targets

| Target                                | Purpose                          |
|---------------------------------------|----------------------------------|
| `MyAIssistant`                        | iOS app (main)                   |
| `MyAIssistantWatch Watch App`         | watchOS companion app            |
| `MyAIssistantWidgets`                 | WidgetKit extension (iOS + Watch widgets) |
| `MyAIssistantTests`                   | Unit tests for iOS               |
| `MyAIssistantWatch Watch AppTests`    | Unit tests for Watch             |
| `MyAIssistantWatch Watch AppUITests`  | UI tests for Watch               |

## Bundle Identifiers

| Target          | Bundle ID                                         |
|-----------------|---------------------------------------------------|
| iOS app         | `com.myaissistant.app`                            |
| Watch app       | `com.myaissistant.app.watch`                      |
| Widgets         | `com.myaissistant.app.widgets`                    |
| iOS tests       | `com.myaissistant.tests`                          |
| Watch tests     | `com.myaissistant.app.MyAIssistantWatch-Watch-AppTests` |
| Watch UI tests  | `com.myaissistant.app.MyAIssistantWatch-Watch-AppUITests` |

**Pattern:** `com.<company>.<app>` for iOS, `<iOS-id>.<extension>` for extensions and Watch.

## Deployment Targets

- iOS: **17.0**
- watchOS: **26.0**

(SwiftData + `@Observable` macro require iOS 17+; the Watch target uses the
modern `containerBackground` and vertical TabView APIs.)

## Capabilities (Signing & Capabilities tab)

### iOS app target

| Capability               | Why                                                       |
|--------------------------|-----------------------------------------------------------|
| iCloud (CloudKit)        | SwiftData CloudKit sync for user data                     |
| Push Notifications       | `aps-environment = development`                           |
| Sign in with Apple       | The only auth method (no email collection)                |
| Background Modes         | `fetch`, `processing`, `remote-notification`              |
| App Groups               | `group.com.myaissistant.shared` (Watch + Widgets share)   |

### Watch app target

| Capability               | Why                                                       |
|--------------------------|-----------------------------------------------------------|
| App Groups               | `group.com.myaissistant.shared` (read sync data)          |

### Widgets target

| Capability               | Why                                                       |
|--------------------------|-----------------------------------------------------------|
| App Groups               | `group.com.myaissistant.shared` (read sync data)          |

## Identifiers

| Type                | Value                              | Files                          |
|---------------------|------------------------------------|--------------------------------|
| App Group           | `group.com.myaissistant.shared`    | All three `.entitlements`      |
| iCloud Container    | `iCloud.com.myaissistant`          | iOS `.entitlements`            |
| Keychain accessGroup| `group.com.myaissistant.shared`    | `KeychainService.swift`        |

## Background Tasks (BGTaskScheduler)

Registered in `MyAIssistant/Info.plist` under `BGTaskSchedulerPermittedIdentifiers`:

- `com.myaissistant.daily-snapshot` — overnight pattern recompute
- `com.myaissistant.weekly-review` — Sunday weekly AI review
- `com.myaissistant.calendar-sync` — periodic EventKit pull

Handlers registered in `BackgroundTaskManager.register()` at app launch.

## Privacy Usage Strings (Info.plist)

| Key                                       | Used for                              |
|-------------------------------------------|---------------------------------------|
| `NSCalendarsUsageDescription`             | EventKit read access                  |
| `NSCalendarsFullAccessUsageDescription`   | EventKit write access (iOS 17+)       |
| `NSCameraUsageDescription`                | Scan event flyers                     |
| `NSMicrophoneUsageDescription`            | Voice input to AI chat                |
| `NSRemindersFullAccessUsageDescription`   | Two-way Apple Reminders sync          |
| `NSSpeechRecognitionUsageDescription`     | Speech-to-text                        |
| `NSUserNotificationsUsageDescription`     | Local check-in reminders              |

`ITSAppUsesNonExemptEncryption = false` is set so App Store uploads don't
trigger the export-compliance prompt every time.

## App Store Connect

- **Sign in with Apple** service ID is auto-managed by the capability.
- **StoreKit Configuration**: `StoreKit.storekit` file at project root for
  local sandbox testing. Product IDs are defined in `SubscriptionTier.swift`.
- **App Store Connect API key** (for CI uploads) is NOT in this repo;
  configure separately if/when CI is added.

## External Services

| Service             | Where keys live                              |
|---------------------|----------------------------------------------|
| Anthropic API       | User-entered, stored in Keychain (`anthropicAPIKey`) |
| OpenAI API (failover)| User-entered, stored in Keychain (`openAIAPIKey`)    |
| Sentry (crashes)    | DSN in `MyAIssistantApp.swift` init          |
| TelemetryDeck       | App ID in `MyAIssistantApp.swift` init       |

The Cloudflare Workers proxy backend is documented separately (not in this
repo); users can opt to use it instead of bringing their own API key.

## Known Setup Gotchas

1. **Watch app install fails on simulator** with a `WKApplication` Info.plist
   error. Workaround: install on a real Apple Watch, or rebuild the simulator
   destination. The build itself succeeds; only the simulator install path
   has this quirk.
2. **No SPM dependencies** — this project is pure Apple frameworks. Don't
   add transitive dependencies without a strong reason.
3. **Test target rot**: `MyAIssistantTests/UsageGateManagerTests.swift` had
   stale references that were trimmed during pre-fork cleanup. If you re-add
   gating tests, mirror the current `UsageGateManager` API.
4. **Two `WatchScheduleData.swift` copies** (one in iOS, one in Watch). They
   MUST stay structurally in sync — the smoke test in
   `WatchScheduleDataTests` covers the iOS side; verify the Watch side
   independently if you change the struct.
5. **MetricKit/BackgroundTasks/Speech** are unavailable when building the
   iOS scheme against `watchsimulator` SDK — always build with
   `-sdk iphonesimulator` for the iOS target.

---

# Forking Checklist

Replace these identifiers when forking to a new app. Find-and-replace is
mostly safe; verify each match is intentional.

| Find                                   | Replace with                              |
|----------------------------------------|-------------------------------------------|
| `com.myaissistant.app`                 | `com.<yourcompany>.<yourapp>`             |
| `com.myaissistant.app.watch`           | `com.<yourcompany>.<yourapp>.watch`       |
| `com.myaissistant.app.widgets`         | `com.<yourcompany>.<yourapp>.widgets`     |
| `com.myaissistant.tests`               | `com.<yourcompany>.<yourapp>.tests`       |
| `group.com.myaissistant.shared`        | `group.com.<yourcompany>.<yourapp>.shared`|
| `iCloud.com.myaissistant`              | `iCloud.com.<yourcompany>.<yourapp>`      |
| `com.myaissistant.daily-snapshot`      | `com.<yourcompany>.<yourapp>.<task>`      |
| `com.myaissistant.weekly-review`       | (delete or repurpose)                     |
| `com.myaissistant.calendar-sync`       | (delete or repurpose if not using calendar)|
| `MyAIssistant` (target/scheme name)    | `<YourApp>`                               |
| `Thrivn` (display name in copy)        | `<Your App Display Name>`                 |

After find-and-replace:

1. Open the project in Xcode → Signing & Capabilities → re-check every target's
   bundle ID, App Group, iCloud container, and Sign in with Apple capability.
2. Change the Team if needed.
3. Generate new App Store Connect entries with the new bundle IDs.
4. Update `BGTaskSchedulerPermittedIdentifiers` in Info.plist to match the
   new task identifiers (and delete handlers for tasks you don't need).
5. Update privacy usage strings to describe YOUR app's actual data use.
6. Replace `StoreKit.storekit` configuration with your fork's product IDs.
7. Strip the `STRIP LIST` files (Thrivn-specific domain — see the keeper-file
   header comments in each generic file for what to keep vs throw away).
8. Update `aps-environment` based on whether you're starting in dev/prod.
9. Generate new App Icon assets and replace the `Assets.xcassets` icon set.
10. Run the full build for both iOS and Watch targets to flush any missed refs.

## Schema / Persistence Notes

- SwiftData with versioned schema (see `Schema/` directory).
- CloudKit-synced via `cloudKitDatabase: .automatic`.
- Schema versions are immutable once shipped — every model change requires a
  new `VersionedSchema` and a `MigrationStage` (lightweight or custom).
- App Group container is required for the SwiftData store URL (so Watch can
  read it). Search `appGroupStoreURL()` for the pattern.
- A fork should:
  - Reset to a single `SchemaV1` containing only the fork's models.
  - Strip Thrivn-specific models (BalanceManager state, CheckInRecord,
    DailyBalanceCheckIn, LifeDimension, etc.).
  - Keep the migration plan scaffolding for future use.
