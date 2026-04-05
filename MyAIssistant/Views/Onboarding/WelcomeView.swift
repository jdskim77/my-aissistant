import SwiftUI

struct WelcomeView: View {
    let onContinue: () -> Void
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                Text("✦")
                    .font(AppFonts.icon(64))
                    .foregroundColor(AppColors.accent)
                    .scaleEffect(appeared ? 1 : 0.5)
                    .opacity(appeared ? 1 : 0)

                VStack(spacing: 12) {
                    Text("Thrivn")
                        .font(AppFonts.display(36))
                        .foregroundColor(AppColors.textPrimary)

                    Text("Excel at life by finding balance.")
                        .font(AppFonts.heading(17))
                        .foregroundColor(AppColors.accent)

                    Text("Reveals where you're thriving and where you need attention — across your physical, mental, emotional, and spiritual well-being.")
                        .font(AppFonts.body(14))
                        .foregroundColor(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .offset(y: appeared ? 0 : 20)
                .opacity(appeared ? 1 : 0)

                VStack(alignment: .leading, spacing: 16) {
                    featureRow(icon: "🌅", title: "Daily Check-ins", subtitle: "Track mood, energy, and progress")
                    featureRow(icon: "🧭", title: "Life Compass", subtitle: "See your balance across all dimensions")
                    featureRow(icon: "✦", title: "AI Coach", subtitle: "Personalized guidance toward your goals")
                    featureRow(icon: "📊", title: "Pattern Insights", subtitle: "Discover what's working and what's not")
                }
                .padding(.top, 16)
                .offset(y: appeared ? 0 : 30)
                .opacity(appeared ? 1 : 0)
            }

            Spacer()

            Button(action: onContinue) {
                Text("Get Started")
                    .font(AppFonts.bodyMedium(17))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(AppColors.accent)
                    .cornerRadius(14)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
            .opacity(appeared ? 1 : 0)
        }
        .background(AppColors.background.ignoresSafeArea())
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) {
                appeared = true
            }
        }
    }

    private func featureRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Text(icon)
                .font(AppFonts.icon(28))
                .frame(width: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppFonts.bodyMedium(15))
                    .foregroundColor(AppColors.textPrimary)
                Text(subtitle)
                    .font(AppFonts.body(13))
                    .foregroundColor(AppColors.textSecondary)
            }
        }
        .padding(.horizontal, 24)
    }
}
