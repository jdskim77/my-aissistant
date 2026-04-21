import SwiftUI

/// Home-screen Life Balance card (V3) — "today's momentum" surface.
///
/// Each of the 4 scored dimensions has a vertical bar that fills with the
/// day's tagged-task effort points (0 → 100% = daily target). A 2pt horizontal
/// "tick" notch marks yesterday's same-dimension contribution so the user can
/// see at a glance whether today is tracking above / below yesterday. The
/// tick's visual weight ramps with time of day (whisper at 6 AM → clear at
/// 8 PM) so a 0 bar in the morning never feels punishing.
///
/// Pillar alignment: Pillar 3 (whole-life balance) visualizes the four
/// dimensions; Pillar 1 (daily ritual) gets reinforced by the four-tier
/// deposit animation — every completion registers (Tier 1 elastic bump),
/// crossing yesterday's tick is celebrated (Tier 2 shimmer), hitting daily
/// target pulses (Tier 3 ring), each overflow compounds the glow (Tier 4).
struct BalancePulseCard: View {

    // MARK: - Data inputs

    /// Today's fill per dimension on a 0.0–1.0+ scale (>1.0 = overflow).
    /// Comes from `BalanceManager.todayFill(for:)`.
    let todayFill: [LifeDimension: Double]
    /// Today's raw effort points per dimension. Rendered under each bar as
    /// "X/target" so the user can read the value, not just the fill height.
    /// Optional for existing callers / previews — falls back to fill × target.
    var todayPoints: [LifeDimension: Double] = [:]
    /// Yesterday's tick position per dimension (0.0–1.0), nil when the user
    /// had no activity in the past 7 days (tick is hidden). Sourced from
    /// `BalanceManager.yesterdayTickValue(for:)`.
    let yesterdayTick: [LifeDimension: Double?]
    /// Representative daily target (points) to display under the bars.
    /// Sourced from `BalanceManager.dailyTarget(for:)`; defaults to 4 when
    /// the host doesn't supply one so the caption stays readable.
    var dailyTarget: Int = 4
    /// Display score (30–100, V3-floored). Driven by `BalanceManager.harmonyScore()`.
    let harmonyScore: Int
    /// Current stage derived from the display score. Supplies label + color
    /// for the header and the leaf icon.
    let stage: HarmonyStage
    /// Whether the user has enough real data for a meaningful score.
    /// When false the bars render as staggered breathing pulses and the
    /// stage label is suppressed.
    var hasData: Bool
    /// Pulse signal from `ParticleAnimator` — fires when a particle lands.
    /// Token-keyed so rapid same-dimension pulses re-fire instead of
    /// collapsing. Drives the collapsed-state border flash.
    var flightPulse: ParticlePulseRequest? = nil
    /// Optional wisdom quote rendered as a small italic tagline below the
    /// bars. Replaces the standalone Wisdom card on Home.
    var tagline: (text: String, author: String)? = nil
    /// Optional callback to open the Compass tab from the footer link.
    var onTapCompass: (() -> Void)? = nil

    // MARK: - Persisted state

    /// Collapse state remembered across sessions. Expanded by default so
    /// first-launch users see the whole card.
    @AppStorage("home.lifeBalance.expanded") private var isExpanded: Bool = true

    // MARK: - Pulse animation state (per-dimension)

    /// Per-dim transient "crossed yesterday's tick" flag — drives the
    /// shimmer sweep. Set on detection, cleared after the shimmer duration.
    @State private var crossedDims: Set<LifeDimension> = []
    /// Per-dim transient "just hit 100%" flag — drives the concentric ring
    /// pulse. Set on detection, cleared after the ring animation.
    @State private var goalHitDims: Set<LifeDimension> = []
    /// Per-dim "elastic bump" pulse scale, set to 1.08 on fill change then
    /// animated back to 1.0. One-shot; doesn't persist.
    @State private var bumpScale: [LifeDimension: CGFloat] = [:]
    /// Cached previous fill values so an `onChange` can detect crossing /
    /// goal-hit transitions. Keyed by dim, initialized from `todayFill`
    /// on first appear so a pre-populated state doesn't replay yesterday's
    /// pulses on view (re)mount.
    @State private var previousFills: [LifeDimension: Double] = [:]
    /// Tracking handles for the Tier-1/2/3 reset Tasks so `.onDisappear`
    /// can cancel any in-flight cleanup. Without this, tab switching
    /// mid-animation leaves `bumpScale` / `crossedDims` / `goalHitDims`
    /// state mutations running against a view already torn down.
    @State private var tierResetTasks: [Task<Void, Never>] = []

