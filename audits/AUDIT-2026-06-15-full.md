# Thrivn (MyAIssistant) — Full Codebase Audit

**Date:** 2026-06-15
**Scope:** Whole iOS app (188 Swift files), with priority on the unwanted draggable "accessibility-style" bar.
**Method:** 3-phase audit — plan → independent critical review → 6 specialized read-only agents (Architecture, UI/UX, Accessibility+Bug, Performance, Security/Reliability, Testing). All findings cite real `file:line`. **No code was changed.**

> **Headline:** The drag-bar bug is real and traced. The fix already exists **but was never committed** — HEAD still ships the buggy native `TabView`. Three other Critical issues sit beneath it (data-loss migration trap, a beta flag that disables all paywall enforcement, and 36 of 42 test files that never run). Security hardening elsewhere is genuinely strong.

---

## 0. The Drag-Bar Bug (priority deliverable)

### What it actually is
A draggable horizontal **pill** that scrubs Coach → Today → Compass → Settings. It is **not** an accessibility control — it's the **iOS 26 "Liquid Glass" system tab-bar lens** (`_UITabBarPlatterView` + `_UILiquidLensView`) leaking through `.toolbar(.hidden, for: .tabBar)`. This is documented in `OVERNIGHT-NOTES.md:205` and was identified via the View Debugger on a prior pass.

The app's deployment target is iOS 17, but it is **built with the iOS 26.5 SDK (Xcode 26.5, build 17F42)** — confirmed during this audit — so Liquid Glass is active for the binary.

### Top 3 causes the pill is still visible (ranked, with evidence)

**Cause #1 — PRIMARY: the fix was written but never committed.** HEAD still contains the bug.
- Evidence: `git show HEAD:MyAIssistant/ContentView.swift` → native `TabView(selection:)` at **line 108** and `.toolbar(.hidden, for: .tabBar)` at **line 117** — the exact leaking construct.
- The corrected code (a `ZStack` of opacity-gated subtrees, no `TabView`, no `.toolbar` hidden) exists **only in the uncommitted working tree** (`git diff` for `ContentView.swift` = 45 insertions / 40 deletions, status ` M`).
- Implication: any **clean checkout, CI build, or TestFlight build off HEAD** ships the native tab bar and the pill returns. If the user saw the 4-tab scrubber on a device/TestFlight build, **this is the cause.**

**Cause #2 — SECONDARY: onboarding still uses a native page `TabView`.** A separate, still-live draggable surface — present in **both** HEAD and the working tree.
- Evidence: `OnboardingContainerView.swift:67` `TabView(selection: $currentPage)`, `:131` `.tabViewStyle(.page(indexDisplayMode: .never))`, `:142` `.simultaneousGesture(DragGesture().onChanged { _ in })` (a swipe-suppression hack, not a Liquid-Glass fix).
- **Scoping note that rules this in/out:** this TabView only holds onboarding *pages* — it **cannot** scrub the 4 main tabs. So if the symptom is the 4-tab scrubber, it is **not** onboarding. If a drag affordance appears **only during onboarding**, it **is** this.

**Cause #3 — TERTIARY (dev machine only): stale DerivedData** can keep the old `ContentView` compiled locally, so "I fixed it but still see it" happens on the developer's machine even though the working-tree fix is correct. Not a plausible *user-facing* cause (TestFlight builds are clean).

**Not a root cause:** the absence of a Liquid-Glass opt-out key. It's *why the leak is possible*, but with the working-tree ZStack (no native tab bar) there is no system tab bar to leak. It matters only as a belt-and-suspenders option.

### Recommended fix (in order)
1. **Primary — commit the working-tree `ContentView.swift`** (ZStack opacity-gated subtrees). Removes the leaking surface at the source. **Risk: low**, but it's bundled inside ~50 uncommitted files — review and commit deliberately (see §6 / Needs-Decision).
2. **Secondary — replace onboarding's `.page` TabView with a manual `ZStack` + `.transition`** (mirror the ContentView pattern) and drop the `.simultaneousGesture` hack. Closes the second draggable/page-chrome surface. **Risk: low-medium** (re-test onboarding swipe/advance).
3. **Tertiary — only if a glass artifact survives on-device:** add `UIDesignRequiresCompatibility = YES` (Boolean) to `Info.plist`. **Verified** this is the real opt-out key, but it is **Xcode-26-only (removed in Xcode 27), Apple positions it as temporary, and it does not reliably suppress every glass surface.** Treat as time-boxed tech debt, **not** the primary mechanism. The app's chrome is fully custom, so removing native tab/page views is the durable fix.

