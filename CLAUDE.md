# CLAUDE.md — Thrivn (folder: My AIssistant)

**Brand / product:** Thrivn
**Folder / codebase:** `/Users/joekim/Claude/My AIssistant/`
**Xcode project:** `MyAIssistant.xcodeproj`
**Bundle ID:** `com.myaissistant.app`

The product is branded **Thrivn** for user-facing copy. The folder, Xcode project, bundle ID, and internal code references still use the legacy name "My AIssistant" / `myaissistant`. Match the context: user-facing → Thrivn, code paths → `MyAIssistant`.

**Sources of truth for architecture (read in this order):**

1. **`MY_AISSISTANT_V1_REBUILD.md`** — V1 spec snapshot (Feb 18 2026). App-level architecture, DI, 7-model core, calendar sync, voice mode, subscription tiers. Read first for the foundations.
2. **`MY_AISSISTANT_V1_REBUILD_ADDENDA.md`** — Deltas since the V1 freeze. Compass feature, Habits, Focus Timer, 12-step onboarding, ~15 additional SwiftData models, schema versioning. When this conflicts with the rebuild doc, the addenda wins.
3. **`MyAIssistant/COMPASS_SPEC.md`** — Authoritative spec for the Compass feature (scoring, check-ins, season goals, nudges, dimension learning). Read first for any Compass / Pillar 3 work.

This file composes additively with the workspace file at `/Users/joekim/Claude/CLAUDE.md`. Read both.

---

## What It Is

Thrivn is a **voice-native AI coach** for iOS (iOS 17+, SwiftUI, SwiftData) that notices what you're neglecting and nudges you to act on it across body, mind, heart, and spirit. Not a tracker. Not a journal. A coach that talks and pushes, with your permission.

Everything else in the app exists to sharpen the coach's nudges:

- **Proactive AI coaching** — the spine. Powered by Claude (Sonnet / Haiku) or OpenAI (PowerUser tier). Reaches out on its own based on dimension weakness, streak breaks, calendar gaps, and stated goals. Voice-first; typing is the fallback.
- **Check-ins** (up to 4×/day: morning 8am, midday 1pm, afternoon 6pm, night 10pm) — calibration input for the coach. Voice-first capture; AI extracts mood, energy, and context.
- **Habits + Tasks** — the actionable surface. Every item carries a dimension tag. Completion feeds the coach's model of what the user is and isn't tending.
- **Dimensions (Body / Mind / Heart / Spirit)** — invisible taxonomy that weights tasks, targets nudges, and drives the progress bars on Today. Not a dashboard.
- **Calendar integration** — Apple Calendar (EventKit) + Google Calendar (REST + OAuth2). Coach can create/delete events via action tags.
- **Subscription tiers** (Free / Pro / Student / PowerUser) via StoreKit 2.
- **5 color themes** (Natural, Ocean, High Contrast, Midnight, Twilight).
- **Widgets** — TodayProgress, NextCheckIn, Streak.
- **Background tasks** — on-device rules engine for nudge triggers, daily snapshot, weekly review (Sunday 9pm), hourly calendar sync.
- **Watch companion** — check-in, day list, task completion on the wrist.

**Zero external dependencies.** No CocoaPods, no SPM, no third-party libraries.

---

## Product Pillars

Thrivn is a coach, not a tracker. One pillar is the spine — the other two are instruments that sharpen it. Every feature must make the coach's next nudge more accurate, better-timed, or more specific. If it doesn't, it doesn't ship.

### 1. Proactive coaching *(the spine)*
The AI notices what the user is neglecting — weak dimensions, broken streaks, calendar gaps, stated goals, shifts in mood or energy — and reaches out on its own with specific, well-timed nudges the user didn't ask for but is glad to receive. Voice-first; typing is the fallback. Acts on the user's behalf with consent, not at distance.

Not a cheerleader. Not a drill sergeant. An **agent with consented reach**.