    // MARK: - Collapsed-state border flash

    /// When the card is collapsed, the bar animations are invisible. The
    /// card itself briefly flashes its border in the dimension's color so
    /// the user still gets a "something happened" hint on completion.
    @State private var collapsedFlashOpacity: Double = 0
    @State private var collapsedFlashColor: Color = .clear
    @State private var collapsedFlashTask: Task<Void, Never>?
    @State private var lastCollapsedFlashToken: UUID?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Derived

    private var sortedDimensions: [LifeDimension] {
        LifeDimension.scored.sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Time-of-day opacity for the yesterday tick. Whisper at 4 AM, full
    /// at 8 PM. Formula: `0.15 + 0.40 · clamp((hour − 4) / 16, 0, 1)`.
    /// Solves the "tick at top of bar at 10 AM feels like failure" problem
    /// — morning users barely see the tick; evening users see it clearly.
    private var tickOpacity: Double {
        let hour = Double(Calendar.current.component(.hour, from: Date()))
        let fraction = max(0, min(1, (hour - 4) / 16))
        return 0.15 + 0.40 * fraction
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 12) {
            header

            if isExpanded {
                if hasData {
                    bars
                } else {
                    emptyBars
                }

                if let tagline {
                    taglineView(tagline)
                }

                if let onTapCompass {
                    openCompassLink(onTapCompass)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(AppColors.card)
                .shadow(color: Color.black.opacity(0.04), radius: 6, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppColors.accent.opacity(0.10), lineWidth: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(collapsedFlashColor, lineWidth: 1.5)
                .opacity(collapsedFlashOpacity)
                .animation(.easeInOut(duration: 0.2), value: collapsedFlashColor)
                .allowsHitTesting(false)
        )
        .onAppear {
            // Seed previousFills so the first onChange doesn't retroactively
            // fire crossing/goal animations for data that was already there.
            for dim in LifeDimension.scored {
                previousFills[dim] = todayFill[dim] ?? 0
            }
            lastCollapsedFlashToken = flightPulse?.token
        }
        .onChange(of: flightPulse?.token) { _, newToken in
            handleCollapsedFlash(newToken: newToken)
        }
        .onDisappear {
            // Cancel any Tier-1/2/3 reset Tasks in flight so they don't
            // mutate state on a torn-down view. Also cancel the collapsed
            // flash Task for the same reason.
            tierResetTasks.forEach { $0.cancel() }
            tierResetTasks.removeAll()
            collapsedFlashTask?.cancel()
            collapsedFlashTask = nil
        }
    }

    // MARK: - Header

    private var header: some View {
        Button {
            Haptics.light()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isExpanded.toggle()
            }
        } label: {
            headerLabel
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(hasData
            ? "Today's momentum, harmony \(stage.label) \(harmonyScore) out of 100"
            : "Today's momentum, no data yet")
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
        .accessibilityHint("Double tap to \(isExpanded ? "collapse" : "expand")")
        .accessibilityAddTraits(.isHeader)
    }

    private var headerLabel: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "circle.grid.cross")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(hasData ? stage.color : AppColors.textMuted)
                Text("TODAY'S MOMENTUM")
                    .font(AppFonts.label(11))
                    .tracking(0.8)
                    .foregroundColor(AppColors.textMuted)
                if hasData {
                    Text("·")
                        .font(AppFonts.label(11))
                        .foregroundColor(AppColors.textMuted)
                    Text(stage.label)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(stage.color)
                    Text("\(harmonyScore)")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(stage.color)
                        .monospacedDigit()
                    Text("/100")
                        .font(AppFonts.label(11))
                        .foregroundColor(AppColors.textMuted)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(AppColors.textMuted)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
        }
        .contentShape(Rectangle())
    }

    // MARK: - Bars (with data)

    private var bars: some View {
        HStack(spacing: 10) {
            ForEach(sortedDimensions) { dim in
                dimensionBar(dim)
            }
        }
    }

    private func dimensionBar(_ dim: LifeDimension) -> some View {
        let fillRaw = todayFill[dim] ?? 0
        let fillClamped = max(0, min(1, fillRaw))
        let overflow = fillRaw > 1.0
        let overflowStacks = overflow ? min(5, Int(fillRaw - 1.0) + 1) : 0
        let tickValue = yesterdayTick[dim] ?? nil
        let aboveTick = tickValue.map { fillRaw > $0 && fillRaw > 0 } ?? false
        let scale = bumpScale[dim] ?? 1.0
        let isCrossed = crossedDims.contains(dim)
        let isGoal = goalHitDims.contains(dim)

        return VStack(spacing: 6) {
            ZStack(alignment: .top) {
                // Bar track + fill
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(AppColors.border)
                        .frame(width: 30, height: 54)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(dim.color)
                        .frame(width: 30, height: max(3, 54 * fillClamped))
                        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: fillClamped)
                    // Yesterday tick — opacity ramps with time of day
                    if let tv = tickValue {
                        Rectangle()
                            .fill(AppColors.textMuted)
                            .frame(width: 36, height: 2)
                            .opacity(reduceMotion ? 0.55 : tickOpacity)
                            .offset(y: -(CGFloat(tv) * 54) + 1)
                            .allowsHitTesting(false)
                    }
                    // Crossing shimmer — 700ms, one-shot on detected crossing
                    if isCrossed && !reduceMotion {
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0),
                                Color.white.opacity(0.6),
                                Color.white.opacity(0)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(width: 30, height: 54)
                        .mask(RoundedRectangle(cornerRadius: 6).frame(width: 30, height: 54))
                        .offset(y: isCrossed ? -54 : 0)
                        .animation(.easeOut(duration: 0.7), value: isCrossed)
                        .allowsHitTesting(false)
                    }
                }
                .scaleEffect(scale, anchor: .bottom)
                // Publish this bar's center in the particle coord space so
                // HomeView can aim the completion particle at it. Without
                // this, dimensionBarCenters stays empty, flightLaunchHandler
                // falls through to pulseInPlace for every completion, and no
                // particle flight is visible.
                .background(
                    GeometryReader { proxy in
                        let f = proxy.frame(in: .named(particleCoordinateSpace))
                        Color.clear.preference(
                            key: DimensionBarPositionKey.self,
                            value: [dim: CGPoint(x: f.midX, y: f.midY)]
                        )
                    }
                )
                // Tier 4 glow — breathes when above tick; stronger + stacks on overflow
                .shadow(
                    color: aboveTick ? dim.color.opacity(0.5) : Color.clear,
                    radius: aboveTick ? CGFloat(8 + overflowStacks * 2) : 0
                )
                // Tier 3 goal-hit concentric ring pulse
                if isGoal && !reduceMotion {
                    Circle()
                        .stroke(dim.color, lineWidth: 2)
                        .frame(width: 30, height: 30)
                        .scaleEffect(isGoal ? 2.0 : 1.0)
                        .opacity(isGoal ? 0 : 0.9)
                        .animation(.easeOut(duration: 0.85), value: isGoal)
                        .allowsHitTesting(false)
                }
                // Overflow "+" cap
                if overflow {
                    Text("+")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(dim.color)
                        .offset(y: -8)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            Image(systemName: dim.icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(dim.color)
            Text(dim.shortLabel)
                .font(AppFonts.caption(11))
                .foregroundColor(AppColors.textMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            // Per-bar value — exposes the number so the bar height isn't
            // the only signal. Hidden when the caller didn't supply
            // explicit point values (prevents fill×target fabrication).
            if let label = pointsLabel(for: dim) {
                Text(label)
                    .font(AppFonts.caption(10))
                    .foregroundColor(dim.color)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(for: dim, fill: fillRaw, tick: tickValue))
        .onChange(of: todayFill[dim] ?? 0) { _, newFill in
            handleFillChange(dim: dim, newFill: newFill, tick: tickValue)
        }
    }

    // MARK: - Empty bars (staggered breathing)
    //
    // Each dimension pulses at a different phase (0 / 0.8 / 1.6 / 2.4s) so
    // the empty state feels alive without being nervous. On cream background,
    // phase-locked breathing across all four reads as dashboardy; the stagger
    // softens that to an organic ambient rhythm.

    private var emptyBars: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                ForEach(Array(sortedDimensions.enumerated()), id: \.element) { idx, dim in
                    emptyDimensionBar(dim, phaseIndex: idx)
                }
            }
            Text("Fresh start. Tag a task to begin.")
                .font(AppFonts.caption(12))
                .foregroundColor(AppColors.textMuted)
        }
    }