### Regression guard (prevents the bug returning)
A cheap, deterministic CI grep step scoped to `ContentView.swift` so the benign onboarding pager doesn't trip it:
```bash
# scripts/guard-no-native-tabbar.sh
set -euo pipefail
CV="MyAIssistant/ContentView.swift"; fail=0
grep -nE '(^|[^A-Za-z])TabView\s*[({]' "$CV" && { echo "::error::Native TabView reintroduced in ContentView"; fail=1; }
grep -rnE 'toolbar\(\s*\.hidden\s*,\s*for:\s*\.tabBar\s*\)' MyAIssistant/ && { echo "::error::.toolbar(.hidden, for: .tabBar) reintroduced"; fail=1; }
exit $fail
```

### Manual verification (definitive)
1. `rm -rf ~/Library/Developer/Xcode/DerivedData/MyAIssistant-*` (kill stale build).
2. Clean-build to a real iOS 26 device or iOS 26.5 simulator; launch past onboarding to the 4-tab UI.
3. Xcode → **Debug → View Debugging → Capture View Hierarchy**.
4. Filter for **`_UITabBarPlatterView`**, then **`_UILiquidLensView`**, then **`UIPageControl`**. Expected after the fix: **zero matches** on the main surface. Repeat during onboarding for the pager.

> **Build note:** `xcodebuild … build` failed only because **watchOS 26.5 runtime isn't installed** (the scheme embeds the Watch app: `error: watchOS 26.5 must be installed`). The iOS code itself compiles. Install the runtime or build a watch-less scheme for a clean iOS build / CI.

---

## 1. Critical

### C-1 · Drag-bar fix is uncommitted — HEAD ships the bug
- **File:** `MyAIssistant/ContentView.swift` (HEAD:108,117 vs working tree)
- **What's wrong:** The only real fix lives in the dirty working tree; the committed code still has the native `TabView` + `.toolbar(.hidden, for: .tabBar)`.
- **Why it matters:** The reported, uninstall-grade visual defect re-appears on any clean/CI/TestFlight build. The "fix" provides zero protection until committed.
- **Fix:** Commit the working-tree `ContentView.swift` (after review), then verify per §0.
- **Risk of fix:** Low (the change is already written and reasoned); the only risk is the surrounding ~50 uncommitted files it's entangled with.

### C-2 · SwiftData migration trap → silent total data loss on next model change
- **Files:** `Models/SchemaVersioning.swift:79` (`stages: []`, single `SchemaV1`); `MyAIssistantApp.swift:58-68,486,513` (CloudKit `.automatic`, `try?`-swallowed container fallback to in-memory).
- **What's wrong:** The migration plan is empty and the container creation falls back to a **non-persisting in-memory store with no user-visible signal**. Lightweight migration silently handles *additive optional* changes, but the first non-optional/renamed/typed-changed property added directly to a live `@Model` after a shipped build will fail to open the store → crash-on-launch or silent reset, wiping a user's data.
- **Why it matters:** This is a journaling/coaching app; losing all check-ins/tasks/goals is catastrophic and unrecoverable. Every shipped user is exposed the first time a breaking model edit lands without the documented V2 recipe.
- **Fix:** (a) Add a launch-time guard that surfaces a recoverable error / reset UI instead of silently dropping to in-memory; (b) add a failing round-trip test (open a V1 store with a V2 schema); (c) enforce the file's own duplicate-into-`SchemaV2` recipe in review.
- **Risk of fix:** Low-medium (touches app bootstrap).

### C-3 · `isBetaUnlimited = true` ships with ALL paywall enforcement disabled
- **Files:** `Core/AppConstants.swift:24,41-44`; `Managers/UsageGateManager.swift:78,111,118`.
- **What's wrong:** `isBetaUnlimited = true` makes `isDeveloperMode` true, so every gate (`canSendChat`, `canDoCheckIn`, `canSuggestGoalTasks`) short-circuits to `return true` and **skips `verifyIntegrity()`**. Free behaves like PowerUser; the only backstop is a client-side 1M-token/day counter a reinstall resets.
- **Why it matters:** If a release build reaches the App Store with this flag true, the subscription model is non-functional and all proxy/AI cost is unbilled. It's one source line a human must remember to flip.
- **Fix:** Make `isBetaUnlimited` a **build-configuration flag** (DEBUG/TestFlight only) so a release build can never ship it true.
- **Risk of fix:** Low. *(This is also a release-gate / product decision — see §5.)*