**Make-or-break behavior:** one uncannily-timed nudge per week earns word of mouth. One wrong nudge earns uninstall. Everything else in the product exists to improve the hit rate.

### 2. Ritual as calibration input *(instrument)*
Up to four brief check-ins per day feed the coach fresh signal about mood, energy, and life context. The check-in is not a destination — it's how the coach knows what to nudge about. Voice-first wherever possible; typing is friction. If a check-in flow doesn't tighten coaching accuracy, simplify or cut it.

### 3. Dimensions as taxonomy *(instrument)*
Body, Mind, Heart, Spirit are the axes along which tasks get weighted and nudges get targeted. They live as invisible infrastructure — driving progress bars on Today and routing the coach's attention. Not a dashboard. Not a radar chart. The taxonomy stays; the visualization dies.

The user should feel nudged, not audited.

### Feature Evaluation Filter

Before building any new feature:

1. **Does this sharpen the coach's next nudge?** If it makes the nudge more specific, better-timed, or more relevant — build it. If not — kill it, regardless of how polished the concept looks.
2. **Instrument or destination?** Instruments feed the coach. Destinations compete with it. New screens must earn their tab cost by visibly improving coaching accuracy; otherwise, fold them into the coach.
3. **Would the coach be worse without it?** If the coach nudges just as well without this feature — defer.

---

## Non-goals

Explicitly OUT of scope:

- **Therapy or clinical claims.** The coach nudges toward action; it does not diagnose, treat, or prevent any condition (FDA SaMD threshold).
- **Journaling app.** Reflection is an input to coaching, not the product. Check-ins calibrate the coach; they aren't a diary to revisit.
- **Generic task manager.** Tasks serve the coach's model of what the user is tending, not a standalone productivity system. Completion % is diagnostic, never the goal.
- **Quantified-self dashboard.** Dimensions route the coach's attention; they are never a radar chart, scorecard, or leaderboard of self. Trend claims also require statistical honesty (see `personal-trend-detection`).
- **Destination screens for their own sake.** If a screen isn't sharpening the next nudge, it's dead weight. The coach is the destination.
- **Social features.** No feed, friends, leaderboards, sharing. Privacy is the wedge.
- **Cheerleading AI.** No "Great job!" after low-mood entries. No toxic positivity. Acknowledge, don't celebrate.
- **Crisis intervention.** Route to 988/Samaritans/findahelpline.com via `crisis-safety-protocols` skill.
- **Cross-user comparison.** "Users like you" is manipulative.
- **Unsolicited nudges without consent.** Proactivity is always opt-in, always tunable, always silenceable. The coach acts on the user's behalf — not at the user.
- **Third-party SDKs** unless replacing >50 lines of Foundation code.

---

## Build & Run

```bash
xcodebuild -project MyAIssistant.xcodeproj \
  -scheme MyAIssistant \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build
```

Open in Xcode:

```bash
open MyAIssistant.xcodeproj
```

**Targets:**
- `MyAIssistant` (main iOS app)
- `MyAIssistantWidgets` (widget extension)
- `MyAIssistantWatch Watch App` (watchOS companion)
- `MyAIssistantTests`, `MyAIssistantWatch Watch AppTests`, `MyAIssistantWatch Watch AppUITests`

**Key setup on fresh install:**
1. Add Anthropic API key in Settings → API Keys (stored in Keychain).
2. Optional: Google Cloud Client ID in Settings → Calendar for Google Calendar OAuth.
3. Optional: Grant Apple Calendar permission on prompt.
4. Optional: Microphone + speech recognition permissions for voice mode.

---

## Status

**V1 spec + post-freeze feature additions.** The V1 rebuild doc describes the foundation. The addenda describes three load-bearing features added after the V1 freeze:

