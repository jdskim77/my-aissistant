# Audit — five-state-screen rule
**Run:** /overnight 2026-05-04
**Rule:** every screen that fetches/computes/displays user data must handle Loading, Empty, Error, Partial, and Ideal states (per `~/.claude/rules/ui-ux.md`).
**Method:** read each major view + count signal words for each state. Flagged below where a state appears underrepresented or absent.

## Per-screen rough scorecard

Count of state-related signals (rough proxy — not a literal grade). 0 in any column is a smoke flag, not a confirmed bug. Each has been spot-checked.

| View | Lines | Loading | Empty | Error | Offline | Likely gap |
|---|--:|--:|--:|--:|--:|---|
| HomeView | 2k+ | 2 | 28 | 0 | 0 | **Error**, **Offline** |
| ChatView | 2k+ | 0 | 25 | 28 | 4 | **Loading** (streaming response) |
| CheckInDetailView | 1k | 15 | 2 | 1 | 0 | **Error** (recap fail), **Offline** |
| CompassView | 603 | 0 | 0 | 0 | 0 | **All four** non-ideal states absent |
| SeasonGoalView | 650 | 0 | 1 | 0 | 0 | **Loading**, **Error** |
| WeeklyReflectionView | 197 | 0 | 1 | 0 | 0 | **Loading**, **Error** |
| SettingsView | 964 | 1 | 1 | 14 | 0 | (Error well-covered, others light) |
| ScheduleView | 1k | 0 | 6 | 3 | 0 | **Loading**, **Offline** |
| HabitsView | 901 | 0 | 3 | 0 | 0 | **Error** |
| CheckInsView | 295 | 0 | 1 | 0 | 0 | **Loading**, **Error** |

## High-priority — confirmed gaps (need real triage on device)

### F1. CompassView has zero non-ideal-state handling
`Views/Compass/CompassView.swift` (603 lines, no loading/empty/error/offline signals). On a fresh install with no check-ins or task completions, the radar should show… what? An empty state with a "Complete your first check-in" CTA? A grayed-out radar? A skeleton? The view code reads as if it always has data.

**Risk:** new-user first-run lands on a tab that visually says "you have no harmony" — opposite of the intended message.

**Fix cost:** ~1h to design + implement an empty state (zero check-ins) and a partial state (1–2 check-ins so the radar would be misleading).

### F2. ChatView lacks an explicit Loading state for streaming responses
ChatView has 0 `ProgressView` / `isLoading` signals. The streaming response shows text as it arrives, but there's no "AI is thinking…" indicator BEFORE the first token. Users hitting send on a slow network may think it ate their message.

**Action:** verify on device. The chat `sendTask` path should expose a "waiting for first chunk" state.

**Fix cost:** ~30 min if missing, including animation.

### F3. CheckInDetailView's recap card lacks an Error state
We just shipped the safety-card variant for crisis routes, but there's no equivalent error state for "LLM call failed" — `generateRecap()` returns `nil` on failure and the recap card simply isn't rendered. User sees nothing where the recap would be, with no explanation.

**Action:** Empty space below mood/energy/notes when recap fails. Should be a small "Couldn't generate today's reflection. [Retry]" card.

**Fix cost:** ~20 min.

### F4. ScheduleView has no Loading state
For users with hundreds of tasks (CalendarLink imports), the initial fetch could take a noticeable beat. Currently no skeleton — just "tasks pop in."

**Action:** verify on a device with ~200 tasks. Add a skeleton or progress if needed.

**Fix cost:** ~30 min.

### F5. HomeView lacks Offline indicator
`offlineBanner()` modifier exists at the app root but HomeView itself doesn't show offline state distinctly. When a user is offline, the AI greeting card just shows the cached fallback — fine — but the "tap to refresh" affordance, if any, wouldn't make it clear the network is the issue.

**Action:** verify the offlineBanner covers HomeView's surface adequately.

## Medium — light coverage, may be intentional

### M1. SeasonGoalView / WeeklyReflectionView have no Loading state
Both views are short modal sheets that load instantly from local data. No async work → no loading state needed. **Likely OK.**

### M2. HabitsView has no Error state
Habit completion is a local SwiftData write — failure is rare. The `safeSave()` wrapper handles error logging. User-facing error UX would be a "save failed, retry?" toast.

**Action:** consider adding a toast for save-fail. Low priority — failure is rare.

### M3. CheckInsView lacks Loading
Same as M1 — short modal, local data. **Likely OK.**

## Low — polish

### L1. Inconsistent empty-state design across views
Each view that has an empty state implements it inline rather than via a shared `EmptyStateView` component. Some are 1-line, some are 20-line, none use a unified style.

**Action:** survey all empty states, create a shared `EmptyStateView` component, migrate. ~2h.

## Recommended fix order

1. **F1 — CompassView empty + partial states** (1h). Highest impact: first-run users land here.
2. **F3 — Recap error card** (20 min). Cheap, prevents silent failure mistaken for "nothing to say."
3. **F2 — Chat loading state** (30 min if missing — verify first).
4. **F4 — Schedule loading** (30 min if needed).
5. **F5 — Offline indicator on Home** (verify first; may already be covered).

Total: ~2.5h once verified on device.
