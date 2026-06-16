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
struct KeywordCrisisClassifier: CrisisClassifier, @unchecked Sendable {
    let patterns: [String]
    /// Precompiled `\b<pattern>\b` regexes for the single-word ASCII
    /// patterns. Built once at init so repeated `evaluate()` calls don't
    /// recompile ~30 regexes per haystack — meaningful when the recap
    /// path iterates over multiple notes-of-the-day. Multi-word and
    /// non-ASCII (CJK) patterns aren't here because they go through
    /// the substring path and don't need a regex.
    /// `@unchecked Sendable` because NSRegularExpression is read-only
    /// after init and Apple documents it as thread-safe in that mode.
    private let compiledRegexes: [String: NSRegularExpression]

    init(patterns: [String] = KeywordCrisisClassifier.defaultPatterns) {
        let normalized = patterns.map { $0.lowercased() }
        self.patterns = normalized
        var compiled: [String: NSRegularExpression] = [:]
        compiled.reserveCapacity(normalized.count)
        for pattern in normalized
        where !pattern.contains(" ")
            && !pattern.unicodeScalars.contains(where: { $0.value > 0x7F }) {
            let escaped = NSRegularExpression.escapedPattern(for: pattern)
            if let regex = try? NSRegularExpression(pattern: "\\b\(escaped)\\b") {
                compiled[pattern] = regex
            }
        }
        self.compiledRegexes = compiled
    }

    func evaluate(_ text: String) -> CrisisEvaluation {
        // Trim before length check so whitespace-only / zero-width-space
        // notes are treated as empty (BUG-09 from the recap-gate QA pass).
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .safe }
        let detected = doEvaluate(text: text)
        return detected
    }

    /// Inner evaluation. Returns CrisisEvaluation with detected language
    /// derived from the FIRST matched pattern. Language detection from the
    /// matched term (rather than `Locale.current`) is what solves the "user
    /// types in Japanese on en-US device" gap from the SafeResourceCopy
    /// localization QA pass.
    private func doEvaluate(text: String) -> CrisisEvaluation {
        // Match against TWO normalized forms so a user can't evade detection
        // by swapping in homoglyphs OR by writing in CJK that wouldn't survive
        // a Latin transliteration:
        //  • `raw`   — NFKC-normalized lowercase, preserves CJK glyphs so the
        //              CJK patterns ("自杀", "死にたい") can still match.
        //  • `latin` — additionally transliterated to Latin and stripped of
        //              diacritics, so Cyrillic-i homoglyph "kіll" matches
        //              "kill" and accented Spanish/Portuguese matches the
        //              accent-stripped patterns.
        let raw = text.precomposedStringWithCompatibilityMapping.lowercased()
        let latin = ((text as NSString)
            .applyingTransform(.toLatin, reverse: false)?
            .applyingTransform(.stripCombiningMarks, reverse: false)?
            .applyingTransform(.stripDiacritics, reverse: false))?
            .precomposedStringWithCompatibilityMapping.lowercased() ?? raw
        let haystacks = [raw, latin]

        // Multi-word patterns carry inherent boundary protection via
        // their spaces ("kill myself" can't match inside "skill
        // myselfmotivated"), so substring-match is fine for them.
        // Single-word patterns match via regex with \b word boundaries
        // to avoid matching "suicide" inside "suicideprevention" or
        // similar compound tokens. Fix for Q1-BUG-36.
        let matched = patterns.filter { pattern in
            if pattern.contains(" ") || pattern.unicodeScalars.contains(where: { $0.value > 0x7F }) {
                // Either multi-word OR contains non-ASCII (CJK characters,
                // which don't have meaningful Latin word boundaries).
                return haystacks.contains { $0.contains(pattern) }
            }
            // Single-word ASCII: word-boundary regex match using the
            // precompiled regex cache. Falls back to substring contains
            // only if the regex couldn't be compiled at init time.
            guard let regex = compiledRegexes[pattern] else {
                return haystacks.contains { $0.contains(pattern) }
            }
            return haystacks.contains { hay in
                let range = NSRange(hay.startIndex..<hay.endIndex, in: hay)
                return regex.firstMatch(in: hay, range: range) != nil
            }
        }
        // Detect language from the FIRST matched pattern. Patterns are
        // grouped by language in `defaultPatterns`; we look up each match
        // against the per-language sets and return the first hit. A user
        // typing "me quiero morir" on an en-US device gets `detectedLanguage:
        // "es"` here, so SafeResourceCopy can render Spanish copy regardless
        // of `Locale.current`. BUG-01 from the localization QA pass.
        let detectedLang: String? = matched.lazy.compactMap { Self.language(for: $0) }.first
        return CrisisEvaluation(
            isCrisis: !matched.isEmpty,
            matchedTerms: matched,
            detectedLanguage: detectedLang
        )
    }

    /// Returns the BCP-47 language code of a matched pattern, or nil if
    /// the pattern isn't in any of the per-language groups (e.g. a custom
    /// caller-supplied pattern).
    private static func language(for pattern: String) -> String? {
        if englishPatterns.contains(pattern) { return "en" }
        if spanishPatterns.contains(pattern) { return "es" }
        if portuguesePatterns.contains(pattern) { return "pt" }
        if chinesePatterns.contains(pattern) { return "zh" }
        if japanesePatterns.contains(pattern) { return "ja" }
        return nil
    }

    /// Curated v1 list — split per-language so the classifier can report
    /// which language matched (used by `SafeResourceCopy` for localized
    /// safety copy regardless of `Locale.current`). Expand with care —
    /// every addition widens the false-positive surface.
    static var defaultPatterns: [String] {
        englishPatterns + spanishPatterns + portuguesePatterns + chinesePatterns + japanesePatterns
    }

    /// English crisis patterns. After `.toLatin` we operate on Latin
    /// characters, so accent-stripped forms also match.
    static let englishPatterns: [String] = [
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

    /// Spanish patterns. Accent-stripped forms match input regardless of
    /// whether the user typed accents (the classifier passes input through
    /// `stripDiacritics` before substring matching).
    static let spanishPatterns: [String] = [
        "quiero morir",
        "no quiero vivir",
        "me quiero matar",
        "matarme",
        "acabar con mi vida",
        "acabar con todo"
    ]

    /// Portuguese patterns.
    static let portuguesePatterns: [String] = [
        "quero morrer",
        "me matar",
        "nao quero viver"
    ]

    /// Chinese patterns. CJK survives `.toLatin` only partially; these
    /// match pre-transform via the multi-word substring path. Note: same
    /// glyphs in Simplified and Traditional for these specific phrases
    /// (自杀 is both; 想死 is both). When extending to phrases that diverge
    /// between Hans/Hant, register both variants explicitly.
    static let chinesePatterns: [String] = [
        "自杀",
        "想死"
    ]

    /// Japanese patterns.
    static let japanesePatterns: [String] = [
        "死にたい",
        "自殺"
    ]
}
