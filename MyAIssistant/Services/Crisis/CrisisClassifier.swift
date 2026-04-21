import Foundation

/// On-device crisis classifier. Runs before any LLM call that processes
/// free-text user input (chat, check-in notes). Per the `crisis-safety-protocols`
/// skill: classifier-first, LLM-never for this boundary.
///
/// A positive classification means the nudge engine (and any other LLM-adjacent
/// surface) must suppress new outbound content for a conservative cooldown
/// period (see `NudgeEngine` §7.4) and the app routes the user to safety
/// resources via dedicated, hardcoded copy — never generated.
///
/// Deliberately interface-based so a CoreML model can replace the keyword-list
/// fallback in a later release without changing any callers.
protocol CrisisClassifier: Sendable {
    func evaluate(_ text: String) -> CrisisEvaluation
}

/// Result of a single classification.
struct CrisisEvaluation: Sendable, Equatable {
    /// True when at least one high-confidence crisis signal matched.
    let isCrisis: Bool
    /// The matched terms (for audit logs / eval harness). Empty when `isCrisis` is false.
    let matchedTerms: [String]

    static let safe = CrisisEvaluation(isCrisis: false, matchedTerms: [])
}
