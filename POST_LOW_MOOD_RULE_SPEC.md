# POST_LOW_MOOD_RULE_SPEC.md — `PostLowMoodCheckInRule`

**Status:** Design draft — 2026-04-22. Implementation spec for the second live rule in `NudgeEngine`, per `NUDGE_ENGINE_SPEC.md` §5. Expert panel (Product A) flagged this as the highest-leverage pre-tester rule because it converts a just-collected state signal into an uncannily-timed action prompt.

---

## 1. Trigger preconditions

`CheckInRecord` carries two 1–5 Int scales: `mood` and `energyLevel`, plus optional `notes`. Moods are **state, not trait** — the rule reads the latest completed record only and never promotes that reading into persisted user facts (per `conversation-memory-design` §6).

Rule fires when ALL hold:

- `context.lastCheckIn != nil` and `completed == true`
- `now - lastCheckIn.date ≤ 90 min` (freshness: the check-in is still the user's present state)
- `now - lastCheckIn.date ≥ 10 min` (cooldown: user needs space after logging before the coach speaks)
- Mood bucket is one of the five below:

| Bucket | Condition on (mood, energy) |
|---|---|
| `veryLow` | `mood == 1` |
| `low` | `mood == 2` |
| `flat` | `mood == 3` AND `energy ≤ 2` |
| `drained` | `energy == 1` AND `mood ≤ 3` |
| `anxious` | `notes` contains any of a curated keyword set (anxious/anxiety/worried/panicked/on edge/racing), mood ≤ 3, safety precheck already passed |

- Streak baseline: `context.streak ≥ 3` (avoid nudging brand-new users on their first-ever check-in)
- User has opted in to post-check-in action suggestions (new UserDefaults flag, §8)
- No existing `.postCheckInAction` nudge whose `triggerContext["checkInID"]` equals this record's `id` (record-scoped dedupe, §2)

Ranking when multiple buckets match: `veryLow > drained > low > anxious > flat`.

---

## 2. Cooldown model

Per-rule cooldown `nudgePostLowMoodCooldownHours = 20` (covers a typical 4-slot day so the same user can't receive two action-prompts across back-to-back slots).

**Record-scoped dedupe overrides cooldown.** The rule persists `triggerContext["checkInID"] = lastCheckIn.id` on every fire. Before firing, it queries `Nudge` for any row whose `categoryRaw == postCheckInAction` and whose stored `triggerContextJSON` contains that same check-in ID; if one exists, skip. This means dismissing a post-check-in nudge does NOT refire for the SAME record at the next foreground cycle — the engine's generic category cooldown already handles most of this, but record-scoped dedupe is the authoritative guard.

Parsing `triggerContextJSON` via `JSONSerialization` on ≤ a handful of candidate rows is cheap; bounded by daily cap.

---

## 3. NudgeEvalContext additions

`LastCheckInSnapshot` already exists in `NudgeTypes.swift` (`date`, `mood`, `energyLevel`, `notes`) but `collectContext` sets `lastCheckIn: nil` — comment says "unused by the Phase 2 rule."

Minimal addition — no struct changes needed. Populate in `NudgeEngine.collectContext`:

```
// after dimensionScores/openByDim/gaps
let last = fetchLatestCompletedCheckIn()   // FetchDescriptor<CheckInRecord>,
                                           // predicate completed == true,
                                           // sortBy date desc, fetchLimit 1
let snapshot = last.map { LastCheckInSnapshot(
    date: $0.date, mood: $0.mood,
    energyLevel: $0.energyLevel, notes: $0.notes
)}
```

Pass `lastCheckIn: snapshot` into the context constructor. Add one field to the snapshot: **`id: String`** so the rule can record it into `triggerContext` for record-scoped dedupe.

---

## 4. Template copy — per bucket

Templates follow the existing `NudgeComposer.renderTemplate(.postCheckInAction)` pattern — pull `moodLabel` and `suggestion` from `templateParams`. Proposed variants (rule rotates deterministically by `checkInID.hashValue % count` for variety without randomness):

**`veryLow`** (suggest `openCheckIn` re-check in 3h; optional chat path)
- "You logged a rough one. Want to talk it through, or set a gentler check-in for later?"
- "That's a hard number to log. No fix needed right now — just noted."
- "Logged. If you want, I can set a lighter check-in at [time+3h]."

**`low`** (suggest `createTask` — 10-min body shift)
- "You said low. Ten minutes outside tends to move this more than anything else. Want it on the schedule?"
- "Noted. A short walk before the next thing — worth a try?"
- "Low mood, logged. A glass of water and five slow breaths is the minimum viable shift."

**`flat`** (suggest `createTask` — novelty / sensory)
- "Flat and low-energy. A change of room or a short walk is usually the smallest lever."
- "You said flat. One small shift — step outside for five minutes?"

**`drained`** (suggest `openCheckIn` deferred OR `none` — permission to rest)
- "Drained. Not every dip needs a plan — rest counts as the action."
- "That energy level deserves a break, not a task. Check in again when you surface."

**`anxious`** (suggest `startFocusTimer` 5-min containment OR `createTask` breathwork)
- "Racing mind, logged. Five minutes of slow breathing is the shortest route back."
- "Anxious, noted. Want a 5-minute timer to sit with it, or add a grounding task?"

Copy rules enforced: ≤ 2 short sentences; no "great job", no exclamation points, no "you got this"; specific action (walk / timer / breath / rest / later check-in), never "self-care."

Template params: `moodLabel` (rule-supplied from bucket: "low", "flat", "drained", "that you're anxious", "a rough one"), `suggestion` (the action clause), `bucketRaw` (for analytics).

NudgeComposer change: `.postCheckInAction` case already exists. Replace the single-line template with a switch on `templateParams["bucketRaw"]` returning the corresponding copy family, falling back to current generic line on missing bucket.

---

## 5. Bucket → NudgeAction mapping

| Bucket | `NudgeAction` | Payload |
|---|---|---|
| `veryLow` | `.openChat` | nil (opens coach chat with a prefilled acknowledgment seed) |
| `low` | `.createTask` | `"walk-10min"` (action payload convention: slug; UI renders as pre-filled task) |
| `flat` | `.createTask` | `"step-outside-5min"` |
| `drained` | `.none` | nil (pure acknowledgment — permission-to-rest) |
| `anxious` | `.startFocusTimer` | `"300"` (5 min in seconds) |

`.none` is valid per `NudgeAction` enum — the existing weak-dimension rule uses `.createTask`, but `drained` is a case where suggesting work is the wrong move.

---

## 6. Safety interaction

`NudgeEngine.evaluate()` already runs `performSafetyPrecheck()` as step 3 before any rule fires (lines 93, 150–175). That precheck reads the latest completed `CheckInRecord.notes` and runs the on-device `CrisisClassifier`; a positive match short-circuits the entire pipeline, emits a `.safetyRoute` nudge, and records a 24h safety pause.

**Therefore this rule inherits the safety guard for free** and needs no additional classifier call. It MUST NOT:

- Copy-paste or re-summarize the user's `notes` into the template (the notes field may contain crisis language the classifier missed on a borderline call — a whisker-threshold miss).
- Send notes text into Path B (LLM) context when that wires up in Phase 3.

Defensive additional gate in the rule itself: if `lastCheckIn.notes` is non-empty, re-run `crisisClassifier.evaluate(notes)` inside the rule — on positive, return `nil` (let the precheck handle the next cycle; do not double-emit). This is belt-and-suspenders against the precheck running against an older record while a newer rushed submission just landed.

**Anxious bucket special handling:** the keyword check for "anxious/worried/panicked" runs ONLY on notes that have already passed the crisis classifier. No overlap between the two keyword lists.

---

## 7. Eval gates for "go live"

Per-rule hit rate must be measurable separately from aggregate. Add `category` faceting to the existing local metrics.

Go-live thresholds for `postLowMoodCheckIn`:

- **≥ 25 delivered nudges** (min sample) within dogfooders + first external cohort
- **Accepted rate ≥ 40%** (accepted / delivered, where "accepted" = user tapped the primary action)
- **Accepted + snoozed-then-returned ≥ 55%** (snoozed-then-returned = same bucket nudge accepted within 6h after a snooze)
- **Silenced rate ≤ 8%** per-category (stricter than the aggregate ≤ 2 silenced-category threshold because low-mood false-positives burn trust fastest)
- **Zero safety bypasses** — no delivered `.postCheckInAction` nudge whose check-in's notes would NOW trigger the classifier (retrospective audit)

Measure via a new `NudgeMetrics.perRuleSummary(category:)` helper that reads the local `Nudge` table (already persisted with `categoryRaw`). Surface in Settings → Coach → Nudge history filtered by category.

If thresholds miss, tune in this order: bucket definitions (mood/energy cutoffs) → template copy → cooldown → disable.

---

## 8. Implementation checklist (file-by-file)

1. **`AppConstants.swift`** — add:
   - `nudgePostLowMoodCooldownHours = 20`
   - `nudgePostLowMoodMaxMinutesSinceCheckIn = 90`
   - `nudgePostLowMoodMinMinutesSinceCheckIn = 10`
   - `nudgePostLowMoodStreakMin = 3`
   - `nudgePostLowMoodEnabledKey = "coach.nudge.postLowMood.enabled"` (default false — explicit opt-in)
   - `anxiousKeywordList: [String]` (small curated set)

2. **`NudgeTypes.swift`** — add `id: String` to `LastCheckInSnapshot`.

3. **`NudgeEngine.swift`**:
   - New private `fetchLatestCompletedCheckIn() -> CheckInRecord?`
   - Populate `lastCheckIn` in `collectContext()` (currently hardcoded nil)
   - Register `PostLowMoodCheckInRule()` in `rules` array after `WeakDimensionWithOpenWindowRule()`
   - Extend `isRuleInCooldown` — no change needed; generic category cooldown already works
   - Add `isCheckInAlreadyNudged(checkInID:)` helper used by the rule (or expose via a new context field `nudgedCheckInIDs: Set<String>`; prefer the context field for determinism).

4. **`PostLowMoodCheckInRule.swift`** — new file next to `WeakDimensionWithOpenWindowRule.swift`. Implements `NudgeTriggerRule`, id `.postCheckInAction`, deterministic bucket selection, record-scoped dedupe check, defensive crisis re-check, variant rotation by `checkInID.hashValue`.

5. **`NudgeComposer.swift`** — replace `.postCheckInAction` case body with bucket-switched copy family; preserve `SafeResourceCopy` exception unchanged.

6. **`CoachSettingsView.swift`** — add:
   - New toggle row: "Action suggestions after check-ins" → `nudgePostLowMoodEnabledKey`. Off by default. Copy beneath: "When you log a low mood, the coach may suggest a small concrete action. You can silence this anytime."

7. **`Onboarding/`** — optional: add this toggle to the Coach-preferences onboarding step (Step in the 12-step flow that covers coach consent) so first-runs see it without hunting.

8. **Tests** (`MyAIssistantTests/PostLowMoodCheckInRuleTests.swift`):
   - Each bucket fires deterministically
   - Stale check-in (>90 min) doesn't fire
   - Too-recent check-in (<10 min) doesn't fire
   - Record-scoped dedupe prevents re-fire on same check-in ID
   - Opt-out disables rule
   - Notes containing crisis-classifier-positive text returns nil
   - Streak < 3 returns nil

9. **Eval harness** — add 5 golden scenarios (one per bucket) plus 3 negative (stale, opted-out, crisis).

---

## 9. Minimum viable version (2-hour cut)

Cut scope to validate the thesis — **does a fresh-mood-triggered nudge land?**

Ship only:

- `PostLowMoodCheckInRule` with **two buckets** (`low` = mood ≤ 2; `flat` = mood == 3 AND energy ≤ 2). Skip anxious/drained/veryLow.
- Single template per bucket (no variants).
- Action mapping: both buckets → `.createTask` with `"walk-10min"` payload.
- Populate `lastCheckIn` + `id` in `collectContext`.
- Record-scoped dedupe via `triggerContextJSON` contains-check.
- Opt-in toggle in `CoachSettingsView` (default OFF).
- No new eval scenarios — piggyback on existing harness; manual dogfood only.

Defer: anxious keyword matching, focus-timer action, chat-open action, variant rotation, bucket analytics faceting, onboarding integration.

This cut answers: "when the user logs low mood, does receiving a 10-minute walk suggestion 15–60 minutes later feel caring or intrusive?" That's the load-bearing question.

---

## 10. Known risks / edge cases

- **No mood set** — check-in completed with only notes. `context.lastCheckIn.mood == nil` → rule returns nil. Same for `energyLevel == nil`.
- **Check-in during quiet hours** — user logs at 10:30pm. Quiet hours already suppress at `evaluate()` step 6 before the rule runs. On next morning's foreground, freshness gate (90 min) rejects. No nudge. Correct behavior.
- **Rapid-fire check-ins** — user logs twice within 20 min (correction). Latest record wins via sort-by-date-desc. The old record's check-in ID never fires because it was never the "latest" at any evaluation pass. No duplicate.
- **Stale check-in (>24h)** — 90-min freshness gate handles this cleanly.
- **Free tier 5/week check-in cap** — unrelated to this rule. If the user hasn't logged a qualifying check-in, the rule has no data to act on. No special-casing.
- **Check-in during `isWithinSafetyPause`** — entire `evaluate()` short-circuits at step 2. Correct — post-crisis, coach stays silent for 24h.
- **Multi-dimension calendar conflict** — if the user already has a task scheduled in the next 30 min, the "walk" suggestion may clash. Not blocking for v1 (action is a suggestion, user declines). Add a calendar-gap check in a v1.1 iteration.
- **Mood = 3, energy = 3** — no bucket matches. Rule returns nil. Correct — that's "fine."
- **Bucket ordering on simultaneous matches** — the `veryLow > drained > low > anxious > flat` ranking prevents a mood=1+energy=1 record from firing twice under different buckets.
- **Template leaking user notes** — explicitly prohibited; templates use only bucket-derived labels, never `lastCheckIn.notes` content.
