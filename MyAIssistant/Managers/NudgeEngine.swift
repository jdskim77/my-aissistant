import Foundation
import Observation
import SwiftData
import os.log

/// Orchestrates proactive coaching nudges: evaluates trigger rules against a
/// context snapshot, enforces safety gates (kill switch, crisis classifier,
/// user tuning), applies frequency caps / dedupe / quiet hours, composes copy,
/// persists `Nudge` records, and hands delivery to `NotificationManager` or an
/// in-app banner surface.
///
/// **Phase 1 state**: rule set is empty and `nudgeEngineKillSwitchEnabled` is
/// true by default — the engine evaluates nothing and delivers nothing. All
/// gating logic is in place so Phase 2's first rule (`weakDimensionWithOpenWindow`)
/// slots in without any orchestration changes.
///
/// Entry points:
/// - `evaluateOnForeground()` — wire from `MyAIssistantApp` on scenePhase.active
/// - `runScheduledEvaluation()` — wire from `BackgroundTaskManager`'s
///   `nudge-evaluation` BGTask handler
@MainActor
@Observable
final class NudgeEngine {
    private let modelContext: ModelContext
    private let composer: NudgeComposer
    private let crisisClassifier: CrisisClassifier

    // Signal sources — optional for Phase 1 since the rule set is empty. Phase 2+
    // rules read these to build `NudgeEvalContext`.
    var patternEngine: PatternEngine?
    var balanceManager: BalanceManager?
    var taskManager: TaskManager?
    var habitManager: HabitManager?
    var checkInManager: CheckInManager?
    var checkInBehaviorEngine: CheckInBehaviorEngine?

    /// Registered trigger rules, evaluated in array order.
    /// **Order matters**: the first rule whose preconditions match wins
    /// (one nudge per run, spec §12 Q5), so time-sensitive rules come
    /// FIRST. `PostLowMoodCheckInRule` only fires within a 90-minute
    /// window after a fresh check-in; `WeakDimensionWithOpenWindowRule`
    /// can fire any day. If weak-dim were listed first it would always
    /// preempt the post-check-in action, even when the check-in signal
    /// is still fresh and more relevant. Fix for BUG-16.
    /// `private var` (not `let`) so tests can swap in a deterministic
    /// rule set without rebuilding the whole engine.
    private var rules: [NudgeTriggerRule] = [
        PostLowMoodCheckInRule(),
        WindowedHabitRule(),
        WeakDimensionWithOpenWindowRule()
    ]

    private let log = AppLogger.app

    /// Re-entrancy guard. `evaluate()` `await`s the composer, which
    /// suspends the MainActor — a second call (e.g. scheduled BGTask
    /// firing while a foreground evaluate is in-flight) can slip in
    /// during that suspension and persist a concurrent nudge, busting
    /// the min-gap + daily caps. Guard flag keeps only one evaluation
    /// in flight at a time. Fix for Q1-BUG-27.
    private var isEvaluating = false

    init(
        modelContext: ModelContext,
        composer: NudgeComposer,
        crisisClassifier: CrisisClassifier
    ) {
        self.modelContext = modelContext
        self.composer = composer
        self.crisisClassifier = crisisClassifier
    }

    // MARK: - Entry points

    /// Call from `MyAIssistantApp` when the scene becomes active.
    func evaluateOnForeground() async {
        await evaluate(trigger: .foreground)
    }

    /// Call from `BackgroundTaskManager`'s `nudge-evaluation` BGTask handler.
    /// Returns true on successful completion (including "nothing to do"),
    /// false only when evaluation was abandoned mid-flight.
    func runScheduledEvaluation() async -> Bool {
        await evaluate(trigger: .scheduled)
        return true
    }

    enum EvaluationTrigger {
        case foreground
        case scheduled
    }

    // MARK: - Core evaluation

