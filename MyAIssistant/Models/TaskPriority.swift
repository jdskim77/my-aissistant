import SwiftUI

enum TaskPriority: String, CaseIterable, Codable, Identifiable {
    case high = "High"
    case medium = "Medium"
    case low = "Low"

    var id: String { rawValue }

    var sortOrder: Int {
        switch self {
        case .high: return 0
        case .medium: return 1
        case .low: return 2
        }
    }

    // MARK: - Display

    /// User-facing label: consequence-framed natural language.
    var displayName: String {
        switch self {
        case .high: return "Must Do"
        case .medium: return "Should Do"
        case .low: return "Could Do"
        }
    }

    /// Short label for badges and compact UI.
    var shortLabel: String {
        switch self {
        case .high: return "Must"
        case .medium: return "Should"
        case .low: return "Could"
        }
    }

    /// SF Symbol for the priority.
    var icon: String {
        switch self {
        case .high: return "exclamationmark.circle.fill"
        case .medium: return "arrow.right.circle.fill"
        case .low: return "minus.circle"
        }
    }

    /// Subtitle explaining the consequence framing — shown in pickers.
    var hint: String {
        switch self {
        case .high: return "Serious consequences if skipped"
        case .medium: return "Important but flexible"
        case .low: return "Nice to have, no pressure"
        }
    }
}
