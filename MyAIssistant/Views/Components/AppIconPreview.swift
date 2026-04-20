import SwiftUI

/// Renders the Thrivn app icon at full 1024×1024 size. Use this view in Xcode
/// previews to experiment with background gradients and screenshot the result
/// for handing to a designer or testing different visual directions.
struct AppIconPreview: View {
    enum BackgroundStyle: String, CaseIterable, Identifiable {
        // Compass-mark variants (kept directions)
        case verticalGradient   = "Vertical Gradient"
        case radialGlow         = "Radial Glow"
        case verticalIndigoGold = "Vertical Gradient + Gold"

        // Venn + glow combos — 4 new concepts
        case vennOnVerticalGradientAmberCore = "Venn — Vertical Gradient + Amber Core"
        case vennOnVerticalGradientLayered   = "Venn — Vertical Gradient + Layered Glow"
        case vennOnDiagonalDuotoneAmberCore  = "Venn — Diagonal Duotone + Amber Core"
        case vennOnDiagonalDuotoneLayered    = "Venn — Diagonal Duotone + Layered Glow"

        var id: String { rawValue }

        var isVennVariant: Bool {
            rawValue.hasPrefix("Venn")
        }
    }

    var style: BackgroundStyle = .vennOnVerticalGradientLayered
    var size: CGFloat = 1024

