import SwiftUI

struct ThemePickerView: View {
    @State private var selected: AppTheme = ThemeManager.shared.selectedTheme

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Choose a look that suits you")
                    .font(AppFonts.body(15))
                    .foregroundColor(AppColors.textSecondary)
                    .padding(.horizontal, 20)

                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(AppTheme.allCases) { theme in
                        themeCard(theme)
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.vertical, 16)
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.background.ignoresSafeArea())
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func themeCard(_ theme: AppTheme) -> some View {
        let colors = ThemeManager.theme(for: theme)
        let isSelected = selected == theme

        return Button {
            withAnimation(.spring(response: 0.3)) {
                selected = theme
                ThemeManager.shared.setTheme(theme)
            }
        } label: {
            VStack(spacing: 12) {
                // Color preview
                VStack(spacing: 0) {
                    // Top: background color with text sample
                    HStack(spacing: 6) {
                        Circle()
                            .fill(colors.accent)
                            .frame(width: 14, height: 14)
                        Circle()
                            .fill(colors.accentWarm)
                            .frame(width: 14, height: 14)
                        Circle()
                            .fill(colors.coral)
                            .frame(width: 14, height: 14)
                        Circle()
                            .fill(colors.gold)
                            .frame(width: 14, height: 14)
                    }
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(colors.background)

                    // Bottom: surface with text colors
                    VStack(alignment: .leading, spacing: 3) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(colors.textPrimary)
                            .frame(width: 60, height: 4)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(colors.textSecondary)
                            .frame(width: 44, height: 3)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(colors.textMuted)
                            .frame(width: 32, height: 3)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(colors.surface)
                }
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(colors.border, lineWidth: 1)
                )

                // Label
                HStack(spacing: 6) {
                    Image(systemName: theme.icon)
                        .font(.system(size: 13))
                        .foregroundColor(isSelected ? AppColors.accent : AppColors.textSecondary)

                    Text(theme.rawValue)
                        .font(AppFonts.bodyMedium(14))
                        .foregroundColor(AppColors.textPrimary)
                }

                Text(theme.subtitle)
                    .font(AppFonts.caption(11))
                    .foregroundColor(AppColors.textMuted)
            }
            .padding(12)
            .background(AppColors.card)
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        isSelected ? AppColors.accent : AppColors.border.opacity(0.5),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(AppColors.accent)
                        .background(Circle().fill(AppColors.card))
                        .offset(x: 6, y: -6)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
