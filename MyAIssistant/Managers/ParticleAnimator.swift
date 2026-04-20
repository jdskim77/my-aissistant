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

    private let particleDuration: TimeInterval = 0.450
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
    func cancelAll() {
        pendingLandings.values.forEach { $0.cancel() }
        pendingLandings.removeAll()
        inFlight.removeAll()
        queue.removeAll()
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
