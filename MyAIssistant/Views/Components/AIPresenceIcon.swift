import SwiftUI

/// Thrivn AI presence mark — a theme-adaptive "puck" containing four
/// translucent True-Thrivn-colored petals (blue / red / lavender / yellow)
/// at N/E/S/W with a white 4-point sparkle on top.
///
/// The surrounding puck gives the mark a proper button affordance. Surface
/// and border adapt to `colorScheme` and `colorSchemeContrast` so the mark
/// reads on cream, white, and OLED-black tab bars, and respects Increase
/// Contrast accessibility settings.
///
/// **Shadow is intentionally NOT baked in.** Callers apply their own shadow
/// AFTER any `.scaleEffect`, so pulsing animations don't drag a wobbly
/// shadow around with them.
///
/// Designed for use at ≥ 36pt.
struct AIPresenceIcon: View {
    var size: CGFloat = 44

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        // Inner mark area is ~86.4% of the puck — leaves a small margin
        // between the petals and the puck edge.
        let innerScale: CGFloat = 0.864
        let inner = size * innerScale
        let circleRadius = inner * 0.25
        let offset       = inner * 0.205
        let sparkleSize  = inner * 0.50
        let sparkleShadowRadius = max(1.0, size * 0.035)
        let puckRadius   = size * 0.455

        ZStack {
            Circle()
                .fill(puckFill)
                .frame(width: puckRadius * 2, height: puckRadius * 2)
                .overlay(
                    Circle()
                        .stroke(puckGradientStroke, lineWidth: puckStrokeWidth)
                )

            Circle().fill(BrandColors.petalTop.opacity(BrandColors.petalAlpha))
                .frame(width: circleRadius * 2, height: circleRadius * 2)
                .offset(y: -offset)
            Circle().fill(BrandColors.petalRight.opacity(BrandColors.petalAlpha))
                .frame(width: circleRadius * 2, height: circleRadius * 2)
                .offset(x: offset)
            Circle().fill(BrandColors.petalBottom.opacity(BrandColors.petalAlpha))
                .frame(width: circleRadius * 2, height: circleRadius * 2)
                .offset(y: offset)
            Circle().fill(BrandColors.petalLeft.opacity(BrandColors.petalAlpha))
                .frame(width: circleRadius * 2, height: circleRadius * 2)
                .offset(x: -offset)

            SparkleMark()
                .fill(Color.white)
                .frame(width: sparkleSize, height: sparkleSize)
                .shadow(color: Color.black.opacity(0.22), radius: sparkleShadowRadius, x: 0, y: 0)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    // MARK: - Theme adaptation

    private var puckFill: Color {
        colorScheme == .dark
            ? Color(red: 0.13, green: 0.13, blue: 0.16) // elevated ink — not pure black, so petals don't "float"
            : Color.white
    }

    /// Increased-contrast fallback: solid colour as before.
    private var puckStrokeFallback: Color {
        if colorScheme == .dark {
            return Color.white.opacity(contrast == .increased ? 0.55 : 0.14)
        }
        return contrast == .increased ? Color.black.opacity(0.35) : BrandColors.puckBorder
    }

    /// Normal contrast in light mode: vertical gradient, white-top to
    /// cream-bottom (iteration 6 from the design review). Dark mode and
    /// increased contrast fall back to the solid colour so legibility
    /// targets are always met.
    private var puckGradientStroke: AnyShapeStyle {
        if colorScheme == .light && contrast != .increased {
            return AnyShapeStyle(LinearGradient(
                colors: [.white.opacity(0.9), BrandColors.puckBorder.opacity(0.5)],
                startPoint: .top,
                endPoint: .bottom
            ))
        }
        return AnyShapeStyle(puckStrokeFallback)
    }

    private var puckStrokeWidth: CGFloat {
        contrast == .increased ? 2 : 0.75
    }
}

/// Brand-fixed color constants for the AI presence mark. Kept private to
/// this file for now; promote to a shared `BrandColors` namespace when a
/// second consumer (app icon in SwiftUI, Venn mark, etc.) needs them.
private enum BrandColors {
    static let petalTop    = Color(red: 0.290, green: 0.565, blue: 0.886) // #4A90E2
    static let petalRight  = Color(red: 0.910, green: 0.365, blue: 0.365) // #E85D5D
    static let petalBottom = Color(red: 0.722, green: 0.608, blue: 0.910) // #B89BE8
    static let petalLeft   = Color(red: 0.961, green: 0.784, blue: 0.259) // #F5C842
    static let puckBorder  = Color(red: 0.941, green: 0.929, blue: 0.910) // #F0EDE8
    static let petalAlpha: CGFloat = 0.78
}

/// Four-point sparkle drawn as a path so it scales crisply at any size.
private struct SparkleMark: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let cx = rect.midX
        let cy = rect.midY
        let armV = h * 0.50
        let armH = w * 0.50
        let waist = w * 0.075

        var p = Path()
        p.move(to: CGPoint(x: cx,         y: cy - armV))
        p.addLine(to: CGPoint(x: cx + waist, y: cy - waist))
        p.addLine(to: CGPoint(x: cx + armH,  y: cy))
        p.addLine(to: CGPoint(x: cx + waist, y: cy + waist))
        p.addLine(to: CGPoint(x: cx,         y: cy + armV))
        p.addLine(to: CGPoint(x: cx - waist, y: cy + waist))
        p.addLine(to: CGPoint(x: cx - armH,  y: cy))
        p.addLine(to: CGPoint(x: cx - waist, y: cy - waist))
        p.closeSubpath()
        return p
    }
}

#Preview {
    VStack(spacing: 24) {
        AIPresenceIcon(size: 88)
        AIPresenceIcon(size: 60)
        AIPresenceIcon(size: 44)
        AIPresenceIcon(size: 36)
    }
    .padding(40)
    .background(Color(red: 0.973, green: 0.961, blue: 0.941))
}
