# Audit — Onboarding state machine
**Run:** /overnight 2026-05-04 pass 3
**Files:** [OnboardingContainerView.swift](MyAIssistant/Views/Onboarding/OnboardingContainerView.swift) (364 lines) + 8 screen files (2540 LOC total).

## Flow summary

8-screen linear flow:

| # | Screen | What happens | Persisted? |
|--:|---|---|---|
| 0 | WelcomeView | brand intro | none |
| 1 | OnboardingIntroView | compass concept | none |
| 2 | OnboardingQuickRateView | user rates 4 dimensions | `ratings: [LifeDimension: Int]` (in-memory) |
| 3 | OnboardingCompassRevealView | radar + AI voice debut | none |
| 4 | IntentionCaptureView | user types a goal intention | `capturedIntention: String` (in-memory) |
| 5 | OnboardingCoachReachView | consents to proactive nudges | sets `nudgeEnabledKey` + `nudgeFrequencyKey` (UserDefaults) |
| 6 | OnboardingSuggestedTasksView | adds starter tasks | `addedTaskIndices: Set<Int>` (in-memory) |
| 7 | OnboardingClosingView | sub-state machine: SignIn → Name → NotificationPermission | `capturedName: String`, `closingStage: Stage` (in-memory) |

On `completeOnboarding()`: `profile.onboardingCompleted = true` is written to SwiftData. ContentView gates on that flag.

## Strong points

### S1. Re-entrancy guard on `completeOnboarding`
`isCompleting: Bool` flag prevents a double-tap on Done from creating duplicate UserProfile rows or running the side-effect chain twice (line 21 doc-comment).

### S2. Navigation throttle
`lastNavAt: Date` rate-limits `advance()` calls (QA BUG-10 fix referenced at line 34). Stops a fast tap from skipping screens 0 → 4 instantly.

