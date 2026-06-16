import Foundation

/// Watch-target port of the iOS `KeywordCrisisClassifier`. Runs before
/// `WatchClaudeService.sendQuery(...)` so user transcripts on the watch
/// chat path are gated identically to iOS chat / iOS check-in notes.
///
/// **Why a separate file rather than sharing iOS code:** the watch and
/// iOS targets have separate Compile Sources lists. Adding the iOS file
/// to the watch target via Xcode UI would also work, but a self-contained
/// watch-only port keeps the watch app's safety surface independent —
/// future edits to the iOS classifier won't silently change watch
/// behavior, and a watchOS-only release branch can ship without coupling.
///
/// Pattern set is the same curated v1 list as iOS (en/es/pt/zh/ja). When
/// the iOS classifier is updated, mirror the change here. Inconsistency
/// between iOS and watch detection is a real risk — ideally a single
/// shared file at the top of the project becomes the source of truth in
/// a future iteration.
struct WatchCrisisEvaluation: Equatable {
    let isCrisis: Bool
    let detectedLanguage: String?

    static let safe = WatchCrisisEvaluation(isCrisis: false, detectedLanguage: nil)
}

enum WatchCrisisClassifier {

    /// Evaluate input text. Returns `.safe` for empty / whitespace-only /
    /// non-matching input. Returns `(isCrisis: true, detectedLanguage:)`
    /// when any pattern matches.
    static func evaluate(_ text: String) -> WatchCrisisEvaluation {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .safe }

        // Same two-form normalization as iOS: NFKC-lowercased + Latin-
        // transliterated for homoglyph defense and accent-strip matching
        // of Spanish/Portuguese phrases.
        let raw = text.precomposedStringWithCompatibilityMapping.lowercased()
        let latin = ((text as NSString)
            .applyingTransform(.toLatin, reverse: false)?
            .applyingTransform(.stripCombiningMarks, reverse: false)?
            .applyingTransform(.stripDiacritics, reverse: false))?
            .precomposedStringWithCompatibilityMapping.lowercased() ?? raw
        let haystacks = [raw, latin]

        for (language, patterns) in patternsByLanguage {
            for pattern in patterns {
                if haystacks.contains(where: { $0.contains(pattern) }) {
                    return WatchCrisisEvaluation(isCrisis: true, detectedLanguage: language)
                }
            }
        }
        return .safe
    }

    /// Per-language pattern groups. Keep in sync with the iOS
    /// `KeywordCrisisClassifier.{english,spanish,portuguese,chinese,japanese}Patterns`.
    /// Order matters for `detectedLanguage` priority — first language with
    /// a match wins. English first because it's the most common input
    /// language; CJK last because CJK phrases are short and false-positive
    /// risk is lower for Latin patterns.
    private static let patternsByLanguage: [(String, [String])] = [
        ("en", [
            "kill myself", "killing myself",
            "end my life", "ending my life",
            "end it all", "take my own life", "take my life",
            "hurt myself", "hurting myself",
            "cut myself", "cutting myself",
            "harm myself", "harming myself",
            "overdose on", "hang myself", "jump off", "shoot myself",
            "want to die", "wish i was dead", "wish i were dead",
            "better off dead", "better off without me",
            "should be dead", "no reason to live", "nothing to live for",
            "can't go on", "cannot go on",
            "can't do this anymore", "cannot do this anymore",
            "no way out", "goodbye forever", "final goodbye",
            "suicide", "suicidal"
        ]),
        ("es", [
            "quiero morir", "no quiero vivir", "me quiero matar",
            "matarme", "acabar con mi vida", "acabar con todo"
        ]),
        ("pt", [
            "quero morrer", "me matar", "nao quero viver"
        ]),
        ("zh", [
            "自杀", "想死"
        ]),
        ("ja", [
            "死にたい", "自殺"
        ])
    ]
}
