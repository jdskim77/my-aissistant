import Foundation

// MARK: - Nudge Candidate
//
// A trigger rule's output when it fires. Consumed by `NudgeComposer` to
// produce the visible body text and by `NudgeEngine` to construct the
// persisted `Nudge` record. Rules emit candidates; the engine decides
// whether to deliver them (caps, dedupe, quiet-hours, crisis gate).

/// A proposed nudge from a triggered rule, not yet composed or delivered.
struct NudgeCandidate: Sendable {
    let category: NudgeCategory
    let dimension: LifeDimension?
    let suggestedAction: NudgeAction
    let actionPayload: String?
    /// Values extracted by the rule for template interpolation (Path A) and
    /// for the LLM volatile block (Path B, Phase 3).
    let templateParams: [String: String]
    /// Signal snapshot for audit / eval. Serialized into
    /// `Nudge.triggerContextJSON` on persistence.
    let triggerContext: [String: String]

    init(
        category: NudgeCategory,
        dimension: LifeDimension? = nil,
        suggestedAction: NudgeAction = .none,
        actionPayload: String? = nil,
        templateParams: [String: String] = [:],
        triggerContext: [String: String] = [:]
    ) {
        self.category = category
        self.dimension = dimension
        self.suggestedAction = suggestedAction
        self.actionPayload = actionPayload
        self.templateParams = templateParams
        self.triggerContext = triggerContext
    }
}

// MARK: - Nudge Eval Context
//
// Snapshot of signal-source state at a single evaluation pass. Rules read
// this and return at most one `NudgeCandidate`. Deterministic by design —
// same context → same candidate — so the eval harness can assert fire
// behavior without mocking every manager.

/// Read-only snapshot of the app's coach-relevant state for one evaluation pass.
/// Populated by `NudgeEngine.collectContext()`; passed into every rule.
struct NudgeEvalContext: Sendable {
    let now: Date

    /// 0–100 rolling score per scored dimension (Physical / Mental / Emotional / Spiritual).
    let dimensionScores: [LifeDimension: Int]

    /// Current ritual streak count.
    let streak: Int

    /// Last completed check-in (mood, energy, time), if any.
    let lastCheckIn: LastCheckInSnapshot?

    /// Count of completed check-ins for the current slot today (0 or 1 typically).
    let currentSlotCheckInComplete: Bool

    /// Today's open calendar windows — gaps between committed events.
    let calendarGaps: [CalendarGap]

    /// Today's open task count by dimension (lets rules detect "dimension neglected today").
    let openTaskCountByDimension: [LifeDimension: Int]

    /// Consecutive missed days by habit id (for habit-slip detection).
    let habitConsecutiveMisses: [String: Int]

    /// Uncompleted habits currently inside their time window AND past the
    /// window's midpoint — i.e. ready for a "still open" nudge. Populated
    /// once per evaluation pass so rules stay deterministic (no `Date()`
    /// calls in rule code). Consumed by `WindowedHabitRule`.
    let activeWindowedHabits: [WindowedHabitSnapshot]

    /// `HabitItem.id` values that have already been nudged today via a
    /// `windowedHabit` nudge. Enforces per-habit-per-day dedupe so the
    /// same habit is never nudged twice the same day, even after the
    /// category cooldown expires. Populated once per evaluation pass.
    let nudgedHabitIDsToday: Set<String>

    /// Check-in record IDs for which a nudge has already been emitted.
    /// Used by `PostLowMoodCheckInRule` for record-scoped dedupe so the
    /// SAME check-in doesn't fire a second nudge after a user dismiss.
    /// Populated once per `collectContext` pass — keeps rules pure.
    let nudgedCheckInIDs: Set<String>

    /// Last few completed check-ins, most-recent first. Rules that want
    /// to react to a specific state (e.g., `PostLowMoodCheckInRule`
    /// looking for a low mood inside a 90-min freshness window) scan
    /// this list to find the newest record that matches their bucket
    /// criteria. Fix for BUG-14 — previously the single `lastCheckIn`
    /// would hide an older qualifying record behind a more-recent
    /// neutral one. Capped at 5 entries by NudgeEngine.collectContext.
    let recentCheckIns: [LastCheckInSnapshot]

    /// Whether the user is currently in the app (affects channel choice downstream).
    let isAppForeground: Bool
}

/// Summary of the most recent completed check-in. `nil` when no check-ins exist.
/// `id` is the `CheckInRecord.id` — rules that want per-record dedupe (e.g.
/// `PostLowMoodCheckInRule`) stamp it into `triggerContext` so the engine
/// can skip re-firing against the same record after a dismiss.
struct LastCheckInSnapshot: Sendable {
    let id: String
    let date: Date
    let mood: Int?         // 1–5
    let energyLevel: Int?  // 1–5
    let notes: String?
}

/// An open window on the user's calendar today.
struct CalendarGap: Sendable {
    let start: Date
    let end: Date
    var minutes: Int { max(0, Int(end.timeIntervalSince(start) / 60)) }
}

/// A habit that's currently in its time-window, past the window's
/// midpoint, and not yet completed today. Passed by reference to
/// rules via `NudgeEvalContext.activeWindowedHabits`; stamped into
/// `Nudge.suggestedActionPayload` so the "Do now" / "Skip today"
/// actions can resolve back to the habit record.
struct WindowedHabitSnapshot: Sendable {
    let habitID: String
    let title: String
    let window: HabitTimeWindow
    /// Current streak length — used by the rule's tie-break when
    /// multiple windowed habits are active simultaneously (highest
    /// streak-at-risk wins). Snapshot at evaluation time; not a
    /// live reference.
    let currentStreak: Int
}

// MARK: - Trigger Rule Protocol
//
// Every rule is a pure function over `NudgeEvalContext` returning an
// optional `NudgeCandidate`. Stateless by convention — all per-rule
// state (cooldowns, last-fire timestamps) is owned by `NudgeEngine`.

/// A single trigger rule. Same context → same candidate. Rules are registered
/// with `NudgeEngine.rules`; adding a new category = implementing this
/// protocol and appending to the engine's rule list.
protocol NudgeTriggerRule: Sendable {
    /// Identifies both the rule and the resulting `Nudge.category`. One rule
    /// per category in v1.
    var id: NudgeCategory { get }

    /// Minimum time between successive firings of this rule.
    var cooldown: TimeInterval { get }

    /// Evaluate a snapshot; return a candidate if the rule should fire.
    func evaluate(context: NudgeEvalContext) -> NudgeCandidate?
}
