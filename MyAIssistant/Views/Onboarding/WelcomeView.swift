import SwiftUI

struct WelcomeView: View {
    let onContinue: () -> Void
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                Text("✦")
                    .font(.system(size: 64))
                    .foregroundColor(AppColors.accent)
                    .scaleEffect(appeared ? 1 : 0.5)
                    .opacity(appeared ? 1 : 0)

                VStack(spacing: 8) {
                    Text("My AIssistant")
                        .font(AppFonts.display(32))
                        .foregroundColor(AppColors.textPrimary)

                    Text("Your AI-powered daily planner")
                        .font(AppFonts.body(16))
                        .foregroundColor(AppColors.textSecondary)
                }
                .offset(y: appeared ? 0 : 20)
                .opacity(appeared ? 1 : 0)

                VStack(alignment: .leading, spacing: 16) {
                    featureRow(icon: "🌅", title: "Smart Check-ins", subtitle: "4 daily rituals to keep you on track")
                    featureRow(icon: "✦", title: "AI Assistant", subtitle: "Chat naturally to manage your day")
                    featureRow(icon: "📊", title: "Pattern Insights", subtitle: "Discover your productivity trends")
                    featureRow(icon: "📅", title: "Calendar Sync", subtitle: "Connect your existing calendars")
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
                .font(.system(size: 28))
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
