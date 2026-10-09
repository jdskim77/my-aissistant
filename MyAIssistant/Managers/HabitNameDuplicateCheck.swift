import Foundation

/// Pure duplicate-habit-name detection (Impeccable Screens audit P2:
/// "warn on near-duplicate habit names"). Separated from `HabitFormView`
/// so it's unit-testable without SwiftData/ModelContext scaffolding.
enum HabitNameDuplicateCheck {
    /// Normalizes a habit title for comparison: lowercased, punctuation
    /// stripped, and whitespace collapsed/trimmed. Two titles that
    /// normalize to the same string are considered duplicates — this is
    /// why "Morning - 10 surf popups" and "10 Surf popups" (the real
    /// example from the audit) still need a smarter check: this alone
    /// only catches *true* near-duplicates (case/whitespace/punctuation),
    /// not reordered words. That's an intentional, conservative scope —
    /// a false "duplicate" warning on genuinely different habits is worse
    /// than missing a loose paraphrase.
    static func normalize(_ title: String) -> String {
        let lowered = title.lowercased()
        let allowed = CharacterSet.alphanumerics.union(.whitespaces)
        let stripped = String(lowered.unicodeScalars.filter { allowed.contains($0) })
        return stripped
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Returns the first existing title (if any) that the candidate
    /// title would collide with after normalization. Excludes the habit
    /// currently being edited (pass its title as `excluding` when
    /// editing) so saving a habit under its own unchanged name never
    /// warns on itself.
    static func duplicate(
        of candidate: String,
        among existingTitles: [String],
        excluding: String? = nil
    ) -> String? {
        let normalizedCandidate = normalize(candidate)
        guard !normalizedCandidate.isEmpty else { return nil }
        let normalizedExcluding = excluding.map(normalize)
        for existing in existingTitles {
            if let normalizedExcluding, normalize(existing) == normalizedExcluding {
                continue
            }
            if normalize(existing) == normalizedCandidate {
                return existing
            }
        }
        return nil
    }
}
