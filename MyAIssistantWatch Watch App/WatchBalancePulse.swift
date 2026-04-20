#if os(watchOS)
import SwiftUI

// MARK: - Dimension descriptor
//
// Local to the Watch target — mirrors LifeDimension's icon/color identity
// without dragging in the full iOS model.

enum WatchDimension: String, CaseIterable, Identifiable {
    case body, mind, heart, spirit

    var id: Self { self }

    var icon: String {
        switch self {
        case .body:   return "figure.walk"    // V3: clearer silhouette
        case .mind:   return "lightbulb.fill" // V3: clearer than brain.head.profile
        case .heart:  return "heart.fill"
        case .spirit: return "sparkles"
        }
    }

    var color: Color {
        switch self {
        case .body:   return Color(red: 0.30, green: 0.69, blue: 0.31) // #4CAF50
        case .mind:   return Color(red: 0.13, green: 0.59, blue: 0.95) // #2196F3
        case .heart:  return Color(red: 0.91, green: 0.12, blue: 0.39) // #E91E63
        case .spirit: return Color(red: 0.61, green: 0.15, blue: 0.69) // #9C27B0
        }
    }

    var shortLabel: String {
        switch self {
        case .body:   return "Body"
        case .mind:   return "Mind"
        case .heart:  return "Heart"
        case .spirit: return "Spirit"
        }
    }

    /// Parse from iOS `LifeDimension.rawValue`. Accepts both the iOS source
    /// names ("physical", "mental", "emotional", "spiritual") and the watch
    /// short names ("body", "mind", ...) so any sync convention works.
    nonisolated static func from(rawValue raw: String) -> WatchDimension? {
        switch raw.lowercased() {
        case "physical", "body":     return .body
        case "mental", "mind":       return .mind
        case "emotional", "heart":   return .heart
        case "spiritual", "spirit":  return .spirit
        default:                     return nil
        }
    }
}

// MARK: - PreferenceKey for bar positions
//
// Each bar reports its center (in the Today view's named coordinate space)
// so the particle layer knows where to land. Container reads via
// onPreferenceChange and stashes a [WatchDimension: CGPoint] dictionary.

