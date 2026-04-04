import SwiftUI

struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(AppFonts.icon(40))
                .foregroundColor(AppColors.textMuted)

            Text(title)
                .font(AppFonts.heading(18))
                .foregroundColor(AppColors.textPrimary)

            Text(subtitle)
                .font(AppFonts.body(14))
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(AppFonts.bodyMedium(15))
                        .foregroundColor(AppColors.onAccent)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(AppColors.accent)
                        .cornerRadius(10)
                }
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}
