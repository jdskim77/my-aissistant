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
        // Gold + indigo variants — exploring the premium luxury direction
        case radialGoldPremium = "Radial Gold (Premium)"
        case solidIndigoGold = "Solid Indigo + Gold"
        case darkIndigoGold = "Dark Indigo + Gold"
        case verticalIndigoGold = "Vertical Gradient + Gold"
        case duotoneGold = "Diagonal Duotone + Gold"

        var id: String { rawValue }
    }

    var style: BackgroundStyle = .duotoneGold  // Variant #11 — production choice
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
                isAnimating: false,
                strokeColor: markStrokeColor,
                strokeWidth: markStrokeWidth,
                centerDotColor: centerDotColor,
                // App icons follow the "rule of one thing" — a single bold mark
                // on a colored background. Notion, Linear, Music, Calm, Things 3
                // all use a single silhouette with no internal element. The dot
                // creates visual noise at icon scale and reads like a "hole."
                hideCenterDot: true,
                // Thicker waist (0.45 vs default 0.32) gives the compass arms
                // visual weight — confident compass needle, not thin asterisk.
                waistRatio: 0.45,
                // Optical correction: compress vertical 3% / stretch horizontal 3%
                // to compensate for the eye's tendency to perceive vertical as
                // longer. The result feels visually balanced even though it's
                // mathematically asymmetric. Logo designers call this "optical
                // alignment" — see Apple logo, Spotify logo, Google G.
                verticalScale: 0.97,
                horizontalScale: 1.03
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
        case .solidIndigo, .solidIndigoGold:
            Color(hex: "4F46E5")

        case .verticalGradient, .verticalIndigoGold:
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

        case .diagonalDuotone, .duotoneGold:
            // More dramatic gradient — light indigo top-left → deep violet
            // bottom-right. Visible at small sizes and reads as "depth + magic".
            LinearGradient(
                colors: [
                    Color(hex: "818CF8"), // indigo-400 (top-left, lighter)
                    Color(hex: "5B21B6")  // violet-800 (bottom-right, deeper)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

        case .darkIndigo, .darkIndigoGold:
            Color(hex: "1E1B4B") // indigo-950

        case .cream:
            Color(hex: "F8F7FB") // matches Indigo theme background

        case .radialGoldPremium:
            // Deep radial glow: indigo-500 center fading to indigo-950 edges
            ZStack {
                Color(hex: "1E1B4B") // indigo-950 base
                RadialGradient(
                    colors: [
                        Color(hex: "6366F1").opacity(0.95), // indigo-500 inner glow
                        Color(hex: "4338CA").opacity(0.40), // indigo-700 mid
                        Color(hex: "1E1B4B").opacity(0)     // fully transparent at edge
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: size * 0.55
                )
            }
        }
    }

    /// All gold variants share the same gold mark + subtle stroke recipe.
    /// Lets us explore which background pairs best with the premium gold treatment.
    private var isGoldVariant: Bool {
        switch style {
        case .radialGoldPremium, .solidIndigoGold, .darkIndigoGold,
             .verticalIndigoGold, .duotoneGold:
            return true
        default:
            return false
        }
    }

    /// Mark color contrasts with the chosen background.
    private var markColor: Color {
        if style == .cream {
            return Color(hex: "4F46E5")     // indigo-600 mark on cream
        }
        if isGoldVariant {
            // Champagne gold (#E8C77F) — desaturated, warm, premium.
            // Replaces the previous bright amber-300 (#FCD34D) which read as
            // "school-bus yellow" / playful. Champagne reads as antique compass
            // face, brushed brass, premium luxury. This is the same tone used
            // by university crest gold leaf and high-end watch faces.
            return Color(hex: "E8C77F")
        }
        return .white                        // white mark on all dark/colored bgs
    }

    /// Optional stroke color — applied to all gold variants for edge definition.
    private var markStrokeColor: Color? {
        isGoldVariant ? Color.white.opacity(0.20) : nil
    }

    /// Stroke width — scales with canvas size so it stays proportional.
    /// 4pt at 1024×1024 = ~visible edge at all sizes.
    private var markStrokeWidth: CGFloat {
        isGoldVariant ? max(1, size / 1024 * 4) : 0
    }

    /// Center dot color — for gold variants, the dot becomes a deep indigo
    /// accent that visually anchors against the gold star body. Without this
    /// override the dot is the same color as the star and disappears.
    private var centerDotColor: Color? {
        isGoldVariant ? Color(hex: "1E1B4B") : nil  // indigo-950 — sharp contrast on gold
    }
}

