import SwiftUI

/// Renders the Thrivn app icon at full 1024×1024 size using the
/// ThrivnCompassMark vector. Use this view in Xcode previews to
/// experiment with background gradients and screenshot the result
/// for handing to a designer or testing different visual directions.
///
/// To export a high-resolution PNG:
/// 1. Open the #Preview canvas in Xcode
/// 2. Choose the variant you like
/// 3. Right-click → "Export Preview" → save as PNG at 1024×1024
/// 4. Hand the PNG to a designer for refinement, OR
/// 5. Drop it directly into Assets.xcassets/AppIcon.appiconset
///
/// The preview shows multiple background variants side-by-side
/// so you can pick the one with the strongest visual identity.
struct AppIconPreview: View {
    enum BackgroundStyle: String, CaseIterable, Identifiable {
        case solidIndigo = "Solid Indigo"
        case verticalGradient = "Vertical Gradient"
        case radialGlow = "Radial Glow"
        case diagonalDuotone = "Diagonal Duotone"
        case darkIndigo = "Dark Indigo"
        case cream = "Cream + Indigo Mark"

        var id: String { rawValue }
    }

    var style: BackgroundStyle = .verticalGradient
    var size: CGFloat = 1024

    var body: some View {
        ZStack {
            background

            // Compass mark — sized at ~58% of canvas (Apple recommends ~60%
            // of icon canvas for the visual centerpiece, with safe padding
            // around the edges so the rounded mask doesn't clip details).
            ThrivnCompassMark(
                color: markColor,
                size: size * 0.58,
                isAnimating: false
            )
        }
        .frame(width: size, height: size)
        // iOS app icons use a continuous corner with ~22.37% radius of size
        // (Apple's "squircle" superellipse). Approximated here.
        .clipShape(RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous))
    }

    @ViewBuilder
    private var background: some View {
        switch style {
        case .solidIndigo:
            Color(hex: "4F46E5")

        case .verticalGradient:
            LinearGradient(
                colors: [
                    Color(hex: "6366F1"), // indigo-500 (top — lighter)
                    Color(hex: "4338CA")  // indigo-700 (bottom — deeper)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

        case .radialGlow:
            ZStack {
                Color(hex: "1E1B4B") // indigo-950 base
                RadialGradient(
                    colors: [
                        Color(hex: "6366F1").opacity(0.9), // indigo-500 glow
                        Color(hex: "1E1B4B").opacity(0)
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: size * 0.55
                )
            }

        case .diagonalDuotone:
            LinearGradient(
                colors: [
                    Color(hex: "4F46E5"), // indigo-600
                    Color(hex: "7C3AED")  // violet-600
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

        case .darkIndigo:
            Color(hex: "1E1B4B") // indigo-950

        case .cream:
            Color(hex: "F8F7FB") // matches Indigo theme background
        }
    }

    /// Mark color contrasts with the chosen background.
    private var markColor: Color {
        switch style {
        case .cream:
            return Color(hex: "4F46E5") // indigo-600 mark on cream
        default:
            return .white                // white mark on all dark/colored bgs
        }
    }
}

// MARK: - Previews

/// Side-by-side comparison of all background styles at thumbnail size.
/// Use this to pick which background you want to commit to.
#Preview("All Variants — Thumbnail") {
    ScrollView {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
            ForEach(AppIconPreview.BackgroundStyle.allCases) { style in
                VStack(spacing: 8) {
                    AppIconPreview(style: style, size: 160)
                        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                    Text(style.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(20)
    }
    .background(Color(white: 0.95))
}

/// Single icon at full 1024×1024 (the actual export size).
/// Use this to screenshot for handing to a designer or testing on device.
#Preview("Full Size — Vertical Gradient (Recommended)") {
    AppIconPreview(style: .verticalGradient, size: 1024)
        .padding(40)
        .background(Color(white: 0.95))
}

#Preview("Full Size — Solid Indigo") {
    AppIconPreview(style: .solidIndigo, size: 1024)
        .padding(40)
        .background(Color(white: 0.95))
}

#Preview("Full Size — Radial Glow") {
    AppIconPreview(style: .radialGlow, size: 1024)
        .padding(40)
        .background(Color(white: 0.95))
}

#Preview("Full Size — Diagonal Duotone") {
    AppIconPreview(style: .diagonalDuotone, size: 1024)
        .padding(40)
        .background(Color(white: 0.95))
}

/// Realistic preview at actual home screen size (60×60pt).
/// This is what users will actually see on their phone — the most
/// important size to test for legibility.
#Preview("Home Screen Size (60×60pt)") {
    HStack(spacing: 16) {
        ForEach(AppIconPreview.BackgroundStyle.allCases) { style in
            VStack(spacing: 6) {
                AppIconPreview(style: style, size: 60)
                Text(style.rawValue)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .frame(width: 60)
                    .multilineTextAlignment(.center)
            }
        }
    }
    .padding(20)
    .background(Color(white: 0.92))
}
