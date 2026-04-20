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
        case .physical:  return "figure.walk"        // V3: clearer silhouette than figure.run
        case .mental:    return "lightbulb.fill"     // V3: clearer than brain.head.profile at 18pt
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

// MARK: - Harmony Stage (V3)
//
// Display-score band → label + earth-tone color + coach copy. Drives the
// BalancePulseCard header and is the ONLY way the UI should colorize the
// harmony number — no more hand-tuned 40 / 70 red-orange-green thresholds.
//
// V3 uses the Growth metaphor (Resting → Growing → Flowing → Thriving →
// Radiant) paired with low-saturation earth tones, replacing the alarm
// palette so the lowest state still reads as "you're here, you're trying."

enum HarmonyStage: String, CaseIterable {
    case resting   // 30–44 — just showing up, recovery
    case growing   // 45–59 — starting to land
    case flowing   // 60–74 — in motion
    case thriving  // 75–89 — steady and well
    case radiant   // 90–100 — a rare strong week

    /// Map a V3 display score (30–100) to its stage.
    static func from(display: Int) -> HarmonyStage {
        switch display {
        case ...44:       return .resting
        case 45...59:     return .growing
        case 60...74:     return .flowing
        case 75...89:     return .thriving
        default:          return .radiant
        }
    }

    var label: String {
        switch self {
        case .resting:  return "Resting"
        case .growing:  return "Growing"
        case .flowing:  return "Flowing"
        case .thriving: return "Thriving"
        case .radiant:  return "Radiant"
        }
    }

    /// Earth-tone palette. Cleared for contrast against cream + conflicts
    /// with existing AppColors (streak flame, medium-priority gold).
    var color: Color {
        switch self {
        case .resting:  return Color(hex: "B87878") // dusty rose
        case .growing:  return Color(hex: "C89868") // sand
        case .flowing:  return Color(hex: "5E8A88") // teal
        case .thriving: return Color(hex: "6B8E72") // moss
        case .radiant:  return Color(hex: "A8915A") // olive-gold
        }
    }

    /// Short "next small step" framing used in coach copy. Never tells the
    /// user they're *below* something — tells them where the next step leads.
    var nextStepCopy: String {
        switch self {
        case .resting:  return "Every small tag counts."
        case .growing:  return "Build the rhythm a little at a time."
        case .flowing:  return "You've got momentum — keep it light."
        case .thriving: return "Steady and whole."
        case .radiant:  return "Every dimension got attention."
        }
    }
}