### C-4 · 36 of 42 test files are orphaned (not in the Xcode target)
- **File:** `MyAIssistant.xcodeproj/project.pbxproj` (test target Sources phase ~lines 1705-1713) vs `MyAIssistantTests/` on disk.
- **What's wrong:** Only **6** test files compile/run (`TaskManagerTests`, `PatternEngineTests`, `UsageGateManagerTests`, `AIProviderFactoryTests`, `AIPromptBuilderTests`, `WatchScheduleDataTests`). The other 36 — including the highest-value safety suites (`KeywordCrisisClassifierTests`, `DailyRecapGeneratorCrisisGateTests`, `ChatManagerParserTests`, `CheckInManagerTests`, `NotificationManagerTests`, `SubscriptionTierTests`, `KeychainServiceTests`, `ColorContrastTests`) — **never execute.**
- **Why it matters:** "42 tests" is false confidence; ~86% protect nothing. Crisis-gate and parser regressions ship silently.
- **Fix:** Add all 36 to the test target's Sources phase via Xcode "add to target" or the `xcodeproj` Ruby gem (never hand-edit pbxproj). Expect a few to need compile repair after months of API drift.
- **Risk of fix:** Low-medium.

---

## 2. High

### H-1 · No CI and no regression guard for the pill bug
- **Files/paths:** no `.github/workflows`, `scripts/`, or `fastlane/` (repo root); `ContentView.swift`.
- **What's wrong:** Nothing gates a PR; a revert of the drag-bar fix merges green.
- **Why it matters:** The Critical bug can silently return; orphaned tests stay invisible.
- **Fix:** One PR-gated workflow (per CLAUDE.md shape: `pull_request` + `workflow_dispatch`, no auto-on-push-to-main, draft-PR skip, paths-ignore, concurrency cancel) running `xcodebuild test` + the §0 grep guard.
- **Risk of fix:** Low (additive).

### H-2 · `BalanceManager` god class (1,182 lines / 51 funcs)
- **File:** `Managers/BalanceManager.swift:1-1183`.
- **What's wrong:** One `@MainActor` type owns scoring, today-fill momentum, check-in CRUD, season goals, activity-pattern learning, smart recall, weekly reflection, energy insights, and AI-context formatting. Every Compass view, NudgeEngine, ChatManager, HabitManager and TaskManager touch it.
- **Why it matters:** Highest-coupled, highest-change-risk type in the graph; a serialization point for change.
- **Fix:** Extract `BalanceScoringEngine` (47-549), `BalanceCheckInStore` (628-719), `SeasonGoalStore` (846-874), `ActivityRecallEngine` (876-1028); keep `BalanceManager` as a thin facade.
- **Risk of fix:** Medium (many call sites).