struct WatchDimensionPositionKey: PreferenceKey {
    static var defaultValue: [WatchDimension: CGPoint] = [:]
    static func reduce(
        value: inout [WatchDimension: CGPoint],
        nextValue: () -> [WatchDimension: CGPoint]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

/// Coordinate space name shared by source (checkbox) and target (bars).
let watchTodayCoordinateSpace = "WatchTodayCoord"

// MARK: - Pulse strip (Concept 3 / spec animation)
//
// Replaces the prior bloom+glow+label with the shared spec:
//   • Landing scale: 1.08× over 120ms then back over 180ms (spring 0.7)
//   • Saturation +15% bump during the pulse
//   • No glow halo, no "+N Body" label — those are decoration the spec drops
//
// The pulse is triggered via `pulseRequest` (set by WatchParticleAnimator
// on landing). We watch the request's token to re-fire on rapid repeats.

struct WatchBalancePulse: View {
    let bodyScore: Double?
    let mindScore: Double?
    let heartScore: Double?
    let spiritScore: Double?
    var pulseRequest: WatchPulseRequest? = nil

    @State private var activePulse: WatchDimension?
    @State private var pulseScale: CGFloat = 1.0
    @State private var saturationBoost: Double = 0
    @State private var settleTask: Task<Void, Never>?
    @State private var lastHandledToken: UUID?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Scaled metrics so the bars and icons grow with Dynamic Type instead
    // of staying as fixed pixel sizes that ignore the user's text setting.
    @ScaledMetric(relativeTo: .caption2) private var barWidth: CGFloat = 26
    @ScaledMetric(relativeTo: .caption2) private var barHeight: CGFloat = 50
    @ScaledMetric(relativeTo: .caption2) private var iconSize: CGFloat = 18

    private var hasAnyData: Bool {
        bodyScore != nil || mindScore != nil || heartScore != nil || spiritScore != nil
    }

    private var allDimensionsPresent: Bool {
        bodyScore != nil && mindScore != nil && heartScore != nil && spiritScore != nil
    }

    private func displayScore(for dim: WatchDimension) -> Double {
        switch dim {
        case .body:   return bodyScore ?? 0
        case .mind:   return mindScore ?? 0
        case .heart:  return heartScore ?? 0
        case .spirit: return spiritScore ?? 0
        }
    }

    private var harmony: Int {
        // V3 match to iOS — blend arith+geom on raw 0–10, then floor +
        // power curve to 30–100. Kept inline because LifeDimension and
        // HarmonyStage live only on the iOS target; the watch ingests the
        // pre-computed weekly dimension values and reapplies the formula.
        let present = [bodyScore, mindScore, heartScore, spiritScore].compactMap { $0 }
        guard !present.isEmpty else { return 30 }
        let mean = present.reduce(0, +) / Double(present.count)
        let product = present.reduce(1.0) { $0 * ($1 + 0.1) }
        let geom = pow(product, 1.0 / Double(present.count))
        let raw = max(0, min(10, 0.7 * mean + 0.3 * geom))
        let display = 30.0 + 70.0 * pow(raw / 10.0, 0.75)
        return Int(display.rounded())
    }

    /// Watch-side mirror of HarmonyStage. Enum + label/color duplicated
    /// because the Watch target doesn't import iOS models.
    private enum WatchHarmonyStage {
        case resting, growing, flowing, thriving, radiant

        static func from(display: Int) -> WatchHarmonyStage {
            switch display {
            case ...44:      return .resting
            case 45...59:    return .growing
            case 60...74:    return .flowing
            case 75...89:    return .thriving
            default:         return .radiant
            }
        }
        var label: String {
            switch self {
            case .resting:  return "Resting"
            case .growing:  return "Growing"
            case .flowing:  return "Flowing"
            case .thriving: return "Thriving"
            case .radiant:  return "Radiant"
            }
        }
        var color: Color {
            switch self {
            case .resting:  return Color(red: 0.72, green: 0.47, blue: 0.47) // dusty rose
            case .growing:  return Color(red: 0.78, green: 0.60, blue: 0.41) // sand
            case .flowing:  return Color(red: 0.37, green: 0.54, blue: 0.53) // teal
            case .thriving: return Color(red: 0.42, green: 0.56, blue: 0.45) // moss
            case .radiant:  return Color(red: 0.66, green: 0.57, blue: 0.35) // olive-gold
            }
        }
    }
    private var currentStage: WatchHarmonyStage {
        WatchHarmonyStage.from(display: harmony)
    }

    private var harmonyColor: Color {
        // V3: derive from the HarmonyStage band (mirrors iOS). With partial
        // data the score is still reported, but rendered in the muted sand
        // "Growing" tone until all four dims are present.
        guard allDimensionsPresent else {
            return WatchHarmonyStage.growing.color
        }
        return currentStage.color
    }

    var body: some View {
        VStack(spacing: 10) {
            header
            bars
        }
        // Header carries the summary; bars are individually focusable
        // (see `bar(for:)` accessibilityLabel) so VoiceOver users can step
        // through each dimension instead of hearing one combined blob.
        .onChange(of: pulseRequest?.token) { _, newToken in
            handlePulseRequest(newToken: newToken)
        }
        .onDisappear {
            settleTask?.cancel()
            settleTask = nil
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 4) {
            Spacer(minLength: 0)
            Text("Balance")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            if hasAnyData {
                Text("·")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text("\(harmony)")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(harmonyColor)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(harmony)))
                Text("/100")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                if !allDimensionsPresent {
                    Text("partial")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(headerAccessibilityLabel)
    }

    // MARK: Bars

    private var bars: some View {
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(WatchDimension.allCases) { dim in
                bar(for: dim)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func bar(for dim: WatchDimension) -> some View {
        let raw = displayScore(for: dim)
        let clamped = max(0, min(10, raw))
        let fraction = clamped / 10.0
        let isPulsing = activePulse == dim
        let scoreOpt = scoreOptional(for: dim)
        // Distinguish "no data" (nil score) from "score=0". A true zero
        // still renders the 3pt min-height fill; a nil score renders
        // nothing, so the empty track communicates "no reading yet"
        // instead of "scored zero."
        let hasData = scoreOpt != nil

        return VStack(spacing: 6) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: barWidth, height: barHeight)
                // Dashed top edge when the dim has no data — cues
                // "nothing to compare yet" without showing a solid stub.
                if !hasData {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(
                            dim.color.opacity(0.35),
                            style: StrokeStyle(lineWidth: 1, dash: [2, 2])
                        )
                        .frame(width: barWidth, height: barHeight)
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(dim.color)
                        .saturation(isPulsing ? 1.15 : 1.0)
                        .frame(width: barWidth, height: max(3, barHeight * fraction))
                        .animation(.spring(response: 0.55, dampingFraction: 0.75), value: fraction)
                }
            }
            .scaleEffect(isPulsing ? pulseScale : 1.0)
            // Anchor the bar's center for the particle target. Y-offset
            // approximates the colored fill's top so particles land where
            // the eye expects, not on the bottom of the track.
            .background(
                GeometryReader { geo in
                    let f = geo.frame(in: .named(watchTodayCoordinateSpace))
                    Color.clear.preference(
                        key: WatchDimensionPositionKey.self,
                        value: [dim: CGPoint(x: f.midX, y: f.midY)]
                    )
                }
            )

            Image(systemName: dim.icon)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(dim.color)
                .frame(height: iconSize)
        }
        // Per-bar accessibility — VoiceOver users can step through each
        // dimension instead of hearing one combined "Balance" blob.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(barAccessibilityLabel(dim: dim, score: scoreOpt))
    }

    private func scoreOptional(for dim: WatchDimension) -> Double? {
        switch dim {
        case .body:   return bodyScore
        case .mind:   return mindScore
        case .heart:  return heartScore
        case .spirit: return spiritScore
        }
    }

    private func barAccessibilityLabel(dim: WatchDimension, score: Double?) -> String {
        guard let score else { return "\(dim.shortLabel), no data" }
        return "\(dim.shortLabel), \(Int(score.rounded())) of 10"
    }

    // MARK: Pulse animation (spec)

    private func handlePulseRequest(newToken: UUID?) {
        guard let req = pulseRequest, let newToken, newToken != lastHandledToken else { return }
        lastHandledToken = newToken
        runLandingPulse(for: req.dimension)
    }

    private func runLandingPulse(for dim: WatchDimension) {
        settleTask?.cancel()
        activePulse = dim
        pulseScale = 1.0

        if reduceMotion {
            // Reduce Motion path: still bump saturation in place, skip the scale.
            withAnimation(.easeOut(duration: 0.12)) {
                saturationBoost = 0.15
            }
            settleTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.18)) {
                    saturationBoost = 0
                }
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled, activePulse == dim else { return }
                activePulse = nil
            }
            return
        }

