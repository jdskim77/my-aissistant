import SwiftUI

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    var color: Color = AppColors.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(icon)
                    .font(.system(size: 16))
                Spacer()
            }

            Text(value)
                .font(AppFonts.displayBold(28))
                .foregroundColor(color)

            Text(title)
                .font(AppFonts.caption(12))
                .foregroundColor(AppColors.textSecondary)
        }
        .padding(14)
        .background(AppColors.card)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppColors.border.opacity(0.5), lineWidth: 1)
        )
    }
}
