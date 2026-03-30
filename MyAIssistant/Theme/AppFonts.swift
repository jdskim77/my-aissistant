import SwiftUI

struct AppFonts {
    private static var scale: CGFloat {
        TextSizeManager.shared.selectedSize.scale
    }

    private static func scaled(_ size: CGFloat) -> CGFloat {
        (size * scale).rounded(.toNearestOrEven)
    }

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
}
