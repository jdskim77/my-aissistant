import SwiftUI

// MARK: - Theme Enumeration

enum AppTheme: String, CaseIterable, Identifiable {
    case natural = "Natural"
    case ocean = "Ocean"
    case highContrast = "High Contrast"
    case midnight = "Midnight"
    case twilight = "Twilight"

    var id: String { rawValue }

    var isDark: Bool {
        self == .midnight || self == .twilight
    }

    var icon: String {
        switch self {
        case .natural: return "leaf.fill"
        case .ocean: return "water.waves"
        case .highContrast: return "eye.fill"
        case .midnight: return "moon.stars.fill"
        case .twilight: return "sunset.fill"
        }
    }

    var subtitle: String {
        switch self {
        case .natural: return "Warm & earthy"
        case .ocean: return "Cool & professional"
        case .highContrast: return "Maximum readability"
        case .midnight: return "True dark (OLED)"
        case .twilight: return "Soft dark mode"
        }
    }
}

// MARK: - Color Theme

struct ColorTheme {
    let background: Color
    let surface: Color
    let card: Color
    let border: Color

    let accent: Color
    let accentWarm: Color
    let accentLight: Color

    let gold: Color
    let coral: Color
    let skyBlue: Color

    let textPrimary: Color
    let textSecondary: Color
    let textMuted: Color

    let morning: Color
    let noon: Color
    let afternoon: Color
    let night: Color

    let overdueRed: Color
    let overdueBg: Color
    let completionGreen: Color

    let userBubbleText: Color
    let aiBubble: Color
    let aiBubbleText: Color
    let aiBubbleBorder: Color

    // Priority checkbox colors (can differ per theme for colorblind support)
    let checkboxHigh: Color
    let checkboxMedium: Color
    let checkboxLow: Color
}
