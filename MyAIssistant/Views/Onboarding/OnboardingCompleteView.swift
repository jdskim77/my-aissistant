import SwiftUI

struct OnboardingCompleteView: View {
    let onFinish: () -> Void
    @State private var appeared = false
    @State private var showConfetti = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                ZStack {
                    if showConfetti {
                        confettiEffect
                    }

                    Text("🎉")
                        .font(AppFonts.icon(72))
                        .scaleEffect(appeared ? 1 : 0.3)
                }

                Text("You're All Set!")
                    .font(AppFonts.display(32))
                    .foregroundColor(AppColors.textPrimary)

                Text("Your AI assistant is ready to help you\nstay organized and motivated.")
                    .font(AppFonts.body(16))
                    .foregroundColor(AppColors.textSecondary)
                    .multilineTextAlignment(.center)

                VStack(spacing: 12) {
                    tipRow(icon: "💬", text: "Chat with your assistant to add tasks")
                    tipRow(icon: "🔔", text: "Check in 4x daily to build your streak")
                    tipRow(icon: "📊", text: "Review your patterns each week")
                }
                .padding(.top, 8)
            }
            .offset(y: appeared ? 0 : 20)
            .opacity(appeared ? 1 : 0)

            Spacer()

            Button(action: onFinish) {
                Text("Let's Go!")
                    .font(AppFonts.bodyMedium(17))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: [AppColors.accent, AppColors.accentWarm],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(14)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
            .opacity(appeared ? 1 : 0)
        }
        .background(AppColors.background.ignoresSafeArea())
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                appeared = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation {
                    showConfetti = true
                }
            }
        }
    }

    private func tipRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Text(icon)
                .font(AppFonts.icon(22))
            Text(text)
                .font(AppFonts.body(14))
                .foregroundColor(AppColors.textSecondary)
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    private var confettiEffect: some View {
        // Simple animated dots as confetti placeholder
        ZStack {
            ForEach(0..<12, id: \.self) { i in
                Circle()
                    .fill(confettiColor(i))
                    .frame(width: 8, height: 8)
                    .offset(
                        x: showConfetti ? CGFloat.random(in: -80...80) : 0,
                        y: showConfetti ? CGFloat.random(in: -100...60) : 0
                    )
                    .opacity(showConfetti ? 0 : 1)
                    .animation(
                        .easeOut(duration: 1.2).delay(Double(i) * 0.05),
                        value: showConfetti
                    )
            }
        }
    }

    private func confettiColor(_ index: Int) -> Color {
        let colors: [Color] = [AppColors.accent, AppColors.accentWarm, AppColors.coral, AppColors.gold]
        return colors[index % colors.count]
    }
}
