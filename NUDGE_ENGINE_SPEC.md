# NUDGE_ENGINE_SPEC.md — Thrivn Proactive Coaching

**Status:** Draft v0.2 — 2026-04-21 (§12 open questions resolved; §3 schema approach corrected against `Models/SchemaVersioning.swift`)
**Scope:** Architectural spec for the proactivity engine that turns Thrivn from a reflective tool into a coach with agency. Authoritative for implementation of the coach-as-spine pillar.

**Related docs:**
- `CLAUDE.md` — pillars + non-goals (proactive coaching is Pillar 1)
- `MyAIssistant/COMPASS_SPEC.md` — dimension scoring (an input to trigger rules)
- `MY_AISSISTANT_V1_REBUILD_ADDENDA.md` — post-freeze feature set

---

## 1. Goal

Ship a system that produces **one uncannily-timed, specific nudge per week that the user is glad to receive.** Hit rate is the product metric. Volume is a vanity metric.

A nudge is: a short, specific, action-suggesting message that arrives when the user didn't ask for it and reshapes the next chunk of their day if they accept.

**North-star example (not literal copy):**
> Tuesday 3:47pm — "Body's been quiet this week. You've got 20 min before the 4:15. Want me to add a walk?"
> → [Add] [Not now] [Ask later]

The product bet: each high-quality nudge earns permission for the next. A single wrong nudge burns weeks of trust.

---

## 2. Non-goals

- **Notification volume targets.** If we ship 5 nudges/week for a month, we've failed. The ceiling is 1–2 per day.
- **Cheerleading nudges.** "You got this!" is not a nudge. Every nudge names a specific action or asks a specific question.
- **Unprompted emotional probes.** "How are you really feeling?" is not allowed outside a check-in surface. Crosses into therapy.
- **Background LLM generation at notification time.** Latency + cost + offline-ness make this unworkable. See §4.
- **Replacing `NotificationManager`'s check-in reminders.** Those stay; nudges are additive and dedupe against them.

---

## 3. Nudge data model

New SwiftData `@Model`:

```swift
@Model
final class Nudge {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var scheduledFor: Date?        // nil = deliver immediately
    var deliveredAt: Date?
    var respondedAt: Date?

    // What triggered this
    var triggerRuleRaw: String     // NudgeTriggerRule.rawValue
    var triggerContextJSON: String // serialized inputs for audit / eval

    // Content
    var bodyText: String           // the visible nudge copy
    var suggestedActionRaw: String // NudgeAction.rawValue
    var suggestedActionPayload: String? // e.g. task title to pre-fill, dimension to focus

    // Taxonomy
    var dimensionRaw: String?      // body/mind/heart/spirit or nil for "general"
    var categoryRaw: String        // NudgeCategory.rawValue

    // Lifecycle
    var statusRaw: String          // NudgeStatus.rawValue
    var userResponseRaw: String?   // accepted/dismissed/snoozed/ignored

    init(...) { ... }
}

enum NudgeCategory: String {
    case weakDimension         // "Body's been quiet this week"
    case streakAtRisk          // "You've got 3 hours to keep your streak"
    case calendarGap           // "You have 45 min open — want a reset?"
    case habitSlip             // "You've skipped meditation 3 of 5 days"
    case postCheckInAction     // "You said flat mood — 10 min walk?"
    case goalCheckpoint        // "It's been 2 weeks since you declared [goal]"
}

enum NudgeAction: String {
    case createTask
    case startFocusTimer
    case openCheckIn
    case openChat
    case none                  // pure reflection nudge, no action
}

enum NudgeStatus: String {
    case pending               // rule fired, copy generated, not yet delivered
    case delivered
    case responded
    case expired               // not acted on before expiry
    case suppressed            // caught by dedupe/quiet-hours/cap
}

enum UserNudgeResponse: String {
    case accepted              // tapped primary action
    case dismissed             // tapped "Not now"
    case snoozed               // "Ask later"
    case ignored               // no interaction before expiry
    case silenced              // "Don't nudge about X again"
}
```

**Schema: additive to `SchemaV1`, no migration.** The project is on a deliberate single-baseline pre-1.0 schema — `Models/SchemaVersioning.swift` header prescribes that new models join `SchemaV1.models` directly and SwiftData handles lightweight auto-migration. Prior drafts (and the V1 rebuild doc / addenda) incorrectly claimed the schema was at V4; that's doc drift. No `VersionedSchema.V5`, no `MigrationStage`, no fixture-based migration test. The V2-recipe in the header stays reserved for a future breaking change.

