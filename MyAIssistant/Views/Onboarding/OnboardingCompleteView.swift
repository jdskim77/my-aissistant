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
                        .font(.system(size: 72))
                        .scaleEffect(appeared ? 1 : 0.3)
                }

                Text("You're All Set!")
                    .font(AppFonts.display(32))
                    .foregroundColor(AppColors.textPrimary)

                Text("Your AI assistant is ready to help you\nstay organized and motivated.")
                    .font(AppFonts.body(16))
                    .foregroundColor(AppColors.textSecondary)
                    .multilineTextAlignment(.center)

                // Quick-start tips
                VStack(spacing: 14) {
                    tipRow(
                        icon: "plus.circle.fill",
                        color: AppColors.accent,
                        text: "Tap + on the schedule tab to add your first task"
                    )
                    tipRow(
                        icon: "sparkles",
                        color: AppColors.accentWarm,
                        text: "Ask the AI to manage your day — tap the center button"
                    )
                    tipRow(
                        icon: "flame.fill",
                        color: AppColors.coral,
                        text: "Check in daily to build your streak"
                    )
                }
                .padding(.top, 4)
            }
            .offset(y: appeared ? 0 : 20)
            .opacity(appeared ? 1 : 0)

            Spacer()

            Button {
                Haptics.success()
                onFinish()
            } label: {
                Text("Let's Go!")
                    .font(AppFonts.bodyMedium(17))
                    .foregroundColor(AppColors.onAccent)
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

    private func tipRow(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(color)
                .frame(width: 32)
            Text(text)
                .font(AppFonts.body(14))
                .foregroundColor(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    private var confettiEffect: some View {
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