    private func evaluate(trigger: EvaluationTrigger) async {
        // 0. Re-entrancy guard (Q1-BUG-27). Without this, a BGTask-
        //    triggered evaluate() firing while a foreground evaluate()
        //    is mid-await-composer can slip past caps and persist a
        //    second nudge.
        guard !isEvaluating else {
            log.notice("NudgeEngine.evaluate: skipping re-entrant call (trigger=\(String(describing: trigger), privacy: .public))")
            return
        }
        isEvaluating = true
        defer { isEvaluating = false }

        // 1. Kill switch — emergency global off.
        guard !AppConstants.nudgeEngineKillSwitchEnabled else { return }

        // 2. Safety pause — blocks everything (including safety re-scan) for
        //    24h after a crisis flag. Placed before the precheck so we don't
        //    re-emit safety nudges on every foreground inside the cooldown.
        guard !isWithinSafetyPause(at: Date()) else { return }

        // 3. Safety precheck — scans the latest check-in note via the
        //    on-device crisis classifier. Bypasses user toggle and frequency
        //    caps: when a signal matches, routing to resources is the single
        //    job the engine has in that moment. Spec §7.4.
        if await performSafetyPrecheck() { return }

        // 4. User-facing toggle (default off — Phase 1 was opt-in; Phase 2
        //    keeps the toggle so non-safety coaching stays consent-gated).
        guard UserDefaults.standard.bool(forKey: AppConstants.nudgeEnabledKey) else { return }

        // 5. Off-frequency short-circuit.
        let frequency = NudgeFrequency(
            rawValue: UserDefaults.standard.string(forKey: AppConstants.nudgeFrequencyKey) ?? ""
        ) ?? .balanced
        guard frequency != .off else { return }

        // 6. Quiet hours — same-day suppression.
        if isQuietHours(at: Date()) { return }

        // 7. Daily + hourly caps.
        guard withinFrequencyCaps(frequency: frequency) else { return }

        // 8. Rule loop — first match wins (one nudge per run, hard cap
        //    per §7.1). Skips rules whose category is on the user's
        //    silenced list (Q1-BUG-29 — previously the UI toggle set
        //    the key but the engine never consulted it).
        guard !rules.isEmpty else { return }

        let silencedCategories = readSilencedCategories()
        let context = collectContext(trigger: trigger)

        for rule in rules {
            // Silenced category → user explicitly opted out of this
            // rule's output. Skip before rule.evaluate so we don't
            // even build a candidate.
            if silencedCategories.contains(rule.id.rawValue) { continue }

            guard !isRuleInCooldown(rule) else { continue }

            guard let candidate = rule.evaluate(context: context) else { continue }

            if let dim = candidate.dimension, isDimensionInCooldown(dim) {
                continue
            }

            let bodyText = await composer.compose(candidate)
            let nudge = persist(candidate: candidate, bodyText: bodyText)
            schedule(nudge: nudge)

            // Hard re-entrancy break: one nudge per run (spec §12 Q5).
            return
        }
    }

    /// Parses the comma-separated silenced-categories string stored in
    /// UserDefaults by CoachSettingsView into a raw-value set. The UI
    /// lets the user toggle categories off; the engine must honor it.
    /// Fix for Q1-BUG-29.
    private func readSilencedCategories() -> Set<String> {
        let raw = UserDefaults.standard.string(forKey: AppConstants.nudgeSilencedCategoriesKey) ?? ""
        guard !raw.isEmpty else { return [] }
        return Set(raw.split(separator: ",").map(String.init))
    }

    // MARK: - Safety precheck

    /// Runs the on-device crisis classifier against the most recent check-in
    /// note. Returns `true` when the classifier flagged — the caller halts
    /// further evaluation. Side effects on a flag: emits a safety-route
    /// `Nudge` record and records a 24h pause so subsequent evaluations
    /// short-circuit at step 2.
    ///
    /// Bypasses user toggle, frequency caps, and quiet hours on purpose:
    /// when someone writes something that matches a safety term, the app's
    /// single responsibility in that moment is offering human help. Copy is
    /// hardcoded in `SafeResourceCopy` — never LLM-generated, never silenced
    /// via the Coach Settings category list.
    private func performSafetyPrecheck() async -> Bool {
        guard let sample = latestFreeTextSafetySample(), !sample.text.isEmpty else {
            return false
        }
        let text = sample.text
        // Per-note dedupe (Q1-BUG-26). Without this, after the 24h
        // safety pause lifts, the same historical flagged note would
        // re-trigger the classifier, emit a second safety nudge, and
        // start another 24h pause — infinite loop for any user whose
        // latest check-in has ever matched.
        let fingerprint = Self.safetyNoteFingerprint(recordID: sample.recordID, text: text)
        if hasEmittedSafetyForFingerprint(fingerprint) { return false }

        let evaluation = crisisClassifier.evaluate(text)
        guard evaluation.isCrisis else { return false }

        log.notice("Crisis classifier flagged — emitting safety-route nudge and suppressing normal nudges for 24h")
        recordSafetyPause(until: Date().addingTimeInterval(60 * 60 * 24))
        recordSafetyFingerprint(fingerprint)

        let candidate = NudgeCandidate(
            category: .safetyRoute,
            dimension: nil,
            suggestedAction: .none,
            actionPayload: SafeResourceCopy.actionURL().absoluteString,
            templateParams: [:],
            triggerContext: [
                SafeResourceCopy.triggerContextKey: "true",
                "matchCount": String(evaluation.matchedTerms.count),
                "safetyFingerprint": fingerprint
            ]
        )
        let bodyText = await composer.compose(candidate)
        let nudge = persist(candidate: candidate, bodyText: bodyText)
        schedule(nudge: nudge)
        return true
    }

