import SwiftUI

/// Compact Home-screen card showing the 4 scored life dimensions as mini progress
/// bars + an overall harmony score. Tapping navigates to the Compass tab.
///
/// This bridges Pillar 1 ("I did stuff") with Pillar 3 ("my life is better") by
/// making balance visible on the highest-traffic screen in the app. When a
/// dimension-tagged task is completed, the matching bar pulses (1.08× scale +
/// saturation bump) — synchronized with the particle-flight landing per the
/// shared iOS+watchOS animation spec.
struct BalancePulseCard: View {
    let scores: [LifeDimension: Double]
    let harmonyScore: Int
    /// Whether the user has real data this week. Passed in from HomeView so
    /// the card doesn't have to rely on a score-value heuristic (which falsely
    /// flagged genuine 5.0 scores as "no data").
    var hasData: Bool
    /// Pulse signal from `ParticleAnimator` — fires on particle
    /// landing (tap-source completions) or in-place pulse (Reduce Motion,
    /// overflow, off-tap completions like Watch sync). Token-keyed so
    /// rapid same-dimension pulses re-fire instead of collapsing.
    var flightPulse: ParticlePulseRequest? = nil
    /// Optional wisdom quote rendered as a small italic tagline below the
    /// harmony row. Replaces the standalone Wisdom card on Home.
    var tagline: (text: String, author: String)? = nil
    /// Optional callback to open the Compass tab. When non-nil, the expanded
    /// card renders a footer "Open Compass" link. The whole-card tap toggles
    /// collapse now, so this link is the sole in-card affordance for reaching
    /// Compass — kept so returning users who relied on the old card-tap
    /// shortcut aren't stranded.
    var onTapCompass: (() -> Void)? = nil

    /// Persisted collapse state. Default expanded on first launch so the user
    /// sees the full card until they choose to hide it — matches the Overdue
    /// section's disclosure pattern.
    @AppStorage("home.lifeBalance.expanded") private var isExpanded: Bool = true

    // MARK: - Pulse state (per the shared iOS+watchOS animation spec)
    //
    // Spec: 1.08× scale over 120ms → return over 180ms (spring damping 0.7).
    // Bar fill saturation bumps +15% during the same window. No glow halo,
    // no floating "+N Body" label — those decorations were dropped when the
    // particle became the celebratory element. The bar pulse is now just
    // synchronized acknowledgment of the landing.

    @State private var activePulseDimension: LifeDimension?
    @State private var pulseScale: CGFloat = 1.0
    /// Cancel-prior-Task handle so a rapid second pulse doesn't get its
    /// settle clobbered by the previous cleanup's reset.
    @State private var pulseAnimationTask: Task<Void, Never>?
    /// Token of the last pulse we actually animated. Used to ignore the
    /// initial onChange fire when the view (re)appears with a pre-existing
    /// pulse value — prevents re-playing the last completion's pulse every
    /// time the user switches back to Home.
    @State private var lastHandledToken: UUID?

    // MARK: - Collapsed-state border flash
    //
    // When the user has the card collapsed, the bar pulse is invisible — they
    // get no signal that their completion moved their balance. A brief
    // dimension-coloured border flash on the collapsed card closes the loop:
    // "something changed; tap to see." The on-expand replay (further down)
    // still plays the full bar pulse when they actually open the card, so this
    // flash is purely a hint, not the feedback itself.
    @State private var collapsedFlashOpacity: Double = 0
    @State private var collapsedFlashColor: Color = .clear
    @State private var collapsedFlashTask: Task<Void, Never>?
    /// Tracked separately from `lastHandledToken` so the collapsed flash
    /// doesn't suppress the on-expand bar pulse — that path checks
    /// `lastHandledToken` only.
    @State private var lastCollapsedFlashToken: UUID?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Computed

