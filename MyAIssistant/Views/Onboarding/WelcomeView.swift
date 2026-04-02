import SwiftUI

struct WelcomeView: View {
    let onContinue: () -> Void
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 28) {
                // App icon / brand
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [AppColors.accent, AppColors.accentWarm],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 88, height: 88)
                        .scaleEffect(appeared ? 1 : 0.5)
                        .opacity(appeared ? 1 : 0)

                    Text("✦")
                        .font(.system(size: 44))
                        .foregroundColor(.white)
                        .scaleEffect(appeared ? 1 : 0.5)
                        .opacity(appeared ? 1 : 0)
                }

                VStack(spacing: 8) {
                    Text("Thrivn")
                        .font(AppFonts.display(34))
                        .foregroundColor(AppColors.textPrimary)

                    Text("Find your rhythm. Balance your day.")
                        .font(AppFonts.body(17))
                        .foregroundColor(AppColors.textSecondary)
                }
                .offset(y: appeared ? 0 : 16)
                .opacity(appeared ? 1 : 0)

                // Three key value props — concise
                VStack(alignment: .leading, spacing: 20) {
                    featureRow(
                        icon: "circle.grid.cross.fill",
                        color: AppColors.accentWarm,
                        title: "Balance mind, body, heart & soul",
                        subtitle: "Track four dimensions of your daily life"
                    )
                    featureRow(
                        icon: "sparkles",
                        color: AppColors.accent,
                        title: "AI that learns your patterns",
                        subtitle: "Intelligent nudges to keep you in rhythm"
                    )
                    featureRow(
                        icon: "chart.line.uptrend.xyaxis",
                        color: AppColors.coral,
                        title: "Tune, don't judge",
                        subtitle: "Supportive guidance toward your best balance"
                    )
                }
                .padding(.top, 8)
                .offset(y: appeared ? 0 : 24)
                .opacity(appeared ? 1 : 0)
            }

            Spacer()

            Button(action: onContinue) {
                Text("Get Started")
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
            withAnimation(.spring(response: 0.7, dampingFraction: 0.8)) {
                appeared = true
            }
        }
    }

    private func featureRow(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(color)
                .frame(width: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppFonts.bodyMedium(16))
                    .foregroundColor(AppColors.textPrimary)
                Text(subtitle)
                    .font(AppFonts.body(14))
                    .foregroundColor(AppColors.textSecondary)
                    .lineHeight(18)
            }
        }
        .padding(.horizontal, 24)
    }
}

// Helper for line height on Text
private extension Text {
    func lineHeight(_ height: CGFloat) -> some View {
        self.lineSpacing(height - 14)
    }
}