    private func emptyDimensionBar(_ dim: LifeDimension, phaseIndex: Int) -> some View {
        VStack(spacing: 6) {
            BreathingBar(color: dim.color, phaseIndex: phaseIndex)
            Image(systemName: dim.icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(AppColors.textMuted)
            Text(dim.shortLabel)
                .font(AppFonts.caption(11))
                .foregroundColor(AppColors.textMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Caption row (always visible under the bars)
    //
    // Resolves the "what is the bar measuring?" UX risk — silent users who
    // never tap a bar get the unit in 5 words without affecting the header.

    private var captionRow: some View {
        Text("Today · target \(dailyTarget) pts each")
            .font(AppFonts.caption(11))
            .foregroundColor(AppColors.textMuted)
            .accessibilityHidden(true)
    }

    /// Per-bar "X/N" label. When raw points exceed target we cap the
    /// numerator at target and append `+` (e.g. `4/4+`) so the text never
    /// reads as a missed goal ("6/4"). Returns nil when the caller didn't
    /// supply `todayPoints` — callers without that data shouldn't fabricate
    /// a numerator from fill×target since it disagrees with the user's
    /// real point total surfaced elsewhere.
    private func pointsLabel(for dim: LifeDimension) -> String? {
        guard let raw = todayPoints[dim] else { return nil }
        let rounded = Int(raw.rounded())
        if rounded > dailyTarget {
            return "\(dailyTarget)/\(dailyTarget)+"
        }
        return "\(rounded)/\(dailyTarget)"
    }

    // MARK: - Tagline (optional wisdom)

    private func taglineView(_ t: (text: String, author: String)) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider().padding(.top, 2)
            HStack(alignment: .top, spacing: 8) {
                Rectangle()
                    .fill(AppColors.accentWarm.opacity(0.6))
                    .frame(width: 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\u{201C}\(t.text)\u{201D}")
                        .font(AppFonts.body(12))
                        .italic()
                        .foregroundColor(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(1)
                        .multilineTextAlignment(.leading)
                    Text("\u{2014} \(t.author)")
                        .font(AppFonts.caption(10))
                        .foregroundColor(AppColors.textMuted)
                        .tracking(0.2)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 8)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Daily wisdom: \(t.text), by \(t.author)")
        }
    }

    // MARK: - Open Compass footer link

    private func openCompassLink(_ action: @escaping () -> Void) -> some View {
        Button {
            Haptics.light()
            action()
        } label: {
            HStack(spacing: 4) {
                Spacer()
                Text("Open Compass")
                    .font(AppFonts.caption(12))
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundColor(AppColors.accent)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open Compass tab")
    }

    // MARK: - Handlers

    private func handleFillChange(dim: LifeDimension, newFill: Double, tick: Double?) {
        let previous = previousFills[dim] ?? 0
        previousFills[dim] = newFill

        // No animation for decreases (uncompleting a task should not celebrate).
        guard newFill > previous else { return }

        // Tier 1 — elastic deposit bump. Always plays.
        // All Tier reset Tasks are stored in `tierResetTasks` so
        // `.onDisappear` can cancel them — without that, a user who
        // taps complete then switches tabs leaves resets running
        // against a view already torn down.
        if !reduceMotion {
            bumpScale[dim] = 1.08
            let tierTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(180))
                guard !Task.isCancelled else { return }
                withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
                    bumpScale[dim] = 1.0
                }
            }
            tierResetTasks.append(tierTask)
        }

        // Tier 2 — crossing yesterday's tick. Fires once per day per dim
        // because previousFills persists within the session; once newFill
        // has crossed tick, subsequent onChange calls have `previous >= tick`
        // and this guard fails.
        if let t = tick, previous < t, newFill >= t, !crossedDims.contains(dim) {
            crossedDims.insert(dim)
            let tierTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(700))
                guard !Task.isCancelled else { return }
                crossedDims.remove(dim)
            }
            tierResetTasks.append(tierTask)
        }

        // Tier 3 — hit daily target (100%). Same one-time-per-day logic.
        if previous < 1.0, newFill >= 1.0, !goalHitDims.contains(dim) {
            goalHitDims.insert(dim)
            let tierTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(850))
                guard !Task.isCancelled else { return }
                goalHitDims.remove(dim)
            }
            tierResetTasks.append(tierTask)
        }

