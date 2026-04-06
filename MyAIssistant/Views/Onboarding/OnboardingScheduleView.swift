import SwiftUI

struct OnboardingScheduleView: View {
    let onFinish: () -> Void
    @State private var appeared = false
    @State private var showConfetti = false

    private let timeSlots: [(CheckInTime, String)] = [
        (.morning,   "Start your day with intention"),
        (.midday,    "Quick midday energy check"),
        (.afternoon, "Reflect on your afternoon"),
        (.night,     "Wind down and review your day"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                ZStack {
                    if showConfetti {
                        confettiEffect
                    }
                    Text("🔔")
                        .font(AppFonts.icon(56))
                        .scaleEffect(appeared ? 1 : 0.5)
                }

                Text("I'll check in 4 times a day")
                    .font(AppFonts.display(24))
                    .foregroundColor(AppColors.textPrimary)
                    .multilineTextAlignment(.center)

                Text("15 seconds each. Here's the schedule:")
                    .font(AppFonts.body(15))
                    .foregroundColor(AppColors.textSecondary)

                // Time slot cards
                VStack(spacing: 10) {
                    ForEach(timeSlots, id: \.0) { slot, description in
                        HStack(spacing: 14) {
                            Text(slot.icon)
                                .font(AppFonts.icon(24))
                                .frame(width: 40)

                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(slot.title)
                                        .font(AppFonts.bodyMedium(15))
                                        .foregroundColor(AppColors.textPrimary)
                                    Spacer()
                                    Text(slot.timeLabel)
                                        .font(AppFonts.caption(13))
                                        .foregroundColor(slot.color)
                                        .monospacedDigit()
                                }
                                Text(description)
                                    .font(AppFonts.caption(12))
                                    .foregroundColor(AppColors.textMuted)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(AppColors.card)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(AppColors.border, lineWidth: 1)
                        )
                    }
                }
                .padding(.horizontal, 20)

                Text("You can customize these times later in Settings.")
                    .font(AppFonts.caption(12))
                    .foregroundColor(AppColors.textMuted)
            }
            .offset(y: appeared ? 0 : 20)
            .opacity(appeared ? 1 : 0)

            Spacer()

            Button(action: onFinish) {
                Text("Get Started!")
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
            withAnimation(.easeOut(duration: 0.6)) {
                appeared = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation { showConfetti = true }
            }
        }
    }

    // MARK: - Confetti

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
