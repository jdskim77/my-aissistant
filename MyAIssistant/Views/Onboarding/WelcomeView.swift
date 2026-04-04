import SwiftUI

struct WelcomeView: View {
    let onContinue: () -> Void
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 28) {
                // App icon
                Image("ThrivnLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 140, height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 32))
                    .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
                    .scaleEffect(appeared ? 1 : 0.5)
                    .opacity(appeared ? 1 : 0)

                VStack(spacing: 8) {
                    Text("Thrivn")
                        .font(AppFonts.display(34))
                        .foregroundColor(AppColors.textPrimary)

                    Text("Find your rhythm. Every day.")
                        .font(AppFonts.body(17))
                        .foregroundColor(AppColors.textSecondary)
                }
                .offset(y: appeared ? 0 : 16)
                .opacity(appeared ? 1 : 0)

                // Three value props — benefit-led, not feature-led
                VStack(alignment: .leading, spacing: 20) {
                    featureRow(
                        icon: "calendar.badge.clock",
                        color: AppColors.accentWarm,
                        title: "Your day, already planned",
                        subtitle: "Add tasks with a tap and start each morning with clarity"
                    )
                    featureRow(
                        icon: "sparkles",
                        color: AppColors.accent,
                        title: "It learns how you work best",
                        subtitle: "Smart nudges toward your goals at the right moments"
                    )
                    featureRow(
                        icon: "safari",
                        color: AppColors.coral,
                        title: "See where your energy goes",
                        subtitle: "Balance mind, body, heart and soul with the Life Compass"
                    )
                }
                .padding(.top, 8)
                .offset(y: appeared ? 0 : 24)
                .opacity(appeared ? 1 : 0)
            }

            Spacer()

            Button {
                Haptics.light()
                onContinue()
            } label: {
                Text("Get Started")
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
            }
        }
        .padding(.horizontal, 24)
    }
}
