# Morning briefing — 2026-05-04

**Run:** /overnight 2026-05-04 13:05–13:17 UTC (~12 min wall clock; would have been ~6h human-pace).
**Mode:** read-only audits. **Zero code changed.** Working tree is exactly as you left it.

## TL;DR

You wake up to:
- Your existing uncommitted diff (~50 files) — untouched, still yours to review.
- A new `audits/` folder with 5 ranked audit reports + this briefing.
- A clear priority order for the next 1–2 weeks of supervised work.

## Why no code changes

Your working tree had ~50 modified files when the run started — today's auto-advance + crisis classifier + latch + neutral pulse work, all uncommitted, all on `main`. Adding code-changes on top of that would have entangled my work with yours and made your morning review painful. So tonight is pure investigation. Report-only output.

## What landed (1 line per audit)

1. **[dont-do-master-list violations](audit-dont-do-violations.md)** — 11 High/Medium violations. ~80 min to close all. Headline: 9 `DispatchQueue.main.async`, 2 `Task.sleep(nanoseconds:)`, 1 `.onAppear { Task { } }`.
2. **[Five-state-screen audit](audit-five-state-screens.md)** — 5 confirmed gaps. ~2.5h once verified on device. Headline: **CompassView has zero non-ideal-state handling** — first-run users land on a tab that visually says "you have no harmony" with no empty-state CTA.
3. **[Accessibility + Dynamic Type](audit-accessibility.md)** — 7 ranked gaps, ~13h to AX5-ready. Headline: 96 hardcoded `.font(.system(size:))` literals bypass Dynamic Type; only 1 `@ScaledMetric` declaration in the whole codebase.
4. **[Test coverage](audit-test-coverage.md)** — only **6 of 41 test files are registered in the Xcode test target**. ~85% of test code on disk doesn't run. **One 10-min Xcode session would 6× your test coverage immediately.**
5. **[Tech debt](audit-tech-debt.md)** — Zero rotting TODOs. 14 of 26 Managers and 13 of 27 Services lack a top-level doc-comment. ~4-5h to close.

## Recommended priority order

If you have **2 hours** today after waking:

1. **Drag the 35 unregistered test files into the Xcode target** (10 min). Cmd+U. Triage failures. ([details](audit-test-coverage.md))
2. **Close the 11 `dont-do` violations** (80 min). Pattern-matched fixes, low-risk. ([details](audit-dont-do-violations.md))
3. **Verify your existing uncommitted diff on device** and commit thematically (~30 min).

If you have **a week** to invest:

4. CompassView empty + partial states (1h)
5. Recap card error state (20 min)
6. Streaming-loading state on chat (verify; 30 min if missing)
7. Manager doc-comment headers for the 6 load-bearing files (2h)
8. `.font(.system(size:))` → `AppFonts.*` cleanup (1.5h)
9. Decorative-icon `.accessibilityHidden(true)` pass on Home + Chat + Settings (2h)
10. CI: GitHub Actions running `xcodebuild test` on every push (2h)

That's ~12h of focused supervised work that would close the highest-leverage gaps without touching any of the load-bearing systems (BalanceManager, IAP, auth) that need separate planning.

## Pass 2 (run 2 of /overnight) — depth audits

After pass 1 finished, /overnight was invoked again. Working tree was still dirty, so pass 2 stayed read-only and went **deep** on the highest-leverage findings + areas pass 1 didn't cover.

### Pass 2 reports

1. **[Test file pre-flight](audit-test-file-preflight.md)** — Most pre-existing tests will compile cleanly when wired to the target. Spot-check found ~20 minutes of expected fix-up across 3-4 files (mostly substring assertions on prompts that drifted). Wire-up step is still safe to do.
2. **[AIPromptBuilder deep-dive](audit-ai-prompt-builder.md)** — The single most load-bearing file (entire coach voice). Strong architecture — stable/volatile split, PII-minimized recap (notes are NOT sent to LLM, only length indicator), 20k-char hard cap. **One real finding:** `userName` is interpolated raw without `.sanitizedForPrompt` (1-line fix). Recommend adding golden-file prompt tests to gate future drift (~1h).
3. **[Performance audit](audit-performance.md)** — Static scan of SwiftUI perf antipatterns. Top finding: ScheduleView's pending+completed timeline ForEach are not in `LazyVStack` — risky for users with calendar imports. ~3h of static fixes; real perf work needs Instruments on device.
4. **[Watch app audit](audit-watch-app.md)** — 🚨 **HIGH-severity finding.** The watch chat path (`WatchVoiceChatView.sendTextQuery`) has **no crisis classifier and no input sanitization**. A watch user typing/speaking crisis content gets it relayed straight to Anthropic. Same severity class as the iOS chat leak we just fixed today. P0 follow-up. ~2-3h to port the classifier + wire safety route.
5. **[Widget audit](audit-widgets.md)** — Architecture is clean (App Group JSON only, no SwiftData access from widget, no chat/check-in note exposure). One verification needed: confirm task titles use `.privacySensitive()` for Lock Screen redaction (~30 min).
6. **[Localization readiness](audit-localization.md)** — App is English-only with zero i18n infrastructure. **Most critical:** `SafeResourceCopy.message()` is English-only despite the crisis classifier covering 5 languages (en/es/pt/zh/ja). A Japanese-speaking user whose note flags 死にたい gets routed to English safety copy. ~3-4h to fix.

### Pass 2's biggest finding

**The crisis-classifier safety boundary stops at the iOS-app edge.** It does NOT cover:

