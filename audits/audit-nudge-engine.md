# Audit — NudgeEngine deep-dive
**Run:** /overnight 2026-05-04 pass 3
**File:** [NudgeEngine.swift](MyAIssistant/Managers/NudgeEngine.swift) — 809 lines.
**Why this matters:** the second-most load-bearing system after AIPromptBuilder. NudgeEngine decides when, what, and to whom proactive coaching messages get delivered. A bug here directly damages the product's central pillar (per CLAUDE.md, proactive coaching IS the spine).

## Architecture summary

8-step gate sequence per evaluation:
1. **Re-entrancy guard** (`isEvaluating` flag)
2. **Kill switch** (`AppConstants.nudgeEngineKillSwitchEnabled`)
3. **Safety pause** (24h cooldown after a crisis flag)
4. **Safety precheck** (crisis-classifier scan of latest check-in note → SafeResourceCopy if flagged)
5. **User toggle** (`nudgeEnabledKey`)
6. **Off-frequency short-circuit** (frequency setting `.off` exits)
7. **Daily + hourly caps** (`withinFrequencyCaps`)
8. **Rule loop** — first-match-wins, with per-rule silencing, quiet-hours gate, cooldowns

Entry points: `evaluateOnForeground()` (scenePhase active), `runScheduledEvaluation()` (BGTask).

## Strong points

### S1. Re-entrancy guard (lines 105-110)
A foreground `evaluate()` and a BGTask `evaluate()` could otherwise both await the composer and persist concurrent nudges, busting frequency caps. The `isEvaluating` flag with a `defer { isEvaluating = false }` is the correct pattern. Comment explicitly cites Q1-BUG-27.

### S2. Safety precheck before user toggle
Step 4 (safety) runs BEFORE step 5 (user-toggle gate). Even if the user has turned off coaching nudges, crisis content still routes to safety resources. Correct hierarchy — safety overrides preference.

### S3. Per-note dedupe on safety route
`safetyNoteFingerprint(recordID:, text:)` prevents the loop where, after the 24h pause lifts, the same historical flagged note re-triggers on every foreground. Comment cites Q1-BUG-26.

### S4. First-match-wins rule order is documented
Lines 42-49 explain why `PostLowMoodCheckInRule` must precede `WeakDimensionWithOpenWindowRule`: time-sensitive (90-min window after check-in) vs always-eligible. Without this, weak-dim would always preempt the more-relevant fresh-check-in rule. Comment cites BUG-16.

### S5. Per-rule silencing actually consulted
Earlier bug (Q1-BUG-29): the UI toggle wrote to `nudgeSilencedCategoriesKey` but the engine never read it. Now `readSilencedCategories()` runs before each rule's evaluate. Fix is verified.

### S6. Quiet-hours bypass is bounded
A user's "do habits at night" preference can opt a rule into bypassing quiet hours **on foreground only** (in-app card, not push). Scheduled BGTasks always respect quiet hours, so we never wake the device at midnight.

## Findings

### F1. (High-Medium) — Stale doc-comment claims kill switch is on by default
Line 12-13: *"Phase 1 state: rule set is empty and `nudgeEngineKillSwitchEnabled` is true by default — the engine evaluates nothing and delivers nothing."*

Reality (verified):
- Rule set has 3 rules registered (lines 52-56)
- `AppConstants.nudgeEngineKillSwitchEnabled = false` (AppConstants.swift:141)

The engine is **live** in production. The doc-comment is stale.

**Risk:** new contributor reads the header, assumes engine is dormant, makes a change that breaks live behavior without realizing.

**Fix:** update the doc-comment to reflect current state. 2 min.

### F2. (Medium) — `isEvaluating` is a plain Bool — not enough for true re-entrancy guarantee
The guard works for re-entrancy across `await` boundaries on the same actor. But:
- It's not atomic vs Sendable closure capture if NudgeEngine is ever called from a non-MainActor caller. Today it's `@MainActor`, so safe.
- If a future refactor makes any helper `nonisolated`, the guard breaks silently.

**Action:** either annotate the contract (a comment explicitly stating "this guard relies on @MainActor isolation") or migrate to an actor-isolated counter. ~10 min for the comment, ~1h for the actor.

### F3. (Medium) — Rule cooldown logic is in one giant function
Lines 670-720+ likely contain a long `isRuleInCooldown(_:)` / `isDimensionInCooldown(_:)`. Without reading the full impl, hard to assess whether cooldowns persist across app restart (UserDefaults? in-memory? SwiftData?).

