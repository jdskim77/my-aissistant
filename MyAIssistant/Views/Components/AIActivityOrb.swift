import SwiftUI

struct AIActivityOrb: View {
    let isActive: Bool
    var size: CGFloat = 40

    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State private var animationPhase = false

    var body: some View {
        ZStack {
            // Layer 3: Outer glow
            if isActive {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                AppColors.gold.opacity(0.3),
                                AppColors.gold.opacity(0.0)
                            ],
                            center: .center,
                            startRadius: size * 0.2,
                            endRadius: size * 0.75
                        )
                    )
                    .frame(width: size * 1.8, height: size * 1.8)
                    .scaleEffect(reduceMotion ? 1.0 : (animationPhase ? 1.15 : 0.95))
                    .opacity(reduceMotion ? 0.6 : (animationPhase ? 0.8 : 0.4))
                    .animation(
                        reduceMotion ? .none : .easeInOut(duration: 1.8).repeatForever(autoreverses: true),
                        value: animationPhase
                    )
            }

            // Layer 2: Middle halo
            if isActive {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                AppColors.accentWarm.opacity(0.4),
                                AppColors.accent.opacity(0.1)
                            ],
                            center: .center,
                            startRadius: size * 0.15,
                            endRadius: size * 0.55
                        )
                    )
                    .frame(width: size * 1.3, height: size * 1.3)
                    .scaleEffect(reduceMotion ? 1.0 : (animationPhase ? 1.12 : 0.92))
                    .animation(
                        reduceMotion ? .none : .easeInOut(duration: 1.4).repeatForever(autoreverses: true),
                        value: animationPhase
                    )
            }

            // Layer 1: Core AI presence mark (theme-adaptive puck + petals + sparkle).
            // Shadow is applied OUTSIDE the scaleEffect so it stays anchored
            // while the puck pulses — scaling the shadow looks jittery.
            AIPresenceIcon(size: size)
                .scaleEffect(reduceMotion ? 1.0 : (isActive ? (animationPhase ? 1.06 : 0.96) : 1.0))
                .animation(
                    reduceMotion
                        ? nil
                        : (isActive
                            ? .easeInOut(duration: 1.0).repeatForever(autoreverses: true)
                            : .easeOut(duration: 0.3)),
                    value: animationPhase
                )
                .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: isActive)
                .shadow(color: Color.black.opacity(0.15), radius: 3, x: 0, y: 2)
        }
        .onChange(of: isActive) { _, active in
            if !reduceMotion {
                animationPhase = active
            }
        }
        .onAppear {
            if isActive && !reduceMotion {
                animationPhase = true
            }
        }
        .accessibilityLabel(isActive ? "AI activity indicator, active" : "AI activity indicator, idle")
    }
}

// MARK: - Quatrefoil Shape

/// Four-petal flower silhouette formed by the union of 4 overlapping circles,
/// mirroring the geometry of `ThrivnVennMark`. Nonzero winding fills the
/// whole 4-lobed clover shape (not just the intersection).
///
/// Geometry matches `ThrivnVennMark`: each petal circle has radius 32% of
/// the bounding box and is offset 18% of the box from center.
struct QuatrefoilShape: Shape {
    var offsetRatio: CGFloat = 0.18
    var circleRadiusRatio: CGFloat = 0.32

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height)
        let r = s * circleRadiusRatio
        let o = s * offsetRatio
        let c = CGPoint(x: rect.midX, y: rect.midY)

        var p = Path()
        p.addEllipse(in: CGRect(x: c.x - r, y: c.y - o - r, width: 2 * r, height: 2 * r)) // top
        p.addEllipse(in: CGRect(x: c.x + o - r, y: c.y - r, width: 2 * r, height: 2 * r)) // right
        p.addEllipse(in: CGRect(x: c.x - r, y: c.y + o - r, width: 2 * r, height: 2 * r)) // bottom
        p.addEllipse(in: CGRect(x: c.x - o - r, y: c.y - r, width: 2 * r, height: 2 * r)) // left
        return p
    }
}
