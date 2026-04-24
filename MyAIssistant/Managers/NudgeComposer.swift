import Foundation

/// Composes the visible body text of a nudge from a triggered `NudgeCandidate`.
///
/// **Phase 1: Path A only** — deterministic template rendering. Zero latency,
/// zero cost, works offline, free tier always sees this.
///
/// **Phase 3: Path B** — LLM rewrite via Claude Haiku behind a Pro+ tier gate,
/// capped per-day, cached per rule × dimension × day to avoid per-trigger API
/// spend. Scaffolded here as the `llmEnhance(_:for:)` stub so call sites stay
/// stable across the Phase 1 → Phase 3 transition. Any Path B failure (offline,
/// quota, API error) falls back to the Path A template.
///
/// Composition runs at **trigger evaluation time** (foreground or BGTask),
/// not at delivery time — the body is fully formed before the notification is
/// scheduled, so delivery is always offline-safe.
actor NudgeComposer {

    /// Produce the visible body for a nudge candidate. Returns the template copy
    /// in Phase 1/2; Phase 3 wraps non-safety cases with LLM enhancement for
    /// eligible users.
    ///
    /// **Safety exception.** `safetyRoute` candidates bypass both templates
    /// and LLM paths entirely and return the hardcoded `SafeResourceCopy`
    /// string directly. Any future change to this function MUST preserve that
    /// bypass — safety copy is reviewed manually per `crisis-safety-protocols`
    /// and must never be regenerated, rewritten, or translated by a model.
    func compose(_ candidate: NudgeCandidate) async -> String {
        if candidate.category == .safetyRoute {
            return SafeResourceCopy.message()
        }
        let template = renderTemplate(for: candidate)
        // Phase 3: `if let enhanced = await llmEnhance(template, for: candidate) { return enhanced }`
        return template
    }

    // MARK: - Path A: Templates
    //
    // Each category has a parameterized template. Template params come from
    // the rule that produced the candidate (`candidate.templateParams`). Every
    // parameter has a graceful fallback — a missing param never crashes the
    // composer; it degrades to a less-specific but still usable line.

    private func renderTemplate(for candidate: NudgeCandidate) -> String {
        switch candidate.category {
        case .weakDimension:
            let label = candidate.dimension?.shortLabel ?? "One dimension"
            let hint = candidate.templateParams["openingHint"]
                ?? "Room to attend to it today?"
            return "\(label) has been quiet this week. \(hint)"

        case .streakAtRisk:
            let slot = candidate.templateParams["slotName"] ?? "current"
            let minutes = candidate.templateParams["minutesLeft"] ?? "a few"
            return "Your \(slot) check-in closes in \(minutes) min. One keeps the streak alive."

        case .calendarGap:
            let minutes = candidate.templateParams["minutes"] ?? "a few"
            let suggestion = candidate.templateParams["suggestion"]
                ?? "a short reset"
            return "\(minutes) min open between meetings — want \(suggestion)?"

        case .habitSlip:
            let habit = candidate.templateParams["habitName"] ?? "that habit"
            let duration = candidate.templateParams["duration"] ?? "a few minutes"
            return "You usually do \(habit) around now. Skip today or \(duration)?"

        case .windowedHabit:
            // Fired mid-window by `WindowedHabitRule` when a timed habit is
            // still open past the window's midpoint. `habitTitle` is the only
            // required param; a missing value falls back to a generic line
            // rather than crashing — same grace pattern as every other
            // category here. No hardcoded duration — the rule doesn't know
            // how long this habit takes, and "5 min" would undersell a
            // 20-min meditation or oversell a 1-min stretch.
            let habit = candidate.templateParams["habitTitle"] ?? "that habit"
            return "Still open: \(habit). Want to take it on now, or set it down for today?"

        case .postCheckInAction:
            // Bucket-switched copy for PostLowMoodCheckInRule (spec §4).
            // MVP ships two buckets; the default branch handles an
            // unknown/missing bucket gracefully so older Nudge records
            // (or non-bucket callers) still render sensibly.
            //
            // Suggestions carry their own punctuation — no trailing "?"
            // on the template, or buckets whose suggestion ends in "?"
            // would double-punctuate.
            let mood = candidate.templateParams["moodLabel"] ?? "what you logged"
            let suggestion = candidate.templateParams["suggestion"]
                ?? "A small shift worth trying."
            return "You said \(mood). \(suggestion)"

        case .goalCheckpoint:
            let goal = candidate.templateParams["goal"] ?? "that goal"
            let days = candidate.templateParams["days"] ?? "a while"
            return "You said \(goal) matters. Nothing's moved in \(days) — still current?"

        case .safetyRoute:
            // Unreachable in practice — compose(_:) short-circuits safetyRoute
            // candidates to SafeResourceCopy before renderTemplate is called.
            // Defensive fallback keeps the exhaustive switch honest and
            // guarantees a non-template path even if a refactor accidentally
            // routes safety through here.
            return SafeResourceCopy.message()
        }
    }

    // MARK: - Path B: LLM Enhancement (Phase 3 stub)
    //
    // Wired in Phase 3 against `AIProviderFactory.forNudge(tier:)`. Deliberately
    // not implemented in Phase 1 — keeping the interface here so Phase 3 can
    // flip the switch in `compose(_:)` with a single line.
    //
    // When implemented, this method:
    // - checks subscription tier (Pro+ only)
    // - checks network availability
    // - checks per-day LLM nudge quota
    // - calls Claude Haiku with `AIPromptBuilder.nudgeSystemPrompt()` (stable)
    //   + the template draft and signal context (volatile)
    // - returns nil on any failure so `compose(_:)` falls back to the template
    //
    // private func llmEnhance(_ base: String, for candidate: NudgeCandidate) async -> String? {
    //     nil
    // }
}
