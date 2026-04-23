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
        let lowered = text.lowercased()
        // Multi-word patterns carry inherent boundary protection via
        // their spaces ("kill myself" can't match inside "skill
        // myselfmotivated"), so substring-match is fine for them.
        // Single-word patterns match via regex with \b word boundaries
        // to avoid matching "suicide" inside "suicideprevention" or
        // similar compound tokens. Fix for Q1-BUG-36.
        let matched = patterns.filter { pattern in
            if pattern.contains(" ") {
                return lowered.contains(pattern)
            }
            // Single-word: word-boundary regex match.
            let escaped = NSRegularExpression.escapedPattern(for: pattern)
            let regexPattern = "\\b\(escaped)\\b"
            guard let regex = try? NSRegularExpression(pattern: regexPattern) else {
                return lowered.contains(pattern) // fallback on regex failure
            }
            let range = NSRange(lowered.startIndex..<lowered.endIndex, in: lowered)
            return regex.firstMatch(in: lowered, range: range) != nil
        }
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