    /// Fetches the most recent completed check-in with a meaningful
    /// (non-whitespace) note. Returns record ID alongside the text so
    /// the precheck can dedupe per-record. Phase 2 scope: check-in
    /// notes only. Phase 3+ may also sample chat messages per §7.4.
    /// Fix for Q1-BUG-32 (prior implementation returned whitespace-only
    /// notes which passed `!isEmpty` but meant nothing).
    private func latestFreeTextSafetySample() -> (recordID: String, text: String)? {
        var descriptor = FetchDescriptor<CheckInRecord>(
            predicate: #Predicate { $0.completed == true },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 5
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        for row in rows {
            guard let raw = row.notes else { continue }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            return (row.id, trimmed)
        }
        return nil
    }

    // MARK: - Safety-note fingerprint (dedupe)

    private var safetyFingerprintsKey: String { "coach.nudge.safetyFingerprints" }

    /// A stable fingerprint per (checkInRecord, note) pair so the
    /// precheck doesn't re-fire on the same historical note after
    /// the 24h pause lifts. Using record-id + a hash of the trimmed
    /// text means an edit to the note (different fingerprint) is
    /// treated as a fresh scan — which is the correct behavior, not
    /// a bug.
    static func safetyNoteFingerprint(recordID: String, text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(recordID):\(trimmed.hashValue)"
    }

    private func hasEmittedSafetyForFingerprint(_ fp: String) -> Bool {
        let raw = UserDefaults.standard.string(forKey: safetyFingerprintsKey) ?? ""
        return raw.split(separator: "|").contains(Substring(fp))
    }

    private func recordSafetyFingerprint(_ fp: String) {
        var fps = (UserDefaults.standard.string(forKey: safetyFingerprintsKey) ?? "")
            .split(separator: "|").map(String.init)
        fps.append(fp)
        // Cap the list to the last ~200 fingerprints so the key doesn't
        // grow without bound across months of use.
        if fps.count > 200 { fps = Array(fps.suffix(200)) }
        UserDefaults.standard.set(fps.joined(separator: "|"), forKey: safetyFingerprintsKey)
    }

    // MARK: - Context collection
    //
    // Phase 1 returns a minimal valid context. Phase 2 rules pull richer signals
    // from the injected managers.

    private func collectContext(trigger: EvaluationTrigger) -> NudgeEvalContext {
        let now = Date()
        let streak = patternEngine?.currentStreak() ?? 0

        // Dimension scores. `BalanceManager.weeklyScores()` returns a composite
        // on a 0-10 scale; rules (and the context API) operate on 0-100 for
        // readability and thresholding. Multiply + round to Int. Dimensions
        // with no data are simply absent — rules see an empty dictionary and
        // short-circuit rather than firing against phantom zeros.
        let scores = balanceManager?.weeklyScores() ?? [:]
        let dimensionScores = scores.reduce(into: [LifeDimension: Int]()) { acc, pair in
            acc[pair.key] = Int(round(pair.value * 10.0))
        }

        // Open tasks today by dimension. "Open" = not yet done. A
        // multi-dimension task (e.g., "family walk" = Physical + Emotional)
        // counts once per tagged dimension — the rule treats any such task
        // as coverage for both quadrants.
        let todaysTasks = taskManager?.todayTasks() ?? []
        let openTasks = todaysTasks.filter { !$0.done }
        var openByDim: [LifeDimension: Int] = [:]
        for task in openTasks {
            for dim in task.dimensions where dim.isScored {
                openByDim[dim, default: 0] += 1
            }
        }

        // Calendar gaps in the next 4 hours. Derived from today's timed
        // commitments (user tasks + calendar-imported events, both live as
        // `TaskItem`). Unknown durations default to 30 min — conservative
        // on purpose: better to understate the open window than to nudge a
        // user who's actually busy.
        let windowEnd = now.addingTimeInterval(4 * 3600)
        let upcoming = todaysTasks
            .filter { $0.date > now && $0.date < windowEnd }
            .sorted { $0.date < $1.date }

        var gaps: [CalendarGap] = []
        var cursor = now
        for task in upcoming {
            if task.date > cursor {
                gaps.append(CalendarGap(start: cursor, end: task.date))
            }
            cursor = task.date.addingTimeInterval(30 * 60)
        }
        if cursor < windowEnd {
            gaps.append(CalendarGap(start: cursor, end: windowEnd))
        }

        // Populate the latest completed check-in so post-check-in rules
        // can read mood/energy state. Also populate a short list of
        // recent check-ins so rules that want to react to a specific
        // state (e.g. PostLowMoodCheckInRule) can find the newest
        // qualifying record — not just the absolute latest. Fix for
        // BUG-14. Rules MUST NOT re-query SwiftData themselves — all
        // signal reads go through the context for eval-harness
        // determinism.
        let recentRecords = fetchRecentCompletedCheckIns(limit: 5)
        let recentSnapshots = recentRecords.map { record in
            LastCheckInSnapshot(
                id: record.id,
                date: record.date,
                mood: record.mood,
                energyLevel: record.energyLevel,
                notes: record.notes
            )
        }
        let snapshot = recentSnapshots.first

        // Set of check-in IDs that have already been nudged. Populated
        // by scanning triggerContextJSON for the `checkInID` key on any
        // non-pending Nudge — record-scoped dedupe for
        // PostLowMoodCheckInRule (spec §2).
        let nudgedIDs = fetchNudgedCheckInIDs()

        // Windowed habits that are currently open for a "still open"
        // nudge: timeWindow set, non-archived, in-window right now AND
        // past the window's midpoint AND not completed today. Filter in
        // two stages — `#Predicate` narrows to non-archived + windowed
        // at the DB layer, then in-memory does the clock-dependent
        // checks (which can't live in a predicate and would be invalid
        // to cache at the DB level anyway).
        let activeWindowedHabits = fetchActiveWindowedHabits(now: now)

        // HabitIDs already nudged today via `windowedHabit`. Record-scoped
        // dedupe so the same habit isn't nudged twice the same day even
        // after the category cooldown expires. Scoped to today only — the
        // same habit CAN be nudged again tomorrow if still open.
        let nudgedHabitIDsToday = fetchNudgedHabitIDsToday(now: now)

        return NudgeEvalContext(
            now: now,
            dimensionScores: dimensionScores,
            streak: streak,
            lastCheckIn: snapshot,
            currentSlotCheckInComplete: false,   // unused by current rules
            calendarGaps: gaps,
            openTaskCountByDimension: openByDim,
            habitConsecutiveMisses: [:],         // unused by current rules
            activeWindowedHabits: activeWindowedHabits,
            nudgedHabitIDsToday: nudgedHabitIDsToday,
            nudgedCheckInIDs: nudgedIDs,
            recentCheckIns: recentSnapshots,
            isAppForeground: trigger == .foreground
        )
    }

    /// Fetch non-archived, windowed habits and filter them down to the
    /// subset that's currently eligible for a windowed-habit nudge:
    /// in-window right now, past the window's midpoint, not completed
    /// today. Returned as `WindowedHabitSnapshot` values (no live model
    /// references) so the context stays `Sendable` and rule code can
    /// never mutate the store.
    private func fetchActiveWindowedHabits(now: Date) -> [WindowedHabitSnapshot] {
        let descriptor = FetchDescriptor<HabitItem>(
            predicate: #Predicate { $0.archivedAt == nil && $0.timeWindowRaw != nil }
        )
        let habits = (try? modelContext.fetch(descriptor)) ?? []
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)

        return habits.compactMap { habit -> WindowedHabitSnapshot? in
            guard let window = habit.timeWindow else { return nil }
            guard habit.windowState(at: now, calendar: calendar) == .inWindow else { return nil }
            guard window.isPastMidpoint(hour: hour) else { return nil }
            guard !habit.isCompletedOn(now) else { return nil }
            return WindowedHabitSnapshot(
                habitID: habit.id,
                title: habit.title,
                window: window,
                currentStreak: habit.currentStreak()
            )
        }
    }

