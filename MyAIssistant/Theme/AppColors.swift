import SwiftUI

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

struct AppColors {
    private static var theme: ColorTheme { ThemeManager.shared.currentTheme }

    // MARK: - Backgrounds & Surfaces
    static var background: Color { theme.background }
    static var surface: Color { theme.surface }
    static var card: Color { theme.card }
    static var border: Color { theme.border }

    // MARK: - Accents
    static var accent: Color { theme.accent }
    static var accentWarm: Color { theme.accentWarm }
    static var accentLight: Color { theme.accentLight }

    // MARK: - Semantic Colors
    static var gold: Color { theme.gold }
    static var coral: Color { theme.coral }
    static var skyBlue: Color { theme.skyBlue }

    // MARK: - Text
    static var textPrimary: Color { theme.textPrimary }
    static var textSecondary: Color { theme.textSecondary }
    static var textMuted: Color { theme.textMuted }

    // MARK: - Check-in Times
    static var morning: Color { theme.morning }
    static var noon: Color { theme.noon }
    static var afternoon: Color { theme.afternoon }
    static var night: Color { theme.night }

    // MARK: - Task Status
    static var overdueRed: Color { theme.overdueRed }
    static var overdueBg: Color { theme.overdueBg }
    static var completionGreen: Color { theme.completionGreen }

    // MARK: - Chat Bubbles
    static var userBubbleText: Color { theme.userBubbleText }
    static var aiBubble: Color { theme.aiBubble }
    static var aiBubbleText: Color { theme.aiBubbleText }
    static var aiBubbleBorder: Color { theme.aiBubbleBorder }

    // MARK: - Priority

    static func priorityColor(_ priority: TaskPriority) -> Color {
        switch priority {
        case .high: return coral
        case .medium: return gold
        case .low: return textMuted
        }
    }

    static func checkboxColor(_ priority: TaskPriority) -> Color {
        switch priority {
        case .high: return theme.checkboxHigh
        case .medium: return theme.checkboxMedium
        case .low: return theme.checkboxLow
        }
    }
}