    private var sortedDimensions: [LifeDimension] {
        LifeDimension.scored.sorted { $0.sortOrder < $1.sortOrder }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 12) {
            // Header — tap anywhere to toggle expand/collapse. Mirrors the
            // Overdue section's disclosure pattern so the two cards behave
            // the same way. The score stays inline with the title, chevron
            // on the right rotates to indicate state.
            Button {
                Haptics.light()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            } label: {
                headerLabel
            }
            .buttonStyle(.plain)
            // Combine the icon + label + chevron into one VoiceOver element
            // and mark it as a section header with an expand/collapse value,
            // so VO reads e.g. "Life balance, harmony 39 out of 100.
            // Collapsed. Header. Double tap to expand."
            .accessibilityElement(children: .combine)
            .accessibilityLabel(hasData
                ? "Life balance, harmony \(harmonyScore) out of 100"
                : "Life balance, no data yet")
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint("Double tap to \(isExpanded ? "collapse" : "expand")")
            .accessibilityAddTraits(.isHeader)

            if isExpanded {
                if hasData {
                    // Dimension bars — real data
                    HStack(spacing: 10) {
                        ForEach(sortedDimensions) { dim in
                            dimensionBar(dim)
                        }
                    }
                } else {
                    // Empty state — no check-ins or tasks yet this week
                    VStack(spacing: 8) {
                        HStack(spacing: 10) {
                            ForEach(sortedDimensions) { dim in
                                emptyDimensionBar(dim)
                            }
                        }
                        Text("Complete a check-in to see your balance")
                            .font(AppFonts.caption(12))
                            .foregroundColor(AppColors.textMuted)
                    }
                }

                // Wisdom tagline (replaces the standalone Wisdom card on Home).
                // Kept small and italic so it reads as a supporting line, not a
                // competing content block.
                if let tagline {
                    Divider()
                        .padding(.top, 2)
                    HStack(alignment: .top, spacing: 8) {
                        Rectangle()
                            .fill(AppColors.accentWarm.opacity(0.6))
                            .frame(width: 2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\u{201C}\(tagline.text)\u{201D}")
                                .font(AppFonts.body(12))
                                .italic()
                                .foregroundColor(AppColors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .lineSpacing(1)
                                .multilineTextAlignment(.leading)
                            Text("\u{2014} \(tagline.author)")
                                .font(AppFonts.caption(10))
                                .foregroundColor(AppColors.textMuted)
                                .tracking(0.2)
                        }
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Daily wisdom: \(tagline.text), by \(tagline.author)")
                }

                // Compass footer link — restored as an explicit button so the
                // old "tap-anywhere-to-open-Compass" shortcut isn't lost. The
                // header tap now handles collapse, so this link takes over
                // the nav role.
                if let onTapCompass {
                    Button {
                        Haptics.light()
                        onTapCompass()
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
        // Collapsed-state pulse hint. Stroke colour is dimension-specific so
        // even the brief flash hints at *which* part of the user's balance
        // moved — the same hue they'll see on the bar when they expand.
        // BUG-07: explicitly animate the colour change so a 2nd pulse on a
        // different dimension arriving mid-fade crossfades instead of popping.
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(collapsedFlashColor, lineWidth: 1.5)
                .opacity(collapsedFlashOpacity)
                .animation(.easeInOut(duration: 0.2), value: collapsedFlashColor)
                .allowsHitTesting(false)
        )
        .onAppear {
            // Record the pre-mount token so the first onChange fire doesn't
            // re-animate the last pulse on view (re)appear.
            lastHandledToken = flightPulse?.token
            lastCollapsedFlashToken = flightPulse?.token
        }
        .onChange(of: flightPulse?.token) { _, newToken in
            handlePulseChange(newToken: newToken)
        }
        // Replay the latest pending pulse when the card expands. While
        // collapsed, `handlePulseChange` returns early WITHOUT marking the
        // token as handled, so the newest pulse can animate on expand —
        // otherwise users who complete tasks with the card collapsed would
        // get no feedback at all when they open it.
        .onChange(of: isExpanded) { _, nowExpanded in
            guard nowExpanded else { return }
            collapsedFlashTask?.cancel()
            withAnimation(.easeOut(duration: 0.15)) { collapsedFlashOpacity = 0 }
            handlePulseChange(newToken: flightPulse?.token, fromExpand: true)
        }
    }

    // MARK: - Pulse animation (spec)
    //
    // Per the shared iOS+watchOS contract:
    //   • Scale: 1.08× over 120ms then back over 180ms (spring damping 0.7)
    //   • Saturation +15% bump on the bar fill during the same window
    //   • No glow halo, no floating "+N Body" label

    private func handlePulseChange(newToken: UUID?, fromExpand: Bool = false) {
        guard let pulse = flightPulse, let newToken, newToken != lastHandledToken else { return }

        // When collapsed, defer the bar pulse but show a brief border flash
        // in the dimension colour so the user gets a "something moved" hint
        // without having to expand. lastHandledToken stays unset so the
        // pulse animates when the card is opened.
        guard isExpanded else {
            if newToken != lastCollapsedFlashToken {
                lastCollapsedFlashToken = newToken
                triggerCollapsedFlash(color: pulse.dimension.color)
            }
            return
        }

        lastHandledToken = newToken

        // Cancel any in-flight settle so a rapid second pulse doesn't get
        // its state clobbered by the previous cleanup.
        pulseAnimationTask?.cancel()
        pulseScale = 1.0
        activePulseDimension = pulse.dimension

        if reduceMotion {
            // Reduce Motion: skip the scale, keep the saturation bump as
            // static color feedback. Same duration so the visible state
            // matches the synchronized haptic timing.
            pulseAnimationTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled, activePulseDimension == pulse.dimension else { return }
                activePulseDimension = nil
            }
            return
        }

        // Phase 1: scale to 1.08× over 120ms (spring damping 0.7).
        withAnimation(.spring(response: 0.12, dampingFraction: 0.7)) {
            pulseScale = 1.08
        }
        // Phase 2: settle back over 180ms.
        pulseAnimationTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.18, dampingFraction: 0.7)) {
                pulseScale = 1.0
            }
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled, activePulseDimension == pulse.dimension else { return }
            activePulseDimension = nil
        }
    }

