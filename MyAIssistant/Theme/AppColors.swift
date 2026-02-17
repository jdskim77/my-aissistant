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
    static let background = Color(hex: "F8F5F0")
    static let surface = Color.white
    static let card = Color(hex: "FFFEFB")
    static let border = Color(hex: "E8E2D9")

    static let accent = Color(hex: "2D5016")
    static let accentWarm = Color(hex: "4A7C2F")
    static let accentLight = Color(hex: "E8F0E0")

    static let gold = Color(hex: "B8860B")
    static let coral = Color(hex: "C94B2B")
    static let skyBlue = Color(hex: "1A5276")

    static let textPrimary = Color(hex: "1A1A14")
    static let textSecondary = Color(hex: "6B6555")
    static let textMuted = Color(hex: "8A8478")

    static let morning = Color(hex: "FF9500")
    static let noon = Color(hex: "34C759")
    static let afternoon = Color(hex: "007AFF")
    static let night = Color(hex: "5856D6")

    static func priorityColor(_ priority: TaskPriority) -> Color {
        switch priority {
        case .high: return coral
        case .medium: return gold
        case .low: return textMuted
        }
    }
}
