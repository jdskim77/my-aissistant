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

    /// Registered trigger rules, evaluated in array order. Phase 2 ships
    /// `WeakDimensionWithOpenWindowRule` as the sole live rule — additional
    /// rules land only after the per-rule hit-rate gate passes (spec §11).
    /// `private var` (not `let`) so tests can swap in a deterministic rule
    /// set without rebuilding the whole engine.
    private var rules: [NudgeTriggerRule] = [
        WeakDimensionWithOpenWindowRule()
    ]

    private let log = AppLogger.app

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
        // 1. Kill switch
        guard !AppConstants.nudgeEngineKillSwitchEnabled else { return }

        // 2. User-facing toggle (default off — Phase 1 is opt-in even without kill switch)
        guard UserDefaults.standard.bool(forKey: AppConstants.nudgeEnabledKey) else { return }

        // 3. Safety pause — prior crisis match extends a 24h suppression. Fixed
        //    the read side: previously `recordSafetyPause` wrote the timestamp
        //    but nothing consulted it, so the pause was a one-shot guard on the
        //    current call only. Now the pause persists across evaluations.
        if isWithinSafetyPause(at: Date()) { return }

        // 4. Off-frequency short-circuit
        let frequency = NudgeFrequency(
            rawValue: UserDefaults.standard.string(forKey: AppConstants.nudgeFrequencyKey) ?? ""
        ) ?? .balanced
        guard frequency != .off else { return }

        // 5. Quiet hours — same-day suppression
        if isQuietHours(at: Date()) { return }

        // 6. Daily + hourly caps
        guard withinFrequencyCaps(frequency: frequency) else { return }

        // 6. Rule loop — first match wins (one nudge per run, hard cap per §7.1)
        guard !rules.isEmpty else { return }

        let context = collectContext(trigger: trigger)

        for rule in rules {
            // Per-rule cooldown
            guard !isRuleInCooldown(rule) else { continue }

            guard let candidate = rule.evaluate(context: context) else { continue }

            // Per-dimension cooldown (if the candidate is dimension-specific)
            if let dim = candidate.dimension, isDimensionInCooldown(dim) {
                continue
            }

            // 7. Crisis gate — run on any free-text signal the rule captured
            //    (e.g. most recent check-in notes). Conservative: if anything
            //    flags, suppress for 24h.
            let freeTextForSafety = candidate.triggerContext["freeTextSafetySample"] ?? ""
            if !freeTextForSafety.isEmpty {
                let evaluation = crisisClassifier.evaluate(freeTextForSafety)
                if evaluation.isCrisis {
                    log.notice("Nudge suppressed by crisis classifier (matched terms redacted)")
                    recordSafetyPause(until: Date().addingTimeInterval(60 * 60 * 24))
                    return
                }
            }

            // 8. Compose copy + persist + deliver
            let bodyText = await composer.compose(candidate)
            let nudge = persist(candidate: candidate, bodyText: bodyText)
            schedule(nudge: nudge)

            // Hard re-entrancy break: one nudge per run (spec §12 question 5).
            return
        }
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

        return NudgeEvalContext(
            now: now,
            dimensionScores: dimensionScores,
            streak: streak,
            lastCheckIn: nil,                    // unused by the Phase 2 rule
            currentSlotCheckInComplete: false,   // unused by the Phase 2 rule
            calendarGaps: gaps,
            openTaskCountByDimension: openByDim,
            habitConsecutiveMisses: [:],         // unused by the Phase 2 rule
            isAppForeground: trigger == .foreground
        )
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
        let descriptor = FetchDescriptor<Nudge>(
            predicate: #Predicate { nudge in
                nudge.statusRaw == deliveredRaw || nudge.statusRaw == respondedRaw
            }
        )
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        return rows.reduce(0) { acc, nudge in
            guard let delivered = nudge.deliveredAt, delivered >= since else { return acc }
            return acc + 1
        }
    }

    private func isRuleInCooldown(_ rule: NudgeTriggerRule) -> Bool {
        let categoryRaw = rule.id.rawValue
        let cutoff = Date().addingTimeInterval(-rule.cooldown)
        let descriptor = FetchDescriptor<Nudge>(
            predicate: #Predicate { nudge in
                nudge.categoryRaw == categoryRaw && nudge.createdAt >= cutoff
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
