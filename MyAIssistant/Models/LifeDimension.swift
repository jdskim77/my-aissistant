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

    var color: Color {
        switch self {
        case .physical:  return Color(hex: "4CAF50") // green
        case .mental:    return Color(hex: "2196F3") // blue
        case .emotional: return Color(hex: "E91E63") // pink
        case .spiritual: return Color(hex: "9C27B0") // purple
        case .practical: return Color(hex: "78909C") // blue-grey
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
}