Concretely for Phase 1: append `Nudge.self` to `SchemaV1.models`; the live `ModelContainer` picks it up on next launch.

---

## 4. Architecture: where nudges come from

Three-stage pipeline. Each stage is on-device; no server round-trip at delivery time.

```
  [Signal collectors]   →   [Trigger Rules]   →   [Copy Generator]   →   [Delivery]
   (existing managers)      (NudgeEngine)        (NudgeComposer)       (NotificationManager
                                                                        / in-app banner)
```

### 4.1 Signal collectors (existing, no changes)

- `BalanceManager` — dimension scores 0–100 per Body/Mind/Heart/Spirit
- `PatternEngine` — streak count, completion rate, mood trend
- `TaskManager` — today's load, overdue count, open windows
- `CalendarSyncManager` — calendar gaps, upcoming meetings
- `HabitManager` — habit completion rate, consecutive-miss count
- `CheckInManager` — most recent check-in mood/energy, time since last
- `CheckInBehaviorEngine` — active windows, user rhythm

All read-only. `NudgeEngine` never mutates these.

### 4.2 `NudgeEngine` (new)

`@Observable @MainActor final class NudgeEngine`

Owns:
- Trigger rule evaluation (see §5)
- Dedupe + frequency caps (see §7)
- Schedule: runs on app foreground + `BGTask` daily (see §4.5)
- Eligibility gate: calls `NudgeComposer` only for eligible triggers

Dependencies (injected via `EnvironmentKey`, per project convention):
- `ModelContext`
- `BalanceManager`, `PatternEngine`, `TaskManager`, `HabitManager`, `CheckInManager`
- `NudgeComposer`
- `NotificationManager`

### 4.3 `NudgeComposer` (new)

`actor NudgeComposer` — network-bound.

Given a triggered rule + context, produces nudge copy. Two paths:

**Path A — Template (offline, free, ~50ms).** Each rule has a parameterized template. Example:

```
weakDimension → "{dimension} has been quiet this week. You've got {minutes} before {nextEvent}. {actionSuggestion}?"
```

Template-generated nudges are the default for v1 — zero LLM cost, zero latency, works offline.

**Path B — LLM-enhanced (when user is online, Pro+ tier).** Template feeds `AIPromptBuilder.nudgeSystemPrompt()` as structured context; Claude Haiku returns a warmer, more specific rewrite. Cached per rule + dimension + day to avoid per-trigger API spend. Capped at N LLM nudges/day (free: 0, Pro: 3, PowerUser: unlimited).

**Critical:** LLM generation happens at **trigger evaluation time** (when `NudgeEngine` runs on app foreground or BGTask), **not at delivery time.** The nudge body is fully formed and stored before the notification is scheduled. This means:
- Delivery is always offline-safe
- No user waits on Claude latency
- Failed LLM calls silently fall back to Path A

### 4.4 `AIPromptBuilder.nudgeSystemPrompt()` (new)

Follows the existing split-prompt pattern (stable cached block + volatile volatile block). Stable block instructs Claude to:
- Produce ≤ 2 sentences
- Name the specific action or the specific observation
- Never begin with praise
- Never use cheerleading language
- Match user's rhythm from pattern context
- Return plain text only — no markdown, no lists

Volatile block supplies: dimension scores, last check-in mood/energy, triggered rule + context, today's schedule digest, template draft.

Uses `cache_control: ephemeral` on the stable block, same pattern as `chatSystemPromptStable`.

### 4.5 When `NudgeEngine` runs

Two entry points:

1. **App foreground** (scene phase `.active`) — runs eligibility check. If any rule fires and we're under daily cap, compose + schedule.
2. **Daily BGTask** — new `com.myaissistant.nudge-evaluation` identifier. Runs early morning (~6am). Evaluates day's schedule and pre-composes up to 2 nudges for delivery during the day.

BGTask hook added to `BackgroundTaskManager.registerAll()` alongside existing daily snapshot / weekly review / calendar sync.

`Info.plist` — add `com.myaissistant.nudge-evaluation` to `BGTaskSchedulerPermittedIdentifiers`.

