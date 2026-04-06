import SwiftUI

struct OnboardingIntroView: View {
    let onContinue: () -> Void
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                Image(systemName: "safari")
                    .font(AppFonts.icon(56))
                    .foregroundColor(AppColors.accent)
                    .scaleEffect(appeared ? 1 : 0.6)

                Text("Let's see where you are today")
                    .font(AppFonts.display(28))
                    .foregroundColor(AppColors.textPrimary)
                    .multilineTextAlignment(.center)

                Text("Rate 4 areas of your life.\nThere are no wrong answers — this is your starting point.")
                    .font(AppFonts.body(16))
                    .foregroundColor(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 24)
            }
            .offset(y: appeared ? 0 : 20)
            .opacity(appeared ? 1 : 0)

            Spacer()

            Button(action: onContinue) {
                Text("Let's Go")
                    .font(AppFonts.bodyMedium(17))
                    .foregroundColor(AppColors.onAccent)
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
            withAnimation(.easeOut(duration: 0.6)) {
                appeared = true
            }
        }
    }
}
