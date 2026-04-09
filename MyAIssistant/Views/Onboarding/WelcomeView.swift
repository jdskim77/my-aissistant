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

                    Text("Daily check-ins, weekly clarity.")
                        .font(AppFonts.heading(17))
                        .foregroundColor(AppColors.accent)

                    Text("Quick check-ins build a picture of your week across body, mind, heart, and spirit. A private AI helps you turn that into small, meaningful actions.")
                        .font(AppFonts.body(14))
                        .foregroundColor(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .offset(y: appeared ? 0 : 20)
                .opacity(appeared ? 1 : 0)

                VStack(alignment: .leading, spacing: 16) {
                    featureRow(icon: "🧭", title: "Your week, at a glance", subtitle: "A four-dimension compass that updates as you check in")
                    featureRow(icon: "✦", title: "An AI assistant with context", subtitle: "Your check-ins inform every reply, so suggestions match your real week")
                    featureRow(icon: "🌅", title: "Four quick check-ins a day", subtitle: "Each one adds to your weekly pattern")
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
