# My AIssistant V1 Rebuild — Addenda

> Supplements `MY_AISSISTANT_V1_REBUILD.md` with features and models that are live in the codebase but were not present in the original V1 rebuild spec (Feb 18 2026). Read the main rebuild doc first, then this.
>
> **When these two documents conflict, live code + this addenda win over the main rebuild doc** — the addenda represents post-spec evolution.

---

## Quick map

The original rebuild doc describes a 7-model schema, a 5-step onboarding, and three tab surfaces (Home, Schedule, Patterns, Settings). Live code extends this with:

- **~15 additional SwiftData models** (Compass, Habits, Focus, Activity Recall, Check-in behaviors, Alarms, Task Builder, Watch)
- **A Compass feature** (new tab replacing Patterns; Pillar 3's visible surface)
- **A Habits feature** (`HabitsView` + `HabitItem` model)
- **A Focus Timer feature** (`FocusTimerView` + `FocusSession` model)
- **A 12-step onboarding flow** (vs the rebuild doc's 5)
- **Schema versioning** (`SchemaVersioning.swift` — migrations are a thing now)

Each section below documents what's real and points at canonical source.

---

## A. Updated SwiftData Schema

The live model list (`/Users/joekim/Claude/My AIssistant/MyAIssistant/Models/`):

### Core (in the original V1 rebuild doc)

| Model | Purpose |
|-------|---------|
| `TaskItem` | Tasks + calendar-linked events |
| `ChatMessage` | Chat with `conversationID` grouping |
| `CheckInRecord` | 4×/day check-in with mood/energy |
| `DailySnapshot` | Daily stats cache |
| `UserProfile` | Onboarding state, display name |
| `UsageTracker` | Singleton tier-based usage counter |
| `CalendarLink` | Linked Apple/Google calendars |

### Compass feature (see Section B and `COMPASS_SPEC.md`)

| Model | Purpose |
|-------|---------|
| `LifeDimension` (enum, not `@Model`) | 5 dimensions: Physical / Mental / Emotional / Spiritual / Practical. Four are scored; Practical is unscored. Internal raw values are Physical/Mental/Emotional/Spiritual; public brand uses Body/Mind/Heart/Spirit (`shortLabel`). Also defines `HarmonyStage` (V3): Resting / Growing / Flowing / Thriving / Radiant with earth-tone colors. |
| `DailyBalanceCheckIn` | Per-dimension satisfaction (1-5) + energy slider (-3 to +3) + best-energy dimension. Multiple per day supported. |
| `SeasonGoal` | 4-week focused intention on one dimension. `dimensionRaw`, `startDate`, `endDate` (28 days), `intention` (free-text), `completedAt` (nilable for early completion), `isActive`, `daysRemaining`, `progress`. |
| `UserDimensionPreference` | Learned keyword → dimension mapping. `keyword`, `dimensionRaw`, `confirmCount`, `totalCount`, computed `confidence`. Drives auto-suggestion (≥0.6 confidence + ≥2 data points pre-selects). |

### Habits feature (see Section C)

| Model | Purpose |
|-------|---------|
| `HabitItem` | Title, icon (emoji), colorHex (falls back to dimension color when tagged), multi-dimension tagging (`dimensionRaw` as comma-separated raw values), `HabitFrequency` enum (daily or specific weekdays 1-7), completion dates + missed dates as comma-separated `yyyy-MM-dd` strings, reminder hour/minute, archived-at. Streak, missed-day count, completion rate all computed. |

### Focus feature (see Section D)

| Model | Purpose |
|-------|---------|
| `FocusSession` | Focus/pomodoro session tracking. (38 lines — lightweight.) |

### Smart activity recall (COMPASS_SPEC §12 — designed, partially built)

| Model | Purpose |
|-------|---------|
| `ActivityEntry` | Logged activity with duration, dimension, recall source |
| `ActivityPattern` | Learned patterns from recall history — frequency × day-match × recency × acceptance → confidence score |

### Check-in behavior extensions

| Model | Purpose |
|-------|---------|
| `CheckIn` | Check-in time enum (morning/midday/afternoon/night at 8/13/18/22) |
| `CheckInBehavior` | Behavior modifiers / preferences per check-in slot |
| `CheckInPreference` | User-facing preferences (order, visibility) |
| `CheckInSuggestion` | Context-specific suggestion shown alongside a check-in |

### Alarms, task builder, watch

| Model | Purpose |
|-------|---------|
| `AlarmEntry` | Task-linked alarms / reminders |
| `TaskBuilderState` | In-progress task-builder state (multi-step form persistence) |
| `WatchScheduleData` | Data shared with watchOS companion |
| `WidgetCheckInWindow` | Next-check-in window for widget display |

### Schema versioning

| File | Purpose |
|------|---------|
| `SchemaVersioning.swift` | Defines `VersionedSchema` stages (V1 → V2 → V3 → V4 per COMPASS_SPEC §13). All lightweight migrations so far. Consult before changing any `@Model` structure. |

**`ModelContainer` setup:** the live schema must register **all** of the above, not the 7-model subset in the rebuild doc. Confirm against `MyAIssistantApp.swift` before assuming.

---

## B. Compass Feature (Pillar 3 Surface)

**Authoritative spec:** `MyAIssistant/COMPASS_SPEC.md` (13KB, 336 lines). Read it as the source of truth for:
- The four scored dimensions + Practical (unscored)
- The 3-signal scoring model (Activity 30% / Satisfaction 40% / Consistency 30%)
- Balance Score formula (`mean - 1.5 × stdev`)
- Harmony Score (0-100 display)
- Balance Streak mechanics
- Evening check-in flow (3 steps)
- Dimension learning (keyword → preference → pre-selection)
- Season Goals (4-week focus)
- Nudge system (one per day, suppressed after 3 dismissals)
- Weekly reflection (Sunday 5pm)
- Energy tracking phases 1-3
- Smart activity recall (designed)
- 15 design principles

### Where Compass lives in the UI

- **Home screen:** `NudgeBannerView` only (actionable — "what should I do?"). The rest is reflective.
- **Compass tab (replaces Patterns in the V1 rebuild):** everything else.

Files in `Views/Compass/`:

| File | Purpose |
|------|---------|
| `CompassTabView.swift` | Main tab host |
| `CompassView.swift` | Radar chart with 3-signal breakdown cards |
| `CompassInfoSheet.swift` | "How it works" explainer |
| `DimensionPickerView.swift` | Reusable chip picker with learned-preference pre-selection |
| `EveningCheckInView.swift` | 3-step check-in flow (dimension ratings → energy slider → confirmation) |
| `GoalSuggestionsSheet.swift` | Suggests intentions when creating a Season Goal |
| `NudgeBannerView.swift` | Inline nudge card (lives on Home; only Compass element there) |
| `SeasonGoalView.swift` | Goal creation + performance cards + weekly trend + AI suggestion |
| `WeeklyReflectionView.swift` | Sunday evening reflection with radar snapshot + contextual prompt |

### Managers (Compass-specific)

- **`BalanceManager`** — Scoring, check-ins, nudges, season goals, reflection, AI summary. Central coordinator for the Compass.
- **`DimensionSuggester`** — Keyword + learned preference → dimension suggestion. Used by task/habit creation flows.
- **`BalancePulseBus`** — Event bus that publishes "dimension X just got activity" pulses when a task or habit completes. Drives the Compass bar animations.

See Section J below for the full managers list — live code has ~20 managers, not the 8 in the rebuild doc.

### Tab structure update (vs rebuild doc)

The rebuild doc specifies 4 tabs: Home, Schedule, **Patterns**, Settings.

The live build replaces **Patterns** with **Compass** at the tab-bar level. Verified in `Views/Components/CustomTabBar.swift` — `enum Tab` is `{ .home, .schedule, .compass, .settings }`. `CompassTabView` is the Patterns tab's successor.

**Important:** `Views/Patterns/` still exists and is NOT deprecated. Its 6 files (`ActivityTimelineView`, `CategoryBreakdownView`, `MoodTrendView`, `PatternsView`, `WeeklyAIReviewView`, `WeeklyChartView`) are **consumed by Compass views** and `DataExportService`. Grep for references before assuming any file is orphaned.

### Tab icons / labels (verified)

| Tab | Icon | Label |
|-----|------|-------|
| Home | `checklist` | **Today** |
| Schedule | `calendar` | Schedule |
| Compass | `safari` (unselected) / `safari.fill` (selected) | Compass |
| Settings | `gearshape.fill` | Settings |

The rebuild doc's `house.fill` / "Home" is out of date.

### Integration with existing models

- `TaskItem.dimension` — optional `LifeDimension` tag on any task. Fed into Compass activity scoring.
- `TaskItem.effort` — effort level for activity-score weighting (feeds `effort_points / personal_target × 10`).
- `HabitItem.dimensions` — multi-dimension tags. Completions feed Compass quadrants.

---

## C. Habits Feature

Lives in `Views/Habits/`:

| File | Purpose |
|------|---------|
| `HabitsView.swift` | List + create/edit entry |
| `HabitFormView.swift` | Create or edit a habit |

### Data model — `HabitItem`

Rich model (~300 lines). Key capabilities:

- **Multi-dimension tagging** (`dimensions: [LifeDimension]`) — a habit can tag multiple dimensions ("family walk" = Physical + Emotional). `primaryScored` picks the canonical one for coloring/pulse.
- **Effective color** — dimension color wins over `colorHex` fallback when tagged, so habits visually match their Compass quadrant.
- **Frequency** — `HabitFrequency.daily` or `.specificDays(Set<Int>)` where weekday is 1=Sun ... 7=Sat.
- **Completion dates as `yyyy-MM-dd` strings** (pinned to `en_US_POSIX` + Gregorian to survive locale changes). Comma-separated persistence.
- **Missed dates** mutually exclusive with completion dates. Invariant: never in both sets; if corrupted, completion wins.
- **Streak** walks back up to 90 days, skipping non-target days for specific-day habits.
- **`daysSinceLastCompletion`** returns target-day count only (weekends don't inflate the overdue count for weekday habits).
- **Completion rate** over N days, considering only applicable (target) days.
- **Reminder hour/minute** for per-habit notifications.
- **Archived-at** soft delete.

### Integration

- Completions pulse the Compass when `dimensions` is non-empty. Untagged habits don't pulse — they're private-to-the-user tracking.
- The habits tab should surface a `DimensionPickerView` on create/edit (see Section B).

---

## D. Focus Feature

Lives in `Views/Focus/` — single file.

| File | Purpose |
|------|---------|
| `FocusTimerView.swift` | Pomodoro/focus timer screen |

### Data model — `FocusSession`

Lightweight (~38 lines). Tracks duration, start/end, and (likely) completion state. Review the file before building; it's small enough to re-read end-to-end.

### Invocation

Focus Timer is invoked as a **modal from `ContentView`**, not a standalone destination in a tab. `ContentView` holds `@State showingFocusTimer = false` and `@State focusDuration = 25`; the view presents when triggered (likely from Home/Schedule task rows).

### Scope

Intentionally minor — one screen, one model. Not a full focus-app feature; complements the assistant's schedule/task flow.

---

## E. Expanded Onboarding (12 Steps, Not 5)

The rebuild doc specifies 5 steps:

1. Welcome
2. Permissions
3. Voice mode selection
4. Subscription offer
5. Complete

**Live onboarding has 12 view files** in `Views/Onboarding/`:

| File | Purpose |
|------|---------|
| `OnboardingIntroView.swift` | Brand intro (separate from Welcome) |
| `WelcomeView.swift` | Feature highlights |
| `SignInWithAppleView.swift` | **NEW — Sign in with Apple flow** (ties to `thrivn-backend/` auth) |
| `NameCaptureView.swift` | Collect display name |
| `NotificationPermissionView.swift` | Permission priming (replaces generic permissions step) |
| `OnboardingQuickRateView.swift` | Initial quick rate across dimensions |
| `OnboardingScheduleView.swift` | Connect calendar / schedule intent |
| `OnboardingSuggestedTasksView.swift` + `StarterTaskPool.swift` | Seed starter tasks |
| `IntentionCaptureView.swift` | Capture user's opening intention |
| `OnboardingCompassRevealView.swift` | **NEW — Reveal the Compass as a first-run moment** |
| `OnboardingContainerView.swift` | Container orchestrating the flow |
| `OnboardingCompleteView.swift` | Confetti celebration |

### Why it matters

The original 5-step flow is a permissions-priming funnel. The 12-step flow is a **value-delivery funnel**: sign-in, name, notification priming, initial dimension rate, calendar hookup, starter tasks, intention capture, Compass reveal. Delivers an "aha" before asking for commitment.

### Recommended rebuild doc update

Replace Section 9's "Onboarding Flow" subsection with the 12-step sequence above. If the full-fidelity order is needed, cross-reference `OnboardingContainerView.swift` which orchestrates it.

---

## F. Schema Versioning & Migration

`Models/SchemaVersioning.swift` defines `VersionedSchema` stages. Per COMPASS_SPEC §13, the current version is **V4** with all lightweight migrations (V1 → V2 → V3 → V4).

### Rules

- Any new `@Model` property or type requires a new `VersionedSchema` stage.
- Migrations have been lightweight so far — keep it that way when possible (avoid renames, type changes, removing required fields).
- When adding a stage: bump the schema, add a `MigrationStage` (lightweight if the change is additive), register in `ModelContainer` setup.

### Rebuild doc integration

Section 2 of the rebuild doc shows a simple `ModelContainer` setup with 7 models and `isStoredInMemoryOnly: false`. The live setup must register **all** models listed in Section A of this addenda plus the `VersionedSchema` stages.

---

## G. How to Merge This Back Into the Rebuild Doc

Two options for long-term hygiene:

### Option 1 — keep addenda separate (recommended short-term)

- Main rebuild doc remains the V1 snapshot.
- This addenda grows as features land.
- Pro: the V1 spec is preserved as a historical reference.
- Con: two files to keep in sync.

### Option 2 — fold into main (recommended after next major refactor)

When the next major refactor happens:

1. Update rebuild doc Section 2 (Project Setup) schema block to include all current models.
2. Update Section 3 (File Structure) tree to include `Views/Compass/`, `Views/Habits/`, `Views/Focus/`.
3. Update Section 4 (Data Layer) with full model list + pointer to `COMPASS_SPEC.md`.
4. Update Section 9 (Views Layer) with Compass + Habits + Focus sections and the 12-step onboarding.
5. Retire this addenda file or reduce it to a changelog.

Pick Option 2 only when you have an hour of uninterrupted time to do it properly.

---

## H. Relationship to Other Specs

- **`COMPASS_SPEC.md`** — authoritative for the Compass feature (scoring, check-ins, season goals, nudges, dimension learning). Read first for any Compass work.
- **`MY_AISSISTANT_V1_REBUILD.md`** — authoritative for the V1 spec freeze (architecture, DI, 7-model core, calendar sync, voice mode, subscription tiers). Read for app-level architecture.
- **This addenda** — deltas since the V1 freeze.
- **`CLAUDE.md`** (same folder) — concise index pointing at all three.

---

## I. Known Gaps / TODOs in the Addenda Itself

- **Model field-level documentation** is summary only. For field-exact detail, read the Swift source.
- **`BalanceManager` interface** documented in COMPASS_SPEC §13 as a bullet list, not a full API. If editing it, read the source.
- **Smart Activity Recall** (`ActivityEntry`, `ActivityPattern`) — **partially built**, not just designed. Both models exist and are actively referenced by `PatternEngine`, `ChatManager`, `Views/Patterns/ActivityTimelineView`, `Views/Compass/EveningCheckInView`, and `DataExportService`. The recall UI cards described in COMPASS_SPEC §12 may or may not be built — verify against Views before claiming. `Resonance Score` (COMPASS_SPEC §11) is NOT implemented — only mentioned in the spec.

## J. Managers — Full Live List

Rebuild doc §8 lists 8 managers. Live `Managers/` folder has 20 (verified). Compass and post-freeze features added the extras.

### In the rebuild doc (8)

`TaskManager`, `PatternEngine`, `CheckInManager`, `CalendarSyncManager`, `GreetingManager`, `NotificationManager`, `UsageGateManager`, `BackgroundTaskManager`.

### Added post-freeze (12)

| Manager | Purpose |
|---------|---------|
| `BalanceManager` | Compass core — scoring, check-ins, nudges, season goals, reflection |
| `DimensionSuggester` | Keyword + learned-preference → dimension suggestion |
| `BalancePulseBus` | Event bus publishing dimension-activity pulses to drive Compass bar animations |
| `ChatManager` | Chat orchestration — was bundled into views in the V1 spec; extracted |
| `CheckInBehaviorEngine` | Learned behavior per check-in slot (when user skips, when user engages deeply) |
| `HabitManager` | Habit CRUD + completion + streak coordination |
| `HabitReminderCoordinator` | Per-habit reminder scheduling across `NotificationManager` |
| `InsightEngine` | Pattern / insight generation beyond raw `PatternEngine` metrics |
| `ParticleAnimator` | Visual flourish on completions (confetti, pulses) |
| `WatchSyncManager` | iOS ↔ watchOS data sync |
| `WeatherManager` | Weather context — likely for schedule / check-in context |
| `WisdomManager` | Wisdom / inspirational content surfacing (detail TBD — read the file) |

### `Services/AI/` extended

Rebuild doc §7 lists 5 files in `Services/AI/`. Live folder has 7:

| File | Status |
|------|--------|
| `AIProvider.swift` | In rebuild doc |
| `AnthropicProvider.swift` | In rebuild doc |
| `OpenAIProvider.swift` | In rebuild doc |
| `AIProviderFactory.swift` | In rebuild doc |
| `AIPromptBuilder.swift` | In rebuild doc |
| `DailyRecapGenerator.swift` | **Added post-freeze** — daily recap generation (likely feeds the evening check-in or morning greeting) |
| `GoalTaskSuggester.swift` | **Added post-freeze** — suggests tasks based on active `SeasonGoal` dimension |

### Verification

All 20 managers and 7 AI services confirmed via `ls` on 2026-04-21. When a new file lands or one retires, update this section rather than the rebuild doc.
