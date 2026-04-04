import SwiftUI

struct AIActivityOrb: View {
    let isActive: Bool
    var size: CGFloat = 40

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
                    .scaleEffect(animationPhase ? 1.15 : 0.95)
                    .opacity(animationPhase ? 0.8 : 0.4)
                    .animation(
                        .easeInOut(duration: 1.8).repeatForever(autoreverses: true),
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
                    .scaleEffect(animationPhase ? 1.12 : 0.92)
                    .animation(
                        .easeInOut(duration: 1.4).repeatForever(autoreverses: true),
                        value: animationPhase
                    )
            }

            // Layer 1: Core orb
            Circle()
                .fill(
                    LinearGradient(
                        colors: [AppColors.accent, AppColors.accentWarm],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
                .scaleEffect(isActive ? (animationPhase ? 1.06 : 0.96) : 1.0)
                .animation(
                    isActive
                        ? .easeInOut(duration: 1.0).repeatForever(autoreverses: true)
                        : .easeOut(duration: 0.3),
                    value: animationPhase
                )
                .animation(.easeOut(duration: 0.3), value: isActive)

            // Center logo
            Image("ThrivnLogo")
                .resizable()
                .scaledToFit()
                .frame(width: size * 0.7, height: size * 0.7)
                .clipShape(Circle())
                .opacity(isActive ? (animationPhase ? 1.0 : 0.7) : 0.9)
                .animation(
                    isActive
                        ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                        : .default,
                    value: animationPhase
                )
        }
        .onChange(of: isActive) { _, active in
            animationPhase = active
        }
        .onAppear {
            if isActive {
                animationPhase = true
            }
        }
    }
}
