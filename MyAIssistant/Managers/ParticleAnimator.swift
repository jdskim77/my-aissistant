import SwiftUI
import UIKit

// MARK: - Animation contract
//
// iOS implementation of the shared task-completion → life-balance spec.
// Per the contract:
//   • Particle: 8pt circle, dimension color, 24pt fading trail
//   • Path: quadratic curve with 20%-of-distance upward arc
//   • Duration: 450ms, easeInOut
//   • Landing: target bar scales 1.08× over 120ms then back over 180ms
//     (spring damping 0.7) + saturation +15% bump
//   • Haptic .impact(.light) fires on landing (not launch)
//   • Reduce Motion: skip flight, in-place pulse + haptic only
//   • Rapid completions: queue with 120ms launch interval, max 4 in flight,
//     overflow collapses to in-place pulses
//
// Source position: TaskCard publishes its checkbox center via
// `TaskCheckboxFrameKey` and HomeView's `flightLaunchHandler` calls
// `fire(...)` directly. Other completion paths (Watch sync, Focus
// auto-complete, swipe-to-complete in Schedule) publish on
// BalancePulseBus; HomeView bridges those into `pulseInPlace(...)` only
// when no recent tap-driven flight is in progress for the same
// dimension — avoids the double-pulse.

/// Pulse-on-arrival signal that BalancePulseCard watches via .onChange.
/// Token is fresh per pulse so back-to-back pulses on the same dimension
/// don't collapse in SwiftUI's equality check.
struct ParticlePulseRequest: Equatable {
    let dimension: LifeDimension
    let token: UUID
}

@MainActor
@Observable
final class ParticleAnimator {

    // MARK: Published

    var inFlight: [InFlight] = []
    var pulseRequest: ParticlePulseRequest?

    // MARK: Spec tunables

    /// Flight duration — sourced from the file-level `flightDuration` so the
    /// animator's landing scheduler and the visual layer (`Wave` / `Particle`)
    /// can't desync. Bumped from 0.45s (particle-era) to 0.70s for the
    /// calmer wave visual — landing haptic + bar pulse fire after this window.
    private let particleDuration: TimeInterval = flightDuration
    private let launchInterval: TimeInterval = 0.120
    private let maxInFlight = 4
    /// How long after a tap-driven fire we ignore an equivalent bus event
    /// for the same dimension. Stops the bus pulse from also pulsing the
    /// bar while a particle for the same completion is still in flight.
    private let busSuppressionWindow: TimeInterval = 0.6
    /// Safety cap on pending queue depth. Without this, a bulk sync (e.g.
    /// reconnect after offline with many Watch toggles) can drain over
    /// seconds, firing haptics long after the user's action ended.
    private let maxQueueDepth = 12
    /// Minimum interval between consecutive haptics. Per the spec, overflow
    /// drops still trigger a landing (visual pulse) — but blasting 8 haptics
    /// in 100ms would be jarring. Visuals continue; haptic is rate-limited.
    private let minHapticInterval: TimeInterval = 0.08

    // MARK: Internal

    private var queue: [QueuedFire] = []
    private var lastLaunchTime: Date = .distantPast
    private var processing = false
    private var lastHapticTime: Date = .distantPast
    /// Per-dimension timestamp of the last fire — HomeView's bus-bridge
    /// asks via `shouldHandleBusPulse` before forwarding bus events.
    private var lastTapFire: [LifeDimension: Date] = [:]
    /// Handles for landing Tasks so `cancelAll` can tear them down when the
    /// host view disappears (tab switch, modal cover). Without this, a
    /// particle in flight when HomeView disappears still fires haptic +
    /// pulseRequest 450ms later while the user is on a different tab.
    private var pendingLandings: [UUID: Task<Void, Never>] = [:]
    /// Haptic generator kept around + pre-warmed so the first landing
    /// haptic doesn't lag 100-200ms (Apple-recommended pattern).
    private let haptic = UIImpactFeedbackGenerator(style: .light)

    struct InFlight: Identifiable, Equatable {
        let id = UUID()
        let dimension: LifeDimension
        let source: CGPoint
        let target: CGPoint
        let startTime: Date
    }

    private struct QueuedFire {
        let dimension: LifeDimension
        let source: CGPoint
        let target: CGPoint
    }

    // MARK: Public API

