import SwiftUI

/// Simplified Thrivn brand mark — a compass derived from the full
/// Mind/Body/Heart/Soul Venn logo. Used at small sizes (AI button,
/// app icon, watch complication) where the full Venn diagram becomes
/// unreadable. Pure SwiftUI vector, theme-aware, scales perfectly.
///
/// The mark is a 4-pointed compass star (one point per life dimension)
/// with a small center dot representing the user — the intersection
/// of all four dimensions, just like the original logo.
struct ThrivnCompassMark: View {
    /// Color of the compass star strokes/fills.
    var color: Color = .accentColor

    /// Size of the rendered mark (square frame).
    var size: CGFloat = 44

    /// When true, shows an animated orbit ring (use during AI processing).
    var isAnimating: Bool = false

    /// Optional stroke around the compass star outline.
    /// Set to nil for no stroke (default — used in chat button + small contexts).
    /// Used by the premium app icon variant for refined edge definition.
    var strokeColor: Color? = nil
    var strokeWidth: CGFloat = 0

    /// Optional override for the center dot color.
    /// When nil (default), the dot uses the same color as the star — looks like
    /// part of the star body. When set, the dot becomes a contrasting accent
    /// (e.g. darker indigo dot inside a gold star for the app icon).
    var centerDotColor: Color? = nil

    /// When true, hides the center dot entirely. Used by the app icon variants
    /// where a dot inside the star creates visual noise at icon scale.
    /// The chat button keeps the dot for personality at small sizes.
    var hideCenterDot: Bool = false

    @State private var orbitRotation: Double = 0
    @State private var pulseScale: CGFloat = 1.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // 1. Animated orbit ring (only visible when isAnimating)
            if isAnimating && !reduceMotion {
                Circle()
                    .trim(from: 0, to: 0.25)
                    .stroke(
                        color.opacity(0.8),
                        style: StrokeStyle(lineWidth: size * 0.045, lineCap: .round)
                    )
                    .frame(width: size * 0.92, height: size * 0.92)
                    .rotationEffect(.degrees(orbitRotation))
                    .onAppear {
                        withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                            orbitRotation = 360
                        }
                    }
                    .onDisappear { orbitRotation = 0 }
            }

            // 2. The compass mark itself — 4-point star (Mind/Body/Heart/Soul)
            // Optionally stroked when strokeColor is set (premium icon variant).
            ZStack {
                CompassStarShape()
                    .fill(color)
                if let strokeColor, strokeWidth > 0 {
                    CompassStarShape()
                        .stroke(strokeColor, lineWidth: strokeWidth)
                }
            }
            .frame(width: size * 0.62, height: size * 0.62)
            .scaleEffect(isAnimating && !reduceMotion ? pulseScale : 1.0)
            .onAppear {
                if isAnimating && !reduceMotion {
                    withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                        pulseScale = 1.08
                    }
                }
            }

            // 3. Center dot — the user / "you are here" anchor
            // Uses centerDotColor when set, otherwise the star color (invisible
            // inside the star body — fine for small button contexts).
            // hideCenterDot suppresses it entirely (used by app icon variants).
            if !hideCenterDot {
                Circle()
                    .fill(centerDotColor ?? color)
                    .frame(width: size * 0.13, height: size * 0.13)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true) // Decorative — parent view should label
    }
}

// MARK: - 4-Point Compass Star Shape

/// A 4-pointed star where each point represents one of the life dimensions
/// (Mind, Body, Heart, Soul). The narrow waist between points creates
/// the iconic compass-needle silhouette.
private struct CompassStarShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = min(rect.width, rect.height) / 2
        let innerRadius = outerRadius * 0.32 // Controls "waist" thickness

        // Generate 8 vertices: alternating outer point + inner waist
        // Starting from top (12 o'clock), going clockwise.
        let points = (0..<8).map { i -> CGPoint in
            let angle = (Double(i) * .pi / 4) - (.pi / 2) // Start at top
            let radius = i.isMultiple(of: 2) ? outerRadius : innerRadius
            return CGPoint(
                x: center.x + radius * CGFloat(cos(angle)),
                y: center.y + radius * CGFloat(sin(angle))
            )
        }

        path.move(to: points[0])
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        path.closeSubpath()

        return path
    }
}

// MARK: - Preview

#Preview("Static states") {
    HStack(spacing: 24) {
        VStack {
            ThrivnCompassMark(color: .accentColor, size: 44, isAnimating: false)
            Text("Idle").font(.caption)
        }
        VStack {
            ThrivnCompassMark(color: .accentColor, size: 44, isAnimating: true)
            Text("Processing").font(.caption)
        }
        VStack {
            ThrivnCompassMark(color: .white, size: 44, isAnimating: false)
                .padding()
                .background(Color.accentColor)
                .cornerRadius(22)
            Text("On accent bg").font(.caption)
        }
    }
    .padding()
}

#Preview("Sizes") {
    HStack(spacing: 16) {
        ThrivnCompassMark(size: 24)
        ThrivnCompassMark(size: 44)
        ThrivnCompassMark(size: 80)
        ThrivnCompassMark(size: 120)
    }
    .padding()
}
