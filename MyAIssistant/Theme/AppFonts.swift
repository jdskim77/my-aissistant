import SwiftUI
import UIKit

struct AppFonts {
    private static var scale: CGFloat {
        TextSizeManager.shared.selectedSize.scale
    }

    /// Scales a point size by the app's TextSizeManager multiplier,
    /// then additionally respects the system-wide Dynamic Type setting
    /// via UIFontMetrics so that iOS Accessibility text sizes are honored.
    static func scaled(_ size: CGFloat) -> CGFloat {
        let appScale = size * scale
        return UIFontMetrics.default.scaledValue(for: appScale)
    }

    // MARK: - Primary type styles

    static func display(_ size: CGFloat) -> Font {
        .system(size: scaled(size), weight: .light, design: .serif)
    }

    static func displayBold(_ size: CGFloat) -> Font {
        .system(size: scaled(size), weight: .semibold, design: .serif)
    }

    static func heading(_ size: CGFloat) -> Font {
        .system(size: scaled(size), weight: .semibold, design: .rounded)
    }

    static func body(_ size: CGFloat = 16) -> Font {
        .system(size: scaled(size), weight: .regular, design: .rounded)
    }

    static func bodyMedium(_ size: CGFloat = 16) -> Font {
        .system(size: scaled(size), weight: .medium, design: .rounded)
    }

    static func caption(_ size: CGFloat = 13) -> Font {
        .system(size: scaled(size), weight: .regular, design: .rounded)
    }

    static func label(_ size: CGFloat = 12) -> Font {
        .system(size: scaled(size), weight: .semibold, design: .rounded)
    }

    // MARK: - Special-purpose helpers

    /// Monospaced font for timer displays and tabular data.
    static func mono(_ size: CGFloat) -> Font {
        .system(size: scaled(size), weight: .light, design: .monospaced)
    }

    /// Sized font for emoji / icon-only text (not SF Symbols).
    static func icon(_ size: CGFloat) -> Font {
        .system(size: scaled(size))
    }
}
