import SwiftUI

struct SubscriptionOfferView: View {
    let onContinue: () -> Void
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                Text("⭐")
                    .font(AppFonts.icon(56))

                Text("Unlock the Full\nExperience")
                    .font(AppFonts.display(28))
                    .foregroundColor(AppColors.textPrimary)
                    .multilineTextAlignment(.center)

                // Free tier info
                VStack(alignment: .leading, spacing: 10) {
                    Text("Free includes:")
                        .font(AppFonts.bodyMedium(14))
                        .foregroundColor(AppColors.textPrimary)

                    benefitRow("5 AI check-ins per week")
                    benefitRow("10 chat messages per month")
                    benefitRow("Full schedule management")
                    benefitRow("Pattern tracking")
                }
                .padding(16)
                .background(AppColors.card)
                .cornerRadius(14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(AppColors.border.opacity(0.5), lineWidth: 1)
                )
                .padding(.horizontal, 24)

                // Pro teaser
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Pro")
                            .font(AppFonts.bodyMedium(14))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(AppColors.accent)
                            .cornerRadius(6)

                        Spacer()

                        Text("$9.99/month")
                            .font(AppFonts.bodyMedium(14))
                            .foregroundColor(AppColors.accent)
                    }

                    benefitRow("Unlimited AI check-ins & chat")
                    benefitRow("Smarter AI model for chat")
                    benefitRow("Weekly AI insight reviews")
                    benefitRow("Calendar sync")
                }
                .padding(16)
                .background(
                    LinearGradient(
                        colors: [AppColors.accent.opacity(0.06), AppColors.accentWarm.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .cornerRadius(14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(AppColors.accent.opacity(0.2), lineWidth: 1)
                )
                .padding(.horizontal, 24)
            }
            .offset(y: appeared ? 0 : 20)
            .opacity(appeared ? 1 : 0)

            Spacer()

            VStack(spacing: 12) {
                Button(action: onContinue) {
                    Text("Continue with Free")
                        .font(AppFonts.bodyMedium(17))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(AppColors.accent)
                        .cornerRadius(14)
                }

                Text("You can upgrade anytime in Settings")
                    .font(AppFonts.caption(12))
                    .foregroundColor(AppColors.textMuted)

                Text("Subscriptions auto-renew unless canceled at least 24 hours before the end of the current period. Manage subscriptions in Settings > Apple ID > Subscriptions.")
                    .font(AppFonts.caption(11))
                    .foregroundColor(AppColors.textMuted.opacity(0.7))
                    .multilineTextAlignment(.center)

                HStack(spacing: 16) {
                    NavigationLink("Privacy Policy") { PrivacyPolicyView() }
                    NavigationLink("Terms of Service") { TermsOfServiceView() }
                }
                .font(AppFonts.caption(11))
                .foregroundColor(AppColors.accent)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .background(AppColors.background.ignoresSafeArea())
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                appeared = true
            }
        }
    }

    private func benefitRow(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark")
                .font(AppFonts.label(12))
                .foregroundColor(AppColors.accentWarm)
            Text(text)
                .font(AppFonts.body(14))
                .foregroundColor(AppColors.textSecondary)
        }
    }
}