        // Tier 4 handled inline via the `aboveTick`/`overflow`/`overflowStacks`
        // derivations in `dimensionBar(_:)` — no state bookkeeping needed.
    }

    private func handleCollapsedFlash(newToken: UUID?) {
        guard let token = newToken,
              token != lastCollapsedFlashToken,
              let pulse = flightPulse else { return }
        lastCollapsedFlashToken = token
        guard !isExpanded else { return }
        triggerCollapsedFlash(color: pulse.dimension.color)
    }

    private func triggerCollapsedFlash(color: Color) {
        collapsedFlashTask?.cancel()
        collapsedFlashColor = color

        if reduceMotion {
            withAnimation(.easeOut(duration: 0.25)) { collapsedFlashOpacity = 0.55 }
            collapsedFlashTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(550))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.5)) { collapsedFlashOpacity = 0 }
            }
            return
        }
        withAnimation(.easeOut(duration: 0.15)) { collapsedFlashOpacity = 0.7 }
        collapsedFlashTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.5)) { collapsedFlashOpacity = 0 }
        }
    }

    // MARK: - Accessibility helpers

    private func accessibilityLabel(for dim: LifeDimension, fill: Double, tick: Double?) -> String {
        let pct = Int((min(1, fill) * 100).rounded())
        var s = "\(dim.shortLabel), \(pct) percent of today's target"
        if fill > 1.0 {
            s += ", exceeded"
        }
        if let t = tick {
            let tPct = Int((t * 100).rounded())
            s += ", yesterday \(tPct) percent"
            if fill > t && fill > 0 {
                s += ", beat yesterday"
            }
        }
        return s
    }
}

// MARK: - Breathing bar (empty-state pulse with staggered phase)

private struct BreathingBar: View {
    let color: Color
    let phaseIndex: Int
    @State private var pulse: Bool = false
    @State private var delayTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(color.opacity(reduceMotion ? 0.22 : (pulse ? 0.32 : 0.18)))
            .frame(width: 30, height: 54)
            .animation(
                reduceMotion
                    ? nil
                    : .easeInOut(duration: 2.8).repeatForever(autoreverses: true),
                value: pulse
            )
            .onAppear {
                // Reduce Motion: hold a static mid-opacity fill so the
                // card isn't visually silent but doesn't pulse at all.
                guard !reduceMotion else { return }
                // Stagger each dim's breathing phase by 800ms so the row
                // reads as an organic rhythm rather than a synchronized
                // pulse (which feels nervous on a cream background).
                let delay = Double(phaseIndex) * 0.8
                delayTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(Int(delay * 1000)))
                    guard !Task.isCancelled else { return }
                    pulse = true
                }
            }
            .onDisappear {
                delayTask?.cancel()
                delayTask = nil
            }
    }
}

// LifeDimension helpers (shortLabel, sortOrder, primaryScored) live in
// LifeDimension.swift so they're visible in the Share Extension target too.