    /// Recent completed `CheckInRecord` rows, newest first. Bounded by
    /// `limit` (typically 5) — cost is trivial. Rules that only care
    /// about the single most recent can read `recentSnapshots.first`;
    /// rules that need to scan a window (e.g.
    /// `PostLowMoodCheckInRule` looking for the newest check-in
    /// inside the 90-min freshness window that also matches a mood
    /// bucket) iterate. Fix for BUG-14.
    private func fetchRecentCompletedCheckIns(limit: Int) -> [CheckInRecord] {
        var descriptor = FetchDescriptor<CheckInRecord>(
            predicate: #Predicate { $0.completed == true },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Returns the set of `CheckInRecord.id` values referenced by any
    /// delivered or responded `Nudge`'s `triggerContextJSON.checkInID`.
    /// Record-scoped dedupe for `PostLowMoodCheckInRule`. Parsing is
    /// bounded by the daily cap × history window — trivial cost.
    ///
    /// Date-bounded to the last 7 days since the post-check-in
    /// freshness window is 90 min. Any check-in older than a week is
    /// already outside the rule's reach; including those rows would be
    /// a growing-over-time linear scan with no benefit. Fix for BUG-15.
    /// Returns the set of `HabitItem.id` values referenced by any
    /// `windowedHabit` nudge created today (user's current calendar day,
    /// in the device timezone). Populated once per evaluation pass so
    /// `WindowedHabitRule` stays deterministic.
    ///
    /// Scoped to calendar day (not a rolling 24h) because "one per day"
    /// is the user-facing promise — a habit nudged at 11pm yesterday
    /// shouldn't block a legitimate morning nudge 8 hours later.
    /// Includes pending/delivered/responded alike; a failed-to-deliver
    /// pending nudge still counts because the rule fired on it.
    private func fetchNudgedHabitIDsToday(now: Date) -> Set<String> {
        let categoryRaw = NudgeCategory.windowedHabit.rawValue
        let startOfToday = Calendar.current.startOfDay(for: now)
        var descriptor = FetchDescriptor<Nudge>(
            predicate: #Predicate { nudge in
                nudge.categoryRaw == categoryRaw &&
                nudge.createdAt >= startOfToday
            }
        )
        // Daily cap is 2 — 50 is comfortably over-provisioned.
        descriptor.fetchLimit = 50
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        var ids = Set<String>()
        for nudge in rows {
            guard let data = nudge.triggerContextJSON.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let habitID = dict["habitID"] as? String else { continue }
            ids.insert(habitID)
        }
        return ids
    }

    private func fetchNudgedCheckInIDs() -> Set<String> {
        let categoryRaw = NudgeCategory.postCheckInAction.rawValue
        let since = Date().addingTimeInterval(-7 * 24 * 3600)
        // Include pending + delivered + responded — any nudge row for
        // the post-check-in category consumes the record. Status
        // filtering would let a `pending` row (scheduling failure)
        // slip through and allow a second fire on the same check-in.
        // Fix for Q1-BUG-35.
        var descriptor = FetchDescriptor<Nudge>(
            predicate: #Predicate { nudge in
                nudge.categoryRaw == categoryRaw &&
                nudge.createdAt >= since
            }
        )
        descriptor.fetchLimit = 200
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        var ids = Set<String>()
        for nudge in rows {
            guard let data = nudge.triggerContextJSON.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let checkInID = dict["checkInID"] as? String else { continue }
            ids.insert(checkInID)
        }
        return ids
    }

