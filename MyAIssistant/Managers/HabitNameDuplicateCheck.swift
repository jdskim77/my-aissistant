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
    /// title would collide with after normalization. `existing` pairs
    /// each title with a stable identifier so the habit currently being
    /// edited can be excluded by ID rather than by title — excluding by
    /// title alone would also hide a *real* duplicate when two other
    /// habits already share that exact name. Pass the ID of the habit
    /// being edited as `excludingID` (nil when creating).
    static func duplicate(
        of candidate: String,
        among existing: [(id: String, title: String)],
        excludingID: String? = nil
    ) -> String? {
        let normalizedCandidate = normalize(candidate)
        guard !normalizedCandidate.isEmpty else { return nil }
        for item in existing {
            if let excludingID, item.id == excludingID {
                continue
            }
            if normalize(item.title) == normalizedCandidate {
                return item.title
            }
        }
        return nil
    }
}