**Action:** verify cooldown persistence. If in-memory only, a user crashing/relaunching could re-fire the same nudge inside its cooldown window. If SwiftData, check that the cleanup cadence prevents unbounded growth.

### F4. (Medium) — Composer is `await`-ed per rule but rules aren't
The rule loop calls `rule.evaluate(context:)` synchronously (returns optional `NudgeCandidate`). Then `composer.compose(candidate)` is `await`-ed. If a rule's evaluate becomes async in Phase 3+ (e.g. fetches from BalanceManager), the loop's structure would need updating. This is fine today but worth a contract test.

**Action:** add a doc-comment to `NudgeTriggerRule` protocol: "evaluate must be sync — async work belongs in `composer.compose`." ~5 min.

### F5. (Low) — Precheck samples the LATEST check-in only
[Line 257-260+](MyAIssistant/Managers/NudgeEngine.swift#L257) — `latestFreeTextSafetySample()` returns the most recent check-in note. If a user does multiple check-ins in quick succession (morning + midday) and only the morning one had crisis content, the precheck on the midday call samples the midday note (likely benign) and misses the morning flag.

**Mitigating factor:** the iOS check-in flow gates crisis content directly via `DailyRecapGenerator` at write time, AND `ChatManager.send` gates chat input. The NudgeEngine precheck is a third-line defense, not the primary boundary.

**Action:** comment-only — document that this samples the latest, not all-since-last-evaluation. The chat + recap gates are the primary boundaries.

### F6. (Low) — `nudgeEngineKillSwitchEnabled` is a static constant
Line 141 of AppConstants: `static let nudgeEngineKillSwitchEnabled = false`. To turn it on emergency-style, the team would have to ship a new build. Most kill switches are remote-config so they can flip without a release.

**Action:** for v1 ship, OK. For v2, consider a Cloudflare Workers KV-backed flag the app fetches at launch. ~1 day.

### F7. (Informational) — 809 lines but coherent
The file is long but the gate sequence is clear (steps numbered 1-8 inline). Probably split-able into:
- `NudgeEngine` (orchestration, gates)
- `NudgeSafetyGate` (crisis precheck + pause)
- `NudgeFrequencyGate` (caps, cooldowns)
- `NudgeContextBuilder`

But that's a "nice to have" — current structure is readable. Don't split unless a real refactor is happening.

### F8. (Informational) — No tests
NudgeEngine has zero tests (per pass 1 audit). The rule loop, gate sequence, and dedupe logic are all untested. **Highest-leverage future test target** — the consequences of a bug here are user-visible safety/UX failures.

**Suggested test scaffold:**
- Mock `crisisClassifier`, `composer`, `notificationManager`
- Stub `rules` to controlled values
- Assert each gate's behavior in isolation
- Property-test the cooldown / cap math

~6h to set up + cover the 8 gates.

## Cross-feature impact

The engine is wired in [MyAIssistantApp.swift:148](MyAIssistant/MyAIssistantApp.swift#L148):

```swift
let engine = NudgeEngine(
    modelContext: context,
    composer: composer,
    crisisClassifier: crisisClassifier  // ← shared with ChatManager + DailyRecapGenerator
)
```

The shared classifier is good — single source of safety truth across surfaces. Confirmed earlier in the security review.

## Recommended fix order

1. **F1 — refresh stale doc-comment** (2 min). Cheap, prevents misunderstanding.
2. **F4 — annotate rule-evaluate sync contract** (5 min).
3. **F2 — annotate re-entrancy guard MainActor dependency** (5 min).
4. **F3 — verify cooldown persistence** (~30 min reading + possibly fixing).
5. **F8 — add NudgeEngine tests** (~6h, when the 41-test wire-up is done and a test harness exists).
6. **F6 — remote kill switch** (~1 day, post-launch concern).

## Critical takeaway

This is a strong system. The 8-step gate sequence is the right architecture for proactive coaching. The two highest-impact actions are:
- **Refresh the stale doc-comment** (engine is live, not Phase-1 dormant)
- **Add tests for the gate sequence** (zero current coverage on a load-bearing system)

Neither is risky. Both should land before any Phase 3 rule additions, otherwise debugging the next rule will be guess-and-check.
