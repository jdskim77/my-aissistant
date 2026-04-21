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
    /// in Phase 1; Phase 3 wraps this with LLM enhancement for eligible users.
    func compose(_ candidate: NudgeCandidate) async -> String {
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

        case .postCheckInAction:
            let mood = candidate.templateParams["moodLabel"] ?? "what you logged"
            let suggestion = candidate.templateParams["suggestion"]
                ?? "a small shift"
            return "You said \(mood). \(suggestion)?"

        case .goalCheckpoint:
            let goal = candidate.templateParams["goal"] ?? "that goal"
            let days = candidate.templateParams["days"] ?? "a while"
            return "You said \(goal) matters. Nothing's moved in \(days) — still current?"
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