    var body: some View {
        ZStack {
            background

            if style.isVennVariant {
                ThrivnVennMark(
                    backgroundIsDark: true,
                    size: size * 0.78
                )
                centerGlowOverlay
            } else {
                ThrivnCompassMark(
                    color: markColor,
                    size: size * 0.58,
                    isAnimating: false,
                    strokeColor: markStrokeColor,
                    strokeWidth: markStrokeWidth,
                    centerDotColor: centerDotColor,
                    hideCenterDot: true,
                    waistRatio: 0.45,
                    verticalScale: 0.97,
                    horizontalScale: 1.03
                )
            }
        }
        .frame(width: size, height: size)
        // iOS app icons use a continuous corner with ~22.37% radius of size.
        .clipShape(RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous))
    }

    /// Glow treatment drawn over the venn mark. `.screen` blend so it
    /// additively brightens the intersection region.
    @ViewBuilder
    private var centerGlowOverlay: some View {
        let glowDiameter = size * 0.30

        switch style {
        case .vennOnVerticalGradientAmberCore, .vennOnDiagonalDuotoneAmberCore:
            RadialGradient(
                colors: [Color(hex: "FCD34D").opacity(0.80), Color(hex: "FCD34D").opacity(0)],
                center: .center,
                startRadius: 0,
                endRadius: glowDiameter / 2
            )
            .frame(width: glowDiameter, height: glowDiameter)
            .blendMode(.screen)

        case .vennOnVerticalGradientLayered, .vennOnDiagonalDuotoneLayered:
            RadialGradient(
                colors: [
                    Color.white.opacity(0.75),
                    Color(hex: "FCD34D").opacity(0.55),
                    Color(hex: "F59E0B").opacity(0)
                ],
                center: .center,
                startRadius: 0,
                endRadius: glowDiameter / 2
            )
            .frame(width: glowDiameter, height: glowDiameter)
            .blendMode(.screen)

        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var background: some View {
        switch style {
        case .verticalGradient, .verticalIndigoGold,
             .vennOnVerticalGradientAmberCore, .vennOnVerticalGradientLayered:
            // V2 palette (indigo-400 → indigo-600). Bumped up 100 steps on the
            // Tailwind indigo scale from the original 500 → 700 because the
            // deployed PNG read too dark on Home Screens next to typical
            // saturated app icons.
            LinearGradient(
                colors: [
                    Color(hex: "818CF8"), // indigo-400 (top)
                    Color(hex: "4F46E5")  // indigo-600 (bottom)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

        case .radialGlow:
            ZStack {
                Color(hex: "1E1B4B") // indigo-950 base
                RadialGradient(
                    colors: [
                        Color(hex: "6366F1").opacity(0.9),
                        Color(hex: "1E1B4B").opacity(0)
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: size * 0.55
                )
            }

        case .vennOnDiagonalDuotoneAmberCore, .vennOnDiagonalDuotoneLayered:
            LinearGradient(
                colors: [
                    Color(hex: "818CF8"), // indigo-400 (top-left)
                    Color(hex: "5B21B6")  // violet-800 (bottom-right)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var isGoldVariant: Bool {
        style == .verticalIndigoGold
    }

    private var markColor: Color {
        isGoldVariant ? Color(hex: "E8C77F") : .white
    }

    private var markStrokeColor: Color? {
        isGoldVariant ? Color.white.opacity(0.20) : nil
    }

    private var markStrokeWidth: CGFloat {
        isGoldVariant ? max(1, size / 1024 * 4) : 0
    }

    private var centerDotColor: Color? {
        isGoldVariant ? Color(hex: "1E1B4B") : nil
    }
}

// MARK: - Venn Diagram Mark

/// A 4-circle Venn diagram representing Mind / Body / Heart / Soul
/// intersecting at center — the "ikigai sweet spot."
struct ThrivnVennMark: View {
    let backgroundIsDark: Bool
    let size: CGFloat
    /// When true, renders with `.normal` blend mode and higher opacity so the
    /// exported PNG works on any background.
    var standalone: Bool = false

    var body: some View {
        let circleRadius = size * 0.32
        let offset = size * 0.18

        ZStack {
            circle(color: mindColor).offset(y: -offset)
            circle(color: bodyColor).offset(x: offset)
            circle(color: heartColor).offset(y: offset)
            circle(color: soulColor).offset(x: -offset)
        }
        .frame(width: circleRadius * 2, height: circleRadius * 2)
        .compositingGroup()
    }

    @ViewBuilder
    private func circle(color: Color) -> some View {
        let circleRadius = size * 0.32
        Circle()
            .fill(color.opacity(standalone ? 0.75 : (backgroundIsDark ? 0.65 : 0.55)))
            .frame(width: circleRadius * 2, height: circleRadius * 2)
            .blendMode(standalone ? .normal : (backgroundIsDark ? .screen : .multiply))
    }

    private var mindColor: Color {
        backgroundIsDark ? Color(hex: "60A5FA") : Color(hex: "3B82F6")
    }

    private var bodyColor: Color {
        backgroundIsDark ? Color(hex: "F87171") : Color(hex: "EF4444")
    }

    private var heartColor: Color {
        backgroundIsDark ? Color(hex: "F472B6") : Color(hex: "EC4899")
    }

    private var soulColor: Color {
        backgroundIsDark ? Color(hex: "FCD34D") : Color(hex: "F59E0B")
    }
}

// MARK: - Gallery

/// Scrollable gallery showing every AppIconPreview variant at multiple sizes.
struct AppIconPreviewGallery: View {
    @State private var exportedURL: URL?
    @State private var showExportShare = false
    @State private var exportError: String?

    private let productionStyle: AppIconPreview.BackgroundStyle = .vennOnVerticalGradientLayered

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 12) {
                    Text("Production Icon")
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
                        Label("Export App Icon (1024×1024, opaque)", systemImage: "app")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    Button {
                        exportTransparentLogoPNG()
                    } label: {
                        Label("Export Logo (1024×1024, transparent)", systemImage: "circle.dotted")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.accentColor.opacity(0.15))
                            .foregroundStyle(Color.accentColor)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    Text("**App Icon**: opaque PNG for iPhone + Watch icon slots.\n**Logo**: transparent PNG of the Venn mark alone — use in-app, onboarding, website, marketing.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.accentColor.opacity(0.08)))
                .padding(.horizontal)

                Divider().padding(.vertical, 8)

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

                Text("Home Screen Size (60×60pt)")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], spacing: 16) {
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

    @MainActor
    private func exportTransparentLogoPNG() {
        let logoView = ThrivnVennMark(backgroundIsDark: false, size: 1024 * 0.78, standalone: true)
            .frame(width: 1024, height: 1024)

        let renderer = ImageRenderer(content: logoView)
        renderer.scale = 1.0

        guard let uiImage = renderer.uiImage else {
            exportError = "Failed to render logo view"
            return
        }
        guard let pngData = uiImage.pngData() else {
            exportError = "Failed to convert to PNG"
            return
        }

        let fileName = "thrivn-logo-transparent-\(Int(Date().timeIntervalSince1970)).png"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            try pngData.write(to: url)
            exportedURL = url
            showExportShare = true
        } catch {
            exportError = "Failed to save: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func exportIconAsPNG() {
        let iconView = AppIconPreview(style: productionStyle, size: 1024)
            .frame(width: 1024, height: 1024)

        let renderer = ImageRenderer(content: iconView)
        renderer.scale = 1.0

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

#Preview("Full Size — Vertical Gradient") {
    AppIconPreview(style: .verticalGradient, size: 1024)
        .padding(40)
        .background(Color(white: 0.95))
}

#Preview("Full Size — Radial Glow") {
    AppIconPreview(style: .radialGlow, size: 1024)
        .padding(40)
        .background(Color(white: 0.95))
}

#Preview("Full Size — Vertical Gradient + Gold") {
    AppIconPreview(style: .verticalIndigoGold, size: 1024)
        .padding(40)
        .background(Color(white: 0.95))
}

#Preview("Full Size — Venn + Vertical Gradient + Layered Glow") {
    AppIconPreview(style: .vennOnVerticalGradientLayered, size: 1024)
        .padding(40)
        .background(Color(white: 0.95))
}

#Preview("Full Size — Venn + Diagonal Duotone + Amber Core") {
    AppIconPreview(style: .vennOnDiagonalDuotoneAmberCore, size: 1024)
        .padding(40)
        .background(Color(white: 0.95))
}

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