        // Spec: scale to 1.08× over 120ms, return over 180ms (spring 0.7).
        // Saturation bumps during the same window.
        withAnimation(.spring(response: 0.12, dampingFraction: 0.7)) {
            pulseScale = 1.08
            saturationBoost = 0.15
        }
        settleTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.18, dampingFraction: 0.7)) {
                pulseScale = 1.0
                saturationBoost = 0
            }
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled, activePulse == dim else { return }
            activePulse = nil
        }
    }

    // MARK: Accessibility

    /// Header summary — terse so VoiceOver doesn't repeat per-bar values
    /// (which now live on each `bar(for:)` element).
    private var headerAccessibilityLabel: String {
        guard hasAnyData else { return "Balance, no data yet" }
        let suffix = allDimensionsPresent ? "" : ", partial"
        return "Balance \(harmony) of 100\(suffix)"
    }
}

// MARK: - AI pill (unchanged from prior pass; 44pt min height)

struct WatchAIPill<Destination: View>: View {
    let destination: Destination
    var dimmed: Bool = false

    init(dimmed: Bool = false, @ViewBuilder destination: () -> Destination) {
        self.dimmed = dimmed
        self.destination = destination()
    }

    var body: some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 7) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 14, weight: .semibold))
                Text("Tell me what to add")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.30, green: 0.69, blue: 0.31).opacity(dimmed ? 0.65 : 0.92),
                                Color(red: 0.18, green: 0.31, blue: 0.09).opacity(dimmed ? 0.65 : 0.92)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
            .shadow(
                color: Color(red: 0.43, green: 0.67, blue: 0.25).opacity(dimmed ? 0 : 0.35),
                radius: dimmed ? 0 : 10
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Tell AI what to add")
        .accessibilityHint("Opens voice chat to dictate a new task")
    }
}
#endif