    /// Fire from `source` to the dimension's bar. Subject to the queue's
    /// 4-in-flight cap and 120ms launch interval. Overflow collapses to
    /// an in-place pulse. Queue depth capped at `maxQueueDepth` — beyond
    /// that, new fires are dropped silently to prevent runaway haptic
    /// vibration during bulk syncs.
    func fire(dimension: LifeDimension, from source: CGPoint, to target: CGPoint) {
        lastTapFire[dimension] = Date()
        guard queue.count < maxQueueDepth else { return }
        queue.append(QueuedFire(dimension: dimension, source: source, target: target))
        startProcessing()
    }

    /// Skip-flight (Reduce Motion, no source position, or off-tap completion):
    /// pulse the matching bar in place + fire haptic. Also records the
    /// fire timestamp so a same-dimension bus pulse arriving shortly after
    /// (via TaskManager.toggleCompletion) is suppressed — otherwise the
    /// bar would pulse twice for one tap under Reduce Motion.
    func pulseInPlace(dimension: LifeDimension) {
        lastTapFire[dimension] = Date()
        triggerLanding(dimension: dimension)
    }

    /// True if a bus pulse for `dim` should be bridged into an in-place
    /// pulse, false if a tap-driven flight already covers it.
    func shouldHandleBusPulse(_ dim: LifeDimension) -> Bool {
        guard let last = lastTapFire[dim] else { return true }
        return Date().timeIntervalSince(last) > busSuppressionWindow
    }

    /// Cancel all pending landing Tasks + clear inFlight + queue. Call from
    /// HomeView's `.onDisappear` so a particle in flight when the user
    /// switches tabs doesn't fire haptic + pulseRequest from the background.
    ///
    /// BUG-11 fix: also reset the `lastTapFire` / `lastLaunchTime` /
    /// `lastHapticTime` ledgers. Without this, a user who taps Home once
    /// then immediately switches tabs carries a 0.6s `busSuppressionWindow`
    /// over the switch — a Watch-driven bus pulse for the same dimension
    /// arriving seconds later gets silently dropped because `shouldHandleBusPulse`
    /// still sees the old fire.
    func cancelAll() {
        pendingLandings.values.forEach { $0.cancel() }
        pendingLandings.removeAll()
        inFlight.removeAll()
        queue.removeAll()
        lastTapFire.removeAll()
        lastLaunchTime = .distantPast
        lastHapticTime = .distantPast
        processing = false
    }

    /// Warms up the internal haptic generator. Call early (e.g. HomeView
    /// onAppear) so the first landing haptic doesn't lag 100–200ms.
    func prepareHaptics() {
        haptic.prepare()
    }

    // MARK: Queue

    private func startProcessing() {
        guard !processing else { return }
        processing = true
        Task { @MainActor in
            await drain()
            processing = false
        }
    }

    private func drain() async {
        while !queue.isEmpty {
            if inFlight.count >= maxInFlight {
                let dropped = queue.removeFirst()
                triggerLanding(dimension: dropped.dimension)
                continue
            }
            let sinceLast = Date().timeIntervalSince(lastLaunchTime)
            if sinceLast < launchInterval {
                try? await Task.sleep(for: .seconds(launchInterval - sinceLast))
            }
            guard !queue.isEmpty else { return }
            let next = queue.removeFirst()
            launch(dimension: next.dimension, source: next.source, target: next.target)
        }
    }

    private func launch(dimension: LifeDimension, source: CGPoint, target: CGPoint) {
        let particle = InFlight(
            dimension: dimension,
            source: source,
            target: target,
            startTime: Date()
        )
        inFlight.append(particle)
        lastLaunchTime = Date()

        let id = particle.id
        let landingTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(particleDuration))
            // Cancellation check: if the host view disappeared (cancelAll
            // called) don't fire landing side-effects for a particle the
            // user can no longer see.
            guard !Task.isCancelled else { return }
            inFlight.removeAll { $0.id == id }
            pendingLandings.removeValue(forKey: id)
            triggerLanding(dimension: dimension)
        }
        pendingLandings[id] = landingTask
    }

    private func triggerLanding(dimension: LifeDimension) {
        pulseRequest = ParticlePulseRequest(dimension: dimension, token: UUID())
        // Haptic throttle — overflow drops still pulse the bar (visual),
        // but if the last haptic fired within `minHapticInterval` we skip
        // this one. Prevents machine-gun vibration on bulk completions.
        let now = Date()
        if now.timeIntervalSince(lastHapticTime) >= minHapticInterval {
            haptic.impactOccurred()
            haptic.prepare() // re-warm for the next one
            lastHapticTime = now
        }
    }
}