- The watch chat surface ([Watch audit F1](audit-watch-app.md#f1-high))
- Multilingual users on iOS check-in notes — they get matched in their language but routed to English copy ([Localization audit F2](audit-localization.md#f2))

Both are P0 follow-ups to today's iOS chat fix. Without them, the safety story is incomplete.

### Updated priority queue (after pass 2)

| Pri | Item | Cost | Why |
|---|---|---|---|
| **P0** | Port crisis classifier to watch chat | 2-3h | Closes the watch leak (Watch F1) |
| **P0** | Localize SafeResourceCopy | 3-4h | Closes the multilingual gap (Loc F2) |
| **P1** | Test target wiring + 20-min fixup | 30m | 6× test coverage; foundation for everything else |
| **P1** | userName `.sanitizedForPrompt` | 1 min | Defense-in-depth consistency |
| **P1** | CompassView empty/partial states | 1h | First-run UX |
| **P2** | LazyVStack on ScheduleView | 30m | Perf win for heavy users |
| **P2** | Verify widget `.privacySensitive()` | 30m | Lock Screen privacy |
| **P2** | Manager doc-comment headers (top 6) | 2h | Maintainability |
| **P3** | `.font(.system(size:))` → AppFonts cleanup | 1.5h | Dynamic Type consistency |
| **P3** | Decorative-icon `.accessibilityHidden(true)` pass | 2h | VoiceOver polish |

That's ~14h of P0+P1 work to close the highest-leverage safety + ship-ready gaps. Doable in a focused 2-day push.

## Pass 3 (run 3 of /overnight) — remaining load-bearing systems

After pass 2, /overnight was invoked a third time. Working tree still dirty (~9 hours stale by this point). Pass 3 covered the systems pass 1/2 didn't reach.

### Pass 3 reports

1. **[NudgeEngine deep-dive](audit-nudge-engine.md)** — second-most load-bearing file (809 lines). Strong 8-step gate sequence; one stale doc-comment claims engine is in dormant Phase 1 but reality is 3 rules registered + kill switch `false`. Engine is **live**. Highest-impact untested system.
2. **[Themes + WCAG audit](audit-themes-wcag.md)** — code has **9 themes**, CLAUDE.md documents 5. Doc drift. Zero automated WCAG contrast verification across themes. Twilight theme's coral safety bubble (0.06 opacity) needs visual verification.
3. **[Onboarding state machine](audit-onboarding-state-machine.md)** — 8-screen flow, well-architected. **HIGH-severity persistence gap:** `currentPage` and `closingStage` are `@State` (not `@SceneStorage`), so phone-call mid-onboarding resets to page 0. Worst case: re-prompt for Apple Sign In after user already signed in.
4. **[Schema V2 cost analysis](audit-schema-v2-cost.md)** — Architecture is right (single-baseline + clear V2 recipe + CloudKit warnings). Today's `isSafetyResource` addition followed the policy correctly. ~3-4h for clean additive V2, ~8-15h for non-trivial migration.

### Plus: composite [PRIORITY-QUEUE-2026-05-04.md](PRIORITY-QUEUE-2026-05-04.md)

The single artifact synthesizing all 18 audit reports into a sequenced fix plan. Tiered P0–P4. Full burndown estimates. **Read this first when you wake up** — the rest are reference detail.

### Pass 3 high-severity findings

| Finding | Severity | Cost |
|---|---|---|
| Onboarding state lost on scene purge | **HIGH** | 1h stop-gap, 3-4h proper |
| Stale NudgeEngine doc-comment | **HIGH** (misinformation) | 2 min |
| 4 undocumented themes (indigo/paper/slate/accessibleDark) | **HIGH** (doc drift) | 10 min |

## Three /overnight passes — totals

- **18 audit reports** (~110KB markdown).
- **Zero code changes.** Working tree still exactly as user left it.
- **Three new P0/HIGH findings** beyond pass 1: watch chat safety leak (pass 2), multilingual SafeResourceCopy gap (pass 2), onboarding state-loss (pass 3).
- **Single morning-read artifact:** [PRIORITY-QUEUE-2026-05-04.md](PRIORITY-QUEUE-2026-05-04.md).

## What I deliberately did NOT touch

- Anything in your uncommitted diff.
- Any `.pbxproj` changes (you'll do the test-target wiring in Xcode UI).
- Any backend (`thrivn-backend/`) work.
- BalanceManager, IAP/StoreKit, auth — these are out of scope for unsupervised work.
- Any device-verification-required item (camera, mic, push, calendar permission).

## State at end of run

```
Branch:      main
Working tree: dirty (your existing pending changes — untouched)
New files:    audits/ (6 .md files, 0 code changes)
Build state: not re-built tonight (no code changed; last green build was your work earlier)
Commits:     none added by this run
/qa runs:    0 (read-only mode; no implementations to review)
/security-review: deferred to next run when there's a diff to review
```

## Stopping reason

Audit queue exhausted. Each cycle ran shorter than estimated because the codebase is in better shape than expected — fewer violations, no rotted TODOs, strong AppFonts adoption. The remaining "long tail" of items (12h+ of accessibility work, week+ of test backfill, multi-week BalanceManager split) all need supervised judgment, not unsupervised time.

## Next time

If you want code changes from `/overnight`, run it on a clean working tree (commit your in-flight work first or stash it). The skill defaults to commit-as-you-go, which only makes sense when there's no concurrent uncommitted work to confuse the diff.

Otherwise, this read-only mode is the right shape: more audits, deeper sampling, more focused recommendations.