    // MARK: - Gating helpers

    /// Returns true if the current time falls inside the user's configured
    /// quiet-hours window. Hours are read via `object(forKey:) as? Int` so that
    /// "set to 0" (midnight) is distinguishable from "never set" — the previous
    /// `UserDefaults.integer(forKey:)` path collapsed both to 0 and silently
    /// substituted the default.
    ///
    /// Hours are clamped to `0...23`. When `startHour == endHour` the window is
    /// treated as "no quiet hours" (current default behavior) — users who want
    /// to stop all nudges should use the master toggle in Coach Settings.
    private func isQuietHours(at date: Date) -> Bool {
        let hour = Calendar.current.component(.hour, from: date)
        let startHour = readHourSetting(
            key: AppConstants.nudgeQuietHoursStartKey,
            default: AppConstants.nudgeQuietHoursStartHour
        )
        let endHour = readHourSetting(
            key: AppConstants.nudgeQuietHoursEndKey,
            default: AppConstants.nudgeQuietHoursEndHour
        )

        // startHour == endHour → no quiet hours. (BUG-06)
        if startHour == endHour { return false }

        // Quiet window wraps midnight (e.g. 21..23 + 0..8).
        if startHour > endHour {
            return hour >= startHour || hour < endHour
        } else {
            return hour >= startHour && hour < endHour
        }
    }

