import Foundation

/// Fires 10–90 minutes after a low-mood check-in, suggesting a small
/// concrete action (10-min walk). The highest-leverage rule after
/// weak-dimension per the expert panel (Product A): it converts a
/// *just-collected* state signal into an uncannily-timed action
/// prompt while the user's present state is still current.
///
/// **MVP scope (POST_LOW_MOOD_RULE_SPEC.md §9):**
/// - Two buckets only: `low` (mood ≤ 2) and `flat` (mood == 3 AND energy ≤ 2)
/// - Single template per bucket (no variant rotation)
/// - Both buckets suggest a 10-min walk as `.createTask`
/// - Default-OFF opt-in; user consents in Coach Settings before this
///   can fire. Mood-triggered nudges need explicit consent.
///
/// **Safety interaction.** `NudgeEngine.performSafetyPrecheck()` runs
/// before any rule at step 3 of `evaluate()`. A crisis-flagged note
/// short-circuits the whole pipeline and routes to `SafeResourceCopy`,
/// so this rule inherits the safety guard for free. It MUST NOT
/// copy the user's notes text into the template or triggerContext —
/// even classifier-negative notes can contain material we don't want
/// re-surfaced.
///
/// **State, not trait.** The rule reads mood from the latest record
/// only. "User logged flat today" is a state reading, not "user is a
/// flat person." Nothing this rule emits promotes the reading into
/// persisted user facts (per `conversation-memory-design` §6).
///
/// Spec: POST_LOW_MOOD_RULE_SPEC.md (design + eval gates).
struct PostLowMoodCheckInRule: NudgeTriggerRule {
    let id: NudgeCategory = .postCheckInAction

    var cooldown: TimeInterval {
        Double(AppConstants.nudgePostLowMoodCooldownHours) * 3600
    }

    func evaluate(context: NudgeEvalContext) -> NudgeCandidate? {
        // 1. Explicit opt-in. Default OFF — mood-triggered nudges need
        //    consent beyond the generic proactive-nudges toggle.
        guard UserDefaults.standard.bool(forKey: AppConstants.nudgePostLowMoodEnabledKey) else {
            return nil
        }

        // 2. Streak baseline — don't nudge on a brand-new user's first
        //    few check-ins. Their baseline hasn't formed; framing noise
        //    as a concern erodes trust.
        guard context.streak >= AppConstants.nudgePostLowMoodStreakMin else { return nil }

        // 3. Find the newest *qualifying* check-in: inside the freshness
        //    window AND matching a mood bucket AND not already nudged.
        //    Fix for BUG-14 — previously the rule only looked at
        //    `context.lastCheckIn` (single most recent), so a newer
        //    neutral/happy check-in hid an older low one that was still
        //    in its action window. Scanning recent records in
        //    newest-first order lets the rule still react to the last
        //    emotionally-meaningful state the user logged, as long as
        //    nothing more recent supersedes it.
        let minMin = AppConstants.nudgePostLowMoodMinMinutesSinceCheckIn
        let maxMin = AppConstants.nudgePostLowMoodMaxMinutesSinceCheckIn

        let match: (snapshot: LastCheckInSnapshot, bucket: Bucket)? = {
            for candidate in context.recentCheckIns {
                let elapsedMin = Int(context.now.timeIntervalSince(candidate.date) / 60)
                // Outside the freshness window entirely → stop scanning
                // (list is sorted newest first, so older records are
                // guaranteed further out of window).
                if elapsedMin > maxMin { return nil }
                // Too recent (give the user breathing room after logging).
                if elapsedMin < minMin { continue }
                // Already acted on this specific record.
                if context.nudgedCheckInIDs.contains(candidate.id) { continue }
                // Must match a mood bucket.
                guard let bucket = Self.bucket(mood: candidate.mood, energy: candidate.energyLevel) else {
                    continue
                }
                return (candidate, bucket)
            }
            return nil
        }()

        guard let (checkIn, bucket) = match else { return nil }

        // 4. Compose template params + trigger context. Note that
        //    `checkInID` is stamped into the trigger context so the
        //    engine's `fetchNudgedCheckInIDs` helper can see it on
        //    subsequent evaluation passes.
        let elapsedMin = Int(context.now.timeIntervalSince(checkIn.date) / 60)
        let templateParams: [String: String] = [
            "bucketRaw": bucket.rawValue,
            "moodLabel": bucket.moodLabel,
            "suggestion": bucket.suggestion
        ]
        let triggerContext: [String: String] = [
            "checkInID": checkIn.id,
            "bucketRaw": bucket.rawValue,
            "elapsedMin": String(elapsedMin),
            "streak": String(context.streak)
        ]

        return NudgeCandidate(
            category: .postCheckInAction,
            // Intentionally nil — the engine's per-dimension cooldown
            // would otherwise block this rule whenever a Physical
            // weak-dimension nudge fired in the last 48h, even though
            // the two rules are unrelated. The post-check-in action is
            // triggered by mood state, not by neglect of a specific
            // dimension. Fix for BUG-23.
            dimension: nil,
            suggestedAction: .createTask,
            actionPayload: "walk-10min",
            templateParams: templateParams,
            triggerContext: triggerContext
        )
    }

    // MARK: - Bucket

    /// Two-bucket MVP selector. Future buckets (veryLow, drained, anxious)
    /// live in the spec but are deferred to the post-MVP iteration.
    enum Bucket: String {
        case low   // mood ≤ 2
        case flat  // mood == 3 AND energy ≤ 2

        var moodLabel: String {
            switch self {
            case .low:  return "low"
            case .flat: return "flat"
            }
        }

        var suggestion: String {
            switch self {
            case .low:
                return "Ten minutes outside tends to move this more than anything else. Want it on the schedule?"
            case .flat:
                return "One small shift — step outside for five minutes?"
            }
        }
    }

    static func bucket(mood: Int?, energy: Int?) -> Bucket? {
        guard let mood else { return nil }
        if mood <= 2 { return .low }
        // Flat bucket: mood == 3 with low OR missing energy.
        // Before BUG-13, this required `energy ≤ 2`, silently skipping
        // check-ins where energyLevel wasn't captured. Treat missing
        // energy as ambiguous-neutral — if mood itself is 3, that's
        // enough signal to suggest a small shift.
        if mood == 3 {
            if let energy {
                return energy <= 2 ? .flat : nil
            }
            return .flat
        }
        return nil
    }
}
