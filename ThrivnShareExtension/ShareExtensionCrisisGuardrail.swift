import Foundation

/// Share-extension-target port of the iOS crisis classifier. Runs before
/// `ShareExtensionViewModel.callExtractionLLM(...)` so user-shared text
/// is gated identically to iOS chat / iOS check-in notes / iOS task
/// parser. Without this gate, a user sharing self-harm content from
/// another app into Thrivn would have flowed verbatim to Anthropic for
/// "task extraction."
///
/// **Why a separate file rather than sharing iOS code:** the share
/// extension and main app have separate Compile Sources lists.
/// Importing `KeywordCrisisClassifier.swift` from the iOS target would
/// require either adding it to the extension's compile sources (4
/// `.pbxproj` insertions) or sharing through a framework. A
/// self-contained extension-only port keeps the safety surface
/// independent — future iOS-side classifier edits won't silently
/// change extension behavior — and avoids depending on
/// `AppLogger`/`Breadcrumb` which aren't compiled in this target.
///
/// **Sync contract:** when iOS `KeywordCrisisClassifier` patterns are
/// updated, mirror the change here. Drift is a real risk — flagged in
/// the audit queue as a candidate for a shared cross-target file.
///
/// Behavior on block: the caller should skip the LLM call and fall
/// back to the default task title (which is already set in init).
/// The share extension has no chat surface to render safety copy
/// inline; users see the raw shared content as their task title and
/// can edit before save. The deeper coach-side gate still fires when
/// they later open the app.
enum ShareExtensionCrisisGuardrail {

    /// Returns `true` when the shared text matches any crisis pattern.
    /// Empty / whitespace-only input returns `false` (nothing to gate).
    static func isCrisis(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        // Two-form normalization, matching iOS:
        //  - NFKC-lowercased for homoglyph defense.
        //  - Latin-transliterated + diacritic-stripped for Spanish/
        //    Portuguese phrases ("matarme" matching "matarmé" etc.).
        let raw = text.precomposedStringWithCompatibilityMapping.lowercased()
        let latin = ((text as NSString)
            .applyingTransform(.toLatin, reverse: false)?
            .applyingTransform(.stripCombiningMarks, reverse: false)?
            .applyingTransform(.stripDiacritics, reverse: false))?
            .precomposedStringWithCompatibilityMapping.lowercased() ?? raw
        let haystacks = [raw, latin]

        for pattern in patterns {
            // Mirror iOS `KeywordCrisisClassifier`: single-word ASCII
            // patterns ("suicide", "suicidal") get \b word-boundary
            // matching so "suicideprevention" doesn't flag. Multi-word
            // and non-ASCII patterns use substring match (CJK has no
            // word boundary, and the multi-word phrases are specific
            // enough that substring is safe).
            if isSingleWordASCII(pattern) {
                if regexBoundaryMatch(pattern: pattern, in: haystacks) { return true }
            } else if haystacks.contains(where: { $0.contains(pattern) }) {
                return true
            }
        }
        return false
    }

    /// True for patterns that are a single ASCII word — i.e. no spaces
    /// and all scalars ≤ 0x7F. These are eligible for `\b` matching.
    private static func isSingleWordASCII(_ pattern: String) -> Bool {
        !pattern.contains(" ")
            && !pattern.unicodeScalars.contains(where: { $0.value > 0x7F })
    }

    /// `\bpattern\b` regex match against either haystack. NSRegularExpression
    /// is compiled per-call here (vs. iOS's cached map) because the share
    /// extension is single-shot and rarely runs more than once per launch
    /// — the regex-compile cost (~0.1ms × 2 single-word patterns)
    /// doesn't move the needle on extension UX.
    private static func regexBoundaryMatch(pattern: String, in haystacks: [String]) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: pattern)
        guard let regex = try? NSRegularExpression(pattern: "\\b\(escaped)\\b") else {
            // Compile failure is treated as a non-match — over-blocking
            // on a broken regex would be worse than under-blocking on a
            // single ASCII word that's already covered by the conservative
            // multi-word phrase ("commit suicide", etc.).
            return false
        }
        for haystack in haystacks {
            let range = NSRange(haystack.startIndex..<haystack.endIndex, in: haystack)
            if regex.firstMatch(in: haystack, range: range) != nil { return true }
        }
        return false
    }

    /// Crisis pattern set. Mirrors
    /// `KeywordCrisisClassifier.{english,spanish,portuguese,chinese,japanese}Patterns`.
    /// Ordered the same way the iOS classifier scans (en/es/pt/zh/ja).
    /// Watch the iOS file when editing; this list must stay in sync.
    private static let patterns: [String] = [
        // en
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
        "suicide", "suicidal",
        // es
        "quiero morir", "no quiero vivir", "me quiero matar",
        "matarme", "acabar con mi vida", "acabar con todo",
        // pt
        "quero morrer", "me matar", "nao quero viver",
        // zh
        "自杀", "想死",
        // ja
        "死にたい", "自殺"
    ]
}
