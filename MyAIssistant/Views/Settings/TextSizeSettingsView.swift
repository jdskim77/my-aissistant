import SwiftUI

struct TextSizeSettingsView: View {
    @State private var selectedSize = TextSizeManager.shared.selectedSize

    var body: some View {
        List {
            // Live preview
            Section {
                previewCard
            } header: {
                Text("Preview")
            }

            // Size options
            Section {
                ForEach(TextSize.allCases) { size in
                    sizeOption(size)
                }
            } header: {
                Text("Text Size")
            } footer: {
                Text("Adjusts all text throughout the app. This works alongside your system Dynamic Type setting.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.background.ignoresSafeArea())
        .navigationTitle("Text Size")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Preview Card

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Good morning, Joe")
                .font(.system(size: scaled(18), weight: .semibold, design: .serif))
                .foregroundColor(AppColors.textPrimary)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("3 tasks today")
                        .font(.system(size: scaled(15), weight: .medium, design: .rounded))
                        .foregroundColor(AppColors.textPrimary)
                    Text("Next: Team standup at 9:00 AM")
                        .font(.system(size: scaled(13), weight: .regular, design: .rounded))
                        .foregroundColor(AppColors.textSecondary)
                }
                Spacer()
            }

            HStack(spacing: 8) {
                Image(systemName: "flame.fill")
                    .font(.system(size: scaled(12)))
                    .foregroundColor(AppColors.accentWarm)
                Text("5-day streak")
                    .font(.system(size: scaled(12), weight: .regular, design: .rounded))
                    .foregroundColor(AppColors.textMuted)
            }
        }
        .padding(16)
        .background(AppColors.card)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppColors.border, lineWidth: 1)
        )
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
    }

    // MARK: - Size Option Row

    private func sizeOption(_ size: TextSize) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.25)) {
                selectedSize = size
                TextSizeManager.shared.selectedSize = size
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: size.icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(selectedSize == size ? AppColors.accent : AppColors.textMuted)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(size.rawValue)
                        .font(AppFonts.bodyMedium(15))
                        .foregroundColor(AppColors.textPrimary)
                    Text(size.subtitle)
                        .font(AppFonts.caption(12))
                        .foregroundColor(AppColors.textMuted)
                }

                Spacer()

                if selectedSize == size {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(AppColors.accent)
                } else {
                    Circle()
                        .stroke(AppColors.border, lineWidth: 1.5)
                        .frame(width: 22, height: 22)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(size.rawValue) text size")
        .accessibilityHint(size.subtitle)
        .accessibilityAddTraits(selectedSize == size ? .isSelected : [])
    }

    // MARK: - Helpers

    private func scaled(_ size: CGFloat) -> CGFloat {
        (size * selectedSize.scale).rounded(.toNearestOrEven)
    }
}
