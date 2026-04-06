import SwiftUI

struct CelebrationView: View {
    let milestone: Int
    let onDismiss: () -> Void

    @State private var showConfetti = false
    @State private var opacity: Double = 0
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var milestoneMessage: String {
        switch milestone {
        case 7:   return "1 Week Strong!"
        case 21:  return "21 Days — Habit Forming!"
        case 30:  return "30 Days — Unstoppable!"
        case 60:  return "60 Days — Deep Roots!"
        case 90:  return "90 Days — Transformed!"
        case 180: return "Half a Year — Remarkable!"
        case 365: return "One Year — Legendary!"
        default:  return "\(milestone) Day Streak!"
        }
    }

    var milestoneEmoji: String {
        switch milestone {
        case 7:   return "\u{1F525}"   // fire
        case 21:  return "\u{1F331}"   // seedling
        case 30:  return "\u{2B50}"    // star
        case 60:  return "\u{1F48E}"   // gem
        case 90:  return "\u{1F3C6}"   // trophy
        case 180: return "\u{1F451}"   // crown
        case 365: return "\u{1F31F}"   // glowing star
        default:  return "\u{2728}"    // sparkles
        }
    }

    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(spacing: 20) {
                // Confetti particles
                if showConfetti && !reduceMotion {
                    ConfettiLayer()
                        .frame(height: 200)
                }

                Text(milestoneEmoji)
                    .font(.system(size: 72))
                    .scaleEffect(showConfetti ? 1.0 : 0.3)
                    .accessibilityHidden(true)

                Text(milestoneMessage)
                    .font(AppFonts.display(28))
                    .foregroundColor(AppColors.textPrimary)
                    .multilineTextAlignment(.center)

                Text("Your consistency is building something extraordinary.")
                    .font(AppFonts.body(15))
                    .foregroundColor(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Button(action: dismiss) {
                    Text("Keep Going")
                        .font(AppFonts.bodyMedium(17))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(AppColors.accent)
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 40)
                .padding(.top, 8)
                .accessibilityLabel("Dismiss celebration")
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(AppColors.card)
            )
            .padding(.horizontal, 32)
            .opacity(opacity)
            .scaleEffect(opacity > 0 ? 1.0 : 0.8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Streak milestone: \(milestoneMessage)")
        .onAppear {
            withAnimation(reduceMotion ? .none : .spring(response: 0.5, dampingFraction: 0.7)) {
                opacity = 1.0
                showConfetti = true
            }
            // Haptic burst for celebration
            Haptics.success()
        }
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.2)) {
            opacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            onDismiss()
        }
    }
}

// MARK: - Confetti Particle Layer

struct ConfettiLayer: View {
    @State private var particles: [ConfettiParticle] = []

    struct ConfettiParticle: Identifiable {
        let id = UUID()
        let x: CGFloat
        let color: Color
        let size: CGFloat
        let delay: Double
        let rotation: Double
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(particles) { p in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(p.color)
                        .frame(width: p.size, height: p.size * 1.5)
                        .rotationEffect(.degrees(p.rotation))
                        .position(x: p.x, y: -10)
                        .modifier(FallingModifier(delay: p.delay, maxY: geo.size.height))
                }
            }
        }
        .onAppear {
            let screenWidth = UIScreen.main.bounds.width
            let colors: [Color] = [.red, .orange, .yellow, .green, .blue, .purple, .pink]
            particles = (0..<40).map { _ in
                ConfettiParticle(
                    x: CGFloat.random(in: 0...screenWidth),
                    color: colors[Int.random(in: 0..<colors.count)],
                    size: CGFloat.random(in: 4...8),
                    delay: Double.random(in: 0...0.5),
                    rotation: Double.random(in: 0...360)
                )
            }
        }
        .allowsHitTesting(false)
    }
}

struct FallingModifier: ViewModifier {
    let delay: Double
    let maxY: CGFloat
    @State private var fallen = false

    func body(content: Content) -> some View {
        content
            .offset(y: fallen ? maxY + 20 : 0)
            .animation(
                .easeIn(duration: Double.random(in: 1.0...2.0))
                .delay(delay),
                value: fallen
            )
            .onAppear { fallen = true }
    }
}

// MARK: - Streak Milestone Detection

enum StreakMilestone {
    static let milestones = [7, 21, 30, 60, 90, 180, 365]

    /// Returns the milestone if the current streak exactly hits one, nil otherwise.
    static func check(streak: Int) -> Int? {
        milestones.contains(streak) ? streak : nil
    }

    /// Key for tracking which milestones have been celebrated (UserDefaults)
    static func celebratedKey(for milestone: Int) -> String {
        "streakMilestoneCelebrated_\(milestone)"
    }

    /// Returns true if this milestone hasn't been celebrated yet
    static func shouldCelebrate(streak: Int) -> Bool {
        guard let milestone = check(streak: streak) else { return false }
        return !UserDefaults.standard.bool(forKey: celebratedKey(for: milestone))
    }

    /// Mark a milestone as celebrated
    static func markCelebrated(streak: Int) {
        guard let milestone = check(streak: streak) else { return }
        UserDefaults.standard.set(true, forKey: celebratedKey(for: milestone))
    }

    /// Reset celebrations (e.g., when streak breaks)
    static func resetCelebrations() {
        for m in milestones {
            UserDefaults.standard.removeObject(forKey: celebratedKey(for: m))
        }
    }
}