    private func readHourSetting(key: String, default fallback: Int) -> Int {
        let defaults = UserDefaults.standard
        let raw = defaults.object(forKey: key) as? Int ?? fallback
        return max(0, min(23, raw))
    }

    /// Enforces the per-day cap and the minimum-gap-between-nudges window. The
    /// previous implementation hard-coded a 1-hour window while comparing count
    /// against `max(1, minHours)` — if `nudgeMinHoursBetween` was raised above 1,
    /// the enforcement silently inverted. Now the window itself scales with
    /// the configured minimum gap. (BUG-03)
    private func withinFrequencyCaps(frequency: NudgeFrequency) -> Bool {
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)

        // Daily cap.
        let deliveredToday = fetchDeliveredCount(since: startOfDay)
        guard deliveredToday < frequency.dailyCap else { return false }

        // Minimum gap: no deliveries inside the last `minHours` window.
        let minHours = max(1, AppConstants.nudgeMinHoursBetween)
        let windowStart = now.addingTimeInterval(-Double(minHours) * 60 * 60)
        let deliveredInWindow = fetchDeliveredCount(since: windowStart)
        guard deliveredInWindow < 1 else { return false }

        return true
    }

    /// Counts delivered/responded nudges whose *delivery* timestamp falls at or
    /// after `since`. Previously counted on `createdAt`, which would include
    /// pending nudges that never actually reached the user (e.g. Phase 2
    /// scheduling failures) — inflating the cap and silently starving future
    /// runs. (BUG-08)
    ///
    /// `#Predicate` can't express optional-aware comparisons cleanly, so we
    /// filter by status in the query (status is always set when `deliveredAt`
    /// is) and do the timestamp filter in Swift. Counts are bounded by the
    /// daily cap (≤ 2), so the in-memory pass is trivial.
    private func fetchDeliveredCount(since: Date) -> Int {
        let deliveredRaw = NudgeStatus.delivered.rawValue
        let respondedRaw = NudgeStatus.responded.rawValue
        let safetyRaw = NudgeCategory.safetyRoute.rawValue
        // Predicate pre-filters by createdAt as an index-friendly lower
        // bound — deliveredAt is always ≥ createdAt, so rows with
        // createdAt < since can never pass the in-memory deliveredAt
        // check. Without this pre-filter we'd scan the full nudge table
        // to count a window bounded by the daily cap. Fix for BUG-17.
        //
        // Excludes safetyRoute nudges per §7.4 — safety deliveries
        // bypass caps so they don't count against the user's daily
        // allotment. Fix for Q1-BUG-33.
        var descriptor = FetchDescriptor<Nudge>(
            predicate: #Predicate { nudge in
                (nudge.statusRaw == deliveredRaw || nudge.statusRaw == respondedRaw) &&
                nudge.categoryRaw != safetyRaw &&
                nudge.createdAt >= since
            }
        )
        descriptor.fetchLimit = 100
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        return rows.reduce(0) { acc, nudge in
            guard let delivered = nudge.deliveredAt, delivered >= since else { return acc }
            return acc + 1
        }
    }

    private func isRuleInCooldown(_ rule: NudgeTriggerRule) -> Bool {
        let categoryRaw = rule.id.rawValue
        let deliveredRaw = NudgeStatus.delivered.rawValue
        let respondedRaw = NudgeStatus.responded.rawValue
        let cutoff = Date().addingTimeInterval(-rule.cooldown)
        // Only delivered/responded nudges consume a cooldown slot —
        // a `pending` nudge that never actually reached the user
        // (e.g. a scheduling failure) should not permanently block
        // the rule from firing again. Fix for Q1-BUG-28.
        let descriptor = FetchDescriptor<Nudge>(
            predicate: #Predicate { nudge in
                nudge.categoryRaw == categoryRaw &&
                (nudge.statusRaw == deliveredRaw || nudge.statusRaw == respondedRaw) &&
                nudge.createdAt >= cutoff
            }
        )
        let count = (try? modelContext.fetchCount(descriptor)) ?? 0
        return count > 0
    }

    private func isDimensionInCooldown(_ dimension: LifeDimension) -> Bool {
        let raw = dimension.rawValue
        let cutoff = Date().addingTimeInterval(-Double(AppConstants.nudgeMaxPerDimensionHours) * 3600)
        let descriptor = FetchDescriptor<Nudge>(
            predicate: #Predicate { nudge in
                nudge.dimensionRaw == raw && nudge.createdAt >= cutoff
            }
        )
        let count = (try? modelContext.fetchCount(descriptor)) ?? 0
        return count > 0
    }

    // MARK: - Persistence + delivery

    private func persist(candidate: NudgeCandidate, bodyText: String) -> Nudge {
        let contextJSON: String = {
            guard let data = try? JSONSerialization.data(withJSONObject: candidate.triggerContext, options: []) else {
                return "{}"
            }
            return String(data: data, encoding: .utf8) ?? "{}"
        }()

        let nudge = Nudge(
            category: candidate.category,
            triggerContextJSON: contextJSON,
            bodyText: bodyText,
            action: candidate.suggestedAction,
            suggestedActionPayload: candidate.actionPayload,
            dimension: candidate.dimension,
            status: .pending
        )
        modelContext.insert(nudge)
        modelContext.safeSave()
        return nudge
    }

    private func schedule(nudge: Nudge) {
        // Phase 1: this is a no-op. Phase 2 wires NotificationManager to
        // actually schedule a UNNotificationRequest with the inline actions
        // (NUDGE_ACCEPT / NUDGE_DISMISS / NUDGE_SNOOZE / NUDGE_SILENCE).
        //
        // For now mark as delivered immediately — with the rule set empty
        // this code path is unreachable anyway, but marking keeps caps
        // accurate if Phase 2 forgets to update status.
        nudge.status = .delivered
        nudge.deliveredAt = Date()
        modelContext.safeSave()
    }

    // MARK: - Safety pause

    private var safetyPauseUntilKey: String { "coach.nudge.safetyPauseUntil" }

    private func recordSafetyPause(until: Date) {
        UserDefaults.standard.set(until.timeIntervalSince1970, forKey: safetyPauseUntilKey)
    }

    /// True while an active safety pause is in effect (set when the crisis
    /// classifier flagged free-text input). Reads the timestamp written by
    /// `recordSafetyPause`; returns false once the pause has elapsed.
    /// Paired fix for BUG-02.
    private func isWithinSafetyPause(at date: Date) -> Bool {
        let ts = UserDefaults.standard.double(forKey: safetyPauseUntilKey)
        guard ts > 0 else { return false }
        return date.timeIntervalSince1970 < ts
    }

    // MARK: - Response recording
    //
    // Phase 2 wires `NotificationDelegate` to call this when the user taps an
    // inline action. Phase 1 defines the signature so the persistence round-trip
    // is present for unit tests and eval harness fixtures.

    func recordResponse(nudgeID: String, response: UserNudgeResponse) {
        let descriptor = FetchDescriptor<Nudge>(
            predicate: #Predicate { $0.id == nudgeID }
        )
        do {
            let rows = try modelContext.fetch(descriptor)
            guard let nudge = rows.first else {
                log.warning("recordResponse: no Nudge found for id=\(nudgeID, privacy: .public)")
                return
            }
            nudge.userResponseRaw = response.rawValue
            nudge.respondedAt = Date()
            nudge.statusRaw = NudgeStatus.responded.rawValue
            modelContext.safeSave()
        } catch {
            log.error("recordResponse: fetch failed for id=\(nudgeID, privacy: .public) — \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - User-facing frequency setting

enum NudgeFrequency: String, CaseIterable {
    case gentle   // 1/day cap
    case balanced // 2/day cap (default)
    case off      // no nudges

    var dailyCap: Int {
        switch self {
        case .gentle: return 1
        case .balanced: return AppConstants.nudgeMaxPerDay
        case .off: return 0
        }
    }

    var label: String {
        switch self {
        case .gentle: return "Gentle"
        case .balanced: return "Balanced"
        case .off: return "Off"
        }
    }
}
