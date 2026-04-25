# Onboarding Restructure — Parked Plan

**Status:** PARKED. Do NOT start until both prerequisites are met:
1. Build 9 archived + uploaded to TestFlight as `v1.4-beta6`.
2. Parallel onboarding agent (microcopy + a11y pass) has merged the 8
   currently-uncommitted `MyAIssistant/Views/Onboarding/*.swift` files.

When both are done, the 5 changes below can run in one focused pass without
merge conflicts.

---

## Goal

Reduce the 10-screen onboarding to 7 screens. Collapse redundant steps,
remove animation theatre, tighten the rating UX. Compass Reveal earns its
keep by carrying both Pillar 3 (radar) and Pillar 1 (AI's first spoken line).

## Conflict Map (vs. parallel agent's WIP at handoff time)

| # | Task | Files | Conflict | Safe before merge? |
|---|------|-------|---------|------|
| 1 | Compass Reveal — drop 0.8s animation theatre | `OnboardingCompassRevealView.swift` | HIGH | NO |
| 2 | Quick-Rate — 44pt → 52pt + sticky "Rating X of 4" VO label | `OnboardingQuickRateView.swift` | LOW | YES |
| 3 | Reassurance copy — reframe Intro, delete second instance in QuickRate | `OnboardingIntroView.swift:22`, `OnboardingQuickRateView.swift:40` | LOW | YES |
| 4 | Merge Notification + Schedule into one screen | `OnboardingScheduleView.swift` (delete), `NotificationPermissionView.swift` (extend) | HIGH | NO |
| 5 | Combine SignIn + Name + Notification | `SignInWithAppleView.swift`, `NameCaptureView.swift`, `NotificationPermissionView.swift` | HIGH | NO |

## The 5 Changes (approved by Joe)

### 1. Compass Reveal — keep, remove animation theatre
- File: `MyAIssistant/Views/Onboarding/OnboardingCompassRevealView.swift:98`
- Current: `withAnimation(.spring(response: 0.8, dampingFraction: 0.7).delay(0.3))`
- Change: drop the 0.8s spring delay. Snappier reveal, no theatre.
- This screen does double duty — reveal the radar AND deliver the AI's first
  spoken line (Pillar 1, proactive coaching is the spine).
- Respect `accessibilityReduceMotion` (parallel agent may already have gated).

### 2. Quick-Rate — lower density, bigger targets, VoiceOver label
- File: `MyAIssistant/Views/Onboarding/OnboardingQuickRateView.swift`
- Scale: keep 5 buttons (1, 3, 5, 7, 9) at line 19–25.
- Touch targets: line 127 currently 44pt → bump to **52pt**.
- Add a sticky `accessibilityLabel` "Rating X of 4" so VoiceOver users know
  their position across the 4 dimensions.

### 3. Reassurance copy — cut second instance, reframe first as strength
- KEEP & REFRAME (`OnboardingIntroView.swift:22`):
  - Old: *"There are no wrong answers — this is your starting point."*
  - New: **"Your honest rating is the only useful one."**
- DELETE (`OnboardingQuickRateView.swift:40`):
  - Remove: *"No wrong answers — go with your gut."*
- Reassures without apologising; one instance, not two.

### 4. Merge Notification + Schedule into ONE screen
- DELETE: `MyAIssistant/Views/Onboarding/OnboardingScheduleView.swift`
- EXTEND: `MyAIssistant/Views/Onboarding/NotificationPermissionView.swift`
- Show the 4 check-in slots (8am morning / 1pm midday / 6pm afternoon /
  10pm night) as **context inside** the notification priming screen — not
  their own destination.
- The `CheckInTime` enum lives in `OnboardingScheduleView.swift:8–13` —
  preserve it (move to a Models file) when deleting that view.

### 5. Collapse SignIn + Name + Notification into ONE screen
- Files: `SignInWithAppleView.swift`, `NameCaptureView.swift`,
  `NotificationPermissionView.swift`.
- Combine all three (plus the schedule context from #4) into a single
  closing screen: Apple sign-in → name confirm/edit → notification permission
  with schedule context.

## Final flow (Option B — value-first, confirmed by Joe)

| # | Screen |
|---|--------|
| 0 | Welcome |
| 1 | Compass Intro (reframed reassurance) |
| 2 | Quick Rate (5-pt, 52pt, no second reassurance) |
| 3 | Compass Reveal (no 0.8s delay, AI's first spoken line) |
| 4 | Intention Capture |
| 5 | Suggested Tasks |
| 6 | Combined SignIn + Name + Notification (with schedule context) |

**Rationale for end-placement:** User has *seen* their Compass and tasted the
coach before any commitments. Notification grant rate goes up. Sign-in
becomes "Sign in to save your Compass" — stronger CTA than upfront auth.

## Container changes

File: `MyAIssistant/Views/Onboarding/OnboardingContainerView.swift`

- `totalPages = 10` → `totalPages = 7`
- Re-tag the TabView pages 0..6 in the new order above.
- `goBack()` (line 166–186) has Apple-name-skip special-casing for old pages
  1→3 — rewrite for the new flow.
- `completeOnboarding()` (line 214–289) already saves everything on the final
  screen (ratings, tasks, intention, profile). Option B reordering matches
  this — no persistence-logic changes needed beyond the call site.

## SwiftData persistence (unchanged, just for context)

- `DailyBalanceCheckIn` at `MyAIssistant/Models/DailyBalanceCheckIn.swift:20–23`
  with fields `physicalSatisfaction` / `mentalSatisfaction` /
  `emotionalSatisfaction` / `spiritualSatisfaction` (all `Int?`). Setter at
  line 62–70.
- Ratings stored as raw 1–9; `BalanceManager` normalizes to 0–10.

## Constraints (CLAUDE.md / dont-do-master-list / ui-ux)

- 5 themes — never hardcode colors; use `AppColors.*` / `AppFonts.*`.
- 4pt spacing grid.
- Every interactive element needs `accessibilityLabel`.
- 44pt minimum touch targets (52pt for #2).
- Test Dynamic Type + dark mode.
- No `print()`, no `try!`, no force-unwraps.

## Build command

```bash
xcodebuild -project MyAIssistant.xcodeproj \
  -scheme MyAIssistant \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build
```

---

**Parked on:** 2026-04-25 (after build 9 push, before TestFlight upload).
**Triggers to start:** parallel agent merge + build 9 uploaded.