// MARK: - Gallery (runtime view for picking icon variants on-device)

/// Scrollable gallery showing every AppIconPreview variant at multiple sizes.
/// Wired into SettingsView temporarily so you can pick the winning icon
/// directly on the simulator/device without waiting for Xcode previews to render.
/// Remove the SettingsView NavigationLink once the icon is finalized.
struct AppIconPreviewGallery: View {
    @State private var exportedURL: URL?
    @State private var showExportShare = false
    @State private var exportError: String?

    /// The chosen production icon — variant #11.
    private let productionStyle: AppIconPreview.BackgroundStyle = .duotoneGold

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                // PRODUCTION CHOICE — Variant #11
                VStack(spacing: 12) {
                    Text("Production Icon — Variant #11")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(productionStyle.rawValue)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    AppIconPreview(style: productionStyle, size: 280)
                        .shadow(color: .black.opacity(0.18), radius: 12, y: 6)

                    Button {
                        exportIconAsPNG()
                    } label: {
                        Label("Export 1024×1024 PNG", systemImage: "square.and.arrow.up")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    Text("Tap export, then tap the share button that appears to save to Photos or Files. Use the saved PNG to replace `app-icon-1024.png` in `Assets.xcassets/AppIcon.appiconset/`.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.accentColor.opacity(0.08))
                )
                .padding(.horizontal)

                Divider().padding(.vertical, 8)

                // Section 1: Hero (large, one per row)
                Text("All Variants (1024×1024 rendered at 280pt)")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)

                ForEach(AppIconPreview.BackgroundStyle.allCases) { style in
                    VStack(spacing: 8) {
                        AppIconPreview(style: style, size: 280)
                            .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
                        Text(style.rawValue)
                            .font(.subheadline.weight(.medium))
                    }
                    .padding(.horizontal)
                }

                Divider().padding(.vertical, 8)

                // Section 2: Home screen size realism check
                Text("Home Screen Size (60×60pt) — what users will actually see")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 90))],
                    spacing: 16
                ) {
                    ForEach(AppIconPreview.BackgroundStyle.allCases) { style in
                        VStack(spacing: 6) {
                            AppIconPreview(style: style, size: 60)
                            Text(style.rawValue)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .frame(width: 80)
                        }
                    }
                }
                .padding(.horizontal)

                Spacer(minLength: 40)
            }
            .padding(.vertical, 20)
        }
        .navigationTitle("App Icon Preview")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showExportShare) {
            if let url = exportedURL {
                IconShareSheet(items: [url])
            }
        }
        .alert("Export Failed", isPresented: .init(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
    }

    /// Renders the production icon to a 1024×1024 PNG and saves it
    /// to Documents/, then opens a share sheet so the user can save
    /// it to Photos or Files. The PNG can be dropped into
    /// Assets.xcassets/AppIcon.appiconset/ to replace the current icon.
    @MainActor
    private func exportIconAsPNG() {
        let iconView = AppIconPreview(style: productionStyle, size: 1024)
            .frame(width: 1024, height: 1024)

        let renderer = ImageRenderer(content: iconView)
        renderer.scale = 1.0  // Render at exact 1024×1024 (not Retina-multiplied)

        guard let uiImage = renderer.uiImage else {
            exportError = "Failed to render icon view"
            return
        }
        guard let pngData = uiImage.pngData() else {
            exportError = "Failed to convert to PNG"
            return
        }

        let fileName = "thrivn-app-icon-\(Int(Date().timeIntervalSince1970)).png"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            try pngData.write(to: url)
            exportedURL = url
            showExportShare = true
        } catch {
            exportError = "Failed to save: \(error.localizedDescription)"
        }
    }
}

// MARK: - Share Sheet Wrapper

private struct IconShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
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

#Preview("Full Size — Radial Glow + Gold (Premium)") {
    AppIconPreview(style: .radialGoldPremium, size: 1024)
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