---

## 5. Trigger rules (v1 set)

All rules are pure functions over collected signals. All return `NudgeCandidate?`.

| Rule | Fires when | Example copy |
|---|---|---|
| `weakDimensionWithOpenWindow` | A dimension's 7-day rolling score is in the bottom quartile of user's baseline AND calendar has a gap ≥ 20 min in next 4 hours AND no existing task in that dimension today | "Body's been quiet this week. 30 min open at 3pm — want a walk?" |
| `streakAtRisk` | Streak ≥ 3 AND current slot's check-in not logged AND ≥ 90 min since slot start AND slot closes in ≤ 60 min | "One more check-in keeps the streak alive. 30 seconds?" |
| `habitSlipEarly` | User's weekly habit has 2 consecutive misses AND it's the habit's usual time | "You usually meditate around now. Skip today or 5 min?" |
| `postLowMoodCheckIn` | Last check-in ≤ 90 min ago AND mood ≤ 3 AND user hasn't acted on the suggestion AND coach-config allows | "You said flat. A 10-min walk shifts mood more than any check-in will. Want one scheduled?" |
| `calendarReset` | 3+ back-to-back meetings finishing in < 15 min AND no buffer task scheduled | "Three meetings just ended. 5 min of stillness before the next?" |
| `goalCheckpoint` | User declared a goal ≥ 14 days ago AND zero tasks tagged to it in last 7 days | "You said [goal] matters. Nothing's moved in a week — still current?" |

Each rule implements:

```swift
protocol NudgeTriggerRule {
    var id: NudgeCategory { get }
    var cooldown: TimeInterval { get }        // min gap between firings of this rule
    func evaluate(context: NudgeEvalContext) -> NudgeCandidate?
}
```

`NudgeEvalContext` is a struct snapshotted from signal collectors at evaluation time. Deterministic: same context → same candidate. Critical for tests.

Adding a new rule = implementing the protocol + registering in `NudgeEngine.rules`. No other changes needed.

---

## 6. Delivery

### 6.1 iOS

**Primary channel: local notification.** `UNUserNotificationCenter` with a new category `NUDGE_CATEGORY` carrying two inline actions:

- `ACCEPT_ACTION` — primary, deep-links to the action (add task pre-filled, open focus timer, etc.)
- `DISMISS_ACTION` — "Not now"

