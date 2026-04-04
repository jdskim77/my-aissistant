import SwiftUI

/// Inline upgrade prompt shown when a free-tier user hits their usage limit.
struct PaywallCard: View {
    let title: String
    let message: String
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "crown.fill")
                    .font(AppFonts.heading(20))
                    .foregroundColor(AppColors.accentWarm)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppFonts.bodyMedium(15))
                        .foregroundColor(AppColors.textPrimary)
                    Text(message)
                        .font(AppFonts.body(13))
                        .foregroundColor(AppColors.textSecondary)
                }

                Spacer()
            }

            if let action {
                Button(action: action) {
                    Text("Upgrade to Pro")
                        .font(AppFonts.bodyMedium(14))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            LinearGradient(
                                colors: [AppColors.accent, AppColors.accentWarm],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(10)
                }
            }
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [AppColors.accentWarm.opacity(0.06), AppColors.accent.opacity(0.03)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppColors.accentWarm.opacity(0.2), lineWidth: 1)
        )
    }
}