// MARK: - Particle view (TimelineView-driven curve, 8pt + 24pt trail)

struct Particle: View {
    let dimension: LifeDimension
    let source: CGPoint
    let target: CGPoint
    let startTime: Date

    private let duration: TimeInterval = 0.450
    private let particleSize: CGFloat = 8        // iOS spec
    private let trailLength: CGFloat = 24        // iOS spec
    private let trailDots = 6

    var body: some View {
        TimelineView(.animation) { context in
            let elapsed = context.date.timeIntervalSince(startTime)
            let raw = max(0, min(1, elapsed / duration))
            let t = easeInOut(raw)
            let head = position(at: t)

            ZStack {
                // Trail dots — fade with index, sampled at lagging progress
                // values so the trail appears to follow the head along the
                // curve (matches the spec's gradient intent in spirit).
                ForEach(0..<trailDots, id: \.self) { i in
                    let lag = (Double(i + 1) / Double(trailDots)) * (Double(trailLength) / 200.0)
                    let trailT = max(0, t - lag)
                    let pos = position(at: trailT)
                    let opacity = 0.4 * (1 - Double(i + 1) / Double(trailDots))
                    Circle()
                        .fill(dimension.color.opacity(opacity))
                        .frame(width: particleSize, height: particleSize)
                        .position(pos)
                }
                Circle()
                    .fill(dimension.color)
                    .frame(width: particleSize, height: particleSize)
                    .position(head)
                    .shadow(color: dimension.color.opacity(0.5), radius: 4)
            }
        }
    }

    /// Quadratic bezier — control point is midpoint pulled UP by 20% of
    /// the source/target distance. Matches the spec's "slight upward arc."
    /// Y axis grows downward in screen space, so subtracting offset bows up.
    private func position(at t: Double) -> CGPoint {
        let dx = target.x - source.x
        let dy = target.y - source.y
        let dist = sqrt(dx * dx + dy * dy)
        let arcOffset = dist * 0.20
        let midX = (source.x + target.x) / 2
        let midY = (source.y + target.y) / 2 - arcOffset

        let oneMinusT = 1 - t
        let x = oneMinusT * oneMinusT * source.x
              + 2 * oneMinusT * t * midX
              + t * t * target.x
        let y = oneMinusT * oneMinusT * source.y
              + 2 * oneMinusT * t * midY
              + t * t * target.y
        return CGPoint(x: x, y: y)
    }

    private func easeInOut(_ t: Double) -> Double {
        t < 0.5
            ? 2 * t * t
            : 1 - pow(-2 * t + 2, 2) / 2
    }
}

// MARK: - Particle layer
//
// Mounted as overlay above the main content. allowsHitTesting(false)
// keeps it visually decorative — taps pass through to underlying buttons.

struct ParticleLayer: View {
    let animator: ParticleAnimator

