import SwiftUI

// MARK: - Theme Enumeration

enum AppTheme: String, CaseIterable, Identifiable {
    // Light themes — Indigo is the brand default (signature Thrivn identity)
    case indigo = "Indigo"
    case natural = "Natural"
    case ocean = "Ocean"
    case paper = "Paper"
    // Note: rawValue kept as "High Contrast" for backward compatibility
    // with existing UserDefaults values. Display name uses `displayName` below.
    case accessible = "High Contrast"
    // Dark themes
    case midnight = "Midnight"
    case twilight = "Twilight"
    case slate = "Slate"
    case accessibleDark = "Accessible Dark"

    var id: String { rawValue }

    var isDark: Bool {
        self == .midnight || self == .twilight || self == .slate || self == .accessibleDark
    }

    /// User-facing name shown in the picker.
    var displayName: String {
        switch self {
        case .indigo: return "Indigo"
        case .natural: return "Natural"
        case .ocean: return "Ocean"
        case .paper: return "Paper"
        case .accessible: return "Accessible"
        case .midnight: return "Midnight"
        case .twilight: return "Twilight"
        case .slate: return "Slate"
        case .accessibleDark: return "Accessible Dark"
        }
    }

    var icon: String {
        switch self {
        case .indigo: return "sparkle"
        case .natural: return "leaf.fill"
        case .ocean: return "water.waves"
        case .paper: return "book.pages.fill"
        case .accessible: return "accessibility"
        case .midnight: return "moon.stars.fill"
        case .twilight: return "sunset.fill"
        case .slate: return "circle.lefthalf.filled"
        case .accessibleDark: return "accessibility"
        }
    }

    var subtitle: String {
        switch self {
        case .indigo: return "Thoughtful & intelligent · Default"
        case .natural: return "Warm & earthy"
        case .ocean: return "Cool & professional"
        case .paper: return "Editorial cream & sepia"
        case .accessible: return "Colorblind-friendly · WCAG AAA"
        case .midnight: return "True dark (OLED)"
        case .twilight: return "Soft dark mode"
        case .slate: return "Cool blue-gray dark"
        case .accessibleDark: return "Colorblind-friendly · Dark mode"
        }
    }

    /// Detailed accessibility note shown only when an accessible theme is selected.
    var accessibilityNote: String? {
        switch self {
        case .accessible:
            return "Designed for users with deuteranopia, protanopia, and tritanopia. Uses blue instead of green for success states. Meets WCAG AAA contrast standards (7:1+)."
        case .accessibleDark:
            return "Dark mode variant of Accessible. Same colorblind-safe palette (blue for success, orange for warnings) on a true black background. Designed for users who need both colorblind support and dark mode (e.g. light sensitivity)."
        default:
            return nil
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

    // Semantic feedback colors
    let error: Color
    let errorBg: Color
    let warning: Color
    let warningBg: Color
    let success: Color
    let successBg: Color
    let disabled: Color
    let textDisabled: Color
}
