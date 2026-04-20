# My AIssistant — Version 1 Rebuild Guide

> **Date:** February 18, 2026
> **Platform:** iOS 17+ (SwiftUI, SwiftData)
> **Bundle ID:** `com.myaissistant.app`
> **No external dependencies.** No CocoaPods, SPM, or third-party libraries.
>
> **⚠️ This document is the V1 snapshot. The live code has evolved — read `MY_AISSISTANT_V1_REBUILD_ADDENDA.md` alongside this file for: the Compass feature (new tab replacing Patterns, full spec in `COMPASS_SPEC.md`), Habits, Focus Timer, 12-step onboarding (vs 5 here), and ~15 additional SwiftData models. When this doc and the addenda conflict, the addenda wins.**

---

## Table of Contents

1. [Overview](#1-overview)
2. [Project Setup](#2-project-setup)
3. [File Structure](#3-file-structure)
4. [Data Layer (Models)](#4-data-layer-models)
5. [Core Configuration](#5-core-configuration)
6. [Theme System](#6-theme-system)
7. [Services Layer](#7-services-layer)
8. [Managers Layer](#8-managers-layer)
9. [Views Layer](#9-views-layer)
10. [App Entry Point](#10-app-entry-point)
11. [Widgets](#11-widgets)
12. [Utilities](#12-utilities)
13. [Build & Run](#13-build--run)

---

## 1. Overview

My AIssistant is a personal assistant iOS app that provides:
- **Daily check-ins** (4x/day: morning, midday, afternoon, night) with AI-generated summaries
- **Schedule management** with task creation, completion, and calendar sync
- **Pattern tracking** (streaks, completion rates, mood trends, category breakdown)
- **AI chat assistant** powered by Claude API (Anthropic) with voice conversation mode
- **Calendar integration** (Apple Calendar via EventKit, Google Calendar via REST API + OAuth2)
- **Subscription tiers** (Free, Pro, Student, PowerUser) via StoreKit 2
- **5 color themes** (Natural, Ocean, High Contrast, Midnight, Twilight) with dark mode
- **Voice mode** (Speech-to-text via SFSpeechRecognizer, text-to-speech via AVSpeechSynthesizer)
- **AI greeting** on app launch with animated pulsing orb
- **Background tasks** (daily snapshots, weekly AI reviews, calendar sync)
- **Onboarding flow** (welcome → permissions → voice mode → subscription → complete)

### Architecture Pattern

- **State management:** SwiftData `@Model` objects queried via `@Query` and `FetchDescriptor`. Managers are injected via SwiftUI `Environment` using custom `EnvironmentKey` types.
- **Navigation:** 4-tab `CustomTabBar` (Home, Schedule, Patterns, Settings) + center AI button that opens `ChatView` as a sheet.
- **AI integration:** Protocol-based `AIProvider` with `AnthropicProvider` and `OpenAIProvider` implementations. Factory selects provider based on subscription tier.
- **Calendar integration:** `CalendarSyncManager` orchestrates `EventKitService` (Apple) and `GoogleCalendarService` (Google). AI chat can create/delete events via action tags parsed from responses.
- **Concurrency:** Services that make network calls are `actor` types. UI managers are `@MainActor`.

---

## 2. Project Setup

### Xcode Project

- **Project name:** `MyAIssistant`
- **Organization identifier:** `com.myaissistant`
- **Deployment target:** iOS 17.0
- **Swift version:** 5.9+
- **Targets:** `MyAIssistant` (main app), `MyAIssistantWidgets` (widget extension)

### Info.plist

```xml
<key>NSCalendarsUsageDescription</key>
<string>My AIssistant uses your calendar to sync events with your schedule and help you stay organized.</string>
<key>NSCalendarsFullAccessUsageDescription</key>
<string>Full calendar access lets My AIssistant create and update events to keep your schedule in sync.</string>
<key>NSSpeechRecognitionUsageDescription</key>
<string>My AIssistant uses speech recognition to let you talk to your AI assistant hands-free.</string>
<key>NSMicrophoneUsageDescription</key>
<string>My AIssistant needs microphone access to transcribe your voice into text for the AI assistant.</string>
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>com.myaissistant.daily-snapshot</string>
    <string>com.myaissistant.weekly-review</string>
    <string>com.myaissistant.calendar-sync</string>
</array>
<key>UIBackgroundModes</key>
<array>
    <string>fetch</string>
    <string>processing</string>
</array>
```

### Entitlements

```xml
<key>com.apple.security.application-groups</key>
<array>
    <string>group.com.myaissistant.shared</string>
</array>
```

### SwiftData Schema (7 models)

```swift
let schema = Schema([
    TaskItem.self,
    ChatMessage.self,
    CheckInRecord.self,
    DailySnapshot.self,
    UserProfile.self,
    UsageTracker.self,
    CalendarLink.self
])
let config = ModelConfiguration("MyAIssistant", isStoredInMemoryOnly: false)
let container = try! ModelContainer(for: schema, configurations: [config])
```

---

## 3. File Structure

```
MyAIssistant/
├── MyAIssistantApp.swift              # App entry point, manager creation, environment injection
├── ContentView.swift                   # CustomTabBar + sheet for ChatView
├── Core/
│   ├── AppConstants.swift             # API endpoints, model names, limits, keys
│   └── DependencyContainer.swift      # 7 custom EnvironmentKey types
├── Models/
│   ├── TaskItem.swift                 # @Model — main task/event entity
│   ├── TaskCategory.swift             # enum: travel, errand, personal, work, health
│   ├── TaskPriority.swift             # enum: high, medium, low
│   ├── ChatMessage.swift              # @Model — chat messages with conversationID
│   ├── CheckIn.swift                  # CheckInTime enum (morning/midday/afternoon/night)
│   ├── CheckInRecord.swift            # @Model — completed check-in records with mood/energy
│   ├── DailySnapshot.swift            # @Model — daily stats snapshot
│   ├── UserProfile.swift              # @Model — user settings/onboarding state
│   ├── UsageTracker.swift             # @Model — tier-based usage counting
│   └── CalendarLink.swift             # @Model — linked calendar reference
├── Services/
│   ├── AI/
│   │   ├── AIProvider.swift           # Protocol + AIResponse + AIError
│   │   ├── AnthropicProvider.swift    # Claude API actor with prompt caching
│   │   ├── OpenAIProvider.swift       # OpenAI GPT actor
│   │   ├── AIProviderFactory.swift    # Factory: tier → provider+model selection
│   │   └── AIPromptBuilder.swift      # System prompts for chat, check-in, weekly review
│   ├── Networking/
│   │   └── APIClient.swift            # Low-level HTTP POST actor
│   ├── Keychain/
│   │   └── KeychainService.swift      # iOS Keychain wrapper (read/save/delete)
│   ├── Calendar/
│   │   ├── EventKitService.swift      # Apple Calendar actor (EKEventStore CRUD)
│   │   └── GoogleCalendarService.swift # Google Calendar REST actor (OAuth2 + CRUD)
│   ├── Speech/
│   │   ├── SpeechRecognizer.swift     # STT with silence detection
│   │   ├── SpeechSynthesizer.swift    # TTS with delegate callbacks
│   │   ├── VoiceGreetingBuilder.swift # Consistent voice greetings
│   │   └── VariedGreetingBuilder.swift # Randomized home greetings
│   └── StoreKit/
│       ├── SubscriptionManager.swift  # StoreKit 2 product loading + purchasing
│       └── SubscriptionTier.swift     # Tier display metadata + features
├── Managers/
│   ├── TaskManager.swift              # Task CRUD, queries, AI context summary
│   ├── PatternEngine.swift            # Streak, completion rate, mood trend, weekly review
│   ├── CheckInManager.swift           # Check-in completion logic with AI prompts
│   ├── CalendarSyncManager.swift      # Orchestrates Apple + Google calendar sync
│   ├── GreetingManager.swift          # App launch greeting with 1-hour cooldown
│   ├── NotificationManager.swift      # Check-in and task reminders via UNUserNotification
│   ├── UsageGateManager.swift         # Tier-based usage limit enforcement
│   └── BackgroundTaskManager.swift    # BGTaskScheduler: snapshots, reviews, sync
├── Theme/
│   ├── ColorTheme.swift               # AppTheme enum + ColorTheme struct (26 colors)
│   ├── ThemeManager.swift             # Singleton with 5 theme definitions
│   ├── AppColors.swift                # Static color accessors + Color(hex:) extension
│   └── AppFonts.swift                 # System serif (display) + rounded (body) fonts
├── Views/
│   ├── Components/
│   │   ├── CustomTabBar.swift         # 4 tabs + center AI button
│   │   ├── TaskCard.swift             # Expandable task card with priority checkbox
│   │   ├── StatCard.swift             # Stat display card (icon, value, title)
│   │   ├── AIActivityOrb.swift        # 3-layer animated pulsing orb
│   │   ├── EmptyStateView.swift       # Empty state placeholder
│   │   ├── LoadingView.swift          # Skeleton loading animation
│   │   └── PaywallCard.swift          # Inline upgrade prompt
│   ├── Home/
│   │   ├── HomeView.swift             # Today dashboard with sections
│   │   ├── AIGreetingCard.swift       # Greeting card with orb + dismiss
│   │   └── CalendarEventRow.swift     # Calendar event row
│   ├── Schedule/
│   │   ├── ScheduleView.swift         # Timeline with filters, add form, dim past
│   │   ├── TaskDetailView.swift       # Task edit view
│   │   └── CalendarImportView.swift   # Calendar linking modal
│   ├── Chat/
│   │   ├── ChatView.swift             # Main chat with voice mode + calendar actions
│   │   ├── ChatBubble.swift           # Message bubble styling
│   │   ├── QuickActionsBar.swift      # Quick action chips
│   │   └── ConversationListView.swift # Conversation switcher
│   ├── CheckIns/
│   │   ├── CheckInsView.swift         # 4-slot check-in hub
│   │   ├── CheckInDetailView.swift    # Multi-step check-in flow
│   │   ├── CheckInHistoryView.swift   # Past check-in list
│   │   └── MoodPicker.swift           # 5-emoji mood selector
│   ├── Patterns/
│   │   ├── PatternsView.swift         # Analytics dashboard
│   │   ├── WeeklyChartView.swift      # Bar chart (Mon-Sun)
│   │   ├── CategoryBreakdownView.swift # Category progress bars
│   │   ├── MoodTrendView.swift        # 14-day mood line chart
│   │   └── WeeklyAIReviewView.swift   # AI weekly review display
│   ├── Settings/
│   │   ├── SettingsView.swift         # Settings hub navigation
│   │   ├── ThemePickerView.swift      # 5 theme selector grid
│   │   ├── APIKeySettingsView.swift   # Anthropic + OpenAI key input
│   │   ├── SubscriptionView.swift     # Tier cards with purchase
│   │   ├── CalendarSettingsView.swift # Calendar connection management
│   │   ├── NotificationSettingsView.swift # Reminder toggles
│   │   └── VoiceSettingsView.swift    # Voice selection + preview
│   └── Onboarding/
│       ├── OnboardingContainerView.swift # 5-step page flow
│       ├── WelcomeView.swift          # Feature highlights
│       ├── PermissionsView.swift      # Notification + mic permissions
│       ├── VoiceModeSelectionView.swift # Voice mode toggle
│       ├── SubscriptionOfferView.swift # Pro features showcase
│       └── OnboardingCompleteView.swift # Confetti celebration
├── Utilities/
│   ├── DateHelpers.swift              # Date extensions (isToday, startOfDay, etc.)
│   ├── DataSeeder.swift               # Sample data for first launch
│   └── PreviewHelpers.swift           # SwiftUI preview container
└── Widgets/
    ├── WidgetBundle.swift             # Widget bundle
    ├── TodayProgressWidget.swift      # Today's completion
    ├── NextCheckInWidget.swift        # Next check-in time
    └── StreakWidget.swift             # Current streak
```

---

## 4. Data Layer (Models)

### TaskItem (`@Model`)

The primary entity. Stores tasks and calendar events.

```swift
@Model
final class TaskItem {
    var id: String                    // UUID string
    var title: String
    var categoryRaw: String           // Stored as raw string for SwiftData compatibility
    var priorityRaw: String           // Stored as raw string
    var date: Date
    var done: Bool
    var icon: String                  // Emoji
    var notes: String
    var createdAt: Date
    var completedAt: Date?
    var externalCalendarID: String?   // "google:EVENT_ID" or Apple's eventIdentifier

    // @Transient computed accessors for category/priority enums
    @Transient var category: TaskCategory { get/set via categoryRaw }
    @Transient var priority: TaskPriority { get/set via priorityRaw }
}
```

**Important:** SwiftData `#Predicate` can only reference stored properties, not `@Transient`. Always filter on `categoryRaw`/`priorityRaw` strings in predicates.

### TaskCategory (enum)

```swift
enum TaskCategory: String, CaseIterable, Codable, Identifiable {
    case travel = "Travel"
    case errand = "Errand"
    case personal = "Personal"
    case work = "Work"
    case health = "Health"
    // Each has an icon emoji
}
```

### TaskPriority (enum)

```swift
enum TaskPriority: String, CaseIterable, Codable, Identifiable {
    case high = "High"
    case medium = "Medium"
    case low = "Low"
    // sortOrder: high=0, medium=1, low=2
}
```

### ChatMessage (`@Model`)

```swift
@Model
final class ChatMessage {
    var id: String
    var roleRaw: String              // "user" or "assistant"
    var content: String
    var timestamp: Date
    var conversationID: String       // Groups messages into conversations

    // @Transient computed role: MessageRole enum (.user, .assistant)
}
```

### CheckIn (enum, not a model)

```swift
enum CheckInTime: String, CaseIterable, Identifiable {
    case morning = "Morning"    // hour: 8,  icon: 🌅, color: AppColors.morning
    case midday = "Midday"      // hour: 13, icon: ☀️, color: AppColors.noon
    case afternoon = "Afternoon" // hour: 18, icon: 🌆, color: AppColors.afternoon
    case night = "Night"        // hour: 22, icon: 🌙, color: AppColors.night

    // Properties: title, hour, icon, color, greeting, motivationTip
}
```

### CheckInRecord (`@Model`)

```swift
@Model
final class CheckInRecord {
    var id: String
    var timeSlotRaw: String          // CheckInTime raw value
    var date: Date
    var mood: Int?                   // 1-5
    var energy: Int?                 // 1-5
    var notes: String
    var aiSummary: String?
    var completed: Bool
}
```

### DailySnapshot (`@Model`)

```swift
@Model
final class DailySnapshot {
    var id: String
    var date: Date
    var tasksTotal: Int
    var tasksCompleted: Int
    var checkInsCompleted: Int
    var checkInsTotal: Int           // Default: 4
    var averageMood: Double?
    var streakCount: Int
}
```

### UserProfile (`@Model`)

```swift
@Model
final class UserProfile {
    var id: String
    var displayName: String
    var onboardingCompleted: Bool
    var notificationsEnabled: Bool
    var calendarSyncEnabled: Bool
    var createdAt: Date
}
```

### UsageTracker (`@Model`)

Singleton pattern (`id = "usage-singleton"`). Tracks monthly chat messages and weekly check-ins for free tier limits. Has `resetIfNeeded()` that checks current month/week keys and resets counters when periods change.

```swift
// Key methods:
func canSendChat(tier:) -> Bool     // Free: < 10/month
func canDoCheckIn(tier:) -> Bool    // Free: < 5/week
func recordChatMessage(inputTokens:outputTokens:)
func recordCheckIn()
```

### CalendarLink (`@Model`)

```swift
@Model
final class CalendarLink {
    var id: String
    var source: String               // "apple" or "google"
    var calendarID: String
    var name: String
    var color: String                // Hex color string
    var enabled: Bool
    var lastSynced: Date?

    // @Transient var calendarSource: CalendarSource (enum)
}

enum CalendarSource: String {
    case apple, google
}
```

---

## 5. Core Configuration

### AppConstants

```swift
enum AppConstants {
    // API
    static let anthropicEndpoint = "https://api.anthropic.com/v1/messages"
    static let anthropicAPIVersion = "2023-06-01"

    // Models
    static let haikuModel = "claude-haiku-4-5-20251001"
    static let sonnetModel = "claude-sonnet-4-5-20250929"
    static let defaultMaxTokens = 1000

    // Free tier limits
    static let freeCheckInsPerWeek = 5
    static let freeChatMessagesPerMonth = 10

    // Check-in defaults
    static let defaultCheckInTimes: [Int] = [8, 13, 18, 22]
    static let taskReminderLeadMinutes = 30

    // Patterns
    static let defaultPatternWindowDays = 30
    static let weeklyReviewDay = 1           // Sunday
    static let weeklyReviewHour = 21         // 9 PM

    // Keychain keys
    static let anthropicAPIKeyKey = "com.myaissistant.anthropic-api-key"
    static let openAIAPIKeyKey = "com.myaissistant.openai-api-key"
    static let googleAccessTokenKey = "com.myaissistant.google-access-token"
    static let googleRefreshTokenKey = "com.myaissistant.google-refresh-token"
    static let googleTokenExpiryKey = "com.myaissistant.google-token-expiry"

    // UserDefaults keys
    static let voiceModeDefaultKey = "voiceModeDefault"
    static let selectedVoiceIDKey = "selectedVoiceID"
    static let appThemeKey = "appTheme"
    static let googleClientIDKey = "googleClientID"
    static let lastGreetedTimestampKey = "lastGreetedTimestamp"
    static let lastGreetingTextKey = "lastGreetingText"

    // App Group
    static let appGroupID = "group.com.myaissistant.shared"

    // StoreKit Product IDs
    enum ProductID {
        static let proMonthly = "com.myaissistant.pro.monthly"
        static let proAnnual = "com.myaissistant.pro.annual"
        static let studentMonthly = "com.myaissistant.student.monthly"
        static let studentAnnual = "com.myaissistant.student.annual"
        static let powerUserMonthly = "com.myaissistant.poweruser.monthly"
        static let powerUserAnnual = "com.myaissistant.poweruser.annual"
    }
}
```

### DependencyContainer

7 custom `EnvironmentKey` types for dependency injection:

| Key | Type | Default |
|-----|------|---------|
| `TaskManagerKey` | `TaskManager?` | `nil` |
| `PatternEngineKey` | `PatternEngine?` | `nil` |
| `KeychainServiceKey` | `KeychainService` | `KeychainService()` |
| `SubscriptionTierKey` | `SubscriptionTier` | `.free` |
| `CheckInManagerKey` | `CheckInManager?` | `nil` |
| `CalendarSyncManagerKey` | `CalendarSyncManager?` | `nil` |
| `GreetingManagerKey` | `GreetingManager?` | `nil` |
| `UsageGateManagerKey` | `UsageGateManager?` | `nil` |

Each follows the pattern:
```swift
struct FooKey: EnvironmentKey { static let defaultValue: Foo? = nil }
extension EnvironmentValues {
    var foo: Foo? {
        get { self[FooKey.self] }
        set { self[FooKey.self] = newValue }
    }
}
```

---

## 6. Theme System

### 5 Themes

| Theme | Style | Dark? |
|-------|-------|-------|
| Natural | Warm cream/green | No |
| Ocean | Cool blue/teal | No |
| High Contrast | WCAG AAA, colorblind-safe | No |
| Midnight | True black (OLED) | Yes |
| Twilight | Soft dark with gold accents | Yes |

### ColorTheme Struct (26 color properties)

```
Layout:     background, surface, card, border
Accent:     accent, accentWarm, accentLight
Semantic:   gold, coral, skyBlue
Text:       textPrimary, textSecondary, textMuted
Check-in:   morning, noon, afternoon, night
Status:     overdueRed, overdueBg, completionGreen
Chat:       userBubbleText, aiBubble, aiBubbleText, aiBubbleBorder
Checkbox:   checkboxHigh, checkboxMedium, checkboxLow
```

### ThemeManager (Singleton)

`@Observable` class with `static let shared`. Persists selection to UserDefaults. Has `themeID: UUID` that changes on every theme switch — used with `.id(themeManager.themeID)` on the root view to force full re-render.

### AppColors (Static Accessors)

All colors delegate to `ThemeManager.shared.currentTheme`. Example:
```swift
static var accent: Color { theme.accent }
static func priorityColor(_ priority: TaskPriority) -> Color { ... }
static func checkboxColor(_ priority: TaskPriority) -> Color { ... }
```

### Color(hex:) Extension

Initializer that parses 6-digit or 8-digit hex strings into SwiftUI `Color`.

### AppFonts

All system fonts (no custom font files needed):
- `display/displayBold` — `.serif` design
- `heading` — `.rounded`, semibold
- `body/bodyMedium` — `.rounded`, regular/medium
- `caption` — `.rounded`, regular, 13pt default
- `label` — `.rounded`, semibold, 12pt default

### Natural Theme Colors (Default)

```
Background: #F8F5F0 (warm cream)
Surface: white
Card: #FFFEFB
Border: #E8E2D9
Accent: #2D5016 (deep green)
AccentWarm: #4A7C2F
AccentLight: #E8F0E0
Gold: #B8860B
Coral: #C94B2B
SkyBlue: #1A5276
TextPrimary: #1A1A14
TextSecondary: #544E3F
TextMuted: #6E6860
Morning: #FF9500, Noon: #34C759, Afternoon: #007AFF, Night: #5856D6
```

---

## 7. Services Layer

### AIProvider Protocol

```swift
protocol AIProvider: Sendable {
    func sendMessage(userMessage: String, conversationHistory: [ChatMessage], systemPrompt: String) async throws -> AIResponse
}

struct AIResponse {
    let content: String
    let inputTokens: Int
    let outputTokens: Int
}

enum AIError: LocalizedError {
    case invalidResponse, apiError(statusCode: Int, message: String), parsingError, noAPIKey, rateLimited, networkError(Error)
}
```

### AnthropicProvider (actor)

- POST to `https://api.anthropic.com/v1/messages`
- Headers: `content-type`, `x-api-key`, `anthropic-version: 2023-06-01`
- Uses **prompt caching** for system prompt: `"cache_control": ["type": "ephemeral"]`
- Sends last 10 messages of conversation history
- Parses `content[0].text` and `usage.input_tokens`/`output_tokens`

### OpenAIProvider (actor)

- POST to `https://api.openai.com/v1/chat/completions`
- Default model: `gpt-4o`
- System prompt as first message with role "system"
- Parses `choices[0].message.content` and `usage.prompt_tokens`/`completion_tokens`

### AIProviderFactory

```
Free tier       → Haiku (all use cases)
Pro/Student     → Sonnet (chat, weekly review), Haiku (check-in)
PowerUser       → OpenAI if key set, else Sonnet
```

### AIPromptBuilder

Three system prompt builders:

1. **chatSystemPrompt** — Includes schedule summary, stats, optional calendar action instructions
   - Calendar actions: `[[CREATE_EVENT:Title|YYYY-MM-DD HH:mm|YYYY-MM-DD HH:mm|Description]]` and `[[DELETE_EVENT:event_id]]`
   - Accepts `hasGoogleCalendar` and `hasAppleCalendar` bools
2. **checkInPrompt** — Time-of-day context, mood if provided
3. **weeklyReviewPrompt** — Week stats, tasks, mood average

### APIClient (actor)

Lightweight `URLSession` wrapper with a `post(url:headers:body:)` method returning `(data: Data, statusCode: Int)`.

### KeychainService

Wraps iOS Keychain with `read(key:)`, `save(key:value:)`, `delete(key:)`. Convenience methods: `anthropicAPIKey()`, `saveAnthropicAPIKey(_:)`, `openAIAPIKey()`, `saveOpenAIAPIKey(_:)`.

### EventKitService (actor)

Wraps `EKEventStore` for Apple Calendar:
- `requestAccess()` — Uses `requestFullAccessToEvents()` on iOS 17+
- `availableCalendars()` — Returns `[EKCalendar]`
- `events(in:from:to:)` — Fetch events by calendar IDs
- `createEvent(title:startDate:endDate:notes:calendarID:)` — Returns `eventIdentifier`
- `updateEvent(identifier:title:startDate:endDate:notes:)`
- `deleteEvent(identifier:)`
- `storeChanges()` — `AsyncStream<Void>` via `EKEventStoreChanged` notification

### GoogleCalendarService (actor)

Full OAuth2 flow + REST API:

**Authentication:**
- `ASWebAuthenticationSession` for OAuth consent
- Token exchange: `https://oauth2.googleapis.com/token`
- Tokens persisted to Keychain (access, refresh, expiry)
- Auto-refresh 60 seconds before expiry
- 401 retry via `authenticatedData(for:)` wrapper

**API methods:**
- `fetchCalendars()` → `[GoogleCalendar]`
- `fetchEvents(calendarID:from:to:)` → `[GoogleEvent]`
- `createEvent(calendarID:title:startDate:endDate:description:)` → event ID string
- `updateEvent(calendarID:eventID:title:startDate:endDate:description:)`
- `deleteEvent(calendarID:eventID:)`

**Data types:** `GoogleCalendar`, `GoogleEvent`, `GoogleDateTime` (all Codable)

### SpeechRecognizer (`@Observable @MainActor`)

- Uses `SFSpeechRecognizer` + `AVAudioEngine`
- `transcript: String` — live transcription result
- `isRecording: Bool`
- `silenceTimeout: TimeInterval` — default 2 seconds
- `onSilenceDetected: (() -> Void)?` — callback for auto-send
- Permission flow with `requestPermission()` async

### SpeechSynthesizer (`@Observable @MainActor`)

- Wraps `AVSpeechSynthesizer`
- `isSpeaking: Bool`
- `onFinishedSpeaking: (() -> Void)?` — callback for auto-listen loop
- `selectedVoiceIdentifier: String?` — custom voice selection
- Configures audio session for playback

### VoiceGreetingBuilder / VariedGreetingBuilder

Both are `enum` types with a static `greeting(...)` method. `VoiceGreetingBuilder` is consistent (used for voice chat greeting). `VariedGreetingBuilder` uses `.randomElement()!` for varied phrasing (used for home screen greeting card). Both build greetings from: time of day + schedule snippet + motivational snippet.

### SubscriptionManager (`@MainActor ObservableObject`)

StoreKit 2 integration:
- `loadProducts()` — `Product.products(for:)` with 6 product IDs
- `purchase(_ product:)` — With verification
- `restore()` — Sync transactions
- `updateTier()` — Checks `Transaction.currentEntitlements` to determine tier
- `listenForTransactions()` — Background task for real-time updates

### SubscriptionTier

```swift
enum SubscriptionTier: String { case free, pro, student, powerUser }
```

Extension with `displayName`, `monthlyPrice`, `annualPrice`, `features: [String]`, `monthlyProductID`, `annualProductID`.

---

## 8. Managers Layer

### TaskManager (`@MainActor ObservableObject`)

CRUD + queries on `TaskItem`:

```swift
addTask(_:), toggleCompletion(_:), deleteTask(_:), rescheduleTask(_:to:)
todayTasks(), upcomingTasks(limit:), highPriorityUpcoming(limit:), allTasks()
tasksGroupedByDate(category:) → [(date: Date, tasks: [TaskItem])]
tasksForCheckIn(_:) // Returns context-appropriate tasks per time slot
scheduleSummary() → String // For AI context, includes {id:...} for calendar events
```

### PatternEngine (`@MainActor ObservableObject`)

Analytics computed from SwiftData queries:

```swift
currentStreak() → Int              // Consecutive days with completed tasks
completionRate(days:) → Int        // Percentage
averageTasksPerDay(days:) → Double
weeklyCompletions() → [Int]        // 7 values, Mon-Sun
checkInConsistency() → [Bool]      // Last 7 days
categoryBreakdown() → [(category, done, total)]
bestCheckInTime() → String
moodTrend(days:) → [MoodDataPoint] // Date + mood + completion rate
moodProductivityCorrelation() → Double? // Pearson correlation
generateWeeklyReview(tier:)        // Async: calls AI, saves to "weekly-review" conversation
```

### CheckInManager (`@MainActor ObservableObject`)

```swift
completeCheckIn(timeSlot:mood:energy:notes:tier:scheduleSummary:completionRate:streak:) async
// Creates CheckInRecord, calls AI for summary, records usage
isCheckInCompleted(timeSlot:date:) → Bool
recentCheckIns(limit:) → [CheckInRecord]
```

### CalendarSyncManager (`@MainActor ObservableObject`)

Orchestrates both calendar services:

```swift
// Apple Calendar
appleCalendarAuthorized: Bool
requestAppleCalendarAccess() → Bool
syncAppleCalendar(days:)
pushTaskToAppleCalendar(_:calendarID:) → String

// Google Calendar
googleCalendarConnected() → Bool
syncGoogleCalendar(days:)
pushTaskToGoogleCalendar(_:calendarID:) → String

// Calendar Links (SwiftData)
linkedCalendars(), enabledCalendarLinks()
linkCalendar(source:calendarID:name:color:)
unlinkCalendar(_:), toggleCalendarLink(_:)

// Full sync
syncAll()
deleteCalendarEvent(for:) // Routes to Google or Apple based on ID prefix
```

### GreetingManager (`@Observable @MainActor`)

```swift
var currentGreeting: String
var isShowingGreeting: Bool

generateGreetingIfNeeded(todayTaskCount:completedTodayCount:highPriorityTitles:completionRate:streak:) → Bool
// Returns true if fresh greeting, false if cached (within 1-hour cooldown)
// Uses UserDefaults for lastGreetedTimestamp + lastGreetingText

dismissGreeting() // Animated hide
```

### NotificationManager (`@MainActor ObservableObject`)

```swift
requestAuthorization() → Bool
scheduleCheckInReminders()    // 4 daily repeating notifications
scheduleTaskReminder(taskID:title:date:)  // 30 min before
cancelTaskReminder(taskID:)
cancelAllReminders()
```

Registers notification categories: `CHECKIN` (with "Start Check-in" action) and `TASK` (with "Mark Done" action).

### UsageGateManager (`@MainActor ObservableObject`)

Wraps `UsageTracker` model with tier-aware checks:
```swift
canSendChat(tier:) → Bool
canDoCheckIn(tier:) → Bool
remainingChatMessages, remainingCheckIns
recordChatMessage(inputTokens:outputTokens:)
recordCheckIn()
```

### BackgroundTaskManager (`@MainActor`)

Registers 3 `BGTask` types:
1. **Daily snapshot** — After midnight, creates `DailySnapshot`
2. **Weekly review** — Sunday 9 PM, calls `patternEngine.generateWeeklyReview`
3. **Calendar sync** — Hourly, calls `calendarSyncManager.syncAppleCalendar()`

---

## 9. Views Layer

### ContentView

`CustomTabBar` with 4 tabs: Home, Schedule, Patterns, Settings. Center AI button opens `ChatView` as a `.fullScreenCover` or `.sheet`. Tracks `onboardingCompleted` from `UserProfile` to show `OnboardingContainerView` first.

### CustomTabBar

4 tab items (Home `house.fill`, Schedule `calendar`, Patterns `chart.bar.fill`, Settings `gearshape.fill`) + center AI button (gradient circle with "✦" symbol). Badge count on Schedule tab for pending today tasks.

### HomeView

Today dashboard with collapsible sections:
- **AI greeting card** (top) — `AIGreetingCard` with `AIActivityOrb`, auto-dismiss after 30 seconds
- **Header** — Time-appropriate greeting, date, next check-in pill
- **Stats bar** — Progress ring, task counts, streak, overdue badge
- **Overdue section** (red, collapsible) — Past-due incomplete tasks
- **Today section** — Active tasks with `TaskCard`
- **Completed section** (collapsible) — Done tasks (dimmed)
- **Tomorrow section** (collapsible)
- **"All done" celebration** when all today tasks complete

### AIGreetingCard

HStack: `AIActivityOrb` (36pt) | VStack("Your AI Assistant" + greeting text) | dismiss X button. Card styling: `AppColors.card` background, 14pt corners, gradient border stroke.

### AIActivityOrb

3-layer animated orb:
- **Layer 1 (core):** 40pt gradient circle (accent → accentWarm), scales 0.96–1.06, 1.0s animation
- **Layer 2 (halo):** 1.3x size, semi-transparent, scales 0.92–1.12, 1.4s animation
- **Layer 3 (glow):** 1.8x size, blurred gold, scales 0.95–1.15, 1.8s animation
- **Center:** "✦" symbol
- Phase-shifted durations create organic "breathing"
- `isActive: Bool` toggles animation, `size: CGFloat` defaults to 40

### ScheduleView

- **Category filter pills** (All, Travel, Errand, Personal, Work, Health)
- **Add task form** (collapsible) with icon picker grid, title field, date picker, category/priority selectors
- **Past dates** — Collapsed by default, dimmed at 60% opacity
- **Today divider** — Accent-colored separator
- **Future dates** — Expanded
- Each date group: date badge (pulsing for today), task count, list of `TaskCard`
- Calendar import inline prompt

### TaskCard

Expandable card with:
- Priority-colored checkbox (tap to toggle)
- Icon + title + time
- Overdue indicator (red background)
- Expanded: notes, category badge, priority badge, calendar source label
- `PriorityBadge` subview with colored text

### ChatView

Complex view with:

**Header:** `AIActivityOrb` (pulses when AI typing or speaking) + "AI Assistant" title + voice toggle + conversation switcher

**Messages:** `ConversationMessages` inner view uses `@Query` filtered by `conversationID`

**Input bar:** TextField + mic button (with recording pulse) + send button

**Voice mode loop:**
1. On appear: play greeting via `SpeechSynthesizer`
2. After AI finishes speaking → auto-start recording
3. On silence detected → auto-send transcript
4. Repeat

**Calendar action flow:**
1. AI response may contain `[[CREATE_EVENT:...]]` or `[[DELETE_EVENT:...]]` tags
2. `parseCalendarActions(from:)` extracts actions and strips tags from display text
3. `executeCalendarActions(_:)` routes to Google or Apple Calendar:
   - Google: if google calendar link exists
   - Apple: fallback via `EventKitService`
4. Creates/deletes local `TaskItem` linked to the calendar event

**System prompt construction:**
```swift
let enabledLinks = calendarSyncManager?.enabledCalendarLinks() ?? []
let hasGoogle = enabledLinks.contains { $0.calendarSource == .google }
let hasApple = enabledLinks.contains { $0.calendarSource == .apple }
    || calendarSyncManager?.appleCalendarAuthorized == true
// Both flags passed to AIPromptBuilder.chatSystemPrompt(...)
```

### ChatBubble

User messages: right-aligned, accent gradient background, white text
AI messages: left-aligned, `aiBubble` background, `aiBubbleText` color, subtle border
Both: text selection enabled, context menu for copy, timestamp

### CheckInsView

Horizontal tabs for 4 check-in times with completion checkmarks. Selected check-in shows:
- Summary card (title, greeting, stats)
- Motivation/tip card
- Start check-in button (disabled if completed, gated for free tier)
- Context-specific task section per time slot
- History button

### CheckInDetailView

Multi-step flow: greeting → mood picker → energy picker → notes → complete. Calls `CheckInManager.completeCheckIn(...)` which uses AI for summary.

### PatternsView

4 metric cards (streak, completion %, avg tasks/day, best check-in time) + WeeklyAIReview + MoodTrendView + WeeklyChartView + check-in consistency grid (7 boxes) + CategoryBreakdownView.

### WeeklyAIReviewView

Shows last AI review from "weekly-review" conversation. "Generate Review" button calls `patternEngine.generateWeeklyReview(tier:)`. Pro+ only.

### SettingsView

Grouped navigation list:
- **Appearance:** Theme picker
- **Account:** Subscription, API Keys
- **Preferences:** Notifications, Voice, Calendar
- **About:** Version, privacy, terms

### CalendarSettingsView

- Apple Calendar: permission status, link/unlink
- Google Calendar: Client ID input, OAuth sign-in flow via `ASWebAuthenticationSession`, auto-link primary calendar
- Linked calendars list with enable/disable toggles

### Onboarding Flow

5 steps in `OnboardingContainerView`:
1. `WelcomeView` — Feature highlights
2. `PermissionsView` — Notifications + microphone
3. `VoiceModeSelectionView` — Default voice toggle
4. `SubscriptionOfferView` — Free vs Pro
5. `OnboardingCompleteView` — "You're all set!" with confetti

---

## 10. App Entry Point

### MyAIssistantApp

```swift
@main
struct MyAIssistantApp: App {
    let modelContainer: ModelContainer

    // All managers created in init() with shared ModelContext
    @State private var taskManager: TaskManager
    @State private var patternEngine: PatternEngine
    @State private var checkInManager: CheckInManager
    @State private var calendarSyncManager: CalendarSyncManager
    @State private var usageGateManager: UsageGateManager
    @StateObject private var subscriptionManager = SubscriptionManager()
    private let keychainService = KeychainService()
    @State private var greetingManager = GreetingManager()
    @State private var themeManager = ThemeManager.shared
    private var backgroundTaskManager: BackgroundTaskManager?

    init() {
        // Create ModelContainer with all 7 model types
        // Create managers with container.mainContext
        // Register background tasks
        // Seed sample data (DataSeeder.seedIfEmpty)
        // Set up notification delegate
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .id(themeManager.themeID)  // Force re-render on theme change
                .preferredColorScheme(themeManager.selectedTheme.isDark ? .dark : .light)
                // Inject all managers via environment
                .environment(\.taskManager, taskManager)
                .environment(\.patternEngine, patternEngine)
                .environment(\.checkInManager, checkInManager)
                .environment(\.calendarSyncManager, calendarSyncManager)
                .environment(\.usageGateManager, usageGateManager)
                .environment(\.subscriptionTier, subscriptionManager.currentTier)
                .environment(\.keychainService, keychainService)
                .environment(\.greetingManager, greetingManager)
                .environmentObject(subscriptionManager)
                .task {
                    await subscriptionManager.updateTier()
                    await subscriptionManager.loadProducts()
                    backgroundTaskManager?.scheduleDailySnapshot()
                    backgroundTaskManager?.scheduleWeeklyReview()
                    backgroundTaskManager?.scheduleCalendarSync()
                }
        }
        .modelContainer(modelContainer)
    }
}
```

### NotificationDelegate

```swift
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()
    // Shows banner + sound for foreground notifications
    // Handles notification tap actions (deep linking placeholder)
}
```

---

## 11. Widgets

3 widgets in `MyAIssistantWidgets` target:

1. **TodayProgressWidget** — Shows today's task completion
2. **NextCheckInWidget** — Shows next scheduled check-in
3. **StreakWidget** — Shows current streak count

All use App Group (`group.com.myaissistant.shared`) for shared data access.

---

## 12. Utilities

### DateHelpers (Date Extension)

```swift
var startOfDay: Date
var endOfDay: Date
var isToday: Bool
var isTomorrow: Bool
func formatted(as format: String) -> String
static func from(month:day:year:hour:) -> Date
```

### DataSeeder

Seeds 13 sample `TaskItem` entries and 6 `CheckInRecord` entries on first launch. February 2026 dates centered around a Dubai trip (Feb 15-20).

### PreviewHelpers

Creates in-memory `ModelContainer` for SwiftUI Previews.

---

## 13. Build & Run

```bash
# Build
cd "/path/to/My AIssistant"
xcodebuild -project MyAIssistant.xcodeproj \
  -scheme MyAIssistant \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build

# Run in Xcode
open MyAIssistant.xcodeproj
# Select MyAIssistant scheme (NOT MyAIssistantWidgets)
# Build & Run (Cmd+R)
```

### Key Setup Steps

1. **API Key:** Add your Anthropic API key in Settings → API Keys
2. **Google Calendar (optional):** Enter Google Cloud Client ID in Settings → Calendar → Google Calendar section. Add test user email in Google Cloud Console → OAuth consent screen → Test users.
3. **Apple Calendar (optional):** Grant calendar permission when prompted. Link calendars in Settings → Calendar.
4. **Voice mode:** Grant microphone + speech recognition permissions.

---

## Rebuild Instructions for Claude

To rebuild this app from scratch using Claude:

1. **Create Xcode project:** New iOS App, SwiftUI, Swift, bundle ID `com.myaissistant.app`
2. **Add capabilities:** Background Modes (fetch, processing), App Groups
3. **Create file structure** matching Section 3
4. **Build in order:**
   - Models first (Section 4) — they have no dependencies
   - Core configuration (Section 5)
   - Theme system (Section 6)
   - Services (Section 7) — AIProvider protocol first, then implementations
   - Managers (Section 8) — they depend on models + services
   - Views (Section 9) — they depend on everything above
   - App entry point (Section 10) — wires everything together
   - Utilities + Widgets last
5. **Add Info.plist entries** for calendar, mic, speech, background tasks
6. **Add entitlements** for app group
7. **Register SwiftData schema** with all 7 model types
8. **Test:** Build, run, add API key, verify chat works

---

*Version 1 — February 18, 2026*
