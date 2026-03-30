import SwiftUI

/// Text size options aligned with Apple's Dynamic Type accessibility guidelines.
/// Each tier applies a multiplier to all font sizes via AppFonts.
///
/// Reference sizes (Body text):
///   Small  = 15pt  — Power users who want information density
///   Medium = 16pt  — Apple HIG default, optimal for most users
///   Large  = 18pt  — Comfortable reading, recommended for extended use
///   XLarge = 20pt  — Accessibility-friendly, ideal for low-vision users
enum TextSize: String, CaseIterable, Identifiable {
    case small = "Small"
    case medium = "Medium"
    case large = "Large"
    case xLarge = "Extra Large"

    var id: String { rawValue }

    /// Scale factor applied to all font sizes.
    var scale: CGFloat {
        switch self {
        case .small:  return 0.9
        case .medium: return 1.0
        case .large:  return 1.12
        case .xLarge: return 1.25
        }
    }

    /// Human-readable description shown in the picker.
    var subtitle: String {
        switch self {
        case .small:  return "Compact — fits more on screen"
        case .medium: return "Default — balanced readability"
        case .large:  return "Comfortable — easier to read"
        case .xLarge: return "Accessibility — maximum clarity"
        }
    }

    /// SF Symbol for the picker.
    var icon: String {
        switch self {
        case .small:  return "textformat.size.smaller"
        case .medium: return "textformat.size"
        case .large:  return "textformat.size.larger"
        case .xLarge: return "textformat.size.larger"
        }
    }
}

/// Manages text size preference across the app. Works alongside ThemeManager.
@Observable
final class TextSizeManager {
    static let shared = TextSizeManager()

    private static let textSizeKey = "textSize"

    var selectedSize: TextSize {
        didSet {
            UserDefaults.standard.set(selectedSize.rawValue, forKey: Self.textSizeKey)
            sizeID = UUID()
        }
    }

    /// Changes on every size switch; use with `.id()` to force re-render if needed.
    var sizeID = UUID()

    private init() {
        let saved = UserDefaults.standard.string(forKey: Self.textSizeKey) ?? ""
        self.selectedSize = TextSize(rawValue: saved) ?? .medium
    }

    /// Returns the scaled font size.
    func scaled(_ size: CGFloat) -> CGFloat {
        (size * selectedSize.scale).rounded(.toNearestOrEven)
    }
}
