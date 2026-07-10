# Audit — SwiftUI performance patterns
**Run:** /overnight 2026-05-04 pass 2
**Method:** static scan for known perf antipatterns. Real perf needs Instruments + Time Profiler on device — this audit lists *static* indicators worth investigating.

## Summary

| Pattern | Count | Risk |
|---|--:|---|
| ScrollView + VStack (no Lazy) — known files | 10 | Most are content-bounded (settings, legal text, modal sheets). Risky candidates flagged below. |
| ForEach inside non-Lazy VStack on Home/Schedule/Habits | 8 / 3 / 6 | The big lists. Need `LazyVStack` if item count grows. |
| GeometryReader uses | 12 | Each is a re-render trigger. Spot-check the 5 most-used. |
| `.id(UUID())` / `.id(Date())` in body | **0** | **Clean** — no body-level identity-killing. |
| `Date()` / `DateFormatter` inside `body` (top of HomeView) | 0 visible | Probably OK; deeper recursion would need a proper grep. |

## Findings

### F1. (Medium) — ScheduleView's pending+completed timeline lists are NOT in Lazy containers
[ScheduleView.swift:182](MyAIssistant/Views/Schedule/ScheduleView.swift#L182) wraps everything in `ScrollView { VStack { ... } }`. The two `ForEach(pendingTimelineItems)` and `ForEach(completedTimelineItems)` render every row eagerly even when off-screen.

Per the project's don't-do rule: *"NEVER `VStack` for >20 items in a ScrollView — `LazyVStack`."*

**Real-world risk:** users with calendar imports + heavy day plans can hit 50+ tasks easily. Each `timelineRow` is a substantive view (icons, badges, swipe actions). Eager render = noticeable scroll jank.

**Fix:** wrap the outer VStack as `LazyVStack(spacing: ..., pinnedViews: ...)`. ~5 min per ForEach. Test with 100+ tasks.

### F2. (Medium) — HomeView has 8 ForEach but only 1 Lazy container
[HomeView.swift](MyAIssistant/Views/Home/HomeView.swift) — 2k+ lines. The 8 ForEach include task lists, habits-due, completed-today, tomorrow, and various card-internal loops. Only 1 lazy container in the file means most lists render eagerly.

**Action:** map each ForEach to its parent (Lazy or eager). Some are bounded (e.g. 4-element dimension list) — those are fine. Anything user-data-driven needs Lazy.

**Fix cost:** ~30 min audit + 30 min wrapping.

### F3. (Medium) — HabitsView has 6 ForEach, 1 Lazy
Habit lists can grow to 30-50 active habits for power users. Same pattern as F1/F2.

**Action:** verify the habit list is in `LazyVStack`. Per `id` is fine if `HabitItem` conforms to `Identifiable` (which it does).

### F4. (Medium) — 12 `GeometryReader` instances
GeometryReader re-evaluates its child closure every layout pass. In SwiftUI, that can be every animation frame. Heavy children inside GeometryReader = perf cliff.

| File:Line | Suspected purpose |
|---|---|
| `Home/BalancePulseCard.swift:307` | bar-fill width calculation |
| `Home/HomeView.swift:2159` | particle-flight target measurement |
| `Components/LoadingView.swift:31` | shimmer placeholder |
| `Patterns/CategoryBreakdownView.swift:28` | bar widths |
| `Compass/CompassView.swift:145` | radar chart sizing |

**Fix candidates:** `BalancePulseCard.swift:307` is on a hot path (re-renders on every fill change). Consider `containerRelativeFrame` or caching width via `.onGeometryChange`.

**Action:** profile each with Instruments on device while completing tasks rapidly. The static scan can't tell which are actually expensive.

### F5. (Low) — Settings views in ScrollView+VStack
Settings, Subscription, Legal — all small/static. Eager render is fine. **No action.**

### F6. (Informational) — No `.id(UUID())` / `.id(Date())` antipattern
The codebase is clean of the worst SwiftUI perf trap (per-render identity reset). Good discipline.

### F7. (Low) — 93 `var body: some View` declarations
The project has many small view bodies, which is good — small views compose well, re-render scope is bounded. The risk is heavy work happening in computed properties called from `body` on every render.

**Spot-check candidates:** `HomeView.swift` (2k lines, lots of derived properties), `BalancePulseCard.swift` (~700 lines, many fill-derived computations).

**Action:** Instruments → Time Profiler under realistic load. Static scan can't catch this.

## Recommended next steps

1. **F1 — wrap ScheduleView's two ForEach in `LazyVStack`** (15 min). Test with a CalendarImport-heavy account.
2. **F2/F3 — audit HomeView + HabitsView for Lazy needs** (~1h).
3. **F4 — Instruments profile of BalancePulseCard rendering** (~30 min on device).
4. **F7 — Time Profiler under realistic load** (~1h on device).

Total: ~3h of perf work + device time. None blocks ship; all are quality-of-life.

## What this audit can't tell you

- Actual frame rate under real data shape.
- Memory growth across long sessions.
- ProMotion (120 Hz) compliance.
- Cold launch time (the 2s/4s targets in `ui-ux.md`).

Those need device instrumentation. This static audit narrows where to point Instruments.