Long-press reveals: `SNOOZE_ACTION` (ask in 2 hours) + `SILENCE_ACTION` (don't nudge about this category this week).

Notification body = `nudge.bodyText`. Title = "Thrivn". No subtitle (notification UI clutter).

**Secondary channel: in-app banner.** If user is in the app when a nudge would fire, no notification — a small banner slides in at the top of whatever surface they're on, dismissable by swipe. Same actions.

**Rejected:** Push notifications from Cloudflare backend. All nudge logic stays on-device for v1 — simpler, cheaper, better privacy. Revisit if we need cross-device coordination.

### 6.2 Watch

Watch receives nudges via existing `WatchConnectivity` (through `WatchSyncManager`) as read-only notifications. Accept action on watch → deep-links to watch surface for trivial actions (start focus timer, log a check-in). For anything needing text input (task creation) → defers to phone: "Continue on your phone."

---

## 7. Safety, dedupe, caps

All enforced by `NudgeEngine` before scheduling delivery.

### 7.1 Frequency caps

- **≤ 2 nudges/day.** Hard cap.
- **≤ 1 nudge/hour.**
- **Same rule:** cooldown per rule (default 48h; `streakAtRisk` 24h; `weakDimensionWithOpenWindow` 72h).
- **Same dimension:** ≤ 1 dimension-specific nudge per dimension per 48h.

### 7.2 Quiet hours

- Default **9pm – 8am** — no nudges delivered. Pre-composed nudges that fall in quiet hours either get rescheduled to 8am or expire.
- User-configurable in Settings → Coach → Quiet Hours.

### 7.3 Dedupe vs existing notifications

`NudgeEngine` checks `NotificationManager`'s pending notification queue before scheduling. If a check-in reminder is within ±30 min of the proposed nudge time, the nudge loses. Check-ins are calibration input — they must not be drowned out.

### 7.4 Crisis bypass

Before composing any nudge, `NudgeEngine` calls the crisis classifier (per `crisis-safety-protocols` skill) on the most recent check-in free-text + chat transcripts. If the classifier returns positive:
- All nudges suppressed for 24h
- A single safety-resource nudge is composed instead (hardcoded copy, never LLM, links to 988/Samaritans per user's locale)

Classifier runs on-device; no LLM call.

### 7.5 Kill switch

Remote kill switch in `AppConstants` (default on) lets us disable the engine entirely for a release if we need to.

### 7.6 User-facing tuning

Settings → Coach:
- [toggle] Proactive nudges (default ON)
- [picker] Nudge frequency: Gentle (1/day cap) / Balanced (2/day cap, default) / Off
- [time range] Quiet hours
- [list] Categories — per-category silence toggles
- [link] Nudge history — list of past nudges with response status, so user sees what the coach has been doing

Transparency is load-bearing: the user must always be able to see what the coach decided, why, and silence it.

---

## 8. Data flow

```
Every foreground OR every BGTask run:
  1. NudgeEngine.collectContext() → NudgeEvalContext
  2. For each rule in priority order:
        candidate = rule.evaluate(context)
        if candidate != nil AND passes caps/dedupe/quiet-hours:
            copy = NudgeComposer.compose(candidate)    [Path A always runs, Path B if eligible]
            nudge = Nudge(...) + modelContext.insert + safeSave
            NotificationManager.schedule(nudge) OR in-app banner
            break   (one nudge per run, hard)

On user interaction with a delivered nudge:
  NotificationCenter delegate → NudgeEngine.recordResponse(nudgeId, response)
  → nudge.userResponseRaw = response.rawValue
  → safeSave
  → if accepted: perform the deep link's action
```

All writes go through `modelContext.safeSave()` per project convention.

---

## 9. Telemetry and eval

Per the `coach-eval-framework` skill, the coach must be measurable or it drifts.

### 9.1 Local metrics (always collected, never leaves device)

- Nudges composed / delivered / accepted / dismissed / ignored / silenced, per category
- Per-rule fire rate
- Response latency (delivered → responded)
- **Hit rate** = `accepted / (accepted + dismissed + ignored)` per week

Surfaced to the user in Settings → Coach → Nudge history. Also surfaced in the weekly review.

### 9.2 Eval harness (dev-only)

Golden-scenario test suite: 20–30 synthetic `NudgeEvalContext`s with expected outcomes ("should fire `weakDimensionWithOpenWindow`", "should suppress — quiet hours"). Runs on every PR. Blocks merge on regression.

LLM-as-judge for `NudgeComposer` copy quality: "Does this nudge name a specific action? Does it avoid cheerleading? Is it ≤ 2 sentences?" Per the `coach-eval-framework` skill. Runs nightly on Claude-generated nudges (Path B).

### 9.3 Opt-in remote telemetry (deferred)

Not in v1. If added later: aggregate hit rate per rule, nothing user-identifiable, opt-in only, routed through `thrivn-backend`.

---

## 10. Integration points

### New files

```
MyAIssistant/
├── Managers/
│   ├── NudgeEngine.swift                (new — @Observable @MainActor)
│   └── NudgeComposer.swift              (new — actor)
├── Models/
│   └── Nudge.swift                      (new — @Model, plus enums)
└── Services/AI/
    └── AIPromptBuilder+Nudge.swift      (new — extension on existing enum)
```

### Modified files

- `BackgroundTaskManager.swift` — register new `nudge-evaluation` BGTask ID, add handler calling `NudgeEngine.runScheduledEvaluation()`
- `MyAIssistantApp.swift` — instantiate `NudgeEngine` + `NudgeComposer`, wire into environment via new `EnvironmentKey`s
- `Core/DependencyContainer.swift` — add `NudgeEngineKey`, `NudgeComposerKey`
- `Core/AppConstants.swift` — add `nudgeEvaluationBGTaskID`, `nudgeKillSwitchEnabled`, cap constants
- `Info.plist` — add `com.myaissistant.nudge-evaluation` to `BGTaskSchedulerPermittedIdentifiers`
- `Views/Settings/SettingsView.swift` — add Coach section entry point
- `Views/Settings/` — new `CoachSettingsView.swift` for tuning
- `Models/SchemaVersioning.swift` — bump to V5, register `Nudge.self`

### Untouched

- `PatternEngine`, `BalanceManager`, `TaskManager`, `HabitManager`, `CheckInManager`, `NotificationManager` — no internal changes. `NudgeEngine` consumes them read-only. `NotificationManager` gains a new category registration but the category list is already extensible.

---

## 11. Rollout plan

### Phase 1 — Scaffolding (day 1)

- `Nudge` model appended to `SchemaV1.models` (no migration per §3)
- `NudgeEngine` skeleton with empty rule set + cap/dedupe/quiet-hours/re-entrancy logic
- `NudgeComposer` with Path A (templates) only — Path B stubbed behind a clear interface, activated in Phase 3
- `CrisisClassifier` protocol + `KeywordCrisisClassifier` implementation (keyword-list fallback)
- `Info.plist` + BGTask registration (`com.myaissistant.nudge-evaluation`)
- Settings stub: Coach section with proactive-nudges toggle (off by default) and frequency picker

Ships to internal TestFlight with engine **disabled by default** via kill switch in `AppConstants`. Verify no regressions in notifications, BGTasks, check-ins.

### Phase 2 — First rule live (day 2-3)

- Implement `weakDimensionWithOpenWindow` rule (highest-value, lowest-risk signal combination)
- Ship to internal TestFlight with kill switch on per-device
- Dogfood for 1 week; hand-rate every nudge fired

Success criteria: ≥ 50% of fired nudges rated "would accept in real life" by dogfooders. Below that, tune rule thresholds before adding more rules.

### Phase 3 — Full v1 rule set (day 4-6)

- Add remaining 5 rules
- Wire Path B (LLM copy enhancement) for Pro+
- Eval harness with 20 golden scenarios
- User-facing Nudge history screen

### Phase 4 — Beta (week 2)

- Public TestFlight with engine ON by default, Balanced frequency
- Collect local metrics; surface hit rate in Settings
- Tune cooldowns and thresholds based on dogfood data

### Phase 5 — GA

- Ship to App Store only after: hit rate ≥ 40% in beta, zero crash reports tied to engine, eval harness green, kill switch verified.

---

## 12. Open questions — resolved 2026-04-21

All five resolved before Phase 1 code started:

1. **LLM copy in v1 or v2?** → **v1, spec proposal (a).** Path A templates as default for all tiers; Path B (LLM rewrite) behind Pro+ tier gate, both in v1. Free tier always sees templates; Pro+ sees LLM-warmed copy when online and under tier quota. Any Path B failure (offline, quota, API error) falls back to Path A. Phase 1 scaffolds Path A only; Path B wires in Phase 3.

2. **First rule.** → **`weakDimensionWithOpenWindow`.** Proves the coach-as-spine thesis (noticing neglect + timing into a calendar gap). `streakAtRisk` is table stakes and would teach us less about whether the product works.

3. **Crisis classifier.** → **Keyword-list fallback.** No ML model to train today; a curated ~30–50 high-confidence phrase list (explicit self-harm / SI language, idioms of hopelessness) satisfies `crisis-safety-protocols` ("classifier-first, LLM-never"). False-positive-leaning is the correct asymmetry for a safety layer. Implemented via `CrisisClassifier` protocol so a CoreML model can replace the keyword list later without touching callers.

4. **Nudge history.** → **Inline on Today, no destination.** Collapsible "Recent nudges" section on Today preserves transparency without earning a tab cost. Per pillar 2 filter — destinations compete with the coach.

5. **Re-entrancy.** → **One nudge per run, hard cap.** Accepting a nudge that ripples through signal sources must not cascade into follow-up nudges in the same run. Foreground-event + daily-BGTask cadence gives enough re-evaluation opportunities without storm-risk.

---

## 13. What this spec explicitly defers

- **Coach tab restructure.** Step #1 in the execution order. Happens only after this engine produces real nudges.
- **Voice reply to nudges.** "Hey Thrivn, snooze that" — not in v1. Voice-first capture for check-ins + tasks ships alongside; voice response to nudges is v1.1.
- **Multi-device coordination.** Nudges don't sync across devices in v1. If user accepts on iPhone, watch just sees it via existing WC mirror.
- **Adaptive learning.** The engine does not learn from user responses in v1 (beyond per-rule cooldowns). Thompson-sampling / contextual bandits are v2+.
- **Server-side generation.** Deferred. See §6.1 rejected alternative.