- **Compass** (replaces the Patterns tab) — Pillar 3's visible surface. Spec: `MyAIssistant/COMPASS_SPEC.md`.
- **Habits** — full habit tracker with multi-dimension tagging, dimension-colored rows, streak math.
- **Focus Timer** — lightweight focus/pomodoro session.
- **12-step onboarding** (vs the rebuild doc's 5) — Sign in with Apple, name capture, Compass reveal, starter tasks, intention capture.

Schema is at V4 (see `Models/SchemaVersioning.swift`). Live `ModelContainer` registers all models in addenda §A, not the rebuild doc's 7-model subset.

Open engineering work:
- No CI yet.
- No comprehensive test suite yet — test targets exist but coverage is thin.
- Production API key pipeline: must route through a proxy or user-supplied key (Keychain); never bundle.

See `prototype-to-production` skill for the sequencing to first TestFlight.

---

## Architecture

### Stack

- **iOS 17+**, SwiftUI, Swift 5.9+
- **SwiftData** for persistence (7 `@Model` types — see below)
- **`@Observable` managers** injected via custom `EnvironmentKey` types (not `@EnvironmentObject`)
- **`actor` types** for network-bound services; **`@MainActor`** for UI managers
- **No external package dependencies**

### SwiftData schema (7 models)

```swift
let schema = Schema([
    TaskItem.self,          // tasks + calendar-linked events
    ChatMessage.self,       // chat with conversationID grouping
    CheckInRecord.self,     // 4×/day check-in with mood/energy
    DailySnapshot.self,     // daily stats cache
    UserProfile.self,       // onboarding state, display name
    UsageTracker.self,      // singleton tier-based usage counter
    CalendarLink.self       // linked Apple/Google calendars
])
```

**SwiftData rules:**
- Store enums as `rawValue` strings (`categoryRaw`, `priorityRaw`, `roleRaw`, `timeSlotRaw`) with `@Transient` computed accessors. `#Predicate` can only reference stored properties.
- `UsageTracker` is a singleton (`id = "usage-singleton"`) with `resetIfNeeded()` for monthly/weekly resets.

### Navigation

**`CustomTabBar`** with 4 tabs + center AI button (verified in `ContentView.swift` + `Views/Components/CustomTabBar.swift`):

| Tab | Icon (selected) | Label | Purpose |
|-----|-----------------|-------|---------|
| Home | `checklist` | **Today** | Today dashboard — greeting card, stats, overdue, today, completed, tomorrow; plus `NudgeBannerView` (the only Compass element on Home) |
| Schedule | `calendar` | Schedule | Timeline with category filters, add form, dim past |
| **Compass** | `safari` / `safari.fill` | Compass | Radar chart, 3-signal breakdown, season goals, evening check-in, weekly reflection. **Replaces the Patterns tab** at the tab-bar level. Full spec in `MyAIssistant/COMPASS_SPEC.md`. |
| Settings | `gearshape.fill` | Settings | Appearance, Account (subscription + API keys), Preferences, About |

**Center AI button** (gradient circle, "✦" symbol) opens `ChatView` as a sheet / full-screen cover (`@State showingChat` in `ContentView`).

**Focus Timer** is also invoked as a modal from `ContentView` (`@State showingFocusTimer`, `@State focusDuration = 25`), not a separate destination.

`Views/Patterns/` still contains 6 files (`ActivityTimelineView`, `CategoryBreakdownView`, `MoodTrendView`, `PatternsView`, `WeeklyAIReviewView`, `WeeklyChartView`). They're no longer a tab but are **consumed into Compass views** and `DataExportService`. Do NOT delete them outright — check references first.

### Folder layout (V1 rebuild spec)

```
MyAIssistant/
├── MyAIssistantApp.swift       # @main, manager creation, environment injection
├── ContentView.swift           # CustomTabBar + ChatView sheet
├── Core/
│   ├── AppConstants.swift      # endpoints, model names, Keychain keys, product IDs
│   └── DependencyContainer.swift  # 8 custom EnvironmentKey types
├── Models/                     # 7 @Model types + enums (see SwiftData schema)
├── Services/
│   ├── AI/                     # AIProvider protocol + Anthropic + OpenAI + Factory + PromptBuilder
│   ├── Networking/             # APIClient (actor)
│   ├── Keychain/               # KeychainService
│   ├── Calendar/               # EventKitService + GoogleCalendarService (OAuth2)
│   ├── Speech/                 # STT + TTS + VoiceGreetingBuilder + VariedGreetingBuilder
│   └── StoreKit/               # SubscriptionManager + SubscriptionTier
├── Managers/                   # 8 @MainActor coordinators (see below)
├── Theme/                      # ColorTheme + ThemeManager (5 themes) + AppColors + AppFonts
├── Views/
│   ├── Components/             # CustomTabBar, TaskCard, StatCard, AIActivityOrb, EmptyStateView, LoadingView, PaywallCard
│   ├── Home/                   # HomeView + AIGreetingCard + CalendarEventRow
│   ├── Schedule/               # ScheduleView + TaskDetailView + CalendarImportView
│   ├── Chat/                   # ChatView + ChatBubble + QuickActionsBar + ConversationListView
│   ├── CheckIns/               # CheckInsView + CheckInDetailView + CheckInHistoryView + MoodPicker
│   ├── Patterns/               # PatternsView + WeeklyChartView + CategoryBreakdownView + MoodTrendView + WeeklyAIReviewView
│   ├── Settings/               # SettingsView + ThemePickerView + APIKeySettingsView + SubscriptionView + CalendarSettingsView + NotificationSettingsView + VoiceSettingsView
│   └── Onboarding/             # 5-step container (Welcome → Permissions → VoiceMode → Subscription → Complete)
├── Utilities/                  # DateHelpers, DataSeeder, PreviewHelpers
└── Widgets/                    # TodayProgressWidget, NextCheckInWidget, StreakWidget (in separate target)
```

### Managers (8 `@MainActor` coordinators)

| Manager | Purpose |
|---------|---------|
| `TaskManager` | Task CRUD, queries, `scheduleSummary()` for AI context |
| `PatternEngine` | Streak, completion rate, mood trend, weekly AI review |
| `CheckInManager` | Check-in completion with AI summary generation |
| `CalendarSyncManager` | Orchestrates Apple (EventKit) + Google (REST) calendars |
| `GreetingManager` | App-launch greeting with 1-hour cooldown |
| `NotificationManager` | Check-in reminders (4 daily) + task reminders (30 min lead) |
| `UsageGateManager` | Tier-based limit enforcement (Free: 10 chat/month, 5 check-ins/week) |
| `BackgroundTaskManager` | 3 `BGTask` registrations: daily snapshot, weekly review, calendar sync |

### AI integration

**Protocol-based `AIProvider`** with two implementations:

- **`AnthropicProvider` (actor)** — POST to `https://api.anthropic.com/v1/messages`; prompt caching enabled on system prompt; sends last 10 messages.
- **`OpenAIProvider` (actor)** — POST to `https://api.openai.com/v1/chat/completions`; default `gpt-4o`.

**Factory tier mapping:**

| Tier | Chat / Weekly review | Check-in |
|------|----------------------|----------|
| Free | Haiku | Haiku |
| Pro / Student | Sonnet | Haiku |
| PowerUser | OpenAI if key set, else Sonnet | Haiku |

**Models (pinned in `AppConstants`):**
- Haiku: `claude-haiku-4-5-20251001`
- Sonnet: `claude-sonnet-4-5-20250929`

**AI calendar actions** — responses can contain `[[CREATE_EVENT:Title|YYYY-MM-DD HH:mm|YYYY-MM-DD HH:mm|Description]]` and `[[DELETE_EVENT:event_id]]` tags, parsed client-side and routed to Apple or Google Calendar.

### Dependency injection

Custom `EnvironmentKey` types (NOT `@EnvironmentObject` on iOS 17+):

```swift
struct TaskManagerKey: EnvironmentKey { static let defaultValue: TaskManager? = nil }
extension EnvironmentValues {
    var taskManager: TaskManager? {
        get { self[TaskManagerKey.self] }
        set { self[TaskManagerKey.self] = newValue }
    }
}
```

Wired in `MyAIssistantApp.body`:

```swift
ContentView()
    .environment(\.taskManager, taskManager)
    .environment(\.patternEngine, patternEngine)
    // ... 6 more
    .environmentObject(subscriptionManager)
```

---

## Design System

**Brand:** warm, grounded, tactile. Serif for display trust; rounded sans for approachability.

### 5 themes (managed by `ThemeManager.shared`)

| Theme | Style | Dark? |
|-------|-------|-------|
| Natural | Warm cream / deep green (default) | No |
| Ocean | Cool blue / teal | No |
| High Contrast | WCAG AAA, colorblind-safe | No |
| Midnight | True black (OLED) | Yes |
| Twilight | Soft dark with gold accents | Yes |

`ThemeManager.themeID: UUID` changes on every theme switch — attach via `.id(themeManager.themeID)` to force re-render.

### 26-property `ColorTheme` struct

Layout: `background, surface, card, border`
Accent: `accent, accentWarm, accentLight`
Semantic: `gold, coral, skyBlue`
Text: `textPrimary, textSecondary, textMuted`
Check-in slots: `morning, noon, afternoon, night`
Status: `overdueRed, overdueBg, completionGreen`
Chat: `userBubbleText, aiBubble, aiBubbleText, aiBubbleBorder`
Checkbox: `checkboxHigh, checkboxMedium, checkboxLow`

### Natural theme (default) anchors

Cream `#F8F5F0` bg, deep green `#2D5016` accent, gold `#B8860B`, coral `#C94B2B`, sky blue `#1A5276`, text primary `#1A1A14`. Check-in colors: morning orange `#FF9500`, noon green `#34C759`, afternoon blue `#007AFF`, night purple `#5856D6`.

### Typography — `AppFonts`

System-only (no custom font files):
- `display / displayBold` — `.serif`
- `heading` — `.rounded`, semibold
- `body / bodyMedium` — `.rounded`, regular / medium
- `caption` — `.rounded`, 13pt default
- `label` — `.rounded`, semibold, 12pt default

### Accessibility

- Every interactive element has `accessibilityLabel`
- Dynamic Type mandatory — no hardcoded point sizes
- 44×44pt minimum touch targets
- `accessibilityReduceMotion` respected on `AIActivityOrb` and all transitions
- Color never the sole indicator of meaning (pair with icon/label)

---

## Relevant Skills

**Built specifically for Thrivn — use liberally here:**

| Skill | When |
|-------|------|
| `coaching-philosophy` | Any coach voice / tone work |
| `coaching-prompt-craft` | Editing Claude system prompts in `AIPromptBuilder` |
| `coach-eval-framework` | Regression testing prompt changes |
| `conversation-memory-design` | Chat history compression, cross-session continuity |
| `check-in-micro-ux` | `CheckInDetailView` flow, `MoodPicker`, reminder UX |
| `wellness-ritual-design` | Slot timing (8/13/18/22), question design, streak psychology |
| `personal-trend-detection` | `PatternEngine`, mood trend, trend-claim honesty |
| `goal-intention-architecture` | Future goal system (not yet in V1) |
| `llm-data-boundary` | What schedule / check-in content crosses to Claude |
| `crisis-safety-protocols` | Any free-text input path to the AI |

**Generally relevant:**

`claude-api`, `ai-integration`, `swiftui-state-concurrency`, `swiftdata-persistence`, `ios-networking`, `push-notifications`, `widgetkit`, `watchos-patterns`, `ios-background-lifecycle`, `storekit2-subscriptions`, `onboarding-activation`, `test-engineering`, `agentic-evals`, `accessibility`, `error-monitoring`, `analytics-instrumentation`, `security-privacy`, `privacy-vault`, `app-store-submission`, `prototype-to-production`, `design-system-architecture`, `visual-design-systems` (5 themes).

**Skills to NOT apply:**

`surf-data-apis`, `apple-wallet-passkit`, `barcode-generation`, `vision-ingestion`, `agentic-scraping`, `core-motion`, `core-location-mapkit`, `healthkit` (unless HealthKit integration is later added), `game-design-gamification` (anti-pattern per Non-goals).

---

## External Dependencies

- **Anthropic Claude API** — `https://api.anthropic.com/v1/messages`. Key in Keychain (`com.myaissistant.anthropic-api-key`). Prompt caching enabled.
- **OpenAI API** (PowerUser tier only) — `https://api.openai.com/v1/chat/completions`. Key in Keychain (`com.myaissistant.openai-api-key`).
- **Apple EventKit** — `EKEventStore` with `requestFullAccessToEvents()` on iOS 17+.
- **Google Calendar REST API** — OAuth2 via `ASWebAuthenticationSession`; tokens in Keychain; auto-refresh 60s before expiry.
- **Apple Speech** — `SFSpeechRecognizer` + `AVSpeechSynthesizer`.
- **StoreKit 2** — 6 product IDs: `com.myaissistant.pro.monthly`, `pro.annual`, `student.monthly`, `student.annual`, `poweruser.monthly`, `poweruser.annual`.
- **Backend (proxy):** `thrivn-backend/` — Cloudflare Workers / TypeScript (see that folder's own CLAUDE.md).
- **No third-party SDKs.**

### Info.plist required entries

```
NSCalendarsUsageDescription, NSCalendarsFullAccessUsageDescription
NSSpeechRecognitionUsageDescription, NSMicrophoneUsageDescription
BGTaskSchedulerPermittedIdentifiers:
  com.myaissistant.daily-snapshot
  com.myaissistant.weekly-review
  com.myaissistant.calendar-sync
UIBackgroundModes: [fetch, processing]
```

### Entitlements

```
App Group: group.com.myaissistant.shared   # for widget data sharing
```

---

## Project-Specific Conventions

Beyond workspace-level conventions:

- **SwiftData `@Transient` accessors** over stored enums. `#Predicate` must reference `categoryRaw`/`priorityRaw` strings, never the enum.
- **Custom `EnvironmentKey` DI**, not `@EnvironmentObject`, for iOS 17+ managers.
- **`actor` for network-bound services**; `@MainActor` for UI managers.
- **Prompt caching on system prompts** — every AI call uses `"cache_control": ["type": "ephemeral"]`.
- **Send only last 10 messages of conversation history** to AI. Older turns handled via summarization (see `conversation-memory-design`).
- **Coach behavior rules in system prompt, not user turn.** User input can override user-turn instructions; system-level rules persist.
- **State vs trait extraction.** Moods are NEVER stored as traits. "I'm anxious today" must not become "user is anxious." Multi-session evidence required before fact promotion (see `conversation-memory-design` §6).
- **Crisis routing at the app layer, not the prompt layer.** Run classifier before calling `ClaudeService` (see `crisis-safety-protocols`).
- **No API key in binary.** Use Keychain or proxy via `thrivn-backend/`.
- **No "Great job!" on low-mood entries.** Acknowledge, don't celebrate.
- **Rolling streak with grace days**, not consecutive-day streak (see `wellness-ritual-design` §7).
- **Patterns tab refuses claims below statistical thresholds.** No "mood declined 40%" unless effect-size gate passes (see `personal-trend-detection` §3-§4).
- **5 themes, not 1.** Never hardcode colors — always `AppColors.*` which delegate to `ThemeManager.shared.currentTheme`.
- **Voice mode auto-listen loop** requires `onFinishedSpeaking` → `speechRecognizer.start()` chaining. Preserve on edits.
- **AI calendar actions** parsed client-side from `[[CREATE_EVENT:...]]` / `[[DELETE_EVENT:...]]` tags — preserve the tag grammar when touching `AIPromptBuilder`.
- **Widget target requires App Group** access for shared data. `group.com.myaissistant.shared`.