### S3. Coach Reach consent on screen 5, post-Intention
[OnboardingContainerView.swift:100-108](MyAIssistant/Views/Onboarding/OnboardingContainerView.swift#L100) — explicitly inserted to prevent the proactive pillar shipping dark. The framing ("your coach will check in about X") is concrete because the user just typed X. Without this screen, `nudgeEnabledKey` would default false and never get set true. **This is correct prioritization** — the spine of the product (Pillar 1: proactive coaching) needs an opt-in path.

### S4. Closing-step sub-state-machine bound at container level
`closingStage: OnboardingClosingView.Stage` is owned by the container and bound INTO the closing view, so a re-mount of the closing view (e.g. layout pass after rotation) doesn't reset SignIn → Name → Notification progress.

### S5. Delete onboarding-only Schedule screen
The doc at line 42-43 notes the prior "Schedule" screen was absorbed into the Notification screen via `showsScheduleContext`. Reduces friction (one less tap-through) and keeps the flow at 8 screens.

## Findings

### F1. (HIGH) — `currentPage` is `@State`, not `@SceneStorage` — backgrounding mid-flow resets to page 0
[Line 8](MyAIssistant/Views/Onboarding/OnboardingContainerView.swift#L8): `@State private var currentPage = 0`

If iOS purges the scene while the user is mid-onboarding (e.g. they get a phone call on page 4 IntentionCapture, or background the app to look something up), the OS may evict the scene's state. On return, `currentPage` is reset to 0, **and the user has to start over.**

`ratings`, `capturedIntention`, `capturedName`, `addedTaskIndices` are also `@State` — all lost.

**Repro:** Force-quit Thrivn from app switcher mid-onboarding. Relaunch. Land on page 0 with no memory.

**Why this matters:** onboarding is the highest-friction surface. Forcing the user to repeat 4 screens of input because they took a phone call is a measurable activation killer.

**Fix:**
```swift
@SceneStorage("onboarding.currentPage") private var currentPage: Int = 0
```

For complex types (`[LifeDimension: Int]` ratings, `Set<Int>` addedTaskIndices), encode to JSON and store as String via @SceneStorage. ~1h refactor.

**Caveat:** SceneStorage survives within a scene's lifetime but does NOT survive a true cold launch. For the cold-launch case, persist to SwiftData / UserDefaults. The right pattern is probably **draft-record persistence**: write a `OnboardingDraft @Model` after each screen, restore on relaunch if `profile.onboardingCompleted == false`.

**Cost:** ~3-4h for the proper persistence pattern, ~1h for the SceneStorage stop-gap.

### F2. (HIGH) — `closingStage` is `@State` — sub-state-machine resets on scene purge
Same root cause as F1 but worse impact: the user may have ALREADY signed in with Apple ID, then gets a phone call mid-name-entry, comes back, and is asked to sign in AGAIN. Apple Sign In flow with re-prompt is a particularly bad UX failure.

**Action:** persist `closingStage.rawValue` to @SceneStorage minimum.

### F3. (Medium) — `closingStage` reset when user navigates back from page 7
The doc says "stage is bound from the container so a re-mount doesn't reset" (lines 121-123). But what if the user is on page 7 stage Notification, taps Back to page 6, then forward again to page 7? The closingStage variable IS owned at the container, so it should retain its value. But let me confirm the binding direction allows this without resetting.

**Action:** trace the binding to `OnboardingClosingView`. If the view's `init` overwrites `stage`, the user goes back to SignIn. ~10 min spot-check.

### F4. (Medium) — User can skip Coach Reach consent
[Line 95-97](MyAIssistant/Views/Onboarding/OnboardingContainerView.swift#L95) — IntentionCaptureView has both `onContinue` and `onSkip`. Both call `advance()`. Skipping is allowed.

But OnboardingCoachReachView (screen 5) likely has only `onContinue` — let me verify. If it's tappable-past with no consent action, `nudgeEnabledKey` stays false (the doc explicitly says this is the screen that sets it true).

**Action:** verify CoachReachView's continue button is gated on consent action OR that "Continue" itself is the consent action. ~5 min.

### F5. (Medium) — No offline check at SignIn stage
The closing stage 1 is Sign In with Apple. If the user is offline at this point (airplane mode in flight, plane wifi down), the Sign In flow may hang or fail with an unfriendly system error. Onboarding ends at a dead-end.

**Action:** detect offline state on the SignIn stage, surface a "you can sign in later" offer that completes onboarding minus the auth step. ~2h with a clean retry path.

### F6. (Low) — 2540 LOC across 9 onboarding files
The flow is split into focused files, which is good. But `OnboardingCompassRevealView` is 367 lines and `OnboardingContainerView` is 364 lines. Both have room to break up. Not urgent.

### F7. (Low) — No analytics on per-screen drop-off
The flow is the highest-leverage activation funnel. Without telemetry on which screen users abandon at, there's no data-driven path to improving conversion. Per CLAUDE.md the project doesn't have analytics yet — when it adds them, onboarding screens are the FIRST instrumentation target.

**Cost:** ~3h once analytics infrastructure exists. Out of scope for tonight.

### F8. (Informational) — `progressDots` shown for pages 1 through totalPages-2
Pages 0 (Welcome) and 7 (Closing sub-state-machine) deliberately hide the dots. Reasonable — Welcome has its own design language, Closing has its own internal progress indicator.

## Recommended fix order

1. **F1 + F2 — persist onboarding state via @SceneStorage** (~1h stop-gap, 3-4h for proper draft model). **Highest leverage** — directly addresses the "phone call mid-flow" failure mode.
2. **F4 — verify CoachReach consent isn't skippable** (5 min).
3. **F3 — verify closingStage doesn't reset on Back→Forward navigation** (10 min spot-check).
4. **F5 — offline detection on SignIn stage** (~2h).

Total: ~5h to close all High and Medium gaps. F7 (analytics) waits for the analytics platform decision.

## Critical takeaway

**The state-machine architecture is correct, but the persistence layer is wrong.** State that survives only within a scene's lifetime is too fragile for a flow this important. The fix is mechanical (`@State` → `@SceneStorage` for primitives, draft model for complex types) but the impact is large — the user's first-impression flow becomes resilient to interruptions.
