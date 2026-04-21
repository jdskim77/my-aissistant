import Foundation

/// Fires when the user's weakest scored dimension has been quiet for the
/// week AND there's a meaningful open window in the next few hours AND no
/// existing task today already covers that dimension.
///
/// Phase 2 ships with conservative thresholds because external testers join
/// from week two. Tunable via `AppConstants`:
///
/// - Weakest dimension must be in the **bottom quintile** (score ≤ 20 on a
///   0–100 scale). Higher-than-that weakness isn't weak enough to justify
///   interrupting the user.
/// - **14-day baseline** required — the rule returns `nil` when the ritual
///   streak is too short for the weekly score to mean anything. New users
///   shouldn't see "body is quiet" nudges on day 3.
/// - Open window must be **≥ 30 min** inside the next 4 hours — enough time
///   for a real act, not a manufactured break.
/// - Per-dimension cooldown **96h** (in `AppConstants.nudgeWeakDimensionCooldownHours`) —
///   if a dimension has been nudged recently, let it breathe before the next
///   one from the same quadrant.
///
/// Deterministic by design: same `NudgeEvalContext` always produces the same
/// candidate. The eval harness relies on this — do not introduce randomness.
/// Spec: §5 · rollout §11 Phase 2.
struct WeakDimensionWithOpenWindowRule: NudgeTriggerRule {
    let id: NudgeCategory = .weakDimension

    var cooldown: TimeInterval {
        Double(AppConstants.nudgeWeakDimensionCooldownHours) * 3600
    }

    func evaluate(context: NudgeEvalContext) -> NudgeCandidate? {
        // 1. Baseline gate. Without enough history the "weakest" label is
        //    noise-on-noise — and framing noise as a deficiency erodes trust.
        guard context.streak >= AppConstants.nudgeBaselineMinDays else { return nil }

        // 2. We need at least one scored dimension to compare against.
        guard !context.dimensionScores.isEmpty else { return nil }

        // 3. Find the weakest dimension. Ties broken by `LifeDimension.sortOrder`
        //    for determinism — the eval harness expects reproducible results
        //    across equal scores.
        let weakest = context.dimensionScores.min { a, b in
            if a.value != b.value { return a.value < b.value }
            return a.key.sortOrder < b.key.sortOrder
        }
        guard let (dimension, score) = weakest else { return nil }

        // 4. Bottom-quintile gate — only truly low scores fire.
        guard score <= AppConstants.nudgeWeakDimensionQuintileCeiling else {
            return nil
        }

        // 5. Already attending this dimension today? The point of the nudge is
        //    to surface an unattended weakness, not to duplicate plans.
        let openCount = context.openTaskCountByDimension[dimension] ?? 0
        guard openCount == 0 else { return nil }

        // 6. Pick the first calendar gap that meets the minimum duration.
        //    Sorted by start; we take the earliest usable window so the
        //    suggestion is immediate rather than speculative.
        let minMinutes = AppConstants.nudgeMinOpenWindowMinutes
        guard let gap = context.calendarGaps.first(where: { $0.minutes >= minMinutes }) else {
            return nil
        }

        // 7. Compose template params + audit trail.
        let startLabel = Self.timeFormatter.string(from: gap.start)
        let templateParams: [String: String] = [
            "openingHint": "\(gap.minutes) min open at \(startLabel) — want to attend to it?"
        ]
        let triggerContext: [String: String] = [
            "dimensionRaw": dimension.rawValue,
            "score": String(score),
            "gapMinutes": String(gap.minutes),
            "gapStartTS": String(Int(gap.start.timeIntervalSince1970)),
            "streak": String(context.streak)
        ]

        return NudgeCandidate(
            category: .weakDimension,
            dimension: dimension,
            suggestedAction: .createTask,
            actionPayload: dimension.rawValue,
            templateParams: templateParams,
            triggerContext: triggerContext
        )
    }

    // MARK: - Helpers

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        f.locale = Locale.current
        return f
    }()
}
