# Priority queue — 2026-05-04 (after 3 /overnight passes)

**Source:** consolidated from 18 audit reports across passes 1, 2, 3.

This is the sequenced fix plan. Higher = more urgent. Each item has cost, blast radius, and the audit it came from.

## P0 — safety boundary holes

### P0-1. Port crisis classifier to watch chat — 2-3h
Watch chat (`WatchVoiceChatView.sendTextQuery`) sends user transcripts straight to Anthropic with NO classifier. Same severity as today's iOS chat fix, just on the other surface.

**Source:** [audit-watch-app.md](audit-watch-app.md) F1
**Blast radius:** Watch target only. Add 2 new files, edit 1 existing (not in user's pending diff).
**Path:** Port `KeywordCrisisClassifier.swift` + `SafeResourceCopy.swift` into watch target. Add precheck in `sendTextQuery` before API call. Render safety bubble in WatchVoiceChatView.

### P0-2. Localize `SafeResourceCopy.message()` — 3-4h
Crisis classifier covers 5 languages (en/es/pt/zh/ja). Safety copy is English-only. A Japanese user whose 死にたい flags gets routed to English copy + English hotline.

**Source:** [audit-localization.md](audit-localization.md) F2
**Blast radius:** `Services/SafeResourceCopy.swift` (NOT in user's pending diff).
**Path:** add locale-specific message bodies for es/pt/zh/ja. Region-specific hotlines per [findahelpline.com](https://findahelpline.com/) directory.

## P1 — high-leverage, low-risk

### P1-1. Drag 35 unregistered test files into Xcode target — 30m
Test code on disk: 41 files. Tests registered in `.pbxproj`: 6. **85% of test code doesn't run.** Single 10-min Xcode session = 6× test coverage.

**Source:** [audit-test-coverage.md](audit-test-coverage.md), [audit-test-file-preflight.md](audit-test-file-preflight.md)
**Blast radius:** `.pbxproj` only.
**Path:** Multi-select 35 .swift files in Finder, drag into MyAIssistantTests group, uncheck app targets, choose "Create groups." Cmd+U. Triage 3-4 expected failures (~20 min).

### P1-2. Refresh stale NudgeEngine doc-comment — 2 min
Header claims "Phase 1: rule set is empty, killSwitch is true by default." Reality: 3 rules registered, killSwitch is `false`. Engine is **live**.

**Source:** [audit-nudge-engine.md](audit-nudge-engine.md) F1
**Blast radius:** doc-comment only.

### P1-3. Reconcile CLAUDE.md theme count (5 vs 9) — 10 min
CLAUDE.md says 5 themes; code has 9 (indigo, paper, slate, accessibleDark are undocumented). Decide ship/prune; update doc.

**Source:** [audit-themes-wcag.md](audit-themes-wcag.md) F1

### P1-4. `userName` `.sanitizedForPrompt` — 1 min
The one user-input string in AIPromptBuilder that bypasses sanitization. Defense-in-depth gap.

**Source:** [audit-ai-prompt-builder.md](audit-ai-prompt-builder.md) F1

### P1-5. Onboarding `@SceneStorage` for currentPage + closingStage — 1h
User who gets a phone call mid-onboarding restarts at page 0. Worst case: re-prompts for Apple Sign In after they already signed in.

**Source:** [audit-onboarding-state-machine.md](audit-onboarding-state-machine.md) F1, F2
**Blast radius:** `OnboardingContainerView.swift`. NOT in user's pending diff (verify).

## P2 — quality-of-life

### P2-1. CompassView empty + partial states — 1h
First-run users land on a tab that visually says "you have no harmony" with no empty-state CTA.

**Source:** [audit-five-state-screens.md](audit-five-state-screens.md) F1

### P2-2. Recap card error state — 20 min
`generateRecap()` returns nil on failure → blank space. Add a "Couldn't generate. [Retry]" card.

**Source:** [audit-five-state-screens.md](audit-five-state-screens.md) F3

### P2-3. ScheduleView `LazyVStack` migration — 30m
ForEach over pending+completed timelines is non-Lazy. Risky for users with calendar imports.

**Source:** [audit-performance.md](audit-performance.md) F1

### P2-4. Verify widget `.privacySensitive()` on task titles — 30 min
Lock Screen widgets visible to anyone holding the device. Verify titles redact when locked.

**Source:** [audit-widgets.md](audit-widgets.md) F1

### P2-5. Manager doc-comment headers (top 6 load-bearing) — 2h
ChatManager, TaskManager, HabitManager, ParticleAnimator, PatternEngine, BackgroundTaskManager — all lack a top-of-file `///` block explaining purpose + invariants.

**Source:** [audit-tech-debt.md](audit-tech-debt.md)

### P2-6. Close 11 don't-do violations — 80 min
9 `DispatchQueue.main.async`, 2 `Task.sleep(nanoseconds:)`, 1 `.onAppear { Task { } }`. Pattern-matched fixes.

**Source:** [audit-dont-do-violations.md](audit-dont-do-violations.md) H1, H2, M2

### P2-7. WCAG contrast test harness — 3h
9 themes × 12 critical color pairs need 4.5:1 verification. Today: zero automated checks. Highest leverage = catches future regressions automatically.

**Source:** [audit-themes-wcag.md](audit-themes-wcag.md) F2

## P3 — polish

### P3-1. `.font(.system(size:))` → AppFonts cleanup — 1.5h
96 hardcoded literals bypass Dynamic Type. Pattern-matched fixes.

**Source:** [audit-accessibility.md](audit-accessibility.md) G1

### P3-2. Decorative-icon `.accessibilityHidden(true)` pass — 2h
267 SF Symbols, only 32 explicitly hidden. Many likely cause double-announce in VoiceOver.

**Source:** [audit-accessibility.md](audit-accessibility.md) G3

### P3-3. NudgeEngine test coverage — 6h
809 lines, zero tests. Highest-impact untested system.

**Source:** [audit-nudge-engine.md](audit-nudge-engine.md) F8

### P3-4. AIPromptBuilder golden-file tests — 1h
Lock the prompt content under test so future edits are explicit.

**Source:** [audit-ai-prompt-builder.md](audit-ai-prompt-builder.md) F6

### P3-5. WatchFonts migration — 1.5h
Watch app has 0 AppFonts uses. Dynamic Type doesn't apply.

**Source:** [audit-watch-app.md](audit-watch-app.md) F4

### P3-6. CompassView empty state design + 3 more five-state-screen gaps — 2h
Per the audit's full table.

**Source:** [audit-five-state-screens.md](audit-five-state-screens.md)

## P4 — strategic / multi-day

### P4-1. CI: GitHub Actions running `xcodebuild test` on every push — 2h
Without CI, the 35-test wire-up is only as effective as manual Cmd+U habit.

**Source:** [audit-test-coverage.md](audit-test-coverage.md)

### P4-2. Onboarding draft-record persistence — 3-4h
P1-5 is the stop-gap. The proper fix is a `OnboardingDraft @Model` that survives true cold launch.

**Source:** [audit-onboarding-state-machine.md](audit-onboarding-state-machine.md) F1

### P4-3. BalanceManager god-class split — 2 days
Documented but DON'T DO IT WITHOUT TESTS FIRST. Write a black-box behavior contract, get green, then split.

**Source:** Pre-existing (referenced in CLAUDE.md and pass 1 audit).

### P4-4. Remote kill switch for NudgeEngine — 1 day
Static `nudgeEngineKillSwitchEnabled = false` requires a release to flip. Cloudflare KV-backed flag would let it flip without ship.

**Source:** [audit-nudge-engine.md](audit-nudge-engine.md) F6

### P4-5. App-wide i18n extraction — 6-8h
364 hardcoded `Text("...")` strings. Mechanical convert to `String(localized:)`.

**Source:** [audit-localization.md](audit-localization.md) Option B

### P4-6. CI lane for schema consistency — 1h
Catch accidental V1 schema changes before they ship. Pairs with the V2 recipe.

**Source:** [audit-schema-v2-cost.md](audit-schema-v2-cost.md)

## Burndown estimates

| Tier | Total cost | If done in order |
|---|---|---|
| P0 | 5-7h | 1 day |
| P1 | ~3h | half day |
| P2 | ~9h | 1.5 days |
| P3 | ~14h | 2-3 days |
| P4 | 4-7+ days | weeks |

**P0 + P1 = ~8-10h.** This is the **realistic 1-2 day push** to close the safety boundary holes and unlock test coverage. Do these before P2+.

## What I would actually start with on Monday morning

1. **P1-1** (test target wiring) — 10 min. Unlocks every other test-related improvement.
2. **P0-1** (watch crisis classifier) — 2-3h. P0 safety.
3. **P0-2** (localize SafeResourceCopy) — 3-4h. P0 safety.
4. **P2-7** (WCAG contrast test harness) — 3h. Locks in theme correctness for the future.

That's a single-day push that closes both P0 items, the highest-leverage P1, and one P2 with strong long-tail value. Everything else can be sequenced opportunistically.