### H-3 · All four tab subtrees stay mounted simultaneously
- **File:** `ContentView.swift:111-121` (the `ZStack` + `tabContent` opacity gating).
- **What's wrong:** ChatView, HomeView, CompassTabView, SettingsView are all in the hierarchy continuously (only `.opacity(0)`/`.allowsHitTesting(false)`). Opacity-0 does not pause `@Query` observation, `.task`, or `.onReceive` — so HomeView's and Compass's expensive work re-runs on **any** data mutation even when the user is on Settings.
- **Why it matters:** Elevated idle memory (4 live screens) and off-screen body churn → battery drain and return-to-tab jank. It is also the **multiplier** for PERF findings below.
- **Fix:** Keep **ChatView** resident (the reason for this design) but lazily mount Home/Compass/Settings on first visit and pause their `@Query`/`.task` while hidden; tear down on memory warnings.
- **Risk of fix:** Medium — this code is deliberate (it's the drag-bar workaround); changing it risks the ChatView-state-loss regression it was built to fix. **Needs Instruments to quantify first.**

### H-4 · ~96 fixed `.font(.system(size:))` calls bypass Dynamic Type
- **Files:** `HomeView.swift` (24, incl. hero "%" `:1251` size 26, slot icons `:1119` size 40), `ChatView.swift` (15), `CheckInDetailView.swift` (9), `BalancePulseCard.swift` (8), `FocusTimerView.swift:147` (timer size 56), others.
- **What's wrong:** `AppFonts` **does** scale correctly via `UIFontMetrics` (`AppFonts.swift:12-15`), but these direct `.system(size:)` calls pin fixed point sizes that won't grow at Accessibility text sizes. (A few are legitimately fixed — tab-bar icon `CustomTabBar.swift:94`, SF Symbol point sizes.)
- **Why it matters:** Systemic Dynamic Type gap; at AX5, pinned text stays small while neighbors grow, breaking layouts and failing the accessibility bar.
- **Fix:** Route text through `AppFonts.*`; keep fixed sizing only for symbols/icons with a documented reason.
- **Risk of fix:** Medium — re-flows many screens; test at XXL.

### H-5 · User-facing name is "AI Assistant", not "Coach"
- **Files:** `ChatView.swift:632`, `Home/AIGreetingCard.swift:16`, `Onboarding/WelcomeView.swift:39`, `OnboardingCompleteView.swift:27,33`, `SignInWithAppleView.swift:34`, `Settings/VoiceSettingsView.swift:198`, `Settings/SettingsView.swift:342`.
- **What's wrong:** The product spine is the **Coach** (tab label is literally "Coach"), but every user-visible string calls it "AI assistant" — the generic jargon the design ethos bans.
- **Why it matters:** Quietly tells the user it's a chatbot, undercutting the coach positioning before first use. It's also the cheapest top-severity fix (a copy sweep).
- **Fix:** Global rename "AI assistant" → "coach"/"your coach"; chat header "AI Assistant" → "Coach".
- **Risk of fix:** Trivial (copy only).

### H-6 · Core check-in controls are weak for VoiceOver
- **Files:** `Views/Compass/EveningCheckInView.swift:212` (energy `Slider`, the `energyLabel` string already exists at `:225`); `Views/CheckIns/MoodPicker.swift:35-64`.
- **What's wrong:** The energy Slider has **no `accessibilityValue`** — VoiceOver announces "-3, -2, -1…" instead of "Drained…Energized." MoodPicker buttons have **no `accessibilityLabel`** and no `.isSelected` trait — VoiceOver reads raw emoji names and never says which mood is selected.
- **Why it matters:** These are the primary calibration inputs that feed the coach; they're effectively unusable via screen reader.
- **Fix:** `.accessibilityValue(energyLabel)` on the slider; `.accessibilityLabel("\(mood.label), \(mood.value) of 5")` + `.accessibilityAddTraits(selected ? .isSelected : [])` on mood buttons.
- **Risk of fix:** None.

### H-7 · Onboarding native page `TabView` (secondary drag surface)
- **File:** `OnboardingContainerView.swift:67,131,142`.
- **What's wrong:** Still a native paging `TabView` with a `.simultaneousGesture` swipe hack; can render system page chrome under Liquid Glass and is a residual draggable surface.
- **Why it matters:** Even after the main-tab fix, this is a still-live native pager during onboarding.
- **Fix:** Replace with a manual `ZStack` + `.transition` (same pattern as the ContentView fix).
- **Risk of fix:** Low-medium (re-test onboarding navigation/throttle).

---

## 3. Medium

### M-1 · `balanceStreak()` does up to ~52 uncached weekly recomputes per call
- **File:** `BalanceManager.swift:597-623`, called from `CompassTabView.swift:67-80` body and `balanceSummaryForAI()`.
- **What's wrong:** The streak loop runs `weeklyScores(for:)` (uncached for past weeks) + `hasRealData(for:)` each iteration — worst case ~200 SwiftData round-trips for one number. The 30s cache only holds the current week.
- **Why it matters:** Stutter opening Compass; amplified by H-3 (runs while hidden).
- **Fix:** Memoize per-week breakdowns in a dictionary cache keyed by `weekStart`; compute a single snapshot in `.task`/`.onChange` (HomeView's `HomeBalanceSnapshot` pattern).
- **Risk of fix:** Low. *(Confirm real cost with Instruments.)*

### M-2 · Home per-body snapshot does ~50+ fetches every render
- **File:** `HomeView.swift:356-382`.
- **What's wrong:** Inline `body` snapshot loops 4 dims × (`todayFill` + `yesterdayTickValue` (itself 7-day loop of `pointsInWindow`, 2 fetches each) + `todayPoints`). Memoized within one eval, not across; re-runs on every scroll/toggle/@Query change.
- **Why it matters:** Frame drops on Home, especially older devices.
- **Fix:** Cache `pointsInWindow`/`todayFill` in BalanceManager (TTL), or compute the snapshot in `.task`/`.onChange(of: tasks)` into `@State`.
- **Risk of fix:** Medium (freshness vs. live particle-bar animation reading `todayFill`).

### M-3 · Unbounded `Nudge` `@Query` observed twice
- **Files:** `ContentView.swift:81-89` (`allNudges`), `ChatView.swift:25` (`allRecentNudges`).
- **What's wrong:** Both fetch the entire `Nudge` table (no `fetchLimit`), filter in Swift; with H-3 both views are always mounted so both re-run on every nudge write.
- **Why it matters:** Latent cliff as the table grows; needless double-observation.
- **Fix:** Add `fetchLimit` (e.g. 50, newest-first), or compute the badge via `fetchCount` + predicate.
- **Risk of fix:** Very low.

### M-4 · `ParticleAnimator` ignores Reduce Motion
- **File:** `Managers/ParticleAnimator.swift` (no `reduceMotion` check anywhere; `AIActivityOrb.swift:7,27-61` does it correctly).
- **What's wrong:** Particle pulses fire on completion regardless of the Reduce Motion setting.
- **Why it matters:** Violates the motion-accessibility rule the rest of the app honors.
- **Fix:** Gate `fire`/`shouldHandleBusPulse` on `UIAccessibility.isReduceMotionEnabled`; skip or shorten.
- **Risk of fix:** Low.

### M-5 · Duplicated scoring + week-window logic
- **Files:** `BalanceManager.swift:266-326,332-377,420-470,525-549,724-763` (effort-split loop ×4); `:73,574,601,710,726,749,1136` + `Compass/SeasonGoalView.swift` (week-interval math ×~9, incl. in a View).
- **What's wrong:** The multi-dimension effort split and the week-boundary computation are copy-pasted; a view computing its own week boundary can disagree with the manager.
- **Why it matters:** Scores can drift between Home, Compass, and AI context; fixes land in only one copy.
- **Fix:** `private func effortPoints(for:) -> [LifeDimension: Double]` and a `Calendar.currentWeekInterval()` helper in `DateHelpers`.
- **Risk of fix:** Low.

### M-6 · `recordCheckIn` deletes-then-inserts (data loss vector)
- **File:** `BalanceManager.swift:663-676`.
- **What's wrong:** Legacy path deletes the day record and inserts a fresh one rather than mutating, discarding existing satisfaction ratings.
- **Why it matters:** If the legacy path and `recordSatisfaction` both run for the same day (Watch + phone), ratings are lost.
- **Fix:** Mutate in place like `recordSatisfaction`, or remove the method if unused.
- **Risk of fix:** Medium.

### M-7 · GoogleCalendar token refresh is not coalesced (race)
- **File:** `Services/Calendar/GoogleCalendarService.swift:261,294-299`.
- **What's wrong:** Two concurrent 401s each call `refreshAccessToken()`; a failed refresh's `signOut()` can clear a token another in-flight call just refreshed. The backend service already solves this with `inFlightRefresh` coalescing (`ThrivnBackendService.swift:138-152`).
- **Why it matters:** Sporadic sign-outs / failed calendar ops under parallel requests.
- **Fix:** Mirror the `inFlightRefresh` coalescing pattern.
- **Risk of fix:** Low-medium.

### M-8 · `KeychainService` `@unchecked Sendable`, non-atomic `save()`
- **File:** `Services/Keychain/KeychainService.swift:21,88-99`.
- **What's wrong:** No synchronization or documented justification for `@unchecked Sendable`; `save()` does delete-then-add non-atomically — concurrent same-key saves could interleave and lose a write.
- **Why it matters:** Rare in practice (writes are per-actor) but violates the `@unchecked` rule and is a latent token-loss vector.
- **Fix:** Add a lock around mutating ops, or document the justification.
- **Risk of fix:** Low.

### M-9 · StoreKit: raw error to user + substring tier detection
- **File:** `Services/StoreKit/SubscriptionManager.swift:80,106-112`.
- **What's wrong:** `lastError = error.localizedDescription` surfaces raw StoreKit strings; tiers are classified via `productID.contains("pro")`/`"student"` (works today only because `"poweruser"` contains neither).
- **Why it matters:** Raw errors violate the UX rule; substring matching is fragile against future SKUs/promo IDs. *(Verification itself is correct — `checkVerified` throws on `.unverified`, respects `revocationDate`.)*
- **Fix:** Friendly error copy (the `restore()` path already does this); match against the explicit `AppConstants.ProductID` set.
- **Risk of fix:** Low.

### M-10 · Deep-link routing is stringly-typed and untested
- **Files:** `ContentView.swift:255-294` (`navigateToDestination`), posted from `NotificationDelegate`.
- **What's wrong:** Routing on bare strings ("assistant", "patterns", "schedule") across 3 files; a typo/rename fails silently to `default: .home`. Zero tests.
- **Why it matters:** Every notification/nudge tap depends on this; each case previously fixed a QA bug and can silently re-break.
- **Fix:** A shared `DeepLinkDestination` enum + a unit test over the switch.
- **Risk of fix:** Low-medium.

### M-11 · Three text inputs lack keyboard dismissal
- **Files:** `Onboarding/NameCaptureView.swift`, `Schedule/ScheduleView.swift` (TextEditor), `Settings/CalendarSettingsView.swift`.
- **What's wrong:** No `scrollDismissesKeyboard`/Done toolbar (ChatView, CheckInDetail, SeasonGoal, IntentionCapture, HabitForm handle it correctly).
- **Why it matters:** NameCapture can trap a first-run user behind the keyboard.
- **Fix:** Add `.scrollDismissesKeyboard(.interactively)` + Done toolbar.
- **Risk of fix:** Trivial.

### M-12 · Hardcoded hex / literal colors break in dark themes
- **Files:** `Settings/CalendarSettingsView.swift:214` (`Color(hex: "4285F4")`), `Habits/HabitFormView.swift:172,176` (`Color(hex:)`, `Color.white`), `Home/DayTickerView.swift:65`, `Settings/SettingsView.swift:552,561` (`Color.black.opacity` scrims).
- **What's wrong:** Non-token colors that don't adapt to Midnight/Twilight (white dot on near-white selection; black scrim that should be theme-aware).
- **Why it matters:** Visual breakage in 2 of 5 themes.
- **Fix:** Add `AppColors.scrim`, `.googleBlue`, etc.
- **Risk of fix:** Low.

### M-13 · ChatView has no first-run empty state
- **File:** `Views/Chat/ChatView.swift` (has error/offline/paywall/typing states; missing empty transcript).
- **What's wrong:** A brand-new Coach tab opens to a bare scroll view with only the quick-actions bar.
- **Why it matters:** Five-state rule — the empty state should show what the surface becomes; this is the **default landing tab**.
- **Fix:** An empty-coach hero ("Ask me to plan your day…").
- **Risk of fix:** Low.

### M-14 · `try?` used in tests (14×) and no SwiftLint
- **Files:** `PatternEngineTests:37,49`, `CheckInManagerTests:48,86`, `DataSeederTests` (6×), `DailyRecapGeneratorCrisisGateTests:56,223,251`, etc.; no `.swiftlint.yml`.
- **What's wrong:** `try?` (incl. on `context.save()`) can make tests pass against an empty store — false green; prohibitions are unenforced by tooling.
- **Why it matters:** Wrong-pattern tests + no automated guardrails for the dont-do list.
- **Fix:** `try` in `throws` tests / `#require`; add SwiftLint mirroring the prohibition list in the PR workflow.
- **Risk of fix:** Low.

### M-15 · Dimension satisfaction rating costs 20+ VoiceOver swipes
- **File:** `Views/Compass/EveningCheckInView.swift:173-197`.
- **What's wrong:** Each of 5 dots per dimension is its own button; selection isn't announced as state.
- **Why it matters:** High navigation cost (4 dims × 5 dots) and unclear current value via screen reader.
- **Fix:** Wrap each row in `.accessibilityElement(children: .ignore)` + `.accessibilityAdjustableAction` with `.accessibilityValue`, or add `.isSelected` to the chosen dot.
- **Risk of fix:** Low.

### M-16 · Watch test target is empty boilerplate
- **File:** `MyAIssistantWatch Watch AppTests/...Tests.swift` (stub `@Test func example()` empty).
- **What's wrong:** WCSession bridge (schedule/API-key/check-in transfer) has effectively no coverage.
- **Why it matters:** Cross-device sync regressions ship unguarded.
- **Fix:** Test `WatchScheduleData` encode/decode + message routing.
- **Risk of fix:** Low.

---

## 4. Low

| ID | File:line | What's wrong | Fix | Risk |
|----|-----------|--------------|-----|------|
| L-1 | `BalanceManager.swift:777,829`; `ChatManager.swift:699,528-553` | Uncached `DateFormatter` created per-call in `todayNudge`/`parseResponseTags` (the day-key one at `:389` is correctly static) | Hoist to `static let` | Low |
| L-2 | `BalanceManager.swift:767` vs `Models/Nudge.swift:12` | Nested struct `Nudge` collides with the `Nudge` `@Model` | Rename struct `CompassNudge` | Low |
| L-3 | `ChatManager.swift:589`, `ChatView.swift:1614`, `NotificationSettingsView.swift:172,181`; 5× `KeychainService()` | Throwaway `NotificationManager()`/`KeychainService()` instances bypass DI | Inject the shared instance | Low |
| L-4 | `Managers/NudgeEngine.swift` | ~6 `print(` calls (per grep) in production code — confirm not `#if DEBUG`-gated | Use `Logger`/`os.log` with privacy annotations | Low |
| L-5 | `HabitsView.swift:191-194` | Today-habits list is plain `VStack`, not `LazyVStack` (fine <20 items; weekly grid `:773` correctly Lazy) | `LazyVStack` if counts grow | Trivial |
| L-6 | `Focus/FocusTimerView.swift`, `Compass/CompassInfoSheet.swift` | `NavigationStack` without `.navigationTitle()` | Add titles (`.inline` for the sheet) | None |
| L-7 | `Components/CustomTabBar.swift:131-132` | Custom tab buttons lack `.isButton` trait | Add `.accessibilityAddTraits(.isButton)` | None |
| L-8 | `Onboarding/OnboardingCompleteView.swift:18`; `ChatView.swift:1169` | Confetti/🎉 + "✅ Task created" — celebration chrome the coach ethos avoids | Restrained completion moment; drop confetti | Low |
| L-9 | `Onboarding/*` ("Get Started", "You're All Set!", "Let's Go!"), `IntentionCaptureView.swift:115`, alert buttons | Title Case in buttons/titles (rule = sentence case) | Sentence case | Trivial |
| L-10 | `CustomTabBar.swift:94,114-120` | Tab icon pinned to 22pt; labels tail-truncate at AX5 with no larger-type fallback (comment references a "system modal tab bar" that doesn't exist) | Allow 2-line labels / grow bar height at large AX sizes | Low-med |

---

## What's already solid (verified, not flagged)
- **Security hardening is strong:** API keys in Keychain headers (`x-api-key`/`Bearer`), never URL params, never logged; OAuth uses PKCE + `state` + single-use + registered scheme; push payloads carry only IDs + dimension, never note text/PII; `.whenUnlockedThisDeviceOnly`; `PrivacyInfo.xcprivacy` present; `ITSAppUsesNonExemptEncryption = NO` set; usage descriptions complete.
- **Crisis safety is fail-closed:** both `ChatManager.sendMessage:166-170` and `DailyRecapGenerator.generate:119-123` fall back to a non-nil `KeywordCrisisClassifier` — a nil classifier can't disable the gate.
- **Re-entrancy guards present** on chat send (`isSending`), nudge eval (`isEvaluating`), onboarding (`isCompleting`), purchase (`purchaseInProgress`).
- **No `try?`/`try!` on writes** (except `PreviewHelpers.swift:15`, test-only); all `URL(string:)!` are on compile-time literals; `safeSave()` logs failures and onboarding bails loudly.
- **APIClient** (actor): explicit timeouts, token-bucket throttle, retry only on 429/5xx with backoff, no 4xx retry.
- **ChatView transcript:** 200-message window + `LazyVStack` + cached `DateFormatter`. **ParticleAnimator:** in-flight cap (4), queue cap (12), haptic rate-limit, Tasks torn down on `.onDisappear`. **SpeechRecognizer:** `[weak self]` throughout, timer invalidated. No retain cycles found in the voice loop.
- **StoreKit verification** correct (`checkVerified` throws on unverified, respects `revocationDate`).
- **`Views/Patterns/` is not dead** — all 6 files are live via `CompassTabView` → `PatternsView` and `DataExportService`.

---

## 5. Do Not Fix Yet / Needs Product Decision
1. **Commit strategy for the ~50 uncommitted files.** The drag-bar fix is entangled with a large dirty working tree. Decide whether to commit `ContentView.swift` surgically vs. the whole batch, and review the rest before it becomes the new baseline. *(Blocks C-1.)*
2. **`isBetaUnlimited` (C-3).** Keep unlimited for the current beta, or convert to a build-config flag now? This is a release-gate + monetization decision, not just an edit. **Must be resolved before any public App Store build.**
3. **Liquid Glass stance.** Stay fully-custom (current direction) vs. eventually adopt Liquid Glass. The `UIDesignRequiresCompatibility` opt-out is removed in Xcode 27, so a long-term plan is needed regardless.
4. **H-3 tab-mounting tradeoff.** Lazy-mounting non-Coach tabs improves memory/battery but risks the ChatView-state-loss regression the ZStack was built to prevent. Quantify with Instruments before changing.
5. **Compass vs Home overlap.** CLAUDE.md itself flags Compass as possibly overlapping Home and competing with Coach for daily attention — an IA decision above the code level.
6. **Localization timing (UX-05).** No `NSLocalizedString`/String Catalog anywhere. Fine to defer for an English-only indie launch, but it's a full retrofit later — decide when.

---

## 6. Quick Wins (low risk, high value, fast)
1. **Commit the working-tree `ContentView.swift`** + add the §0 grep regression guard. *(Kills the priority bug.)*
2. **`accessibilityValue(energyLabel)`** on the energy slider (the label string already exists). *(H-6)*
3. **`accessibilityLabel` + `.isSelected`** on MoodPicker buttons. *(H-6)*
4. **"AI Assistant" → "Coach"** copy sweep. *(H-5)*
5. **Title Case → sentence case** in onboarding/alerts. *(L-9)*
6. **Friendly StoreKit error copy** instead of `error.localizedDescription`. *(M-9)*
7. **`fetchLimit` on the two `Nudge` queries.** *(M-3)*
8. **Reduce-Motion gate on `ParticleAnimator`.** *(M-4)*
9. **Map hardcoded scrim/Google colors to `AppColors` tokens.** *(M-12)*
10. **Keyboard-dismiss on NameCapture/Schedule/Calendar text fields.** *(M-11)*

---

## 7. Recommended Implementation Order
1. **Resolve & verify the drag-bar bug (C-1):** review the dirty tree → commit `ContentView.swift` → clean-build + View-Debugger verify (§0) → add the grep guard. *(Also install watchOS 26.5 runtime to unblock the full-scheme build.)*
2. **Decide `isBetaUnlimited` (C-3)** and convert to a build-config flag — **before any TestFlight/App Store** build.
3. **Lock the schema migration (C-2):** add launch-failure recovery + a V1→V2 round-trip test + enforce the V2 recipe — **before the next `@Model` edit.**
4. **Register the 36 orphaned tests (C-4)** and stand up the PR-gated CI (H-1) with the grep guard.
5. **Onboarding page TabView → manual ZStack (H-7)** — closes the secondary draggable surface.
6. **Accessibility batch:** H-6 (slider/mood), M-4 (reduce motion), then the H-4 Dynamic Type sweep, plus L-6/L-7/M-15.
7. **Terminology + microcopy sweep** (H-5, L-8, L-9).
8. **Performance:** profile with Instruments, then H-3 (lazy-mount non-Coach tabs) + M-1/M-2 (memoize BalanceManager snapshots) + M-3.
9. **`BalanceManager` split (H-2)** — larger refactor once tests are running to catch regressions.
10. **Deferred:** localization (UX-05), broader test coverage (NudgeEngine, deep-link routing, Watch sync), SwiftLint adoption.
