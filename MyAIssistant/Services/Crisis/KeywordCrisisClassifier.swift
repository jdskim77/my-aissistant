import Foundation

/// Conservative keyword-list `CrisisClassifier` fallback for Phase 1.
///
/// Deliberately biased toward false positives: if a curated phrase is present,
/// we suppress nudges. The cost of a false positive is one silenced nudge; the
/// cost of a false negative is a coach message arriving during a crisis.
///
/// The phrase list covers explicit self-harm / suicidal ideation language and
/// high-confidence idioms of hopelessness. It deliberately does NOT try to
/// detect sadness, frustration, tiredness, or burnout — those are exactly what
/// the check-in surface is for, and subtle-distress detection belongs to a
/// trained model, not a keyword list.
///
/// Match is case-insensitive substring on whitespace-normalized input. Sub-word
/// false matches (e.g. "kill" inside "skill") are avoided by using multi-word
/// phrases; the two single-word terms ("suicide", "suicidal") can match inside
/// psychoeducation content, which we accept as safe over-triggering.
///
/// A CoreML model can replace this class by implementing `CrisisClassifier` and
/// swapping the DI binding — no callers change.
struct KeywordCrisisClassifier: CrisisClassifier {
    let patterns: [String]

    init(patterns: [String] = KeywordCrisisClassifier.defaultPatterns) {
        self.patterns = patterns.map { $0.lowercased() }
    }

    func evaluate(_ text: String) -> CrisisEvaluation {
        guard !text.isEmpty else { return .safe }
        let normalized = text
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let matched = patterns.filter { normalized.contains($0) }
        return CrisisEvaluation(isCrisis: !matched.isEmpty, matchedTerms: matched)
    }

    /// Curated v1 list. ~35 high-confidence phrases. Expand with care — every
    /// addition widens the false-positive surface and one wrong addition can
    /// silence the coach for days.
    static let defaultPatterns: [String] = [
        // Explicit self-harm / suicidal ideation
        "kill myself",
        "killing myself",
        "end my life",
        "ending my life",
        "end it all",
        "take my own life",
        "take my life",
        "hurt myself",
        "hurting myself",
        "cut myself",
        "cutting myself",
        "harm myself",
        "harming myself",

        // Method references
        "overdose on",
        "hang myself",
        "jump off",
        "shoot myself",

        // Permanence of death wish
        "want to die",
        "wish i was dead",
        "wish i were dead",
        "better off dead",
        "better off without me",
        "should be dead",
        "no reason to live",
        "nothing to live for",

        // Crisis escalation language
        "can't go on",
        "cannot go on",
        "can't do this anymore",
        "cannot do this anymore",
        "no way out",
        "goodbye forever",
        "final goodbye",

        // Explicit terms
        "suicide",
        "suicidal"
    ]
}