    /// Brief border glow when a pulse arrives while the card is collapsed.
    /// ~800ms total — short enough to feel like a notification, not an
    /// animation that demands action. Reduce Motion users get a slightly
    /// longer fade with no perceived "bloom" curve, only opacity change.
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

    // MARK: - Header label

    /// Extracted to break up the Button label expression — with the nested
    /// `if hasData` branch and five chained modifiers per Text, the inline
    /// form tripped the Swift type-checker's "expression too complex" limit.
    private var headerLabel: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "circle.grid.cross")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppColors.accent)
                Text("LIFE BALANCE")
                    .font(AppFonts.label(11))
                    .tracking(0.8)
                    .foregroundColor(AppColors.textMuted)
                if hasData {
                    headerScore
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

    /// Inline "· 39/100" fragment shown next to the header title when the
    /// user has real data. Split out so the parent `headerLabel` stays
    /// shallow enough for the type-checker.
    private var headerScore: some View {
        HStack(spacing: 1) {
            Text("·")
                .font(AppFonts.label(11))
                .foregroundColor(AppColors.textMuted)
                .padding(.trailing, 2)
            Text("\(harmonyScore)")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(harmonyColor)
                .monospacedDigit()
            Text("/100")
                .font(AppFonts.label(11))
                .foregroundColor(AppColors.textMuted)
        }
    }

    // MARK: - Dimension Bar (with data)

    private func dimensionBar(_ dim: LifeDimension) -> some View {
        let score = max(0, min(10, scores[dim] ?? 5.0))
        let fraction = score / 10.0
        let isPulsing = activePulseDimension == dim

        return VStack(spacing: 6) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(AppColors.border)
                    .frame(width: 28, height: 48)
                    // Publishes this bar's center in the particle coord space
                    // so ParticleAnimator.fire knows where to aim. Uses the
                    // full bar center — not the filled portion's top — so
                    // particles always land on the bar regardless of the
                    // current score (fill height varies with score).
                    .background(
                        GeometryReader { proxy in
                            let f = proxy.frame(in: .named(particleCoordinateSpace))
                            Color.clear.preference(
                                key: DimensionBarPositionKey.self,
                                value: [dim: CGPoint(x: f.midX, y: f.midY)]
                            )
                        }
                    )
                RoundedRectangle(cornerRadius: 4)
                    .fill(dim.color)
                    // Spec: saturation +15% bump during the pulse window.
                    // Combined with the 1.08× scaleEffect below, this is the
                    // entire landing-pulse signal — no glow halo, no label.
                    .saturation(isPulsing ? 1.15 : 1.0)
                    .frame(width: 28, height: max(4, 48 * fraction))
                    .animation(.spring(response: 0.55, dampingFraction: 0.75), value: fraction)
            }
            .scaleEffect(isPulsing ? pulseScale : 1.0)

            Image(systemName: dim.icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(dim.color)
            Text(dim.shortLabel)
                .font(AppFonts.caption(11))
                .foregroundColor(AppColors.textMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    // MARK: - Empty Dimension Bar (no data)

    private func emptyDimensionBar(_ dim: LifeDimension) -> some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 4)
                .fill(AppColors.border)
                .frame(width: 28, height: 48)
                // Publish center even in the no-data branch — otherwise
                // day-0 users who complete a tagged task before any
                // check-ins exist get a silent in-place pulse instead
                // of the celebratory particle flight.
                .background(
                    GeometryReader { proxy in
                        let f = proxy.frame(in: .named(particleCoordinateSpace))
                        Color.clear.preference(
                            key: DimensionBarPositionKey.self,
                            value: [dim: CGPoint(x: f.midX, y: f.midY)]
                        )
                    }
                )
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

    // MARK: - Helpers

    private var harmonyColor: Color {
        switch harmonyScore {
        case 70...: return AppColors.completionGreen
        case 40..<70: return AppColors.accentWarm
        default: return AppColors.overdueRed
        }
    }
}

// LifeDimension helpers (shortLabel, sortOrder, primaryScored) moved to
// LifeDimension.swift so they're visible in the Share Extension target too.
