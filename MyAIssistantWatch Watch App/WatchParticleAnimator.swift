#if os(watchOS)
import SwiftUI
import WatchKit

// MARK: - Animation contract
//
// Implements the shared task-completion → life-balance spec on watchOS.
// Per the contract:
//   • Particle: 5pt circle, dimension color, 16pt fading trail
//   • Path: quadratic curve with 20%-of-distance upward arc
//   • Duration: 450ms, easeInOut
//   • Landing: target bar scales 1.08× over 120ms then back over 180ms
//     (spring damping 0.7) + saturation +15% bump
//   • Haptic .click fires on landing (not launch)
//   • Reduce Motion: skip flight, in-place pulse + haptic only
//   • Rapid completions: queue with 120ms launch interval, max 4 in flight,
//     overflow collapses to in-place pulses

/// A pulse-on-arrival signal the WatchBalancePulse view watches via .onChange.
/// Token is a UUID so back-to-back pulses on the same dimension don't collapse
/// in SwiftUI's equality check.
struct WatchPulseRequest: Equatable {
    let dimension: WatchDimension
    let token: UUID
}

@MainActor
@Observable
final class WatchParticleAnimator {

    // MARK: Published state

    /// Particles currently flying. Rendered by WatchParticleLayer.
    var inFlight: [InFlight] = []
    /// Latest landing/skip pulse signal. WatchBalancePulse observes this and
    /// runs the 1.08× scale + saturation animation on the matching bar.
    var pulseRequest: WatchPulseRequest?

    // MARK: Tunables (match the spec)

    private let particleDuration: TimeInterval = 0.450
    private let launchInterval: TimeInterval = 0.120
    private let maxInFlight = 4

    // MARK: Internal state

    private var queue: [QueuedFire] = []
    private var lastLaunchTime: Date = .distantPast
    private var processing = false

    struct InFlight: Identifiable, Equatable {
        let id = UUID()
        let dimension: WatchDimension
        let source: CGPoint
        let target: CGPoint
        let startTime: Date
    }

    private struct QueuedFire {
        let dimension: WatchDimension
        let source: CGPoint
        let target: CGPoint
    }

    // MARK: Public API

    /// Fire a particle from `source` to the dimension's bar. Subject to the
    /// 4-in-flight cap and 120ms launch interval. Overflow collapses to an
    /// in-place pulse (see `pulseRequest`).
    func fire(dimension: WatchDimension, from source: CGPoint, to target: CGPoint) {
        queue.append(QueuedFire(dimension: dimension, source: source, target: target))
        startProcessing()
    }

    /// Reduce-Motion or no-source path. Skips flight, fires landing
    /// behaviors immediately (bar pulse + haptic).
    func pulseInPlace(dimension: WatchDimension) {
        triggerLanding(dimension: dimension)
    }

    // MARK: Queue processing

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
            // Cap: collapse anything that can't get an in-flight slot.
            if inFlight.count >= maxInFlight {
                let dropped = queue.removeFirst()
                triggerLanding(dimension: dropped.dimension)
                continue
            }

            // Throttle: respect the 120ms launch interval.
            let sinceLast = Date().timeIntervalSince(lastLaunchTime)
            if sinceLast < launchInterval {
                let wait = launchInterval - sinceLast
                try? await Task.sleep(for: .seconds(wait))
            }

            guard !queue.isEmpty else { return }
            let next = queue.removeFirst()
            launch(dimension: next.dimension, source: next.source, target: next.target)
        }
    }

    private func launch(dimension: WatchDimension, source: CGPoint, target: CGPoint) {
        let particle = InFlight(
            dimension: dimension,
            source: source,
            target: target,
            startTime: Date()
        )
        inFlight.append(particle)
        lastLaunchTime = Date()

        // Schedule arrival — remove particle, fire haptic + bar pulse.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(particleDuration))
            inFlight.removeAll { $0.id == particle.id }
            triggerLanding(dimension: dimension)
        }
    }

    private func triggerLanding(dimension: WatchDimension) {
        pulseRequest = WatchPulseRequest(dimension: dimension, token: UUID())
        WKInterfaceDevice.current().play(.click)
    }
}

// MARK: - Particle view
//
// TimelineView drives the position update at display refresh rate so the
// particle slides along the curve continuously rather than snapping in
// SwiftUI animation steps. easeInOut curve matches the spec.

struct WatchParticle: View {
    let dimension: WatchDimension
    let source: CGPoint
    let target: CGPoint
    let startTime: Date

    private let duration: TimeInterval = 0.450
    private let particleSize: CGFloat = 5
    private let trailLength: CGFloat = 16  // 16pt total trail
    private let trailDots = 5

    var body: some View {
        TimelineView(.animation) { context in
            let elapsed = context.date.timeIntervalSince(startTime)
            let raw = max(0, min(1, elapsed / duration))
            let t = easeInOut(raw)
            let head = position(at: t)

            ZStack {
                // Trail — render previous positions with fading opacity.
                // 16pt total trail divided across `trailDots` samples.
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
                // Head particle.
                Circle()
                    .fill(dimension.color)
                    .frame(width: particleSize, height: particleSize)
                    .position(head)
                    .shadow(color: dimension.color.opacity(0.5), radius: 3)
            }
        }
    }

    /// Quadratic bezier position at parameter t ∈ [0, 1]. Control point is
    /// the midpoint pulled UP (negative y) by 20% of the source-target
    /// distance — matches the spec's "slight upward arc."
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

    /// Cubic ease-in-out. Matches CSS `cubic-bezier(.42,0,.58,1)` shape.
    private func easeInOut(_ t: Double) -> Double {
        t < 0.5
            ? 2 * t * t
            : 1 - pow(-2 * t + 2, 2) / 2
    }
}

// MARK: - Particle layer
//
// Mounted as an overlay above the main content. allowsHitTesting(false)
// keeps it visually decorative — taps pass through to underlying buttons.

struct WatchParticleLayer: View {
    let animator: WatchParticleAnimator

    var body: some View {
        ZStack {
            ForEach(animator.inFlight) { p in
                WatchParticle(
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
#endif
