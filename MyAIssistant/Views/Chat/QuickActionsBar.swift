import SwiftUI

struct QuickActionsBar: View {
    let actions: [String]
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(actions, id: \.self) { action in
                    Button {
                        onSelect(action)
                    } label: {
                        Text(action)
                            .font(AppFonts.bodyMedium(13))
                            .foregroundColor(AppColors.accent)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(AppColors.accentLight)
                            .cornerRadius(20)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
    }
}

// MARK: - Task Builder Chips Bar

struct TaskBuilderChipsBar: View {
    let chips: [TaskBuilderChip]
    let onSelect: (TaskBuilderChip) -> Void
    let onCancel: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Cancel button
                Button {
                    Haptics.light()
                    onCancel()
                } label: {
                    Text("✕ Cancel")
                        .font(AppFonts.bodyMedium(13))
                        .foregroundColor(AppColors.textMuted)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(AppColors.border.opacity(0.3))
                        .cornerRadius(20)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel task creation")

                ForEach(chips) { chip in
                    Button {
                        Haptics.light()
                        onSelect(chip)
                    } label: {
                        HStack(spacing: 4) {
                            if let icon = chip.icon {
                                Text(icon)
                                    .font(AppFonts.body(13))
                            }
                            Text(chip.label)
                                .font(AppFonts.bodyMedium(13))
                        }
                        .foregroundColor(AppColors.accent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(AppColors.accentLight)
                        .cornerRadius(20)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        [chip.icon, chip.label].compactMap { $0 }.joined(separator: " ")
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
    }
}