    var body: some View {
        ZStack {
            ForEach(animator.inFlight) { p in
                Particle(
                    dimension: p.dimension,
                    source: p.source,
                    target: p.target,
                    startTime: p.startTime
                )
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - PreferenceKey for bar positions
//
// BalancePulseCard publishes each bar's center via this key so HomeView
// can look up the target point for `animator.fire(...)`.

struct DimensionBarPositionKey: PreferenceKey {
    static var defaultValue: [LifeDimension: CGPoint] = [:]
    static func reduce(
        value: inout [LifeDimension: CGPoint],
        nextValue: () -> [LifeDimension: CGPoint]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

/// Coordinate space name — both bar centers and TaskCard checkbox
/// positions resolve into this space so particle math is consistent.
let particleCoordinateSpace = "iOSParticleCoord"

/// Single source of truth for flight duration. The animator's landing
/// scheduler (`ParticleAnimator.particleDuration`) and the visual layer
/// (`Wave.duration`) both reference this so haptic + bar pulse fire as the
/// visual arrives. Changing this one value re-tunes the whole system.
let flightDuration: TimeInterval = 0.700

// MARK: - Wave view (Option A — soft color band rising from tap to bar)
//
// Drop-in alternative to `Particle` / `ParticleLayer`. Same animator API,
// same coord space, same source+target semantics. Only the visual changes:
// a full-width, gaussian-edged horizontal band of the dimension colour
// translates from the tap origin up to the Balance bar over `duration` ms.
//
// Why full-width rather than a narrow aimed band: four dimension bars sit
// side by side at the top. A narrow band "aimed" at one bar reads as a
// projectile (the thing we're moving AWAY from). A full-width band lets the
// *colour* do the identification — pink wave → pink bar pulses. The landing
// pulse (saturation + scale on the matching bar) names the specific
// dimension precisely.
//
// Duration must match `ParticleAnimator.particleDuration` so the landing
// scheduler fires haptic + bar pulse as the wave arrives.
struct Wave: View {
    let dimension: LifeDimension
    let source: CGPoint
    let target: CGPoint
    let startTime: Date

    /// Pulled from the file-level `flightDuration` so it can never desync
    /// from `ParticleAnimator.particleDuration` — BUG-06 fix.
    private let duration: TimeInterval = flightDuration
    /// Band thickness. Small enough not to dominate the screen, big enough
    /// to read as a swell rather than a line.
    private let bandHeight: CGFloat = 140
    /// Peak opacity at the band's centre-line. Intentionally low — waves
    /// should whisper, not announce. Tuned down from 0.18 → 0.14 (BUG-09):
    /// 3–4 overlapping waves used to accumulate to ~0.55 effective opacity
    /// over list text during bulk completions; 0.14 caps the stack at ~0.45
    /// while a single wave stays plenty visible.
    private let maxOpacity: Double = 0.14
    /// Soft edge blur. Sells "water" over "rectangle." Reduced 8 → 4pt
    /// (BUG-04): blur is an off-screen render pass and cost scales with
    /// radius² × area; 4pt is ~4× cheaper per-frame which matters when up
    /// to 4 waves animate simultaneously.
    private let blurRadius: CGFloat = 4

    var body: some View {
        TimelineView(.animation) { context in
            let elapsed = context.date.timeIntervalSince(startTime)
            let raw = max(0, min(1, elapsed / duration))
            let t = easeInOut(raw)

            // Vertical travel — source (tap) → target (bar). Y decreases on
            // iOS when moving up the screen, so this works for both upward
            // (tap below Balance card) and downward (unlikely but safe)
            // trajectories.
            let y = source.y + (target.y - source.y) * t

            // Opacity envelope — quick fade-in (~15%), long hold, gentle
            // fade-out (~20%) so the wave dissolves into the bar rather
            // than slamming into it.
            let alpha = opacityEnvelope(t: t)

            GeometryReader { proxy in
                Rectangle()
                    .fill(
                        // Gaussian-feathered top + bottom edges so the band
                        // dissolves into the background instead of showing
                        // two hard horizontal lines.
                        LinearGradient(
                            colors: [
                                dimension.color.opacity(0),
                                dimension.color.opacity(maxOpacity),
                                dimension.color.opacity(0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    // Extend past the screen edges by just enough to hide
                    // the blur's inward feather — BUG-04 fix. Was +40pt
                    // (overkill: wasted ~32pt of off-screen fill per side).
                    // `2 * blurRadius` is the minimum that keeps the feather
                    // from biting into visible pixels.
                    .frame(width: proxy.size.width + blurRadius * 2, height: bandHeight)
                    .blur(radius: blurRadius)
                    .opacity(alpha)
                    .position(x: proxy.size.width / 2, y: y)
                    .allowsHitTesting(false)
            }
        }
    }

    /// Triangular-ish envelope — ramps in, holds, ramps out. Prevents the
    /// "pop in" that a hard opacity=1 would cause at t=0 and the "slam" at
    /// arrival when the wave meets the bar.
    private func opacityEnvelope(t: Double) -> Double {
        if t < 0.15 { return t / 0.15 }
        if t > 0.80 { return max(0, (1.0 - t) / 0.20) }
        return 1.0
    }

    private func easeInOut(_ t: Double) -> Double {
        t < 0.5
            ? 2 * t * t
            : 1 - pow(-2 * t + 2, 2) / 2
    }
}

/// Drop-in replacement for `ParticleLayer`. Reads the same `animator.inFlight`
/// array — no API changes in `ParticleAnimator` — and renders each flight as
/// a `Wave` instead of a `Particle`. Swap `ParticleLayer(animator:)` for
/// `WaveLayer(animator:)` in HomeView to toggle.
struct WaveLayer: View {
    let animator: ParticleAnimator

    var body: some View {
        ZStack {
            ForEach(animator.inFlight) { item in
                Wave(
                    dimension: item.dimension,
                    source: item.source,
                    target: item.target,
                    startTime: item.startTime
                )
            }
        }
        .allowsHitTesting(false)
    }
}
