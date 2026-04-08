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

                    Text("A coach for the whole you.")
                        .font(AppFonts.heading(17))
                        .foregroundColor(AppColors.accent)

                    Text("Most apps optimize your to-do list. Thrivn looks at your whole life — body, mind, heart, spirit — and helps you spend your time on what actually matters.")
                        .font(AppFonts.body(14))
                        .foregroundColor(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .offset(y: appeared ? 0 : 20)
                .opacity(appeared ? 1 : 0)

                VStack(alignment: .leading, spacing: 16) {
                    featureRow(icon: "🧭", title: "See your whole life", subtitle: "A weekly compass across four dimensions")
                    featureRow(icon: "✦", title: "Talk to a coach who knows you", subtitle: "Context-aware AI, not a generic chatbot")
                    featureRow(icon: "🌅", title: "15 seconds, 4 times a day", subtitle: "Quick check-ins build the picture over time")
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
