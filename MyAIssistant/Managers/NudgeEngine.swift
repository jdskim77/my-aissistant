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

    /// Registered trigger rules, evaluated in array order. Phase 1 is empty.
    /// Phase 2 appends `WeakDimensionWithOpenWindowRule()`.
    private var rules: [NudgeTriggerRule] = []

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

        // 3. Off-frequency short-circuit
        let frequency = NudgeFrequency(
            rawValue: UserDefaults.standard.string(forKey: AppConstants.nudgeFrequencyKey) ?? ""
        ) ?? .balanced
        guard frequency != .off else { return }

        // 4. Quiet hours — same-day suppression
        if isQuietHours(at: Date()) { return }

        // 5. Daily + hourly caps
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
        // Phase 1: rule set is empty, so the context is never read. Return an
        // empty snapshot. Phase 2 (`WeakDimensionWithOpenWindowRule`) will fill
        // in `dimensionScores` from `BalanceManager.weeklyScores()`, `streak`
        // from `PatternEngine.currentStreak()`, `calendarGaps` from
        // `CalendarSyncManager`, and `openTaskCountByDimension` from
        // `TaskManager`. Each rule pulls only what it needs, so we avoid a
        // giant always-on snapshot.
        let streak = patternEngine?.currentStreak() ?? 0
        return NudgeEvalContext(
            now: Date(),
            dimensionScores: [:],
            streak: streak,
            lastCheckIn: nil,
            currentSlotCheckInComplete: false,
            calendarGaps: [],
            openTaskCountByDimension: [:],
            habitConsecutiveMisses: [:],
            isAppForeground: trigger == .foreground
        )
    }

    // MARK: - Gating helpers

    private func isQuietHours(at date: Date) -> Bool {
        let hour = Calendar.current.component(.hour, from: date)
        let start = UserDefaults.standard.integer(forKey: AppConstants.nudgeQuietHoursStartKey)
        let end = UserDefaults.standard.integer(forKey: AppConstants.nudgeQuietHoursEndKey)
        let startHour = start > 0 ? start : AppConstants.nudgeQuietHoursStartHour
        let endHour = end > 0 ? end : AppConstants.nudgeQuietHoursEndHour
        // Quiet window wraps midnight (e.g. 21..23 + 0..8).
        if startHour > endHour {
            return hour >= startHour || hour < endHour
        } else {
            return hour >= startHour && hour < endHour
        }
    }

    private func withinFrequencyCaps(frequency: NudgeFrequency) -> Bool {
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let hourAgo = now.addingTimeInterval(-60 * 60)

        // Count delivered nudges today
        let deliveredToday = fetchDeliveredCount(since: startOfDay)
        let cap = frequency.dailyCap
        guard deliveredToday < cap else { return false }

        // Count delivered within the last hour
        let deliveredInHour = fetchDeliveredCount(since: hourAgo)
        let minHours = AppConstants.nudgeMinHoursBetween
        guard deliveredInHour < max(1, minHours) else { return false }

        return true
    }

    private func fetchDeliveredCount(since: Date) -> Int {
        let deliveredRaw = NudgeStatus.delivered.rawValue
        let respondedRaw = NudgeStatus.responded.rawValue
        let descriptor = FetchDescriptor<Nudge>(
            predicate: #Predicate { nudge in
                (nudge.statusRaw == deliveredRaw || nudge.statusRaw == respondedRaw)
                    && nudge.createdAt >= since
            }
        )
        return (try? modelContext.fetchCount(descriptor)) ?? 0
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

    // MARK: - Response recording
    //
    // Phase 2 wires `NotificationDelegate` to call this when the user taps an
    // inline action. Phase 1 defines the signature so the persistence round-trip
    // is present for unit tests and eval harness fixtures.

    func recordResponse(nudgeID: String, response: UserNudgeResponse) {
        let descriptor = FetchDescriptor<Nudge>(
            predicate: #Predicate { $0.id == nudgeID }
        )
        guard let nudge = try? modelContext.fetch(descriptor).first else { return }
        nudge.userResponseRaw = response.rawValue
        nudge.respondedAt = Date()
        nudge.statusRaw = NudgeStatus.responded.rawValue
        modelContext.safeSave()
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
