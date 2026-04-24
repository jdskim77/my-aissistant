# Time-Windowed Habits — Implementation Plan (v2)

**Status:** Revised per expert review. Executing Phase 1 now.
**Scope:** Four fuzzy slots (morning / midday / afternoon / night), dim-but-never-hide, streak-credit-independent-of-clock, split into two phases so Phase 1 ships standalone.
**Philosophy:** Window is for *nudge targeting and visual emphasis*, NOT for gating streak credit (both UX agents + expert review converged).

---

## Phase 1 — Model + UI (this round)

### 1.1 Data model — additive, NO SchemaV2

**Decision (revised):** add `timeWindowRaw: String?` directly to `HabitItem` in `SchemaV1`. The SchemaVersioning header's V2 prescription applies when you need V2 (breaking/renaming changes). Lightweight-automatic migration handles a new optional String property natively. Defer V2 to the next genuinely breaking change and bundle.

```swift
// HabitItem.swift — added property
var timeWindowRaw: String?
```

- `nil` = all-day (default, preserves every existing habit)
- Non-nil values: `"morning"`, `"midday"`, `"afternoon"`, `"night"`

### 1.2 `HabitTimeWindow` enum

Lives at the bottom of `HabitItem.swift`. **Night range is `20...23`** — no post-midnight wrap in v1 per expert review (explicit, deterministic; "night stretches at 00:15" is an edge case we'll learn from dogfood before wiring wrap logic).

```swift
enum HabitTimeWindow: String, CaseIterable, Identifiable {
    case morning, midday, afternoon, night

    var id: String { rawValue }

    /// Fuzzy 4-hour band. Centered on the matching `CheckInTime.hour`
    /// so windows align with the check-in taxonomy users already know.
    /// Night is `20...23` — post-midnight night habits are out of scope
    /// for v1 (see plan §1.2).
    var hourRange: ClosedRange<Int> {
        switch self {
        case .morning:   return 6...10
        case .midday:    return 11...15
        case .afternoon: return 16...19
        case .night:     return 20...23
        }
    }

    var label: String { ... }
    var sfSymbol: String {
        // Reuse CheckInTime glyphs for taxonomy consistency.
        switch self {
        case .morning:   return "sunrise.fill"
        case .midday:    return "sun.max.fill"
        case .afternoon: return "sunset.fill"
        case .night:     return "moon.stars.fill"
        }
    }
}
```

### 1.3 `windowState(at:)` method — injectable Date

Per expert: no `Date()` inside `@Transient` computed properties (testable-Clock rule). A plain method with a default-Date parameter.

```swift
// HabitItem.swift
enum HabitWindowState {
    case inWindow     // full opacity
    case allDay       // full opacity
    case outOfWindow  // 0.5 opacity
}

@Transient
var timeWindow: HabitTimeWindow? {
    get { timeWindowRaw.flatMap(HabitTimeWindow.init(rawValue:)) }
    set { timeWindowRaw = newValue?.rawValue }
}

func windowState(at now: Date = Date(), calendar: Calendar = .current) -> HabitWindowState {
    guard let window = timeWindow else { return .allDay }
    let hour = calendar.component(.hour, from: now)
    return window.hourRange.contains(hour) ? .inWindow : .outOfWindow
}
```

Streak math stays untouched. Add a one-line comment to `currentStreak()` asserting the invariant:

```swift
/// Streak math is intentionally independent of `timeWindow`. Completing
/// a "morning stretches" habit at 2pm still earns today's streak credit.
/// Time-window is for nudge targeting and visual emphasis only.
```

### 1.4 UI — `HabitFormView` picker

5-segment picker just above the reminder row. **SF Symbols only**, no emoji (expert note — consistency with rest of app):

```
Section: "Time of day"
  Picker("Window", selection: $timeWindow)
    Label("Any time",    systemImage: "clock")             → nil
    Label("Morning",     systemImage: "sunrise.fill")      → .morning
    Label("Midday",      systemImage: "sun.max.fill")      → .midday
    Label("Afternoon",   systemImage: "sunset.fill")       → .afternoon
    Label("Night",       systemImage: "moon.stars.fill")   → .night

  Caption (textMuted 12pt):
    "Shown prominently during this window. Counts toward your streak
     any time you complete it."
```

Default for new habits: "Any time" (preserves legacy behavior).

### 1.5 UI — two-band rendering (simplified per expert)

Drop the original 4-band sort. v1 = two bands only:

- **`.inWindow` or `.allDay`** → opacity 1.0
- **`.outOfWindow`** → opacity 0.5

Sites to update: `HabitsView.todaySection` and `HomeView.habitsToDoToday` both sort/render habit rows. Add a helper and wire both.

Completed habits continue to use the existing "✓ N done" collapsed chip — same as today's behavior. Missed-today (via explicit `markMissed`) behavior unchanged.

### 1.6 Auto-re-render — TimelineView

A habit at 9:59 must auto-demote at 10:00 without user interaction. Wrap the habits list in:

```swift
TimelineView(.periodic(from: .now, by: 60)) { timeline in
    // habit rows — pass `timeline.date` to `habit.windowState(at:)`
}
```

Applied to both `HabitsView.todaySection` and `HomeView`'s habits section. 60s granularity is plenty — windows are hour-bucketed.

### 1.7 Files touched in Phase 1

| File | Change |
|---|---|
| `MyAIssistant/Models/HabitItem.swift` | `timeWindowRaw`, `HabitTimeWindow`, `HabitWindowState`, `timeWindow` / `windowState(at:)`, streak comment |
| `MyAIssistant/Views/Habits/HabitFormView.swift` | Window picker Section + caption |
| `MyAIssistant/Views/Habits/HabitsView.swift` | `TimelineView` wrap on today section; opacity binding |
| `MyAIssistant/Views/Home/HomeView.swift` | `TimelineView` wrap on habits section; opacity binding |

**Not touched in Phase 1:**
- `SchemaVersioning.swift` — additive change, no migration needed
- `Nudge.swift` / `NudgeEngine.swift` — deferred to Phase 2
- `HabitReminderCoordinator` — reminder scheduling stays `reminderHour/Minute`-driven
- `Compass` / streak math — explicitly unchanged

### 1.8 Phase 1 test plan

| # | Scenario | Pass criterion |
|---|---|---|
| 1 | Create habit with `timeWindow = .morning`. Open at 9am. | Row at 1.0 opacity |
| 2 | Same habit, open at 2pm, uncompleted. | Row at 0.5 opacity |
| 3 | Complete at 2pm. | Streak +1, row moves to "✓ done" chip |
| 4 | Legacy habit (timeWindow == nil). | Row at 1.0 opacity always |
| 5 | Open at 9:59, wait ≥60s without leaving view. | Row opacity auto-drops at 10:00 |
| 6 | Fresh install → create windowed habit → restart app. | Window persists |
| 7 | Upgrade from main-branch build → assign window to existing habit. | No crash, value persists |
| 8 | Dynamic Type XXL, picker rendered. | Options readable, not clipped |

---

## Phase 2 — Coach nudge integration (next round)

Deferred until Phase 1 ships and dogfoods clean for ≥3 days.

### 2.1 Additive enum case (NO schema change)

`NudgeCategory` stored as rawValue String in `Nudge.categoryRaw` at [Nudge.swift:27](MyAIssistant/Models/Nudge.swift#L27). Adding `case windowedHabit` to the enum is **purely additive** — no `@Model` change, no migration. Existing records keep parsing.

`Nudge.suggestedActionPayload: String?` already exists as a free-form payload → store habit ID there. Zero new stored fields on the Nudge model.

### 2.2 `WindowedHabitRule: NudgeTriggerRule`

New rule struct mirroring existing `WeakDimensionWithOpenWindowRule` / `PostLowMoodCheckInRule` at [NudgeEngine.swift:47](MyAIssistant/Managers/NudgeEngine.swift#L47). Registered in `NudgeEngine.rules`.

Fires when ALL of:
1. A habit has `timeWindow != nil`.
2. Current time is past the window's *midpoint* (e.g., morning 6-10 → past 8am).
3. `isCompletedOn(today) == false`.
4. One-per-day-per-habit dedupe (via existing `isRuleInCooldown` or new per-habit key).
5. Existing daily cap / quiet-hours / safety pause all pass.

### 2.3 `NudgeEvalContext` extension

Add to `NudgeEvalContext` in [NudgeTypes.swift:49](MyAIssistant/Managers/NudgeTypes.swift#L49):

```swift
struct WindowedHabitSnapshot: Sendable {
    let habitID: String
    let title: String
    let window: HabitTimeWindow
}

/// Uncompleted habits currently inside their time window and past the
/// window's midpoint. Populated once per evaluation pass so rules stay
/// deterministic (no Date() calls in rule code).
let activeWindowedHabits: [WindowedHabitSnapshot]
```

`NudgeEngine.collectContext()` populates this from SwiftData + the current clock.

### 2.4 Nudge copy

```
"Still open: {habit.title}. 5 min now, or skip for today?"
```

Actions: **Do now** (existing `.openChat` or new custom) / **Skip today** (marks `missedDates.insert(todayKey)`).

### 2.5 Explicit NON-goals (both UX agents)

- NO post-window interrogation ("Did you skip?")
- NO push notification for window nudges
- NO streak-panic UI
- NO dimension-weighted Compass penalty for skipped windowed habits
- NO custom-hour windows in v2 either — defer to explicit user demand

---

## Open questions (for Phase 2, not blocking Phase 1)

1. How does the windowed-habit rule interact with the existing `habitSlip` category in `NudgeCategory`? One-rule-per-category is the current convention.
2. If a user has 3 windowed habits in a morning, does the rule fire 3 times (spammy) or pick one (how)? Propose: highest-streak-at-risk, ties broken by title sort.
3. Should the "Do now" action scroll the Home tab to the habit row, or open the Habits screen focused on the row?
