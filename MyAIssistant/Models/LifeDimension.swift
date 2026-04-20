import SwiftUI

/// The five life dimensions used by the Life Compass.
/// Four are scored (Physical, Mental, Emotional, Spiritual); Practical is unscored.
enum LifeDimension: String, CaseIterable, Codable, Identifiable {
    case physical = "Physical"
    case mental = "Mental"
    case emotional = "Emotional"
    case spiritual = "Spiritual"
    case practical = "Practical"

    var id: String { rawValue }

    /// Only the four scored dimensions count toward the balance evaluation.
    var isScored: Bool {
        self != .practical
    }

    /// The four dimensions that contribute to balance scoring.
    static var scored: [LifeDimension] {
        allCases.filter(\.isScored)
    }

    var icon: String {
        switch self {
        case .physical:  return "figure.run"
        case .mental:    return "brain.head.profile"
        case .emotional: return "heart.fill"
        case .spiritual: return "sparkles"
        case .practical: return "wrench.and.screwdriver"
        }
    }

    var label: String { rawValue }

    var color: Color { Color(hex: colorHex) }

    /// Canonical hex string for this dimension. Used to sync `HabitItem.colorHex`
    /// so legacy UI paths that read colorHex stay consistent with the dimension
    /// color shown elsewhere (Compass bars, task dots).
    var colorHex: String {
        switch self {
        case .physical:  return "4CAF50" // green
        case .mental:    return "2196F3" // blue
        case .emotional: return "E91E63" // pink
        case .spiritual: return "9C27B0" // purple
        case .practical: return "78909C" // blue-grey
        }
    }

    /// Brief description shown during onboarding or tooltips.
    var summary: String {
        switch self {
        case .physical:  return "Exercise, sleep, nutrition, healthcare"
        case .mental:    return "Learning, reading, creative work, problem-solving"
        case .emotional: return "Relationships, social time, fun, self-care"
        case .spiritual: return "Meditation, gratitude, service, helping others"
        case .practical: return "Errands, admin, chores, life maintenance"
        }
    }

    /// Short display label for compact contexts (BalancePulseCard, pulse labels).
    var shortLabel: String {
        switch self {
        case .physical:  return "Body"
        case .mental:    return "Mind"
        case .emotional: return "Heart"
        case .spiritual: return "Spirit"
        case .practical: return "Life"
        }
    }

    /// Stable sort order for Compass layout consistency (Physical < Mental <
    /// Emotional < Spiritual < Practical). Used by `primaryScored` so the
    /// UI and the pulse animation always agree on which bar represents a
    /// multi-tagged task/habit.
    var sortOrder: Int {
        switch self {
        case .physical: return 0
        case .mental: return 1
        case .emotional: return 2
        case .spiritual: return 3
        case .practical: return 4
        }
    }
}

extension Array where Element == LifeDimension {
    /// First scored dimension by `sortOrder` — the canonical "primary"
    /// dimension for a multi-tagged item. Used by the task/habit row dot,
    /// TaskManager/HabitManager pulse publish, and the Compass animation so
    /// the visual + the pulse always pick the same bar.
    var primaryScored: LifeDimension? {
        self.filter(\.isScored).min(by: { $0.sortOrder < $1.sortOrder })
    }
}
